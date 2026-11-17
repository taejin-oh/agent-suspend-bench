#!/usr/bin/env bash
# 가상 Agent(glutton) 템플릿 + worker pool + Locust(부하 생성기)를 배포한다.
# 사용: scripts/05_deploy_benchmark.sh [대본.yaml]      (기본: workloads/smoke-5step.yaml)
# 환경변수: WORKER_COUNT(기본 4) = 동시에 깨어 있을 수 있는 Agent 수의 상한(worker pod 1개 = 깨어 있는 actor 1개),
#           ACTOR_MEMORY(기본 512Mi) = Agent 1개의 메모리 한도. 대본의 min_actor_memory 이상이어야 한다.
set -euo pipefail
source "$(dirname "$0")/env.sh"
script="$(cd "$(dirname "${1:-$ROOT/workloads/smoke-5step.yaml}")" && pwd)/$(basename "${1:-smoke-5step.yaml}")"
cd "$SUBSTRATE_DIR"
[ -x "$ROOT/bin/boomer-worker" ] || go build -o "$ROOT/bin/boomer-worker" ./cmd/benchmarking/boomer-worker
boomer-worker --check-agentsession-script "$script"
{ time ./benchmarking/deploy_locust.sh --deploy --sandbox-class gvisor \
    --actor-memory "${ACTOR_MEMORY:-512Mi}" --worker-count "${WORKER_COUNT:-4}" ${SKIP_BUILD:+--skip-build}
  time ./benchmarking/locust/deploy.sh --deploy --user-class agentsession --agentsession-script "$script"
} 2>&1 | tee "$RESULTS/05_deploy_benchmark.log"
kubectl --context "$KCTX" get pods -n benchmark-workloads -n benchmarking -o wide || true
kubectl --context "$KCTX" get pods -n benchmarking; kubectl --context "$KCTX" get pods -n benchmark-workloads
