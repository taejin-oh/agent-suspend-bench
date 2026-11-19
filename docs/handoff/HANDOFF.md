# 서버 검증 핸드오프

이 문서는 회사 Linux 서버에서 이 저장소의 검증을 이어서 진행하는 에이전트를 위한 작업 지시서입니다. 이 문서와 저장소만 보고 진행할 수 있게 썼습니다. 앞선 대화 내용은 몰라도 됩니다.

문서가 깁니다. 처음에는 1~4절을 읽고 시작하고, 나머지 절은 해당 상황이 생겼을 때 찾아 읽으면 됩니다.

## 1. 무슨 작업인가

**알고 싶은 것.** Agent를 많이 띄워 놓고 "깨어 있음 ↔ 잠듦"을 계속 반복시키면, 재울 때마다 만드는 checkpoint(메모리와 파일을 디스크와 객체 저장소에 저장한 것) 때문에 스토리지나 다른 자원에 실제로 문제가 생기는가.

**방법.** [Agent Substrate](https://github.com/agent-substrate/substrate)라는 오픈소스를 서버 안의 kind 클러스터(Docker 컨테이너 하나로 만든 Kubernetes)에 설치하고, 그 부하 도구로 가상 Agent를 만들어 재우기(suspend)와 깨우기(resume)를 반복합니다. 실제 LLM은 쓰지 않고, 외부 클라우드 자원도 쓰지 않습니다.

**지금까지 된 것.** Mac(10 vCPU / 8 GB 가상 머신)에서 설치부터 부하 실행까지 실패 없이 끝냈습니다. 결과는 `results/darwin-arm64/`, 요약은 `README.md`에 있습니다.

**남은 것(이 핸드오프의 범위).** 같은 절차를 회사 Linux 서버에서 돌려 결과를 얻는 것입니다. Linux에서는 아직 한 번도 돌려 보지 않았습니다. 스크립트의 Linux 부분은 작성만 된 상태이므로, 처음 보는 오류가 날 수 있습니다.

**이 작업이 끝난 상태.** `scripts/stage.sh status`가 "모든 단계가 끝났다"고 하거나 STOP을 알리고, 그 내용을 9절의 형식으로 사용자에게 보고한 상태입니다.

## 2. 반드시 지킬 것

각 규칙에는 이유가 있습니다. 규칙에 없는 상황에서는 이유를 보고 판단하되, 확신이 없으면 멈추고 사용자에게 묻습니다.

1. **숫자는 파일에 있는 것만 씁니다.** 측정값을 기억이나 짐작으로 쓰지 않습니다. 보고할 숫자는 `results/<HOST_LABEL>/REPORT.md`와 각 실행 폴더의 `summary.txt`에서 그대로 옮깁니다. 이 결과는 대외 발표 자료에 들어갑니다. 틀린 숫자 하나가 전체 신뢰를 떨어뜨립니다.
2. **실행하지 않은 것을 했다고 쓰지 않습니다.** 건너뛴 것, 실패한 것, 확인하지 못한 것은 그대로 적습니다.
3. **오래 걸리는 명령은 `scripts/bg.sh start`로 돌립니다.** 설치는 10분 가까이, 부하 단계는 수십 분이 걸립니다. 직접 실행하면 명령 시간 제한에 걸려 중간에 끊깁니다.
4. **부하가 도는 동안에는 클러스터를 건드리는 다른 명령을 실행하지 않습니다.** 측정값이 섞입니다. 기다릴 때는 `scripts/bg.sh wait`만 씁니다. 파일을 읽는 것은 괜찮습니다.
5. **STOP이 나오면 멈춥니다.** 스스로 우회하지 않습니다. 8절을 따릅니다.
6. **다음은 하지 않습니다.** 사용자가 분명히 지시한 경우만 예외입니다.
   - `sudo`, 시스템 설정 변경(sysctl, Docker 데몬 설정, 방화벽, 프록시 설정). 회사 서버의 설정은 이 작업의 권한 밖입니다.
   - TLS 검증 끄기, 인증서 검사 우회, 출처가 불분명한 미러나 이미지 사용.
   - 이 작업이 만들지 않은 Docker 컨테이너·kind 클러스터·Kubernetes 자원을 지우거나 바꾸기. 서버를 다른 사람이 함께 쓸 수 있습니다.
   - `git commit`, `git push`. 회사 서버의 결과를 외부 저장소에 올려도 되는지는 사용자가 정합니다.
   - `scripts/99_teardown.sh`(클러스터 삭제). 사용자가 추가 실행을 원할 수 있습니다.
   - `src/substrate/` 아래 소스 수정, `scripts/env.sh`의 고정 버전 변경. 바꾸면 Mac 결과와 비교할 수 없게 됩니다.
   - `scripts/stage.sh`의 계획표에 없는 조건을 지어내서 실행하기. 추가 실행이 필요하면 6.3절의 방법을 씁니다.
7. **`scripts/env.sh`를 셸에서 직접 `source`하지 않습니다.** bash 전용이라 다른 셸에서는 경로가 틀어집니다. 항상 `scripts/` 안의 스크립트를 실행합니다.
8. **비밀 값(비밀번호, 토큰, 프록시 계정)을 파일이나 보고에 적지 않습니다.** 필요하면 사용자가 직접 입력하게 합니다.

## 3. 시작

저장소 주소는 `https://github.com/taejin-oh/agent-suspend-bench.git`입니다. 지금 있는 폴더에 `scripts/stage.sh`가 있으면 그 폴더가 저장소이고, 경로를 따로 물을 필요가 없습니다. 없으면 아래 명령으로 받습니다.

```bash
git clone https://github.com/taejin-oh/agent-suspend-bench.git && cd agent-suspend-bench
```

비공개 저장소라 인증이 필요합니다. 인증을 요구하며 실패하면 멈추고 사용자에게 받아 달라고 요청합니다. 토큰이나 비밀번호를 직접 입력하지 않습니다.

저장소 폴더에서 한 번만 합니다.

```bash
[ -f site.env ] || cp site.env.example site.env
cat site.env
```

`site.env`는 이 서버용 설정입니다. 기본값은 결과 폴더 `results/company-server/`, 클러스터 이름 `asb`, 이 폴더 안의 전용 kubeconfig입니다. 전용 kubeconfig를 쓰는 이유는 서버에 이미 있는 다른 클러스터 설정을 건드리지 않고, 다른 클러스터에 잘못 배포하지 않기 위해서입니다. 사용자가 10절의 표에 적어 준 값이 있으면 `site.env`에 반영합니다. 없으면 기본값으로 진행합니다.

## 4. 진행 방법: 이 순서만 반복합니다

```
1) scripts/stage.sh status 를 실행한다
2) 맨 아래 NEXT 줄을 읽는다
   - 명령이면            → 그 명령을 글자 그대로 실행한다 (짧아 보여도 bg.sh 를 빼고 직접 실행하지 않는다)
   - "scripts/bg.sh wait" → 실행하고, 끝날 때까지 반복한다
   - "STOP: ..."         → 8절로 간다
   - "모든 단계가 끝났다" → 9절로 간다
3) 1)로 돌아간다
```

무엇을 하고 있었는지 모르겠을 때도 `scripts/stage.sh status`를 실행하면 됩니다. 진행 상태는 전부 `results/<HOST_LABEL>/` 아래 파일에 남으므로, 대화가 끊기거나 새로 시작해도 이어서 할 수 있습니다.

### 명령

| 명령 | 하는 일 |
|---|---|
| `scripts/stage.sh status` | 진행 상태와 다음에 할 일. 아무것도 바꾸지 않음 |
| `scripts/stage.sh plan` | 단계별 실행 목록과 조건 |
| `scripts/bg.sh start <이름> <명령>` | 명령을 백그라운드로 실행. 이미 도는 것이 있으면 거부함 |
| `scripts/bg.sh wait [초]` | 끝나거나 그 시간(기본 240초)이 지날 때까지 기다린 뒤 상태 출력. 명령 시간 제한이 240초보다 짧으면 더 작은 값을 준다 (예: `scripts/bg.sh wait 100`) |
| `scripts/bg.sh status` | 백그라운드 작업 상태와 로그 마지막 12줄 |
| `python3 scripts/report.py` | 모든 실행을 표로 모아 `results/<HOST_LABEL>/REPORT.md` 생성 |

`scripts/bg.sh wait`의 첫 줄 읽는 법:

| 첫 줄 | 뜻 | 할 일 |
|---|---|---|
| `BG=RUNNING` | 아직 도는 중 | `scripts/bg.sh wait`를 다시 실행 |
| `BG=DONE ... rc=0` | 정상 종료 | `scripts/stage.sh status` |
| `BG=DONE ... rc=`(0이 아님) | 실패 또는 STOP | `scripts/stage.sh status`. 안내가 나온다 |
| `BG=DIED` | 프로세스가 사라짐(서버 재시작 등) | `scripts/stage.sh status`. 같은 단계를 다시 시작하면 끝난 실행은 건너뛰고 이어서 한다 |

### 준비 단계 (0~4)

| # | 스크립트 | 하는 일 | 성공의 기준 | Mac에서 걸린 시간 |
|---|---|---|---|---|
| 0 | `00_preflight.sh` | 서버 조건 점검. 아무것도 바꾸지 않음 | 마지막 줄 `PREFLIGHT=PASS` | 3초 |
| 1 | `01_setup.sh` | Go를 이 폴더 안에 내려받고 substrate 소스를 고정 버전으로 받음 | `substrate d283af4e...` 줄 출력 | 1분 |
| 2 | `02_cluster.sh` | kind 클러스터와 로컬 이미지 저장소(registry) 생성. 노드가 Ready가 될 때까지 기다림 | 마지막 줄 `CLUSTER_READY` | 1.5분 |
| 3 | `03_deploy_substrate.sh` | Agent Substrate 설치 (소스에서 빌드) | `ate-system`의 pod가 전부 `Running` | 8분 |
| 4 | `04_counter_cycle.sh 3` | Actor 하나를 3번 재웠다 깨움 | `PASS:` 줄 | 1분 |

준비 단계는 한 번 성공하면 다시 실행하지 않습니다. status의 "클러스터 상태" 줄에 Ready가 아닌 노드나 Running이 아닌 pod가 보여도 재설치하지 않고, 1분 뒤 status를 다시 봅니다.

`WARN:` 줄은 진행을 막지 않습니다. 내용을 읽고 보고에 포함합니다. `FAIL:` 줄이 있으면 `PREFLIGHT=FAIL`이 되고 status가 STOP을 알립니다.

### 부하 단계 (S, T, A~G)

**순서의 원칙: substrate가 기본 제공하는 시나리오(S)를 먼저 돌리고, 이 저장소가 정한 조건(T 이하)은 그 뒤에 돌립니다.** 처음부터 임의의 설정으로 측정하면 결과의 신뢰도가 떨어지기 때문입니다. S 단계의 값은 바꾸지 않습니다. 보고할 때도 두 묶음을 섞지 않습니다(`REPORT.md`가 두 표로 나눠 줍니다).

`scripts/stage.sh <단계>` 하나가 그 단계의 실행을 차례로 돌립니다. 실행마다 가상 Agent 정리 → 부하 실행 → 지표 수집 → 판정을 자동으로 합니다. 대본이나 설정이 달라지는 단계에서는 재배포도 자동으로 합니다.

| 단계 | 확인하는 것 | 실행 | Mac 기준 소요 |
|---|---|---|---|
| **S** | **substrate 기본 제공 시나리오.** 이 서버에서 substrate가 자기 기준 시험을 실패 없이 도는가, 그때의 재우기·깨우기 시간 | `S_glutton_*` 11개: substrate 야간 시험 목록의 gVisor glutton 항목 그대로(사용자 1·5·10명, 메모리 1Gi·2Gi, 15명 초과 배정. 각 1~2분). `S_coding_*` 2개: 문서의 기본 실행(내장 대본 `coding-session`, 세션 1개와 4개, 각 5분) | 약 50분 (첫 배포 5분 포함) |
| T | 자체 조건의 배관 점검. 자체 대본과 turnover가 이 서버에서 끝까지 도는가 | 세션 1개 90초, turnover 6개 180초 | 약 8분 |
| A | Mac과 같은 조건. 서버와 Mac의 차이, 같은 조건을 반복했을 때의 흔들림 | 세션 1개 ×3, 세션 4개 ×2, turnover 12개(활성 3, 초당 1) ×3 | 약 40분 |
| B | 일반 모드에서 동시에 일하는 Agent 수를 늘림 | 세션 8, 16, 32 | 약 15분 |
| C | turnover 규모를 늘림. **이 작업의 원래 질문에 가장 가까운 단계** | 24개(활성 6, 초당 2), 48개(12, 4), 96개(24, 8) | 약 25분 |
| D | 메모리가 큰 Agent(약 640 MiB)로 snapshot 크기를 키움 | 세션 1개 ×2, 세션 4개, turnover 12개 (각 7분) | 약 35분 |
| E | async 모드(업로드를 나중에 하는 substrate 기본 방식) | 세션 4개 10분, turnover 12개 15분 | 약 30분 |
| F | 업로드 메모리 한도를 2Gi로 올렸을 때의 차이 (Mac에서 찾은 지연 원인의 재확인) | 2Gi ×2, 기본값 ×1 | 약 25분 |
| G | **자리가 모자란 환경.** worker 1개의 메모리를 5Gi로 제한해 깨어 있을 수 있는 수를 작게 고정하고, 재우기 방식에 따라 받을 수 있는 Agent 수가 어떻게 달라지는지 봄. 설계는 `docs/capacity-eval.md` | 재우지 않음 ×2(세션 8, 16), sync·async·sync+2Gi 각각 세션 8, 16, 32, 48, 64 | Mac에서는 작은 규모로만 확인. 서버에서 약 2~3시간 |

S 단계의 출처: `S_glutton_*`은 substrate의 `benchmarking/automation/tests.yaml`에 있는 항목과 이름, 사용자 수, worker 수, Actor 메모리, 실행 시간, 옵션이 같습니다(microVM 항목만 뺐습니다). **glutton**은 substrate의 기본 부하 종류로, 가상 사용자 하나가 "깨우기 → (메모리 채우기) → ping → 재우기 → 잠깐 대기"를 반복합니다. `_pause`가 붙은 항목은 async 재우기입니다. `S_coding_*`은 substrate 문서(`docs/guides/benchmarking.md`의 Agent-Session Benchmark 절)의 기본 실행 명령을 따른 것이고, 세션 수와 실행 시간은 문서에 없어 이 저장소가 정했습니다. 실행 방법(Locust API 호출)과 지표 수집, 판정은 S 단계에서도 이 저장소의 것입니다.

T 이하 단계는 이 저장소가 쓴 대본(`workloads/smoke-5step.yaml`, `workloads/agent-1g.yaml`)과 이 저장소가 정한 조건입니다.

**G 단계는 다른 단계와 세 가지가 다릅니다.**

1. `FAILURES` 판정이 나오는 것이 정상입니다. 자리가 모자라 깨우기가 실패하는 지점을 찾는 단계이기 때문입니다. G 단계는 실패 판정이 나와도 멈추지 않고(한 번 다시 돌린 뒤) 다음 실행으로 넘어갑니다. STOP이 아니면 사용자에게 묻지 않고 계속합니다.
2. G 단계의 배포가 `Insufficient memory`로 실패하면(로그 `results/<HOST_LABEL>/05_deploy_last.log` 또는 `kubectl describe pod`의 Events) worker에 준 메모리 5Gi가 노드의 여유보다 큰 것입니다. 멈추고 사용자에게 보고합니다. 사용자가 값을 정해 주면 `site.env`에 `export ASB_CAP_WORKER_MEMORY=<값>`을 넣고 `scripts/stage.sh resume` 뒤 다시 진행합니다.
3. 끝난 뒤 `python3 scripts/report.py`에 더해 `python3 scripts/capacity_report.py`를 실행합니다. `results/<HOST_LABEL>/CAPACITY.md`가 생기고, 맨 아래 "요약" 절에 갈래별 "기준을 지킨 최대 세션 수"가 나옵니다. 보고할 때는 이 요약 절을 그대로 옮깁니다. 숫자를 보고 원인을 스스로 판단하지 않습니다.

용어: **세션** = 가상 Agent 하나(Actor 하나). **turnover** = N개를 만들어 전부 재운 뒤 K개만 깨워 두고, 초당 R개씩 "깨어 있는 것과 자는 것"을 맞바꾸는 방식. **sync** = 재울 때 객체 저장소 업로드가 끝날 때까지 기다림. **async** = 노드 디스크에 쓰면 끝나고 업로드는 나중(기본 5분 뒤).

Mac에서 실제로 돌려 본 것은 S 단계 13개 중 11개(메모리 2Gi 항목 2개는 Mac의 메모리가 모자라 건너뜀), T 단계, A·F와 같은 조건(다른 실행 이름으로), D의 세션 1개 실행(4분짜리)입니다. B, C의 규모와 D의 나머지는 Mac의 메모리가 작아 돌리지 못했고, E의 긴 async 실행도 해 보지 않았습니다. 초당 2개 이상 교체는 작은 규모(8개 중 4개 활성, 초당 2개)로 한 번만 돌려 봤습니다. 즉 B, C, E와 D의 대부분은 서버에서 처음 도는 조건입니다.

## 5. 판정의 뜻

실행이 끝날 때마다 `scripts/check_run.py`가 판정을 내려 실행 폴더의 `verdict.txt`에 남깁니다. 판정에 따른 처리는 `stage.sh`가 자동으로 합니다. 판정은 직접 바꾸지 않습니다.

| 판정 | 뜻 | `stage.sh`가 하는 일 |
|---|---|---|
| `OK` | 실패 없이 측정됨 | 다음 실행으로 |
| `LIMIT` | turnover의 실제 교체 속도가 목표의 80% 미만. 실패는 없음. **오류가 아니라 "그 구성의 처리 한계에 닿았다"는 측정 결과** | 다음 실행으로 |
| `FAILURES` | 실패한 요청이 있음. 그 조건에서 문제가 생겼다는 측정 결과 | 한 번 다시 실행. 또 같으면: T·A 단계와 S의 첫 항목(`S_glutton_baseline_1_user`)은 STOP. S의 나머지 항목은 그 항목만 기록하고 다음 항목으로. B~F 단계는 그 단계의 남은 실행을 건너뛰고 끝냄 |
| `RESOURCE` | 노드의 가용 메모리가 1 GiB 밑으로 내려갔거나 worker pod가 재시작함 | `FAILURES`와 같음 |
| `BROKEN` | 통계가 없거나 재우기가 0건. 측정이 아니라 실행 자체가 잘못됨 | 한 번 다시 실행. 또 같으면 STOP |

status에 나오는 그 밖의 표시:

- `건너뜀: 메모리 부족 / 디스크 부족`: 실행 전에 서버 자원을 보고 스스로 건너뛴 것입니다. 정상 동작입니다. 서버를 보호하기 위한 것이므로 억지로 돌리지 않습니다. 보고에 "자원 부족으로 건너뜀"이라고 적습니다.
- `건너뜀: 앞 실행 ... 두 번 연속 ...`: 더 작은 규모에서 이미 문제가 나서 그 단계의 더 큰 규모를 돌리지 않은 것입니다. "어느 규모에서 문제가 났는가"가 곧 결과입니다.
- `[1차 시도: ...]`: 멈춤 판정을 받아 다시 돌린 실행입니다. 1차 결과는 `<실행이름>.bad1` 폴더에 남아 있습니다.

S의 첫 항목이나 T, A 단계에서 문제가 나면 STOP하는 이유: S의 첫 항목은 substrate의 가장 단순한 기준 시험(사용자 1명)이고, T와 A는 Mac에서 실패 없이 돈 작은 조건입니다. 여기서 실패하면 부하의 한계가 아니라 서버 환경이나 설치에 문제가 있다는 뜻이므로, 더 큰 단계를 돌려도 의미가 없습니다.

## 6. 상황별 처리

### 6.1 명령이 오래 걸리거나 대화가 끊겼을 때

`scripts/bg.sh status`로 확인합니다. `BG=RUNNING`이면 그대로 둡니다. 같은 작업을 또 시작하지 않습니다(`bg.sh start`가 거부합니다).

### 6.2 실행 중인 작업을 멈춰야 할 때

서버에 다른 문제가 생겼거나 사용자가 멈추라고 했을 때만 `scripts/bg.sh stop`을 씁니다. 중단된 실행은 다음에 같은 단계를 시작하면 처음부터 다시 돕니다.

### 6.3 사용자가 계획표에 없는 조건을 요청했을 때

`site.env`에 X 단계를 추가합니다(형식은 `site.env.example`의 마지막 부분). 그다음 `scripts/stage.sh plan`으로 확인하고 `scripts/bg.sh start stage_X scripts/stage.sh X`로 실행합니다. 추가 인자로 쓸 수 있는 key는 `docs/workload-patterns.md`의 3.2절 표에 있는 것만 씁니다. 표에 없는 key를 만들어 쓰지 않습니다.

### 6.4 일부 단계만 하라고 했을 때

`site.env`에 `ASB_STAGES` 줄을 넣습니다(주석으로 된 예시 줄을 고치거나 파일 끝에 추가). 예: `export ASB_STAGES="T A C"`.

### 6.5 서버 자원이 Mac보다 훨씬 클 때

정해진 단계를 먼저 끝냅니다. 기본 제공 시나리오(S)를 건너뛰고 큰 규모부터 돌리지 않습니다. C 단계의 가장 큰 실행(96개)까지 전부 `OK`이면 한계에 닿지 않은 것입니다. 보고에 "96개까지 한계에 닿지 않음"이라고 적고, 더 큰 규모는 사용자에게 원하는 수치(전체 수, 깨어 있는 수, 초당 교체 수)를 물어 6.3의 방법으로 추가합니다. 스스로 규모를 정하지 않습니다.

## 7. 자주 나는 문제

준비 단계나 배포가 실패하면 로그(`results/<HOST_LABEL>/bg/<이름>.log`)에서 오류 문구를 찾아 아래 표와 맞춰 봅니다. **표에 있는 조치만 합니다. 표에 없는 오류면 멈추고 8절의 형식으로 보고합니다.** 같은 준비 단계가 두 번 실패하면 status가 STOP을 알립니다.

"확인"은 Mac에서 실제로 겪고 해결한 것, "미확인"은 문서나 일반 지식에 근거한 것으로 이 저장소에서 겪어 보지 않은 것입니다.

| 증상 (로그나 출력의 문구) | 원인 | 조치 | 근거 |
|---|---|---|---|
| `STOP: 컨테이너 ... 가 이미 있다` (2단계) | 같은 이름의 kind 클러스터나 `kind-registry` 컨테이너가 이미 있음 | 이 작업의 이전 시도가 만든 것이 분명하거나(`results/<HOST_LABEL>/02_kind_create.log`가 있음) 사용자가 써도 된다고 하면 `scripts/bg.sh start step2 env ASB_RECREATE=1 scripts/02_cluster.sh`. 아니면 STOP하고 사용자에게 묻는다. `kind-registry`는 이름이 고정이라 `KIND_CLUSTER_NAME`을 바꿔도 피할 수 없다. 다른 사람의 것이면 사용자가 결정해야 한다 | 확인 |
| `STOP: kubectl 현재 context 가 ...` | 전용 kubeconfig를 쓰지 않고 있음 | `site.env`에 `KUBECONFIG` 줄이 있는지 확인. 없으면 `site.env.example`에서 복사 | 확인 |
| `FAIL: proxy 가 뜨지 않음 (포트 ... 사용 중?)` (4단계) | 로컬 포트 8000이 사용 중 | `site.env`에 `export PORT=18000` 추가 후 4단계 다시 | 확인 |
| 부하 실행에서 `curl` 연결 실패, `stats.json`이 비어 있음 → `BROKEN` | 로컬 포트 8089가 사용 중 | `site.env`에 `export LOCUST_PORT=18089` 추가 | 미확인 |
| `PREFLIGHT=FAIL`, `외부 통신 불가` 또는 `curl_exit=60` | 서버에서 외부로 나가는 통신이 막혔거나 TLS를 가로채는 프록시가 있음 | STOP. FAIL 줄을 그대로 사용자에게 전달. 필요한 주소: `github.com`, `go.dev`, `proxy.golang.org`, `ghcr.io`, `registry-1.docker.io`, `storage.googleapis.com` | 미확인 |
| `permission denied ... docker.sock` | 현재 사용자가 docker를 쓸 권한이 없음 | STOP. 사용자에게 전달 (docker 그룹 추가는 관리자 권한이 필요) | 미확인 |
| `toomanyrequests` 또는 `429` (이미지 받기) | Docker Hub의 익명 내려받기 횟수 제한 | 30분 뒤 같은 단계를 한 번 다시. 또 나면 STOP하고 보고 | 미확인 |
| `too many open files`, pod가 `CrashLoopBackOff` | Linux의 inotify 한도가 낮음 (kind에서 알려진 문제) | STOP. 관리자 권한으로 sysctl을 바꿔야 하므로 사용자에게 전달 | 미확인 |
| 2단계가 `kubectl wait` 에서 시간 초과 | 노드가 5분 안에 Ready가 되지 않음 | STOP. `kubectl --kubeconfig kubeconfig describe node`의 출력을 저장해 보고 | 미확인 |
| 서버가 재시작된 뒤 status가 2단계를 다시 하라고 하고, 2단계는 `STOP: 컨테이너 ... 가 이미 있다` | kind 노드 컨테이너가 꺼져 있음 | STOP하고 보고. 컨테이너를 다시 켤지(`docker start`) 새로 만들지는 사용자가 정한다 | 미확인 |
| 3단계가 `rollout` 대기 중 시간 초과 | 이미지 내려받기가 느리거나 pod가 뜨지 못함 | `kubectl --kubeconfig kubeconfig get pods -A`의 출력을 저장하고 3단계를 한 번 다시 실행(다시 실행해도 안전함. Mac에서 4분). 또 실패하면 STOP | 재실행은 확인 |
| worker pod가 `Running`이 되지 않음 | 호스트가 cgroup v1 | 0단계가 FAIL로 잡는다. STOP | 미확인 |
| `ImagePullBackOff` (locust 또는 worker) | 로컬 registry에 이미지가 없음 (클러스터를 다시 만든 뒤 배포 기록이 남은 경우 등) | `rm results/<HOST_LABEL>/deployed.txt` 후 단계를 다시 시작 (이미지를 다시 빌드한다) | 미확인 |
| `no space left on device` | Docker 데이터 디스크가 가득 참 | STOP. `scripts/cleanup_actors.sh`로 가상 Agent의 snapshot만 지우고 보고. 다른 것은 지우지 않는다 | 미확인 |

## 8. 멈췄을 때 (STOP)

1. 더 진행하지 않습니다. `scripts/stage.sh resume`은 사용자가 "원인을 해결했으니 계속하라"고 한 뒤에만 실행합니다.
2. `python3 scripts/report.py`를 실행해 지금까지의 결과를 정리합니다(부하 실행이 하나라도 있었을 때).
3. 사용자에게 아래 형식으로 보고합니다.

```
[멈춤 보고]
- 멈춘 곳: (status 의 STOP 줄 그대로)
- 그 전까지 끝난 것: (status 의 준비 단계와 부하 단계 목록 그대로)
- 오류 원문: (로그의 관련 줄 그대로, 최대 30줄. 로그 파일 경로)
- 7절 표에서 해당하는 항목: (있으면 그 행, 없으면 "표에 없음")
- 내가 한 조치: (한 것만. 없으면 "없음")
- 사용자에게 필요한 것: (예: 외부 통신 허용, docker 권한, 계속 여부 결정)
```

원인을 추측해서 단정하지 않습니다. 추측이면 "추측"이라고 적습니다.

사용자가 "계속 진행하라"고 답했으면 그것이 resume의 승인입니다. 다시 묻지 않습니다.

사용자가 원인을 해결했다고 하면: 준비 단계의 문제였으면 `scripts/stage.sh resume` 뒤 status의 NEXT를 따릅니다. 특정 실행의 문제였으면 `scripts/stage.sh resume <실행이름>`으로 그 실행의 결과를 옆으로 치우고 다시 돌립니다.

## 9. 끝났을 때

1. `python3 scripts/report.py`를 실행합니다.
2. `scripts/stage.sh status`의 출력과 `results/<HOST_LABEL>/REPORT.md`를 읽습니다.
3. 아래 형식으로 보고합니다. 표와 숫자는 파일에서 그대로 옮깁니다.

```
[서버 검증 결과 보고]
1. 서버: (00_preflight.txt 의 OS, CPU 수, 메모리, Docker 버전, 디스크 종류)
2. 진행: 준비 단계 0~4 결과 / 단계별로 실행한 수, 건너뛴 수와 이유, 멈춘 곳
3. 결과 표: (REPORT.md 의 표 전체)
4. 관찰: (아래 "쓸 수 있는 문장" 중 조건에 맞는 것만)
5. 확인하지 못한 것: (건너뛴 실행, 돌리지 않은 단계, 미확인 사항)
6. 서버에 남아 있는 것: kind 클러스터 <이름>, kind-registry 컨테이너, Docker 이미지, 이 폴더 (정리는 사용자가 지시하면 scripts/99_teardown.sh)
7. 결과 파일 위치: results/<HOST_LABEL>/ (사용자가 가져갈 폴더)
```

### 쓸 수 있는 문장

관찰은 아래 조건에 맞을 때 그 문장만 씁니다. 빈칸은 `REPORT.md`의 값으로 채웁니다. 조건에 없는 해석(원인 추정, 성능 예측, 실제 서비스에 대한 결론)은 쓰지 않습니다. 필요하면 "원인은 확인하지 못했다"고 적습니다.

| 조건 | 문장 |
|---|---|
| S 단계가 모두 `OK`, 실패 0 | "substrate가 기본 제공하는 시나리오(야간 시험 목록의 glutton 항목 __개, 기본 대본 coding-session)가 이 서버에서 실패 없이 돌았다." |
| S의 `S_glutton_baseline_1_user` / `_5_users` / `_10_users` 재우기 p50 | "substrate 기준 시험(glutton, sync)의 재우기 중앙값은 사용자 1명 __초, 5명 __초, 10명 __초였다." |
| S의 `S_glutton_mem_1gi_gvisor` / `_2gi_gvisor` 재우기 p50, snapshot MiB | "메모리 1Gi를 채운 Actor의 재우기 중앙값은 __초(snapshot __ MiB), 2Gi는 __초(snapshot __ MiB)였다." |
| S에 `FAILURES`나 `RESOURCE`, 건너뜀이 있음 | "기본 제공 시나리오 중 __은 (verdict.txt 의 reason 또는 SKIPPED 이유 그대로)." |
| A 단계가 모두 `OK` 또는 `LIMIT`, 실패 0 | "Mac과 같은 조건(자체 대본)에서 서버에서도 실패 없이 끝까지 동작했다." |
| A의 `A_s1_r1~3` 재우기 p50 | "겹침이 없을 때 재우기 중앙값은 __ / __ / __초였다 (Mac 0.83초)." |
| A의 `A_turn12_r1~3` 재우기 p50 / p95 | "12개 중 3개를 깨워 두고 초당 1개씩 교체할 때 재우기 중앙값은 __ / __ / __초, p95는 __ / __ / __초였다 (Mac 8.9 / 9.8 / 11초, p95 15~16초)." |
| 어떤 실행이 `LIMIT` | "__에서 실제 교체 속도가 초당 __회로 목표 __회에 못 미쳤다. 실패는 없었다." |
| C 단계가 전부 `OK` | "전체 96개, 활성 24개, 초당 8개 교체까지 실패 없이, 목표 속도대로 처리됐다." |
| 어떤 실행이 `FAILURES` | "__에서 요청 __건이 실패했다. 오류 문구: (verdict.txt 의 ERROR 줄 그대로)" |
| 어떤 실행이 `RESOURCE` | "__에서 (verdict.txt 의 reason 그대로)." |
| "주의" 열에 `disk_busy` | "__에서 부하 구간의 디스크 사용률 평균이 80% 이상(__%)이었다." |
| "주의" 열에 `cpu_busy` | "__에서 부하 구간의 CPU 사용률 평균이 80% 이상(__%)이었다." |
| "주의" 열에 `io_pressure` | "__에서 커널의 IO pressure(avg10)가 20 이상으로 올라갔다." |
| F의 2Gi 실행 재우기 p50이 `F_def_turn12`의 절반 이하 | "업로드 메모리 한도를 2Gi로 올리자 재우기 중앙값이 __초에서 __초로 줄었다. Mac 결과와 같은 방향이다." |
| F의 2Gi 실행이 절반 이하가 아님 | "업로드 메모리 한도를 올려도 재우기 중앙값의 차이가 뚜렷하지 않았다 (__초 대 __초)." |
| D의 snapshot MiB 열 | "메모리 약 640 MiB를 쓰는 대본에서 Actor 하나의 snapshot은 약 __ MiB였다 (작은 대본은 약 __ MiB)." |
| 건너뛴 실행이 있음 | "__은 (SKIPPED 이유 그대로)로 실행하지 않았다." |

`REPORT.md`의 "기준 대비" 열은 같은 대본의 세션 1개 실행(판정 OK) 재우기 중앙값에 대한 배수입니다. Mac의 비교값은 `results/darwin-arm64/REPORT.md`에 같은 형식으로 있습니다(S 단계 포함).

### 해석할 때 알아 둘 것 (사용자가 물으면 답할 수 있게)

- 숫자의 뜻과 한계는 `docs/workload-patterns.md` 7절에 있습니다. 묻는 내용이 거기 있으면 그 문서를 근거로 답하고, 없으면 모른다고 답합니다.
- 가상 사용자는 앞 요청이 끝나야 다음 요청을 보냅니다. 시스템이 느려지면 부하도 같이 줄어듭니다. 그래서 "실패 0"만 보면 안 되고 실제 속도가 목표를 따라갔는지(`LIMIT` 여부)를 같이 봐야 합니다.
- 같은 조건을 다시 돌려도 값이 움직입니다. 실행 한 번의 값을 결론으로 쓰지 않습니다. 그래서 A 단계가 같은 조건을 3번 돕니다.
- 판정 기준(목표의 80%, 가용 메모리 1 GiB 등)과 단계 계획은 이 저장소가 정한 것입니다. Agent Substrate의 공식 합격 기준이 아닙니다. 어떤 것이 substrate 기본 제공이고 어떤 것이 추가한 것인지는 `docs/origin.md`에 있습니다. 보고할 때 둘을 섞어 쓰지 않습니다.
- Mac에서 찾은 지연의 원인은 디스크가 아니라 업로드에 쓰는 메모리 한도(`--upload-memory-budget`, 기본 512Mi)였습니다. 서버에서도 그런지는 F 단계가 확인합니다. 서버 결과를 보기 전에는 "서버도 그렇다"고 쓰지 않습니다.

## 10. 사용자가 알려 줄 정보

사용자가 채워 주는 표입니다. 비어 있으면 "기본" 열대로 진행하고, "비어 있으면" 열의 행동을 따릅니다.

| # | 항목 | 값 (사용자 기입) | 기본 | 비어 있으면 |
|---|---|---|---|---|
| 1 | 서버에서 외부 인터넷으로 직접 나갈 수 있는가. 프록시나 사내 미러가 있으면 그 내용 | | 직접 통신 가능 | 0단계가 확인. 막혀 있으면 STOP하고 보고 |
| 2 | 서버를 다른 사람이나 다른 작업과 함께 쓰는가 | | 함께 쓴다고 가정 | 다른 컨테이너·클러스터를 건드리지 않음. 측정값에 잡음이 있을 수 있다고 보고에 적음 |
| 3 | 현재 계정이 `docker` 명령을 쓸 수 있는가 | | 쓸 수 있음 | 0단계가 확인 |
| 4 | 돌릴 단계 (`S T A B C D E F G` 중. S는 substrate 기본 제공 시나리오) | | 전부 | 전부 |
| 5 | 꼭 보고 싶은 규모 (전체 Agent 수 / 깨어 있는 수 / 초당 교체 수) | | 없음 | 정해진 단계만. 6.5절 참고 |
| 6 | 실제 Agent 하나의 메모리 크기 (snapshot 크기를 맞추기 위한 값) | | 모름 | 준비된 대본 두 가지(약 80 MiB, 약 640 MiB)만 사용 |
| 7 | 서버 결과를 git으로 커밋·푸시해도 되는가. 안 되면 결과를 가져갈 방법 | | 안 됨 | 커밋·푸시하지 않고 `results/<HOST_LABEL>/` 위치만 보고 |
| 8 | 작업 가능한 시간대, 끝내야 하는 시각 | | 제한 없음 | 순서대로 진행. 전체 약 4시간 + 설치 약 15분 (Mac 기준) |
| 9 | 에이전트의 명령 1회 실행 시간 제한(초) | | 모름 | `scripts/bg.sh wait 100`처럼 짧게 기다리기를 반복 |
| 10 | 끝난 뒤 클러스터를 지울 것인가 | | 남겨 둠 | 남겨 두고 보고에 적음 |

## 11. 사용자가 미리 알아야 하는 것 (서버에 생기는 변화)

- Docker 컨테이너 2개: `asb-control-plane`(kind 노드), `kind-registry`(로컬 이미지 저장소, 127.0.0.1:5001). Docker 네트워크 `kind`. Docker 이미지 수 GB.
- 이 폴더 안: `toolchain/`(Go), `src/`(substrate 소스), `gopath/`, `gocache/`, `bin/`, `kubeconfig`, `results/`. 홈 폴더의 `~/.cache/ate-setup/`.
- `~/.kube/config`는 건드리지 않습니다(`site.env`의 전용 kubeconfig를 쓸 때).
- **서버에 `/dev/kvm`이 있으면** substrate의 클러스터 생성 스크립트가 kind 노드 안에서 `chmod 666 /dev/kvm`을 실행합니다. 장치를 그대로 연결한 것이라 호스트의 `/dev/kvm` 권한도 바뀝니다. 이 작업은 gVisor 방식만 쓰므로 KVM이 필요 없지만, 스크립트가 자동으로 합니다. 보안 정책상 문제가 되면 2단계 전에 사용자가 결정해야 합니다. 0단계 출력의 `ls -l /dev/kvm` 줄로 해당 여부를 알 수 있습니다.
- sudo는 쓰지 않습니다.
- 부하가 도는 동안 디스크 쓰기가 초당 수백 MiB, CPU와 메모리 사용이 큽니다. 실행 전에 자원을 보고 큰 실행은 스스로 건너뛰지만, 함께 쓰는 서버라면 시간대를 정해 주는 것이 좋습니다.

## 12. 이 핸드오프의 범위 밖

- 발표 자료(`docs/presentation/`) 수정. 서버 결과가 나오면 사용자가 따로 진행합니다.
- `README.md`, `docs/workload-patterns.md`의 내용 수정. 틀린 곳을 발견하면 고치지 말고 보고에 적습니다.
- microVM 방식, 실제 LLM Agent, 여러 노드 클러스터.

## 부록: 파일 위치

| 무엇 | 어디 |
|---|---|
| 서버별 설정 | `site.env` (없으면 `site.env.example`을 복사) |
| 모든 결과 | `results/<HOST_LABEL>/` |
| 준비 단계 출력 | `results/<HOST_LABEL>/00_preflight.txt` ~ `04_counter_cycle.txt` |
| 실행 하나의 결과 | `results/<HOST_LABEL>/runs/<실행이름>/` (`summary.txt` 요약, `verdict.txt` 판정, `run_output.log` 실행 출력) |
| 결과 표 | `results/<HOST_LABEL>/REPORT.md` |
| 백그라운드 작업 로그 | `results/<HOST_LABEL>/bg/<이름>.log` |
| 멈춤 사유 | `results/<HOST_LABEL>/STOP.txt` |
| Mac 결과 (비교용) | `results/darwin-arm64/REPORT.md`, `README.md` |
| 배경 지식 | `README.md` (절차와 결과 읽는 법), `docs/workload-patterns.md` (조절값의 뜻, 결과의 한계), `docs/origin.md` (substrate가 기본 제공하는 것과 이 저장소가 추가한 것의 구분) |
