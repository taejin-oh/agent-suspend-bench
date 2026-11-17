# 모든 스크립트가 source 하는 공통 설정. bash 전용.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 재현을 위해 고정한 버전. 바꾸면 results/ 의 숫자와 비교할 수 없게 됨.
SUBSTRATE_REPO="https://github.com/agent-substrate/substrate.git"
SUBSTRATE_COMMIT="${SUBSTRATE_COMMIT:-d283af4ebaa9aba0bac571a827d3fbc954e2ec9a}"   # main, 2026-11-17
GO_VERSION="${GO_VERSION:-go1.27.4}"                                               # substrate go.mod: go 1.27.0

SUBSTRATE_DIR="$ROOT/src/substrate"
HOST_LABEL="${HOST_LABEL:-$(uname -s | tr '[:upper:]' '[:lower:]')-$(uname -m | sed 's/x86_64/amd64/;s/aarch64/arm64/')}"
RESULTS="$ROOT/results/$HOST_LABEL"
mkdir -p "$RESULTS"

# Go 와 빌드 산출물은 전부 이 저장소 폴더 안에 둔다 (시스템에 설치하지 않음).
export PATH="$ROOT/toolchain/go/bin:$ROOT/bin:$ROOT/gopath/bin:$PATH"
export GOPATH="$ROOT/gopath" GOCACHE="$ROOT/gocache" GOFLAGS=-modcacherw
export ATE_INSTALL_KIND=true
export KO_DOCKER_REPO="${KO_DOCKER_REPO:-localhost:5001}"
KCTX="kind-${KIND_CLUSTER_NAME:-kind}"
