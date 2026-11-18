# 기본 제공되는 것과 이 저장소가 추가한 것

이 저장소의 스크립트와 결과에는 두 종류가 섞여 있습니다. Agent Substrate가 원래 제공하는 것(upstream, commit `d283af4e`)과, 그것을 감싸거나 그 위에 이 저장소가 새로 만든 것입니다. 결과를 인용하거나 발표할 때 둘을 구분할 수 있도록 정리했습니다.

기준 문서는 substrate의 `docs/guides/benchmarking.md`입니다. 설치할 때 주는 권한 설정, 배포 스크립트, 부하 종류와 옵션, 대본 형식, 구간별 시간 분석은 모두 이 문서의 절차를 그대로 따랐습니다. 아래 "근거" 열의 절 이름은 그 문서의 것입니다.

## 1. 한눈에 보기

| 구분 | 내용 |
|---|---|
| **substrate 기본 제공** | 재우기·깨우기 기능 자체, 설치 도구, 부하 도구(Locust + boomer)와 부하 종류·옵션, 대본 형식과 내장 대본, 구간별 시간 로그와 집계 도구 |
| **이 저장소가 추가** | 실행 순서를 묶은 스크립트, 사전 점검, 디스크·메모리·CPU 수집과 요약, 업로드 대기 분석, 판정 규칙, 단계 계획(T, A~F), 보고서 생성, 대본 2개, 모든 측정 결과와 그 해석 |

## 2. substrate가 기본 제공하는 것 (이 저장소는 호출만 함)

| 무엇 | substrate에서의 위치 | 이 저장소에서 쓰는 곳 | 근거 |
|---|---|---|---|
| kind 클러스터와 로컬 registry 생성·삭제 | `hack/create-kind-cluster.sh`, `hack/delete-kind-cluster.sh` | `02_cluster.sh`, `99_teardown.sh` | 소스 |
| Substrate 설치 | `cmd/ate-setup` (`deploy ate-system`). 벤치마크용 권한 두 가지(`ATE_API_AUTHZ_BOOTSTRAP_OWNERS`, `ATE_INGRESS_ALLOWED_SPIFFE_IDS`)를 설치할 때 줘야 함 | `03_deploy_substrate.sh` | Deploy benchmarks |
| counter 데모, `kubectl ate` CLI (`suspend actor --mode=sync`, `proxy actor` 등) | `ate-setup deploy demo counter`, `cmd/kubectl-ate` | `04_counter_cycle.sh`, `cleanup_actors.sh` | 소스 |
| 벤치마크 배포 (가상 Agent 템플릿, worker pool, Locust) | `benchmarking/deploy_locust.sh`, `benchmarking/locust/deploy.sh` | `05_deploy_benchmark.sh` | Deploy benchmarks |
| 부하 생성기: Locust(제어) + boomer(Go로 만든 실행기), 가상 Agent 프로그램(glutton) | `benchmarking/locust/`, `cmd/benchmarking/boomer-worker`, `internal/benchmarking/` | 전체 | Running Tests |
| 부하 종류: `agentsession`(일반, turnover), `glutton`, `sweperf`, `resumepaused`, `spawn`, `durdir`, `ate_env` | 위와 같음 | `agentsession`만 사용 | 각 Benchmark 절 |
| 실행 옵션: `lifecycle_mode`, `resume_mode`, `agentsession_awake`, `target_rps`, `agentsession_think_scale` 등 | Locust 옵션 | `06_run_load.sh`의 `key=value` | Agent-Session Configuration Knobs |
| 대본(YAML) 형식, 동작 10종, 검사기 | `boomer-worker --check-agentsession-script` | `05_deploy_benchmark.sh`가 배포 전에 검사 | Writing an agent-session script |
| 내장 대본 3종 (`coding-session` 20단계가 기본, `personal-assistant`, `personal-assistant-light`) | `internal/benchmarking/boomer/agentsession/scripts/` | **쓰지 않음** (3절) | Built-in script variants |
| 결과 표의 행 이름: `SuspendActor`, `SuspendActor_Register`, `ResumeActor`, `TimeToWake`, `WakeFirstTouch`, `Step_*` | boomer가 Locust에 보고 | `summary.txt`의 요청 표 | Agent-Session Reported Metrics |
| turnover에서 등록 구간과 교체 구간을 가르는 로그 `turnover fill done` | boomer 로그 | `window_stats.py`, `analyze_uploads.py`가 이 줄로 구간을 자름 | Analyzing a Turnover Run |
| 재우기·깨우기의 구간별 시간 (`worker_checkpoint`, `persist`, `download`, `worker_restore`) | atelet·worker의 "timing breakdown" 로그, `benchmarking/analysis/phase_report.py` | `06_run_load.sh`가 로그를 모아 이 도구로 집계 → `phases.txt` | Suspend/resume phase breakdown |
| 업로드 메모리 한도 `--upload-memory-budget` (기본 512Mi), 파일별 업로드 로그 `Compressed zstd upload` | objectstore-plugin (`pkg/objectstorage/upload.go`) | `upload_budget.sh`가 값을 바꿈, `analyze_uploads.py`가 로그를 읽음 | 소스 (문서에는 설명 없음) |

