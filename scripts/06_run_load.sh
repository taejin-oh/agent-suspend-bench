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
{ echo "name=$name users=$users duration_s=$dur extra=$*"
  echo "deployed=$(cat "$RESULTS/deployed.txt" 2>/dev/null)"
  echo "objectstore_plugin_args=$(kubectl --context "$KCTX" -n ate-system get ds atelet -o jsonpath='{.spec.template.spec.initContainers[0].args}' 2>/dev/null)"
  date -u +start=%FT%TZ; } | tee "$out/run.txt"
kubectl --context "$KCTX" get pods -n benchmark-workloads --no-headers > "$out/workers_before.txt" 2>&1
"$ROOT/scripts/collect.sh" start "$out" >/dev/null
curl -s -X POST "$L/stats/reset" >/dev/null
curl -s -X POST "${args[@]}" "$L/swarm" | tee -a "$out/run.txt"; echo
sleep "$dur"
curl -s "$L/stats/requests" > "$out/stats.json"
curl -s "$L/stats/requests/csv" > "$out/stats.csv"
curl -s "$L/stats/failures/csv" > "$out/failures.csv"
# 정지 전에 actor 별 snapshot 크기를 남긴다 (노드 로컬 KB, 객체 저장소 KB)
NODE="${KIND_CLUSTER_NAME:-kind}-control-plane"
{ echo "## node /var/lib/ate/snapshots/<actor-uid> (KB)"; docker exec "$NODE" sh -c 'du -sk /var/lib/ate/snapshots/* 2>/dev/null'
  echo "## object store atespaces/benchmark/actors/<actor-uid> (KB)"; kubectl --context "$KCTX" exec -n ate-system deploy/rustfs -- sh -c 'du -sk /data/ate-snapshots/atespaces/benchmark/actors/* 2>/dev/null'; } > "$out/snapshot_sizes.txt" 2>&1 || true
curl -s "$L/stop" >/dev/null
date -u +end=%FT%TZ | tee -a "$out/run.txt"
sleep "${DRAIN_S:-20}"     # 남은 suspend/업로드가 끝나도록 잠깐 더 수집
"$ROOT/scripts/collect.sh" stop "$out" >/dev/null
kubectl --context "$KCTX" get pods -n benchmark-workloads --no-headers > "$out/workers_after.txt" 2>&1
kubectl --context "$KCTX" logs -n benchmarking -l app=locust -c boomer-worker --tail=300 > "$out/boomer_worker.log" 2>&1 || true
# suspend/resume 구간별 시간: atelet 과 worker 가 남긴 "timing breakdown" 로그를 substrate 의 분석 도구로 집계한다.
start_ts="$(sed -n 's/^start=//p' "$out/run.txt")"; tmp="$(mktemp -d)"
kubectl --context "$KCTX" logs -n ate-system ds/atelet --since-time="$start_ts" 2>/dev/null | grep "timing breakdown" > "$tmp/atelet.log"
for p in $(kubectl --context "$KCTX" get pods -n benchmark-workloads -o name); do
  kubectl --context "$KCTX" logs -n benchmark-workloads "$p" --since-time="$start_ts" 2>/dev/null | grep "timing breakdown" > "$tmp/$(basename "$p").log"; done
python3 "$SUBSTRATE_DIR/benchmarking/analysis/phase_report.py" "$tmp"/*.log > "$out/phases.txt" 2>&1 || true
# 원본 기록도 남긴다: atelet 의 구간별 시간, objectstore-plugin 의 파일별 업로드 시간(예산 대기를 뺀 실제 압축·전송 시간)
cp "$tmp/atelet.log" "$out/phases_raw.jsonl"
kubectl --context "$KCTX" logs -n ate-system ds/atelet -c objectstore-plugin --since-time="$start_ts" 2>/dev/null | grep '"Compressed zstd upload"' > "$out/uploads_raw.jsonl" || true
rm -rf "$tmp"
{ echo "## requests"; python3 - "$out/stats.json" <<'PY'
import json,sys
s=json.load(open(sys.argv[1]))
print(f"{'name':34} {'reqs':>6} {'fail':>5} {'p50ms':>8} {'p95ms':>8} {'p99ms':>8} {'maxms':>8}")
for r in s["stats"]:
    g=lambda *k: next((r[x] for x in k if x in r), 0)
    print(f"{r['name'][:34]:34} {r['num_requests']:>6} {r['num_failures']:>5} {g('median_response_time'):>8.0f} {g('response_time_percentile_0.95','ninetieth_response_time'):>8.0f} {g('response_time_percentile_0.99','ninety_ninth_response_time'):>8.0f} {g('max_response_time'):>8.0f}")
for e in s.get("errors",[]): print("ERROR x%s %s: %s"%(e.get("occurrences"),e.get("name"),str(e.get("error"))[:200]))
PY
echo "## storage / memory / cpu"; python3 "$ROOT/scripts/analyze_io.py" "$out"
echo "## suspend(checkpoint) / resume(restore) phases, ms (atelet)"; grep -E "^layer|^atelet +(checkpoint|restore) .* (worker_checkpoint|persist|download|worker_restore|total) " "$out/phases.txt"
echo "## snapshot size per actor, MiB"; python3 - "$out/snapshot_sizes.txt" <<'PY'
import sys, statistics as st
sec = None; d = {"node": [], "object": []}
for l in open(sys.argv[1]):
    if l.startswith("## node"): sec = "node"; continue
    if l.startswith("## object"): sec = "object"; continue
    p = l.split()
    if sec and len(p) == 2 and p[0].isdigit(): d[sec].append(int(p[0]) / 1024)
for k, v in d.items():
    if v: print(f"{k}: actors={len(v)} median={st.median(v):.0f} min={min(v):.0f} max={max(v):.0f} total={sum(v):.0f}")
PY
echo "## load window only (부하가 걸린 구간: turnover 는 교체 구간)"; python3 "$ROOT/scripts/window_stats.py" "$out"
echo "## worker pods after"; cat "$out/workers_after.txt"; } 2>&1 | tee "$out/summary.txt"
