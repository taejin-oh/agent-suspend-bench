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
ate proxy actor "$ACTOR" -a "$NS" >"$RESULTS/04_proxy.log" 2>&1 & PROXY=$!
trap 'kill $PROXY 2>/dev/null' EXIT
sleep 4
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
echo "## actor status.snapshots"
ate get actor "$ACTOR" -a "$NS" -o yaml | sed -n '/snapshots:/,$p' | head -60
echo "## 노드 로컬 파일 (/var/lib/ate)"
docker exec "${KIND_CLUSTER_NAME:-kind}-control-plane" sh -c 'du -sh /var/lib/ate/* 2>/dev/null; find /var/lib/ate/snapshots /var/lib/ate/snapshot-cache /var/lib/ate/actors -type f -exec ls -l {} + 2>/dev/null | head -60'
} 2>&1 | tee "$out"
echo "saved: $out"
