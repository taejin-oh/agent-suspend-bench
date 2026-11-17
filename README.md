# agent-suspend-bench

다수의 Agent가 활성/비활성을 반복하면서 checkpoint(suspend)를 만들 때 스토리지에 실제로 문제가 생기는지 확인하기 위한 재현 환경입니다.

실제 Agent(LLM)는 돌리지 않습니다. [Agent Substrate](https://github.com/agent-substrate/substrate)의 agent-session 부하 도구가 대본(YAML)대로 CPU·메모리·디스크를 소모하는 가상 Agent를 만들고, checkpoint는 gVisor가 실제로 수행합니다.

## 실행 순서

모든 스크립트는 이 폴더 안에서만 작업합니다(Go 툴체인 포함, sudo 불필요). 필요한 것: Docker, kubectl, git, curl, python3.

```bash
scripts/00_preflight.sh         # 사전 조건 확인 (읽기 전용)
scripts/01_setup.sh             # Go 내려받기, substrate 를 고정 commit 으로 checkout
scripts/02_cluster.sh           # kind 클러스터 + 로컬 registry (기존 'kind' 클러스터가 있으면 지움)
scripts/03_deploy_substrate.sh  # Agent Substrate 컨트롤 플레인 설치
```

결과는 `results/<os>-<arch>/`에 쌓입니다. 다른 이름을 쓰려면 `HOST_LABEL=company-server scripts/...`처럼 지정합니다.

고정한 버전은 `scripts/env.sh`에 있습니다.
