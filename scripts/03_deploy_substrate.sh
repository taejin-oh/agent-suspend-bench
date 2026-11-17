#!/usr/bin/env bash
# Agent Substrate 컨트롤 플레인 설치 (소스에서 ko 빌드). 벤치마크용 권한 두 개를 처음부터 넣는다
# (docs/guides/benchmarking.md "Deploy benchmarks"). 실패하면 ~/.cache/ate-setup/failed/ 에 설정이 남는다.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$SUBSTRATE_DIR"
mkdir -p "$ROOT/bin"
go build -o "$ROOT/bin/ate-setup" ./cmd/ate-setup
go build -o "$ROOT/bin/kubectl-ate" ./cmd/kubectl-ate
{ time env \
  ATE_API_AUTHZ_BOOTSTRAP_OWNERS=system:serviceaccount:ate-system:ate-client,spiffe://cluster.local/ns/benchmarking/sa/default \
  ATE_INGRESS_ALLOWED_SPIFFE_IDS=spiffe://cluster.local/ns/benchmarking/sa/default,spiffe://cluster.local/ns/ate-system/sa/atenet-client \
  ate-setup deploy ate-system --credential-provider='{"name":"k8s.io"}' --rollout-timeout=600s ${ATE_SETUP_EXTRA_ARGS:-}; } 2>&1 | tee "$RESULTS/03_deploy_ate_system.log"
kubectl --context "$KCTX" get pods -A -o wide | tee "$RESULTS/03_pods.txt"
