#!/usr/bin/env bash
# kind 클러스터 + 로컬 registry(127.0.0.1:5001) 생성. substrate 의 hack/create-kind-cluster.sh 그대로.
# 주의: 같은 이름(KIND_CLUSTER_NAME, 기본 kind)의 기존 kind 클러스터를 지우고 다시 만든다.
#       ~/.kube/config 에 kind-kind context 가 추가된다.
set -euo pipefail
source "$(dirname "$0")/env.sh"
node="${KIND_CLUSTER_NAME:-kind}-control-plane"
if { docker inspect "$node" >/dev/null 2>&1 || docker inspect kind-registry >/dev/null 2>&1; } && [ "${ASB_RECREATE:-0}" != 1 ]; then
  found="$(for c in "$node" kind-registry; do docker inspect "$c" >/dev/null 2>&1 && printf "'%s' " "$c"; done)"
  echo "STOP: 컨테이너 ${found}가 이미 있다. 이 스크립트는 이름이 같은 kind 클러스터('$node')가 있으면 지우고 다시 만들고, 'kind-registry' 가 있으면 그것을 그대로 같이 쓴다."
  echo "  (2단계가 이미 성공했는데 이 메시지를 봤다면 다시 만들 필요가 없다. scripts/stage.sh status 를 다시 본다.)"
  echo "  ('kind-registry' 라는 이름은 substrate 스크립트에 고정돼 있어, KIND_CLUSTER_NAME 을 바꿔도 달라지지 않는다.)"
  echo "  이 작업이 만든 것이 맞고 다시 만들어도 되면: ASB_RECREATE=1 scripts/02_cluster.sh"
  echo "  다른 사람의 것이거나 모르겠으면: 멈추고 사용자에게 묻는다 (클러스터 이름은 site.env 의 KIND_CLUSTER_NAME 으로 바꿀 수 있다)"
  exit 3
fi
rm -f "$RESULTS/deployed.txt"      # 새 클러스터에는 벤치마크가 배포돼 있지 않다
cd "$SUBSTRATE_DIR"
{ time hack/create-kind-cluster.sh; } 2>&1 | tee "$RESULTS/02_kind_create.log"
# 노드가 Ready 가 될 때까지 기다린 뒤에 끝낸다 (만든 직후에는 잠깐 NotReady 다).
kubectl --context "$KCTX" wait --for=condition=Ready node --all --timeout=300s | tee -a "$RESULTS/02_kind_create.log"
kubectl --context "$KCTX" get nodes -o wide | tee -a "$RESULTS/02_kind_create.log"
echo "CLUSTER_READY $(date -u +%FT%TZ)" | tee -a "$RESULTS/02_kind_create.log"
