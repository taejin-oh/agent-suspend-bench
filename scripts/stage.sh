#!/usr/bin/env bash
# 미리 정해 둔 부하 실행 묶음(단계)을 차례로 돌리고 실행마다 판정을 남긴다.
# 끝난 실행은 건너뛰므로, 중간에 끊겨도 같은 명령을 다시 실행하면 이어서 한다.
# 사용: scripts/stage.sh status            지금까지의 진행 상태와 다음에 할 일(NEXT). 무엇을 할지 모르면 이것부터
#       scripts/stage.sh plan              단계별 실행 목록과 조건
#       scripts/stage.sh <단계>            그 단계의 남은 실행을 차례로 실행. 오래 걸리므로 scripts/bg.sh start 로 돌린다
#       scripts/stage.sh resume [실행이름]  STOP 상태를 푼다. 사용자가 원인을 해결했다고 확인한 뒤에만 쓴다
source "$(dirname "$0")/env.sh"
NODE="${KIND_CLUSTER_NAME:-kind}-control-plane"; RUNS="$RESULTS/runs"; STOPF="$RESULTS/STOP.txt"
STAGES="${ASB_STAGES:-T A B C D E F}"
SYNC="lifecycle_mode=sync"; TURN() { echo "agentsession_awake=$1 target_rps=$2"; }

# 단계|실행이름|배포|업로드 한도|세션 수|실행 시간(초)|추가 인자
#   T 배관 점검 (짧게)            A Mac 과 같은 조건 + 반복      B 일반 모드에서 겹침 늘리기
#   C turnover 규모 늘리기        D 메모리가 큰 Agent 대본       E async 모드      F 업로드 메모리 한도 비교
PLAN="
T|T_s1|smoke|default|1|90|$SYNC
T|T_turn6|smoke|default|6|180|$SYNC $(TURN 2 1)
A|A_s1_r1|smoke|default|1|180|$SYNC
A|A_s1_r2|smoke|default|1|180|$SYNC
A|A_s1_r3|smoke|default|1|180|$SYNC
A|A_s4_r1|smoke|default|4|180|$SYNC
A|A_s4_r2|smoke|default|4|180|$SYNC
A|A_turn12_r1|smoke|default|12|300|$SYNC $(TURN 3 1)
A|A_turn12_r2|smoke|default|12|300|$SYNC $(TURN 3 1)
A|A_turn12_r3|smoke|default|12|300|$SYNC $(TURN 3 1)
B|B_s8|smoke|default|8|180|$SYNC
B|B_s16|smoke|default|16|180|$SYNC
B|B_s32|smoke|default|32|240|$SYNC
C|C_turn24|smoke|default|24|330|$SYNC $(TURN 6 2)
C|C_turn48|smoke|default|48|360|$SYNC $(TURN 12 4)
C|C_turn96|smoke|default|96|420|$SYNC $(TURN 24 8)
D|D_s1_r1|big|default|1|420|$SYNC
D|D_s1_r2|big|default|1|420|$SYNC
D|D_s4|big|default|4|420|$SYNC
D|D_turn12|big|default|12|420|$SYNC $(TURN 3 1)
E|E_async_s4|smoke|default|4|600|lifecycle_mode=async
E|E_async_turn12|smoke|default|12|900|lifecycle_mode=async $(TURN 3 1)
F|F_2g_turn12_r1|smoke|2Gi|12|300|$SYNC $(TURN 3 1)
F|F_2g_turn12_r2|smoke|2Gi|12|300|$SYNC $(TURN 3 1)
F|F_def_turn12|smoke|default|12|300|$SYNC $(TURN 3 1)
${ASB_EXTRA_PLAN:-}"
PLAN="$(printf '%s\n' "$PLAN" | grep '|')"

# 배포 종류별 값: 대본, Actor 메모리 한도, 깨어 있는 Actor 1개가 쓰는 메모리 어림(MiB), Actor 1개의 snapshot 이 차지하는 디스크 어림(MiB)
spec() { case "$1" in
  smoke) echo "workloads/smoke-5step.yaml 512Mi 200 700";;
  big)   echo "workloads/agent-1g.yaml 1536Mi 1500 4500";;
  *)     echo "";; esac; }
verdict_of() { sed -n 's/^VERDICT=//p' "$1/verdict.txt" 2>/dev/null | head -1; }
stopping() { case "$1" in BROKEN|RESOURCE|FAILURES) return 0;; *) return 1;; esac; }
row_state() {   # 실행 하나의 상태를 한 단어로
  local out="$RUNS/$1"
  if [ -f "$out/SKIPPED.txt" ]; then echo SKIPPED; elif [ -f "$out/verdict.txt" ]; then verdict_of "$out"; elif [ -d "$out" ]; then echo PARTIAL; else echo PENDING; fi; }
