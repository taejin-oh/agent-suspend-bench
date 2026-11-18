#!/usr/bin/env bash
# objectstore-plugin 의 업로드 메모리 한도(--upload-memory-budget)를 바꾼다. 이미 그 값이면 아무것도 하지 않는다.
# 바꾸면 atelet pod 가 다시 뜬다 (약 1분). 부하 실행 중에는 쓰지 말 것.
# 사용: scripts/upload_budget.sh default      (인자를 지워 substrate 기본값 512Mi 로)
#       scripts/upload_budget.sh 2Gi
#       scripts/upload_budget.sh show         (현재 값만 출력)
set -euo pipefail
source "$(dirname "$0")/env.sh"
want="${1:?사용: upload_budget.sh default|show|<크기 예: 2Gi>}"
k() { kubectl --context "$KCTX" -n ate-system "$@"; }
name="$(k get ds atelet -o jsonpath='{.spec.template.spec.initContainers[0].name}')"
[ "$name" = objectstore-plugin ] || { echo "STOP: atelet 의 첫 initContainer 가 objectstore-plugin 이 아니다 ($name). substrate 버전이 달라졌을 수 있다."; exit 3; }
args="$(k get ds atelet -o jsonpath='{.spec.template.spec.initContainers[0].args}')"
cur="$(printf '%s' "$args" | python3 -c 'import json,sys; a=[x.split("=",1)[1] for x in json.load(sys.stdin) if x.startswith("--upload-memory-budget=")]; print(a[-1] if a else "default")')"
echo "upload_memory_budget(now)=$cur"
[ "$want" = show ] && exit 0
[ "$want" = "$cur" ] && { echo "unchanged"; exit 0; }
new="$(printf '%s' "$args" | WANT="$want" python3 -c 'import json,os,sys; w=os.environ["WANT"]; a=[x for x in json.load(sys.stdin) if not x.startswith("--upload-memory-budget=")]; a += [] if w=="default" else ["--upload-memory-budget="+w]; print(json.dumps(a))')"
k patch ds atelet --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/initContainers/0/args\",\"value\":$new}]"
k rollout status ds/atelet --timeout=300s
sleep 10
echo "upload_memory_budget(now)=$want"
