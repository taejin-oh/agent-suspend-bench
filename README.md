# agent-suspend-bench

다수의 Agent가 활성/비활성을 반복하면서 checkpoint(suspend)를 만들 때 스토리지에 실제로 문제가 생기는지 확인하기 위한 재현 환경입니다.

실제 Agent(LLM)는 돌리지 않습니다. [Agent Substrate](https://github.com/agent-substrate/substrate)의 agent-session 부하 도구가 대본(YAML)대로 CPU·메모리·디스크를 소모하는 가상 Agent를 만듭니다. checkpoint 자체는 gVisor가 실제 메모리를 디스크에 쓰고 객체 저장소(클러스터 안 rustfs)로 올리므로, 스토리지 부담은 실제 값입니다. 외부 클라우드 자원은 쓰지 않습니다.

회사 서버에서 에이전트에게 맡겨 진행할 때는 `AGENTS.md`와 `docs/handoff/HANDOFF.md`(작업 지시서)를 따릅니다.

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

발표 자료는 `docs/presentation/`에 있습니다 (HTML, PDF, PPTX, 슬라이드 원본).

## 실행 순서

```bash
git clone https://github.com/taejin-oh/agent-suspend-bench.git && cd agent-suspend-bench
cp site.env.example site.env          # 서버별 설정: 결과 폴더 이름(HOST_LABEL), 전용 클러스터 이름, 전용 kubeconfig
```

`site.env`가 없으면 기본값(결과 폴더 `<os>-<arch>`, 클러스터 이름 `kind`, `~/.kube/config`)으로 동작합니다.

| # | 명령 | 하는 일 | 확인되는 것 | Mac 기준 소요 |
|---|---|---|---|---|
| 0 | `scripts/00_preflight.sh` | 사전 조건 점검 (읽기 전용) | 위 표의 조건 충족 여부 | 3초 |
| 1 | `scripts/01_setup.sh` | Go 내려받기, substrate를 고정 commit으로 checkout | 외부 통신 | 1분 |
| 2 | `scripts/02_cluster.sh` | kind 클러스터 + 로컬 registry 생성 | Docker에서 Kubernetes가 뜨는가 | 1.5분 |
| 3 | `scripts/03_deploy_substrate.sh` | Agent Substrate 설치 (소스 빌드) | 컨트롤 플레인 pod 전부 Running | 8분 (재실행 4분) |
| 4 | `scripts/04_counter_cycle.sh 3` | actor 1개를 3번 재웠다 깨움 | **suspend/resume이 끝까지 되는가**, 상태 보존, snapshot이 남는 위치와 크기 | 1분 |
| 5 | `scripts/05_deploy_benchmark.sh [대본]` | 가상 Agent 템플릿, worker pool, 부하 생성기 배포 | worker pod Running | 5분 |
| 6 | `scripts/06_run_load.sh <이름> <세션수> <초> [옵션]` | 부하 실행 + 지표 수집 + 요약 | 아래 "결과 읽기" | 실행 시간 + 1분 |

주의: 2번은 같은 이름의 kind 클러스터를 **지우고** 다시 만드는 스크립트입니다. 그래서 같은 이름의 클러스터나 `kind-registry` 컨테이너가 이미 있으면 멈추고, `ASB_RECREATE=1`을 줘야 진행합니다. 클러스터 이름은 `site.env`의 `KIND_CLUSTER_NAME`으로 정합니다. `site.env`에 `KUBECONFIG`를 주지 않으면 `~/.kube/config`에 context가 하나 추가됩니다. 5번은 kubectl의 현재 context가 이 클러스터가 아니면 멈춥니다.

정리: 실행 사이에는 `scripts/cleanup_actors.sh`, 전부 끝나면 `scripts/99_teardown.sh`.

## 부하 실행: 정해 둔 묶음으로 (권장)

```bash
scripts/stage.sh status                              # 진행 상태와 다음에 할 일(NEXT)
scripts/stage.sh plan                                # 단계(T, A~F)별 실행 목록
scripts/bg.sh start stage_A scripts/stage.sh A       # A 단계를 백그라운드로 실행
scripts/bg.sh wait                                   # 끝나거나 240초가 지날 때까지 대기
python3 scripts/report.py                            # 모든 실행을 표로: results/<HOST_LABEL>/REPORT.md
```

`scripts/stage.sh <단계>`는 실행마다 재배포(필요할 때), 가상 Agent 정리, 부하 실행, 판정(`scripts/check_run.py` → `verdict.txt`)을 차례로 합니다. 끝난 실행은 건너뛰므로 중간에 끊겨도 다시 실행하면 이어집니다. 자원이 모자란 실행은 스스로 건너뛰고, 멈춤 판정은 한 번 다시 돌린 뒤 정해진 규칙대로 그 단계를 끝내거나 전체를 멈춥니다. 단계의 뜻과 판정 규칙은 `docs/handoff/HANDOFF.md` 4~5절에 있습니다. 업로드 메모리 한도는 `scripts/upload_budget.sh 2Gi|default|show`로 바꿉니다.

## 부하 실행: 하나씩 직접

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
| worker pod 수. worker 하나가 여러 Agent를 받으므로 동시 활성 수의 상한은 아님 (`docs/workload-patterns.md`) | `WORKER_COUNT=N scripts/05_deploy_benchmark.sh` | 4 |
| Agent 1개의 메모리 한도 | `ACTOR_MEMORY=1536Mi scripts/05_deploy_benchmark.sh` | 512Mi |
| Agent가 하는 일(메모리·디스크·CPU·쉬는 시간) | 대본 YAML. `scripts/05_deploy_benchmark.sh workloads/agent-1g.yaml` | `workloads/smoke-5step.yaml` |
| 전체 Agent 수 | `06_run_load.sh`의 `<세션수>` | |
| 그중 깨어 있는 수 / 초당 교체 수 | `agentsession_awake=N`, `target_rps=R` | |
| 쉬는 시간 배율 | `agentsession_think_scale=0.5` | 1.0 |
| suspend 방식 | `lifecycle_mode=sync`(업로드까지 대기) / `async`(백그라운드 업로드, substrate 기본) | |
| 업로드 메모리 한도 (동시 업로드 수와 압축 병렬도를 함께 정함) | atelet DaemonSet의 objectstore-plugin 인자 `--upload-memory-budget` (아래 "원인 확인" 참고) | 512Mi |

대본이나 worker 수, 메모리를 바꾸면 5번을 다시 실행해야 합니다(`SKIP_BUILD=1`을 주면 이미지 빌드를 건너뜀). 패턴을 조절하는 방법과 패턴별 특징은 `docs/workload-patterns.md`에 정리했습니다.

대본 작성 규칙은 substrate 문서 `docs/guides/benchmarking.md`의 "Writing an agent-session script" 절에 있습니다. `workloads/agent-1g.yaml`은 RAM 640Mi를 쓰는 서버용 대본입니다. Mac에서는 세션 1개로만 2회 돌려 봤습니다(`runs/h_D_s1_*`, 240초): 실패 없음, Actor 하나의 snapshot 약 1 GiB, `SuspendActor` 중앙값 4.4~4.5초. 세션 여러 개와 turnover는 Mac의 메모리가 모자라 돌리지 못했습니다.

## 결과 읽기

실행마다 `results/<HOST_LABEL>/runs/<이름>/`에 다음이 남습니다.

- `summary.txt`: 아래 내용의 요약. 먼저 볼 파일
- `run.txt`: 실행 인자와 시작·종료 시각(UTC), objectstore-plugin 인자
- `stats.json`, `stats.csv`, `failures.csv`: 부하 생성기(Locust)의 원본 통계
- `boomer_worker.log`: 부하 생성기 로그 (turnover 교체 시작 시각이 여기 남는다)
- `phases_raw.jsonl`, `uploads_raw.jsonl`: atelet의 suspend별 구간 기록과 objectstore-plugin의 파일별 업로드 기록 원본 (`scripts/analyze_uploads.py` 입력)
- `proc_1s.txt`: 1초 간격 블록 장치 통계, 메모리, IO/메모리 pressure, CPU 누적 시간 원본
- `sizes_5s.txt`: 5초 간격 노드 로컬 snapshot 폴더와 객체 저장소 크기
- `snapshot_sizes.txt`: 정지 직전의 actor별 snapshot 크기 (노드 로컬, 객체 저장소)
- `summary.txt`의 `load window only` 블록: 부하가 실제로 걸린 구간만의 쓰기량·사용률·초당 suspend 수 (`scripts/window_stats.py`). turnover는 등록과 1분 대기를 뺀 교체 구간
- `phases.txt`: suspend/resume 구간별 시간. substrate가 남기는 "timing breakdown" 로그를 substrate의 `benchmarking/analysis/phase_report.py`로 집계한 것

`summary.txt`의 요청 표에서 볼 행:

| 행 | 의미 |
|---|---|
| `SuspendActor` | 재우기(checkpoint) 한 번에 걸린 시간. `sync`면 객체 저장소 업로드까지 포함 |
| `SuspendActor_Register` | turnover에서 처음 등록할 때의 재우기. 대본 1단계만 돈 상태라 snapshot이 작다 |
| `ResumeActor`, `TimeToWake` | 깨우기에 걸린 시간 (재시도 포함) |
| `Step_*` | 깨어난 뒤 대본의 각 단계가 걸린 시간 |
| `fail` 열 | 실패 수. 오류 문구는 표 아래 `ERROR` 줄 |

스토리지 부분에서 볼 값: 총 쓰기량(`written_MiB_by_device`), 1초 피크(`peak_1s`), 디스크 사용률(`disk_util_pct`, `seconds_over_90`), IO pressure(`psi_io_*`, 커널이 제공할 때만), CPU 사용률과 IO 대기(`cpu_pct_all_cores`), 로컬/객체 저장소 점유량의 최대값.

구간별 시간에서 볼 행: `worker_checkpoint`(sandbox의 메모리·파일을 노드 로컬에 쓰는 구간)와 `persist`(zstd로 압축해 객체 저장소에 올리는 구간). 어느 쪽이 늘어나는지로 병목 위치를 좁힌다.

주의: turnover의 `SuspendActor_Register`는 대본 1단계만 돈 작은 snapshot을 재우는 값이라 `SuspendActor`의 기준값으로 쓸 수 없다. 기준값은 같은 대본을 세션 1개로 돌린 실행(`06_run_load.sh s1_sync 1 120 lifecycle_mode=sync`)에서 얻는다.

**문제가 생기는지 보는 방법:** 세션 수나 `target_rps`를 단계적으로 올리면서 `SuspendActor`·`TimeToWake`의 p95/p99가 기준값 대비 몇 배로 늘어나는지, `fail`이 생기기 시작하는 지점, 그때의 디스크 사용률과 IO pressure를 같이 봅니다.

## Mac(Apple M4, OrbStack VM 10 vCPU / 8 GB)에서 확인한 것

원본은 `results/darwin-arm64/`. 이 숫자는 "끝까지 돈다"는 증거이고, 서버의 성능을 예측하는 값이 아닙니다.

- 설치, counter suspend/resume, 부하 실행 모두 실패 없이 완료 (부하 9회 합계 suspend 1,197회, resume 1,175회)
- counter(메모리 수 MB): suspend 0.25~0.32초, 깨우는 첫 요청 0.10~0.24초
- 같은 대본(`smoke-5step`, worker 4개, sync)으로 겹침 정도만 바꾼 결과 (`runs/r2_*`):

| | 세션 1개 | 세션 4개 | turnover 12개/활성 3개/목표 초당 1개 |
|---|---|---|---|
| `SuspendActor` 중앙값 / p95 | 0.83초 / 1.2초 | 2.7초 / 3.7초 | 8.9초 / 16초 |
| `TimeToWake` 중앙값 / p95 | 0.14초 / 0.58초 | 0.46초 / 1.3초 | 1.6초 / 3.2초 |
| suspend 중 `persist` 비중 (중앙값) | 80% | 88% | 90% |
| 부하 구간 디스크 쓰기 평균 | 104 MiB/s | 232 MiB/s | 231 MiB/s |
| 부하 구간 디스크 사용률 / CPU | 15% / 12% | 33% / 28% | 63% / 39% |

표의 속도와 사용률은 각 `summary.txt`의 `load window only` 블록(`scripts/window_stats.py`) 값입니다.

- turnover의 실제 교체 속도는 초당 약 0.72회였습니다(목표 1회). suspend 1회당 디스크 쓰기는 약 320 MiB로, snapshot 크기(actor당 로컬 157 MiB, 객체 저장소 150 MiB)의 약 2배입니다.
- 늘어난 suspend 시간의 대부분은 `persist`(압축·업로드) 구간이었고, 그때 디스크(평균 63%, 1초 최대 94%)와 CPU(평균 39%)는 평균으로는 포화되지 않았습니다.
- **원인 확인 (`runs/r3_upload2g_*`)**: substrate의 objectstore-plugin은 업로드에 쓰는 메모리를 노드당 512Mi로 제한하고(`--upload-memory-budget`), 넘치면 업로드를 기다리게 합니다. 이 값만 2Gi로 올려 같은 부하를 다시 돌리자 turnover의 `SuspendActor` 중앙값이 8.9초 → 2.3초, p95가 16초 → 7.1초, `persist` 중앙값이 7.2초 → 0.84초가 됐습니다. 세션 4개 실행도 같은 방향입니다(`SuspendActor` 중앙값 2.7초 → 1.6초). 기본값으로 되돌려 다시 돌리자(`runs/r4_default_turnover_12_awake3`) 중앙값이 11초로 돌아갔습니다. 반면 `TimeToWake` 중앙값은 1.6초 → 2.2초로 늘었고, CPU 평균은 39% → 52%, 가용 메모리 최소값은 2.6 GiB → 1.8 GiB가 됐습니다. 교체 속도는 초당 0.72회 → 0.77회로 거의 그대로였습니다. 이 설정은 동시 업로드 수와 업로드 하나의 압축 병렬도를 함께 바꾸므로 둘의 효과는 나누어 보지 못했습니다. turnover에서 한도를 올린 실행은 2회이고 결과가 서로 달랐습니다(아래). 패치를 적용하면 atelet pod가 다시 뜹니다. 실험 방법:

  ```bash
  kubectl -n ate-system patch ds atelet --type=json \
    -p '[{"op":"add","path":"/spec/template/spec/initContainers/0/args/-","value":"--upload-memory-budget=2Gi"}]'
  ```

- **왜 줄어드는가 (`scripts/analyze_uploads.py`, `runs/r4_default_*`와 `runs/r5_upload2g_*`)**: objectstore-plugin은 파일마다 "예산을 얻은 뒤부터의 시간"을 로그로 남기므로, `persist`를 대기와 실제 작업으로 나눌 수 있습니다.
  - snapshot 하나는 파일 7개이고 파일마다 따로 예약합니다(전송 버퍼 160 MiB + 압축 worker 수 × 최대 64 MiB). 예약 합계는 한도 512Mi에서 1,736 MiB(한도의 3.4배), 2Gi에서 2,056 MiB입니다.
  - 512Mi: 동시에 작업 중인 파일 평균 1.0개, 한도가 꽉 찬 시간 92%. `persist` 중앙값 9.5초 중 자기 파일의 실제 작업은 0.8초(파일을 하나씩 처리해도 1.3초)이고 84~90%가 대기였습니다.
  - 2Gi: 첫 1분은 대기가 거의 없고 `persist` 0.4~0.6초, 초당 1회 처리. 그 뒤 동시 업로드가 늘면서 큰 파일의 처리 시간이 0.4초 → 3초대, CPU 35% → 72%, 가용 메모리 2.3 → 1.5 GiB가 됐고, 2분쯤부터 한도가 다시 차서 `persist`가 10초대로 돌아갔습니다. 이 실행의 `SuspendActor` 중앙값은 3.8초, p95는 18초입니다(첫 2Gi 실행은 2.3초 / 7.1초).
  - 사용법: `python3 scripts/analyze_uploads.py results/<HOST_LABEL>/runs/<이름> <예산 MiB>`
- 약 12시간 앞서 같은 조건으로 돌린 첫 실행(`runs/s4_sync`, `runs/turnover_12_awake3`)도 같은 경향입니다(turnover `SuspendActor` 중앙값 9.8초, p95 16초). 이 두 실행에는 CPU·구간별 시간·actor별 snapshot 크기가 없습니다.

## 알려진 한계

- Linux 서버에서는 아직 실행해 보지 않았습니다. 스크립트의 Linux 분기는 작성만 한 상태입니다.
- kind는 노드가 컨테이너 하나라서, snapshot 로컬 쓰기와 객체 저장소(rustfs) 쓰기, 이미지 저장이 모두 Docker 데이터 디스크 하나에 섞입니다. 총 쓰기량은 이 셋의 합입니다. snapshot을 전용 디스크로 분리하려면 kind 설정에 `extraMounts`를 넣어야 하며(substrate `docs/guides/node-storage.md`), 이 저장소에는 아직 없습니다.
- `async` 모드에서는 업로드가 기본 5분 뒤에 시작됩니다. 실행 시간을 그보다 길게 잡지 않으면 객체 저장소 쓰기가 측정 창 밖으로 빠집니다.
- 지표 수집은 kind 노드 안의 `/proc/diskstats`를 읽습니다. 장치는 쓰기량이 가장 많은 것을 자동으로 고르며, `scripts/analyze_io.py <폴더> <장치>`로 지정할 수 있습니다.
- 세션 1개 기준 실행은 한 번만 했습니다. "동시에 진행 중인 suspend 수"는 초당 suspend 수 × 중앙값으로 계산한 어림값입니다.
- 실패 수는 부하 생성기 기준입니다. 깨우기는 생성기가 최대 1분까지 재시도합니다.
- OrbStack VM은 IO pressure(PSI)를 제공하지 않아 Mac 결과에는 `psi_*` 줄이 없습니다.
- macOS에서는 기본 bash(3.2)로 substrate의 벤치마크 스크립트가 돌지 않습니다. bash 4.4 이상을 `toolchain/bash5/bash`에 두면 스크립트가 그것을 먼저 씁니다.

고정한 버전(substrate commit, Go)은 `scripts/env.sh`에 있습니다.
