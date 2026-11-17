#!/usr/bin/env bash
# kind 클러스터 + 로컬 registry(127.0.0.1:5001) 생성. substrate 의 hack/create-kind-cluster.sh 그대로.
# 주의: 같은 이름(KIND_CLUSTER_NAME, 기본 kind)의 기존 kind 클러스터를 지우고 다시 만든다.
#       ~/.kube/config 에 kind-kind context 가 추가된다.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$SUBSTRATE_DIR"
{ time hack/create-kind-cluster.sh; } 2>&1 | tee "$RESULTS/02_kind_create.log"
kubectl --context "$KCTX" get nodes -o wide | tee -a "$RESULTS/02_kind_create.log"