row_final() { case "$(row_state "$1")" in OK|LIMIT|SKIPPED) return 0;; PENDING|PARTIAL) return 1;; *) [ -d "$RUNS/$1.bad1" ];; esac; }
stop_all() { echo "$*" | tee "$STOPF"; echo "STOP: 여기서 멈춘다. 다음에 할 일은 scripts/stage.sh status 가 알려 준다."; exit 2; }

bad_pods() { kubectl --context "$KCTX" get pods -n "$1" --no-headers 2>/dev/null | awk '$3!="Running" && $3!="Completed"' | wc -l | tr -d ' '; }
healthy() {
  kubectl --context "$KCTX" get nodes --no-headers 2>/dev/null | grep -qw Ready || return 1
  [ "$(bad_pods ate-system)" = 0 ] && [ "$(bad_pods benchmark-workloads)" = 0 ]; }
wait_healthy() { local i; for i in $(seq 1 30); do healthy && return 0; sleep 10; done; return 1; }

ensure_deploy() {   # $1 = 배포 종류
  set -- $(spec "$1"); local want="script=$(basename "$1") actor_memory=$2 worker_count=${WORKER_COUNT:-4}"
  [ "$(cat "$RESULTS/deployed.txt" 2>/dev/null)" = "$want" ] && return 0
  echo "## 벤치마크 배포를 바꾼다: $want"
  [ -f "$RESULTS/deployed.txt" ] && "$ROOT/scripts/cleanup_actors.sh" >/dev/null 2>&1
  if [ -f "$RESULTS/deployed.txt" ]; then export SKIP_BUILD=1; else unset SKIP_BUILD; fi
  ACTOR_MEMORY="$2" "$ROOT/scripts/05_deploy_benchmark.sh" "$ROOT/$1" > "$RESULTS/05_deploy_last.log" 2>&1 \
    || { tail -n 20 "$RESULTS/05_deploy_last.log"; return 1; }
  [ "$(cat "$RESULTS/deployed.txt" 2>/dev/null)" = "$want" ]; }

guard() {   # 자원이 모자라면 이유를 출력하고 1 을 돌려준다. $1=배포 $2=한도 $3=세션 수 $4=추가 인자
  set -- $(spec "$1") "$2" "$3" "$4"; local ram="$3" disk="$4" budget="$5" users="$6" extra="$7"
  local awake; awake="$(printf '%s' "$extra" | sed -n 's/.*agentsession_awake=\([0-9]*\).*/\1/p')"; [ -n "$awake" ] || awake="$users"
  local mem_av disk_free need_mem need_disk
  mem_av="$(docker exec "$NODE" awk '/MemAvailable/{print int($2/1024)}' /proc/meminfo)"
  disk_free="$(docker exec "$NODE" df -Pm /var/lib/ate | awk 'NR==2{print $4}')"
  need_mem=$(( awake * ram )); [ "$budget" = default ] || need_mem=$(( need_mem + 1024 ))
  need_disk=$(( users * disk + 10240 ))
  if [ $(( need_mem * 10 )) -gt $(( mem_av * 7 )) ]; then echo "메모리 부족: 필요 약 ${need_mem} MiB, 가용 ${mem_av} MiB 의 70% 초과"; return 1; fi
  if [ "$need_disk" -gt "$disk_free" ]; then echo "디스크 부족: 필요 약 ${need_disk} MiB, 여유 ${disk_free} MiB"; return 1; fi
  return 0; }

do_run() {   # 반환: 0 실행함, 10 자원 부족으로 건너뜀
  local name="$1" sp="$2" budget="$3" users="$4" dur="$5" extra="$6" out="$RUNS/$1" why
  [ -n "$(spec "$sp")" ] || stop_all "계획표의 배포 종류 '$sp' 를 모른다 (실행 $name). smoke 또는 big 이어야 한다."
  wait_healthy || stop_all "클러스터 상태 이상: 5분을 기다려도 ate-system / benchmark-workloads 의 pod 가 모두 Running 이 아니다 (실행 $name 직전)."
  ensure_deploy "$sp" || stop_all "벤치마크 배포 실패 (실행 $name 직전). 로그: $RESULTS/05_deploy_last.log"
  "$ROOT/scripts/upload_budget.sh" "$budget" || stop_all "업로드 한도 변경 실패 (실행 $name 직전)."
  wait_healthy || stop_all "클러스터 상태 이상: 배포/설정 변경 뒤 pod 가 Running 으로 돌아오지 않는다 (실행 $name 직전)."
  if ! why="$(guard "$sp" "$budget" "$users" "$extra")"; then mkdir -p "$out"; echo "$why" > "$out/SKIPPED.txt"; echo "SKIP $name: $why"; return 10; fi
  "$ROOT/scripts/cleanup_actors.sh" >/dev/null 2>&1
  echo "## $(date -u +%FT%TZ) 실행 $name (세션 $users, ${dur}초, $extra)"
  "$ROOT/scripts/06_run_load.sh" "$name" "$users" "$dur" $extra > "$out.log" 2>&1
  mv "$out.log" "$out/run_output.log" 2>/dev/null
  python3 "$ROOT/scripts/check_run.py" "$out"; }