## 3. 이 저장소가 추가한 것

| 무엇 | 파일 | 설명 | substrate에 대응하는 것 |
|---|---|---|---|
| 실행 순서 묶음, 버전 고정, 결과 폴더 | `scripts/00~06`, `99`, `env.sh`, `site.env.example` | substrate 명령을 순서대로 부르고 출력을 `results/<HOST_LABEL>/`에 저장. Go를 폴더 안에 내려받음 | 없음 (문서의 절차를 손으로 따라 하는 것이 기본) |
| 사전 점검과 PASS/FAIL | `00_preflight.sh` | cgroup, Docker, 외부 통신, 도구, 디스크, 포트 | 없음 |
| 재우기 3회 반복과 상태 보존 확인 | `04_counter_cycle.sh` | counter 데모를 써서 시간과 snapshot 크기를 기록하고 PASS를 판정 | 데모만 제공. 반복 확인은 추가 |
| 부하 실행을 명령 한 줄로 | `06_run_load.sh` | 웹 UI 대신 Locust의 HTTP API를 호출해 시작·정지·통계 저장 | `runner.py`(자동화 전용. 5절) |
| 디스크·메모리·CPU·IO pressure 수집과 요약 | `collect.sh`, `analyze_io.py` | kind 노드의 `/proc`을 1초 간격으로 읽음. **쓰기량, 디스크 사용률, CPU 사용률, 가용 메모리는 모두 이 수집에서 나온 값** | Prometheus 기반 서버 지표(5절). 디스크 쓰기량과 사용률은 substrate 도구에 없음 |
| 부하 구간만의 통계 | `window_stats.py` | 초당 재우기 수, 재우기 1회당 쓰기량, 진행 중 재우기 수(어림) | `turnover_window.py`(요청 수와 속도만) |
| 업로드 대기와 실제 작업의 분리 | `analyze_uploads.py` | 파일별 업로드 로그와 예약 크기 식(소스에서 옮김)으로 계산 | 없음 |
| 판정 (`OK`/`LIMIT`/`FAILURES`/`RESOURCE`/`BROKEN`) | `check_run.py` | **기준값(목표의 80%, 가용 메모리 1 GiB 등)은 이 저장소가 정한 것**이며 substrate의 합격 기준이 아님 | 없음 |
| 단계 계획 T, A~F와 자동 진행 | `stage.sh`, `bg.sh` | 어떤 조건을 몇 번 돌릴지, 재시도와 건너뛰기 규칙 | 사다리 shape, 야간 자동화(5절) |
| 결과 표 | `report.py` | 실행들을 표 하나로 | 없음 |
| 업로드 한도 전환 | `upload_budget.sh` | DaemonSet을 patch. 옵션 자체는 substrate 것 | 없음 |
| 대본 2개 | `workloads/smoke-5step.yaml`, `workloads/agent-1g.yaml` | substrate의 형식으로 **이 저장소가 쓴 대본**. 모든 측정이 이 둘로 한 것 | 내장 대본 3종 |
| 문서와 발표 자료 | `README.md`, `docs/` | | |
| 측정 결과와 해석 | `results/`, README의 "Mac에서 확인한 것" | "지연의 대부분이 업로드 메모리 한도의 대기"라는 결론 포함. substrate 문서에 있는 내용이 아니라 이 저장소의 측정과 소스 분석으로 얻은 것 | |

## 4. 기본값과 다르게 쓴 설정

결과를 substrate의 기본 동작으로 읽으면 안 되는 부분입니다.

