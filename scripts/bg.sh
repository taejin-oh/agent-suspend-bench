#!/usr/bin/env bash
# 오래 걸리는 명령을 백그라운드로 돌리고 상태를 확인한다. 명령 실행 시간 제한이 있는 에이전트 환경을 위한 것.
# 한 번에 하나만 돌린다 (부하 실행이 겹치면 측정값이 섞인다).
# 사용: scripts/bg.sh start <이름> <명령> [인자...]    예) scripts/bg.sh start stage_A scripts/stage.sh A
#       scripts/bg.sh status                          BG=RUNNING|DONE|DIED|NONE 과 로그 마지막 몇 줄
#       scripts/bg.sh wait [초=240]                    끝나거나 그 시간이 지날 때까지 기다린 뒤 status 를 출력
#       scripts/bg.sh stop                            실행 중인 작업을 강제로 끝냄 (부하 생성기도 다시 띄움)
source "$(dirname "$0")/env.sh"
dir="$RESULTS/bg"; mkdir -p "$dir"
name="$(cat "$dir/current" 2>/dev/null)"; pidf="$dir/$name.pid"; rcf="$dir/$name.rc"; log="$dir/$name.log"
running() { [ -n "$name" ] && [ ! -f "$rcf" ] && [ -f "$pidf" ] && kill -0 "$(cat "$pidf")" 2>/dev/null; }
status() {
  if [ -z "$name" ]; then echo "BG=NONE"; return; fi
  local el=$(( $(date +%s) - $(cat "$dir/$name.start" 2>/dev/null || date +%s) ))
  if running; then echo "BG=RUNNING name=$name elapsed_s=$el log=$log"
  elif [ -f "$rcf" ]; then echo "BG=DONE name=$name rc=$(cat "$rcf") log=$log"
  else echo "BG=DIED name=$name (종료 코드 없이 사라짐. 로그 확인) log=$log"; fi
  echo "--- 로그 마지막 12줄"; tail -n 12 "$log" 2>/dev/null
}
killtree() { local c; for c in $(pgrep -P "$1" 2>/dev/null); do killtree "$c"; done; kill "$1" 2>/dev/null; }
case "${1:-status}" in
start)
  [ $# -ge 3 ] || { echo "사용: bg.sh start <이름> <명령> [인자...]"; exit 1; }
  if running; then echo "REFUSED: 이미 실행 중인 작업이 있다 ($name). 끝날 때까지 기다린다: scripts/bg.sh wait"; exit 1; fi
  name="$2"; shift 2; rm -f "$dir/$name.rc"; echo $(( $(cat "$dir/$name.count" 2>/dev/null || echo 0) + 1 )) > "$dir/$name.count"; date +%s > "$dir/$name.start"; echo "$name" > "$dir/current"
  cd "$ROOT" && nohup bash -c '"$@"; echo $? > "$0"' "$dir/$name.rc" "$@" > "$dir/$name.log" 2>&1 &
  echo $! > "$dir/$name.pid"
  echo "BG=STARTED name=$name log=$dir/$name.log  (다음: scripts/bg.sh wait)";;
status) status;;
wait)
  end=$(( $(date +%s) + ${2:-240} ))
  while running && [ "$(date +%s)" -lt "$end" ]; do sleep 5; done
  status;;
stop)
  if running; then killtree "$(cat "$pidf")"; echo 143 > "$rcf"; fi
  for f in "$RESULTS"/runs/*/.pid_proc; do [ -f "$f" ] && "$ROOT/scripts/collect.sh" stop "$(dirname "$f")"; done
  pkill -f "port-forward svc/locust -n benchmarking" 2>/dev/null
  kubectl --context "$KCTX" rollout restart deploy/locust -n benchmarking 2>/dev/null
  status;;
*) echo "사용: bg.sh start|status|wait|stop"; exit 1;;
esac
