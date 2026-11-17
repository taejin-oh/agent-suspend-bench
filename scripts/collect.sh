#!/usr/bin/env bash
# 부하 실행 중 스토리지·메모리 지표를 1초 간격으로 모은다. sysstat 없이 kind 노드 안의 /proc 만 쓴다
# (kind 노드는 privileged 컨테이너라 호스트/VM 의 블록 장치 통계가 그대로 보인다).
# 사용: scripts/collect.sh start <출력폴더> ; scripts/collect.sh stop <출력폴더>
source "$(dirname "$0")/env.sh"
NODE="${KIND_CLUSTER_NAME:-kind}-control-plane"; d="$2"; mkdir -p "$d"
case "$1" in
start)
  # 1초: 블록 장치 누적 통계, 메모리, IO/메모리 pressure
  docker exec "$NODE" sh -c 'while :; do echo "T $(date +%s.%N)"; cat /proc/diskstats; echo M; grep -E "^(MemTotal|MemAvailable|Dirty|Writeback|Cached|SwapFree):" /proc/meminfo; echo P; cat /proc/pressure/io /proc/pressure/memory 2>/dev/null; sleep 1; done' > "$d/proc_1s.txt" 2>&1 &
  echo $! > "$d/.pid_proc"
  # 5초: snapshot 관련 디렉터리 크기(KB), 객체 저장소(rustfs) 크기, worker 상태
  ( while :; do
      echo "T $(date +%s) node $(docker exec "$NODE" sh -c 'du -sk /var/lib/ate/snapshots /var/lib/ate/snapshot-cache /var/lib/ate/snapshot-scratch /var/lib/ate/actors 2>/dev/null | tr "\n\t" " ="')"
      echo "T $(date +%s) rustfs_kb $(kubectl --context "$KCTX" exec -n ate-system deploy/rustfs -- du -sk /data/ate-snapshots/atespaces 2>/dev/null | cut -f1)"
      sleep 5; done ) > "$d/sizes_5s.txt" 2>&1 &
  echo $! > "$d/.pid_sizes"
  echo "collecting into $d";;
stop)
  for f in "$d"/.pid_*; do kill "$(cat "$f")" 2>/dev/null; rm -f "$f"; done
  pkill -f "docker exec $NODE sh -c while :; do echo \"T" 2>/dev/null
  docker exec "$NODE" sh -c 'pkill -f "cat /proc/diskstats" 2>/dev/null; true'
  echo "stopped";;
esac