| 항목 | substrate 기본 | 이 저장소 | 이유 |
|---|---|---|---|
| 대본 | `coding-session` (20단계) | `smoke-5step` (5단계, RAM 64Mi), `agent-1g` (RAM 640Mi) | 짧게 돌려도 여러 바퀴가 나오게, 그리고 메모리 크기를 직접 정하려고 |
| 재우기 방식 | `async` (업로드는 5분 뒤) | 대부분 `sync` | 업로드까지 포함한 시간을 재려고. async는 90초 실행 1회뿐 |
| 깨우기 방식 | 문서상 `implicit` | `explicit` | Locust HTTP API로 시작하면 Locust 쪽 기본값이 전달됨 (`docs/workload-patterns.md` 3.2) |
| worker 수 | 1 | 4 | |
| Actor 메모리 한도 | 256Mi | 512Mi / 1536Mi | 대본의 `min_actor_memory`에 맞춤 |
| 격리 방식 | gvisor | gvisor | 같음. microvm은 쓰지 않음 |
| ingress 허용 대상 | 문서 예시는 `benchmarking/default`만 | `ate-system/atenet-client`를 함께 넣음 | router 매니페스트의 기본 허용 대상을 유지하려고 |
| 객체 저장소 | 클러스터 안 rustfs (kind 설치 기본) | 같음 | |

## 5. substrate가 제공하지만 이 저장소가 쓰지 않은 것

| 무엇 | 설명 | 근거 |
|---|---|---|
| `runner.py` (headless 실행) | 웹 UI 없이 실행하고 `stats.jsonl`, `server_summary.json` 등을 남김. 문서가 "자동화 전용, 로컬 진입점이 아님"이라고 밝혀 쓰지 않았음 | Headless (automation only), Benchmark output files |
| Prometheus 기반 서버 지표 | 노드·pod의 pressure, snapshot 크기 분포, atelet이 잰 재우기·깨우기 시간, worker 재시작과 OOM | Server ground truth |
| 밀도 지표 | 코어당·GB당 Actor 수 | Density frontiers |
| 부하 모양 (사다리, 버스트) | 시간에 따라 사용자 수나 `target_rps`를 바꿈 | Analyzing a ResumePaused Ladder Run 등 |
| 다른 부하 종류 | `glutton`, `sweperf`, `resumepaused`, `spawn`, `durdir`, `ate_env` | 각 Benchmark 절 |
| 내장 대본 3종의 부하 실행 | 검사기로 구성만 확인 | Built-in script variants |
| Isolate 모드, 추적(Jaeger) 보기, Grafana, 야간 자동화 | | Isolate Mode, Viewing Traces 등 |

## 6. substrate 문서가 권하지만 이 저장소가 반영하지 않은 것

`docs/guides/benchmarking.md`의 "Running at scale" 절은 규모를 키울 때 부딪히는 한계와 봐야 할 지표를 적어 두었습니다. 이 저장소는 그중 아래 항목을 다루지 않습니다. 서버에서 규모를 키운 결과를 해석할 때 알아야 합니다.

- **Actor crash 수(`ate.actor.crashes`)를 직접 세지 않습니다.** 문서는 "crash는 잡음이 아니라 발견"이라고 합니다. 이 저장소는 부하 생성기의 실패 수와 worker pod 재시작만 봅니다. crash가 요청 실패로 이어지면 `FAILURES`로 잡히지만, 그렇지 않은 crash는 놓칠 수 있습니다.
- **PostgreSQL 연결 수와 probe 시간 제한, kubelet용 CPU 예약, 요청 대기 한도(`--parked-request-budget`)를 조정하지 않습니다.** 문서가 든 예는 노드당 수백~천 개 규모입니다. 이 저장소의 계획은 최대 96개라 그 규모는 아니지만, 더 키울 때는 이 절을 먼저 읽어야 합니다.
- **부하가 걸린 노드에서는 깨우기가 시간 초과로 실패해 Actor가 crash될 수 있다**고 문서가 밝히고 있습니다. 규모를 키웠을 때 깨우기 실패가 나오면 이 설명과 맞춰 봐야 합니다.

부하 생성기는 문서의 권고대로 클러스터 안에서 돕니다. `06_run_load.sh`의 port-forward는 Locust의 제어 API(시작, 정지, 통계 읽기)에만 쓰고, 부하 요청은 지나가지 않습니다.
