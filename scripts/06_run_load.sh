#!/usr/bin/env bash
# 가상 Agent 부하를 한 번 실행하고 결과를 저장한다. Locust 웹 UI 대신 그 HTTP API 를 호출한다.
# 사용: scripts/06_run_load.sh <실행이름> <동시세션수> <실행시간초> [locust 추가 인자: key=value ...]
#   예) scripts/06_run_load.sh s4_sync 4 180 lifecycle_mode=sync agentsession_think_scale=1.0
#   예) scripts/06_run_load.sh turnover 12 300 agentsession_awake=3 target_rps=1     # 12개 중 3개만 깨어 있고 초당 1개씩 교체
# 추가 인자의 key 는 locust 옵션 이름에서 '--' 를 떼고 '-' 를 '_' 로 바꾼 것.
set -uo pipefail
source "$(dirname "$0")/env.sh"
name="$1"; users="$2"; dur="$3"; shift 3
out="$RESULTS/runs/$name"; mkdir -p "$out"; PORT="${LOCUST_PORT:-8089}"; L="http://localhost:$PORT"
# 부하 생성기를 매번 새로 띄운다: 한 번 정지 신호를 받은 worker 는 turnover 모드를 다시 돌리지 않는다.
kubectl --context "$KCTX" rollout restart deploy/locust -n benchmarking >/dev/null
kubectl --context "$KCTX" rollout status deploy/locust -n benchmarking --timeout=180s >/dev/null
sleep 5
kubectl --context "$KCTX" port-forward svc/locust -n benchmarking "$PORT:8089" >"$out/portforward.log" 2>&1 & PF=$!
trap 'kill $PF 2>/dev/null; "$ROOT/scripts/collect.sh" stop "$out" >/dev/null 2>&1' EXIT
for i in $(seq 1 30); do curl -s -o /dev/null "$L/" && break; sleep 1; done
args=(-d "user_count=$users" -d "spawn_rate=${SPAWN_RATE:-1}")
for kv in "$@"; do args+=(-d "$kv"); done
{ echo "name=$name users=$users duration_s=$dur extra=$*"; date -u +start=%FT%TZ; } | tee "$out/run.txt"
kubectl --context "$KCTX" get pods -n benchmark-workloads --no-headers > "$out/workers_before.txt" 2>&1
"$ROOT/scripts/collect.sh" start "$out" >/dev/null
curl -s -X POST "$L/stats/reset" >/dev/null
curl -s -X POST "${args[@]}" "$L/swarm" | tee -a "$out/run.txt"; echo
sleep "$dur"
curl -s "$L/stats/requests" > "$out/stats.json"
curl -s "$L/stats/requests/csv" > "$out/stats.csv"
curl -s "$L/stats/failures/csv" > "$out/failures.csv"
curl -s "$L/stop" >/dev/null
date -u +end=%FT%TZ | tee -a "$out/run.txt"
sleep "${DRAIN_S:-20}"     # 남은 suspend/업로드가 끝나도록 잠깐 더 수집
"$ROOT/scripts/collect.sh" stop "$out" >/dev/null
kubectl --context "$KCTX" get pods -n benchmark-workloads --no-headers > "$out/workers_after.txt" 2>&1
kubectl --context "$KCTX" logs -n benchmarking -l app=locust -c boomer-worker --tail=300 > "$out/boomer_worker.log" 2>&1 || true
{ echo "## requests"; python3 - "$out/stats.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
print(f"{'name':34} {'reqs':>6} {'fail':>5} {'p50ms':>8} {'p95ms':>8} {'p99ms':>8} {'maxms':>8}")
for r in s["stats"]:
    g=lambda *k: next((r[x] for x in k if x in r), 0)
    print(f"{r['name'][:34]:34} {r['num_requests']:>6} {r['num_failures']:>5} {g('median_response_time'):>8.0f} {g('response_time_percentile_0.95','ninetieth_response_time'):>8.0f} {g('response_time_percentile_0.99','ninety_ninth_response_time'):>8.0f} {g('max_response_time'):>8.0f}")
for e in s.get("errors",[]): print("ERROR x%s %s: %s"%(e.get("occurrences"),e.get("name"),str(e.get("error"))[:200]))
PY
echo "## storage / memory"; python3 "$ROOT/scripts/analyze_io.py" "$out"
echo "## worker pods after"; cat "$out/workers_after.txt"; } 2>&1 | tee "$out/summary.txt"
