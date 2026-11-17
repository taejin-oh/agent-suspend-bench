# agent-suspend-bench

다수의 Agent가 활성/비활성을 반복하면서 checkpoint(suspend)를 만들 때 스토리지에 실제로 문제가 생기는지 확인하기 위한 재현 환경입니다.

실제 Agent(LLM)는 돌리지 않습니다. [Agent Substrate](https://github.com/agent-substrate/substrate)의 agent-session 부하 도구가 대본(YAML)대로 CPU·메모리·디스크를 소모하는 가상 Agent를 만듭니다. checkpoint 자체는 gVisor가 실제 메모리를 디스크에 쓰고 객체 저장소(클러스터 안 rustfs)로 올리므로, 스토리지 부담은 실제 값입니다. 외부 클라우드 자원은 쓰지 않습니다.

## 서버에 있어야 하는 것

| 항목 | 조건 |
|---|---|
| OS | Linux, **cgroup v2** (`stat -fc %T /sys/fs/cgroup` → `cgroup2fs`). v1이면 worker가 뜨지 않음 |
| Docker | 데몬 동작, 현재 사용자가 `docker` 명령을 쓸 수 있을 것 |
| 도구 | `kubectl`, `git`, `curl`, `python3`, `tar`, bash 4.4 이상 |
| 외부 통신 | `github.com`, `go.dev`, `proxy.golang.org`, `ghcr.io`, `registry-1.docker.io`, `storage.googleapis.com` |
| 디스크 | Docker 데이터 경로에 여유 60 GB 이상 권장 |
| 포트 | 5001(로컬 registry), 8000, 8089 가 비어 있을 것 |

Go 툴체인은 이 폴더 안(`toolchain/`)에 받으므로 따로 설치하지 않습니다. sudo는 쓰지 않습니다.

`/dev/kvm`은 필요 없습니다(gVisor 방식만 사용). 프록시가 TLS를 가로채는 망이면 이미지 pull과 빌드가 실패합니다. 이 경우는 이 저장소에서 다루지 않았습니다.

## 실행 순서

```bash
git clone https://github.com/taejin-oh/agent-suspend-bench.git && cd agent-suspend-bench
export HOST_LABEL=company-server      # 결과 폴더 이름. 생략하면 <os>-<arch>
```

| # | 명령 | 하는 일 | 확인되는 것 | Mac 기준 소요 |
|---|---|---|---|---|
| 0 | `scripts/00_preflight.sh` | 사전 조건 점검 (읽기 전용) | 위 표의 조건 충족 여부 | 3초 |
| 1 | `scripts/01_setup.sh` | Go 내려받기, substrate를 고정 commit으로 checkout | 외부 통신 | 1분 |
| 2 | `scripts/02_cluster.sh` | kind 클러스터 + 로컬 registry 생성 | Docker에서 Kubernetes가 뜨는가 | 1.5분 |
| 3 | `scripts/03_deploy_substrate.sh` | Agent Substrate 설치 (소스 빌드) | 컨트롤 플레인 pod 전부 Running | 8분 (재실행 4분) |
| 4 | `scripts/04_counter_cycle.sh 3` | actor 1개를 3번 재웠다 깨움 | **suspend/resume이 끝까지 되는가**, 상태 보존, snapshot이 남는 위치와 크기 | 1분 |
| 5 | `scripts/05_deploy_benchmark.sh [대본]` | 가상 Agent 템플릿, worker pool, 부하 생성기 배포 | worker pod Running | 5분 |
| 6 | `scripts/06_run_load.sh <이름> <세션수> <초> [옵션]` | 부하 실행 + 지표 수집 + 요약 | 아래 "결과 읽기" | 실행 시간 + 1분 |

주의: 2번은 이름이 `kind`인 기존 kind 클러스터가 있으면 **지우고** 다시 만듭니다. 있으면 `KIND_CLUSTER_NAME=asb`처럼 다른 이름을 주십시오. `~/.kube/config`에 context가 하나 추가됩니다.

정리: 실행 사이에는 `scripts/cleanup_actors.sh`, 전부 끝나면 `scripts/99_teardown.sh`.

## 부하 실행

```bash
# (A) 일반 모드: 세션 N개가 각자 대본을 돌며 단계 사이마다 suspend
scripts/06_run_load.sh s4_sync 4 120 lifecycle_mode=sync

# (B) turnover 모드: 12개를 만들어 전부 재운 뒤 3개만 깨워 두고, 초당 1개씩 "깨어 있는 것 ↔ 자는 것"을 교체
scripts/cleanup_actors.sh
scripts/06_run_load.sh turnover_12_awake3 12 300 lifecycle_mode=sync agentsession_awake=3 target_rps=1
```

"다수의 Agent가 활성/비활성을 반복"하는 상황은 (B)입니다. turnover는 등록 후 1분을 기다렸다가 교체를 시작하므로 실행 시간은 5분 이상으로 잡으십시오.

### 규모를 키우는 손잡이

| 무엇 | 어디서 | 기본 |
|---|---|---|
| 동시에 깨어 있을 수 있는 Agent 수 (worker pod 수) | `WORKER_COUNT=N scripts/05_deploy_benchmark.sh` | 4 |
| Agent 1개의 메모리 한도 | `ACTOR_MEMORY=1536Mi scripts/05_deploy_benchmark.sh` | 512Mi |
| Agent가 하는 일(메모리·디스크·CPU·쉬는 시간) | 대본 YAML. `scripts/05_deploy_benchmark.sh workloads/agent-1g.yaml` | `workloads/smoke-5step.yaml` |
| 전체 Agent 수 | `06_run_load.sh`의 `<세션수>` | |
| 그중 깨어 있는 수 / 초당 교체 수 | `agentsession_awake=N`, `target_rps=R` | |
| 쉬는 시간 배율 | `agentsession_think_scale=0.5` | 1.0 |
| suspend 방식 | `lifecycle_mode=sync`(업로드까지 대기) / `async`(백그라운드 업로드, substrate 기본) | |

대본이나 worker 수, 메모리를 바꾸면 5번을 다시 실행해야 합니다(`SKIP_BUILD=1`을 주면 이미지 빌드를 건너뜀). `agentsession_awake`는 `WORKER_COUNT` 이하여야 합니다.

대본 작성 규칙은 substrate 문서 `docs/guides/benchmarking.md`의 "Writing an agent-session script" 절에 있습니다. `workloads/agent-1g.yaml`은 RAM 640Mi를 쓰는 서버용 대본으로, 검증기만 통과했고 실행해 보지는 않았습니다.

## 결과 읽기

실행마다 `results/<HOST_LABEL>/runs/<이름>/`에 다음이 남습니다.

- `summary.txt`: 아래 두 표의 요약. 먼저 볼 파일
- `stats.json`, `stats.csv`, `failures.csv`: 부하 생성기(Locust)의 원본 통계
- `proc_1s.txt`: 1초 간격 블록 장치 통계, 메모리, IO/메모리 pressure 원본
- `sizes_5s.txt`: 5초 간격 노드 로컬 snapshot 폴더와 객체 저장소 크기

`summary.txt`의 요청 표에서 볼 행:

| 행 | 의미 |
|---|---|
| `SuspendActor` | 재우기(checkpoint) 한 번에 걸린 시간. `sync`면 객체 저장소 업로드까지 포함 |
| `SuspendActor_Register` | turnover에서 처음 등록할 때의 재우기. 경합이 없을 때의 기준값으로 쓸 수 있음 |
| `ResumeActor`, `TimeToWake` | 깨우기에 걸린 시간 (재시도 포함) |
| `Step_*` | 깨어난 뒤 대본의 각 단계가 걸린 시간 |
| `fail` 열 | 실패 수. 오류 문구는 표 아래 `ERROR` 줄 |

스토리지 부분에서 볼 값: 총 쓰기량(`written_MiB_by_device`), 1초 피크(`peak_1s`), 디스크 사용률(`disk_util_pct`, `seconds_over_90`), IO pressure(`psi_io_*`), 로컬/객체 저장소 점유량의 최대값.

**문제가 생기는지 보는 방법:** 세션 수나 `target_rps`를 단계적으로 올리면서 `SuspendActor`·`TimeToWake`의 p95/p99가 기준값 대비 몇 배로 늘어나는지, `fail`이 생기기 시작하는 지점, 그때의 디스크 사용률과 IO pressure를 같이 봅니다.

## Mac(Apple M4, OrbStack VM 8 GB)에서 확인한 것

원본은 `results/darwin-arm64/`. 이 숫자는 "끝까지 돈다"는 증거이고, 서버의 성능을 예측하는 값이 아닙니다.

- 설치, counter suspend/resume, 부하 두 모드 모두 실패 없이 완료
- counter(메모리 수 MB): suspend 0.2~0.3초, 깨우는 첫 요청 0.1~0.3초. 노드 로컬 4.5 MB → 객체 저장소 2.4 MB(zstd)
- `smoke-5step` 대본의 snapshot은 actor당 약 180 MB (메모리 페이지 약 160 MB + rootfs 약 25 MB)
- turnover 12개/활성 3개/초당 1개 교체, 5분: 깨우기 185회, 재우기 175회, 디스크 쓰기 약 58 GB. 재우기 시간은 등록 시 중앙값 0.8초에서 교체 중 중앙값 5.7초, p95 16초로 늘어남

## 알려진 한계

- Linux 서버에서는 아직 실행해 보지 않았습니다. 스크립트의 Linux 분기는 작성만 한 상태입니다.
- kind는 노드가 컨테이너 하나라서, snapshot 로컬 쓰기와 객체 저장소(rustfs) 쓰기, 이미지 저장이 모두 Docker 데이터 디스크 하나에 섞입니다. 총 쓰기량은 이 셋의 합입니다. snapshot을 전용 디스크로 분리하려면 kind 설정에 `extraMounts`를 넣어야 하며(substrate `docs/guides/node-storage.md`), 이 저장소에는 아직 없습니다.
- `async` 모드에서는 업로드가 기본 5분 뒤에 시작됩니다. 실행 시간을 그보다 길게 잡지 않으면 객체 저장소 쓰기가 측정 창 밖으로 빠집니다.
- 지표 수집은 kind 노드 안의 `/proc/diskstats`를 읽습니다. 장치는 쓰기량이 가장 많은 것을 자동으로 고르며, `scripts/analyze_io.py <폴더> <장치>`로 지정할 수 있습니다.
- macOS에서는 기본 bash(3.2)로 substrate의 벤치마크 스크립트가 돌지 않습니다. bash 4.4 이상을 `toolchain/bash5/bash`에 두면 스크립트가 그것을 먼저 씁니다.

고정한 버전(substrate commit, Go)은 `scripts/env.sh`에 있습니다.