run_stage() {
  local st="$1" rows; rows="$(printf '%s\n' "$PLAN" | awk -F'|' -v s="$st" '$1==s')"
  [ -n "$rows" ] || { echo "모르는 단계: $st (있는 단계: $STAGES)"; exit 1; }
  [ -f "$STOPF" ] && { echo "STOP 상태다: $(cat "$STOPF")"; echo "사용자가 원인을 해결한 뒤 scripts/stage.sh resume 으로 푼다."; exit 2; }
  mkdir -p "$RUNS"; local ended=""
  while IFS='|' read -r s name sp budget users dur extra <&3; do
    local out="$RUNS/$name"
    if [ -n "$ended" ]; then [ -d "$out" ] || { mkdir -p "$out"; echo "$ended" > "$out/SKIPPED.txt"; }; continue; fi
    while :; do
      case "$(row_state "$name")" in
        OK|LIMIT|SKIPPED) break;;
        PENDING) do_run "$name" "$sp" "$budget" "$users" "$dur" "$extra";;
        PARTIAL) mv "$out" "$out.partial-$(date +%s)";;
        *) v="$(verdict_of "$out")"
           if [ ! -d "$out.bad1" ]; then echo "## $name 판정 $v → 한 번 다시 실행한다"; mv "$out" "$out.bad1"; sleep 30
           elif [ "$v" = BROKEN ] || [ "$st" = T ] || [ "$st" = A ]; then
             stop_all "실행 $name 이 두 번 연속 $v ($(sed -n 's/^reason=//p' "$out/verdict.txt"))."
           else ended="앞 실행 $name 이 두 번 연속 $v 여서 $st 단계를 여기서 끝냄"; echo "## $ended"; break; fi;;
      esac
    done
  done 3<<EOF
$rows
EOF
  python3 "$ROOT/scripts/report.py" "$RESULTS" >/dev/null && echo "보고서: $RESULTS/REPORT.md"
  echo "STAGE_DONE=$st"; }

show_plan() { printf '%-3s %-18s %-6s %-8s %5s %5s  %s\n' 단계 실행 배포 한도 세션 초 "추가 인자"
  printf '%s\n' "$PLAN" | while IFS='|' read -r s n sp b u d e; do printf '%-3s %-18s %-6s %-8s %5s %5s  %s\n' "$s" "$n" "$sp" "$b" "$u" "$d" "$e"; done; }

