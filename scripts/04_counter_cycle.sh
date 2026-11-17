#!/usr/bin/env bash
# counter 데모로 actor 1개를 만들고 suspend(sync)/resume 을 반복한다.
# 확인하는 것: 상태 보존(세 counter 가 이어서 증가), suspend/wake 시간, snapshot 이 남는 위치와 크기.
# 사용: scripts/04_counter_cycle.sh [반복횟수=3]
set -uo pipefail
source "$(dirname "$0")/env.sh"
cd "$SUBSTRATE_DIR"
N="${1:-3}"; NS=ate-demo-counter; ACTOR="${ACTOR:-my-counter-1}"; PORT="${PORT:-8000}"
out="$RESULTS/04_counter_cycle.txt"
ate() { kubectl ate --context "$KCTX" "$@" 2> >(grep -v '^Warning: no --token-file' >&2); }
now() { python3 -c 'import time;print(time.time())'; }
el() { python3 -c "print(f'{$2-$1:.3f}')"; }
node_du() { docker exec "${KIND_CLUSTER_NAME:-kind}-control-plane" sh -c 'du -sk /var/lib/ate/snapshots /var/lib/ate/snapshot-cache /var/lib/ate/snapshot-scratch /var/lib/ate/actors 2>/dev/null | tr "\n" " "'; }
{
echo "# counter cycle $(date -u +%FT%TZ) host_label=$HOST_LABEL"
if ! kubectl --context "$KCTX" get ns "$NS" >/dev/null 2>&1; then
  { time ate-setup deploy demo counter --rollout-timeout=600s; } 2>&1 | tail -5
fi
kubectl --context "$KCTX" get pods -n "$NS" --no-headers
ate get actor-templates -a "$NS"
ate get actor "$ACTOR" -a "$NS" >/dev/null 2>&1 || ate create actor "$ACTOR" -a "$NS" --template counter
kubectl ate --context "$KCTX" proxy actor "$ACTOR" "$PORT:80" -a "$NS" >"$RESULTS/04_proxy.log" 2>&1 & PROXY=$!   # 함수(ate)로 감싸면 $! 가 하위 셸이라 종료 시 프록시가 남는다
trap 'kill $PROXY 2>/dev/null' EXIT
sleep 4
if ! kill -0 $PROXY 2>/dev/null; then echo "FAIL: proxy 가 뜨지 않음 (포트 $PORT 사용 중? PORT=다른값 으로 재시도): $(cat "$RESULTS/04_proxy.log")"; exit 1; fi
for i in $(seq 1 "$N"); do
  s=$(now); r=$(curl -s -m 120 -X POST "http://localhost:$PORT/"); e=$(now)
  echo "cycle=$i wake_request_s=$(el $s $e) response=[$(echo "$r" | tr '\n' ' ')]"
  ate get actor "$ACTOR" -a "$NS" | tail -1
  echo "  node_kb_before_suspend: $(node_du)"
  s=$(now); ate suspend actor "$ACTOR" -a "$NS" --mode=sync; rc=$?; e=$(now)
  echo "cycle=$i suspend_sync_s=$(el $s $e) rc=$rc"
  ate get actor "$ACTOR" -a "$NS" | tail -1
  echo "  node_kb_after_suspend:  $(node_du)"
done
s=$(now); r=$(curl -s -m 120 -X POST "http://localhost:$PORT/"); e=$(now)
echo "final wake_request_s=$(el $s $e) response=[$(echo "$r" | tr '\n' ' ')]"
want=$((N+1))
if echo "$r" | grep -q "memory count: $want " && echo "$r" | grep -q "file counter: $want " && echo "$r" | grep -q "rootfs counter: $want"; then echo "PASS: suspend/resume ${N}회 뒤 세 counter 모두 ${want} (상태 보존됨)"; else echo "FAIL: 기대값 ${want} 과 다름"; fi
kill $PROXY 2>/dev/null   # bash 3.2 는 파이프 안 EXIT trap 을 돌리지 않으므로 직접 끈다
echo "## actor status.snapshots"
ate get actor "$ACTOR" -a "$NS" -o yaml | sed -n '/snapshots:/,$p' | head -60
echo "## 노드 로컬 파일 (/var/lib/ate)"
docker exec "${KIND_CLUSTER_NAME:-kind}-control-plane" sh -c 'du -sh /var/lib/ate/* 2>/dev/null; find /var/lib/ate/snapshots /var/lib/ate/snapshot-cache /var/lib/ate/actors -type f -exec ls -l {} + 2>/dev/null | head -60'
} 2>&1 | tee "$out"
echo "saved: $out"
grep -q "^PASS" "$out"
