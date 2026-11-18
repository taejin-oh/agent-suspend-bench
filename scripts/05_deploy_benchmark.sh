#!/usr/bin/env bash
# 가상 Agent(glutton) 템플릿 + worker pool + Locust(부하 생성기)를 배포한다.
# 사용: scripts/05_deploy_benchmark.sh [대본.yaml]      (기본: workloads/smoke-5step.yaml)
#       scripts/05_deploy_benchmark.sh builtin          (대본 파일을 주지 않는다: substrate 내장 대본. 기본은 coding-session)
#       USER_CLASS=glutton scripts/05_deploy_benchmark.sh builtin    (substrate 의 기본 부하 종류 glutton)
# 환경변수: WORKER_COUNT(기본 4) = worker pod 수 (worker 하나가 여러 actor 를 받는다. 동시 활성 수의 상한은 아님),
#           ACTOR_MEMORY(기본 512Mi) = Agent 1개의 메모리 한도. 대본의 min_actor_memory 이상이어야 한다.
#           USER_CLASS(기본 agentsession) = 부하 종류. substrate 의 locust/deploy.sh --user-class 로 그대로 전달한다.
set -euo pipefail
source "$(dirname "$0")/env.sh"
USER_CLASS="${USER_CLASS:-agentsession}"
if [ "${1:-}" = builtin ] || [ "$USER_CLASS" != agentsession ]; then script=""
else script="$(cd "$(dirname "${1:-$ROOT/workloads/smoke-5step.yaml}")" && pwd)/$(basename "${1:-smoke-5step.yaml}")"; fi
# substrate 의 배포 스크립트는 kubectl 의 "현재 context" 에 배포한다. 다른 클러스터에 배포되지 않게 확인한다.
cur="$(kubectl config current-context 2>/dev/null)"
if [ "$cur" != "$KCTX" ]; then
  echo "STOP: kubectl 현재 context 가 '$cur' 이다. 이 작업의 클러스터는 '$KCTX' 이다. 다른 클러스터에 배포하지 않도록 멈춘다."
  echo "  site.env 에 KUBECONFIG 가 설정돼 있는지 확인한다 (site.env.example 참고)."; exit 3
fi
cd "$SUBSTRATE_DIR"
[ -x "$ROOT/bin/boomer-worker" ] || go build -o "$ROOT/bin/boomer-worker" ./cmd/benchmarking/boomer-worker
[ -z "$script" ] || boomer-worker --check-agentsession-script "$script"
{ time ./benchmarking/deploy_locust.sh --deploy --sandbox-class gvisor \
    --actor-memory "${ACTOR_MEMORY:-512Mi}" --worker-count "${WORKER_COUNT:-4}" ${SKIP_BUILD:+--skip-build}
  time ./benchmarking/locust/deploy.sh --deploy --user-class "$USER_CLASS" ${script:+--agentsession-script "$script"}
} 2>&1 | tee "$RESULTS/05_deploy_benchmark.log"
kubectl --context "$KCTX" get pods -n benchmark-workloads -n benchmarking -o wide || true
echo "user_class=$USER_CLASS script=$(basename "${script:-builtin}") actor_memory=${ACTOR_MEMORY:-512Mi} worker_count=${WORKER_COUNT:-4}" > "$RESULTS/deployed.txt"
kubectl --context "$KCTX" get pods -n benchmarking; kubectl --context "$KCTX" get pods -n benchmark-workloads