status() {
  local next="" p0 p1 p2 p3 p4
  echo "== 설정: host_label=$HOST_LABEL cluster=$KCTX site.env=$([ -f "$ROOT/site.env" ] && echo 있음 || echo "없음(기본값)") 단계=$STAGES"
  echo "== 준비 단계"
  if grep -q '^PREFLIGHT=PASS' "$RESULTS/00_preflight.txt" 2>/dev/null; then p0=done; elif grep -q '^PREFLIGHT=FAIL' "$RESULTS/00_preflight.txt" 2>/dev/null; then p0=FAIL; else p0=todo; fi
  { [ -x "$ROOT/toolchain/go/bin/go" ] && [ -d "$SUBSTRATE_DIR/.git" ] && [ -f "$RESULTS/01_substrate_commit.txt" ]; } && p1=done || p1=todo
  kubectl --context "$KCTX" get nodes --no-headers 2>/dev/null | grep -qw Ready && p2=done || p2=todo
  { [ "$p2" = done ] && [ -f "$RESULTS/03_pods.txt" ] && kubectl --context "$KCTX" -n ate-system get ds atelet >/dev/null 2>&1 && [ "$(bad_pods ate-system)" = 0 ]; } && p3=done || p3=todo
  grep -q '^PASS' "$RESULTS/04_counter_cycle.txt" 2>/dev/null && p4=done || p4=todo
  echo "[$p0] 0 사전 점검      scripts/00_preflight.sh"
  echo "[$p1] 1 도구 준비      scripts/01_setup.sh"
  echo "[$p2] 2 클러스터       scripts/02_cluster.sh"
  echo "[$p3] 3 Substrate 설치 scripts/03_deploy_substrate.sh"
  echo "[$p4] 4 재우기 확인    scripts/04_counter_cycle.sh 3"
  if [ "$p0" = todo ]; then next="scripts/00_preflight.sh"
  elif [ "$p0" = FAIL ]; then next="STOP: 사전 점검이 FAIL 이다. $RESULTS/00_preflight.txt 맨 아래의 FAIL 줄을 사용자에게 그대로 전달한다. (고친 뒤에는 scripts/00_preflight.sh 를 다시 실행)"
  elif [ "$p1" = todo ]; then next="scripts/bg.sh start step1 scripts/01_setup.sh"
  elif [ "$p2" = todo ]; then next="scripts/bg.sh start step2 scripts/02_cluster.sh"
  elif [ "$p3" = todo ]; then next="scripts/bg.sh start step3 scripts/03_deploy_substrate.sh"
  elif [ "$p4" = todo ]; then next="scripts/bg.sh start step4 scripts/04_counter_cycle.sh 3"; fi
  echo "== 부하 단계 (판정: OK 정상 / LIMIT 처리 한계 / FAILURES 요청 실패 / RESOURCE 자원 위험 / BROKEN 실행 불량)"
  local st name sp b u d e state pending
  for st in $STAGES; do
    pending=""
    while IFS='|' read -r s name sp b u d e; do
      [ "$s" = "$st" ] || continue
      state="$(row_state "$name")"; row_final "$name" || pending=1
      case "$state" in
        SKIPPED) state="건너뜀: $(head -1 "$RUNS/$name/SKIPPED.txt")";;
        PENDING) state="(아직 안 함)";; PARTIAL) state="(중단된 실행. 다시 돌리면 새로 한다)";;
      esac
      [ -d "$RUNS/$name.bad1" ] && state="$state  [1차 시도: $(verdict_of "$RUNS/$name.bad1")]"
      printf '  %-2s %-18s %s\n' "$st" "$name" "$state"
    done <<EOF
$PLAN
EOF
    [ -z "$next" ] && [ -n "$pending" ] && next="scripts/bg.sh start stage_$st scripts/stage.sh $st"
  done
  [ -z "$next" ] && next="모든 단계가 끝났다. python3 scripts/report.py 를 실행하고 docs/handoff/HANDOFF.md 의 '끝났을 때' 절대로 보고한다."
  [ -f "$STOPF" ] && next="STOP: $(cat "$STOPF") → docs/handoff/HANDOFF.md 의 '멈췄을 때' 절을 따른다. 스스로 풀지 않는다."
  local bg; bg="$("$ROOT/scripts/bg.sh" status | head -1)"; echo "== 백그라운드 작업: $bg"
  case "$bg" in
    BG=RUNNING*) next="scripts/bg.sh wait    (실행 중인 작업이 끝날 때까지 다른 명령으로 클러스터를 건드리지 않는다)";;
    BG=DONE*rc=0*|BG=NONE) ;;
    *) case "$next" in STOP*) ;; *) local n; n="$(printf '%s' "$bg" | sed -n 's/.*name=\([^ ]*\).*/\1/p')"
         if [ "$(cat "$RESULTS/bg/$n.count" 2>/dev/null || echo 0)" -ge 2 ]; then next="STOP: 백그라운드 작업 $n 이 2번 실패했다. $RESULTS/bg/$n.log 의 마지막 30줄을 사용자에게 전달한다."
         else echo "   직전 작업 $n 이 실패했다. 로그($RESULTS/bg/$n.log)의 오류를 docs/handoff/HANDOFF.md 의 '자주 나는 문제' 표에서 찾아 조치한 뒤 아래 NEXT 를 실행한다. 표에 없으면 멈추고 보고한다."; fi;; esac;;
  esac
  echo "NEXT: $next"; }

case "${1:-status}" in
  status) status;;
  plan) show_plan;;
  resume) rm -f "$STOPF" "$RESULTS"/bg/*.count; [ -n "${2:-}" ] && for d in "$RUNS/$2" "$RUNS/$2.bad1"; do [ -d "$d" ] && mv "$d" "$d.old-$(date +%s)"; done; echo "STOP 상태를 풀었다."; status;;
  *) run_stage "$1";;
esac
