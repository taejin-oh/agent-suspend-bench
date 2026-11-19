# 이 저장소에서 일하는 에이전트에게

이 저장소는 "다수의 Agent가 활성/비활성을 반복하며 checkpoint를 만들 때 스토리지에 문제가 생기는가"를 확인하는 재현 환경입니다. Mac에서 한 검증을 회사 Linux 서버에서 이어서 하는 것이 지금의 작업입니다.

**먼저 `docs/handoff/HANDOFF.md`의 1~4절을 읽습니다.** 작업 방법, 지켜야 할 것, 멈춰야 할 때가 거기 있습니다.

## 진행 방법

```
[ -f site.env ] || cp site.env.example site.env     # 처음 한 번
scripts/stage.sh status                             # 진행 상태와 다음에 할 일
```

`scripts/stage.sh status`의 맨 아래 `NEXT:` 줄을 그대로 실행하고, 다시 status를 봅니다. 이것을 반복합니다. 무엇을 하고 있었는지 모르겠을 때도 status부터 실행합니다.

## 꼭 지킬 것

- 숫자는 `results/` 아래 파일에 있는 것만 씁니다. 기억이나 짐작으로 쓰지 않습니다.
- `NEXT:`가 `STOP`이면 멈추고 사용자에게 보고합니다 (`docs/handoff/HANDOFF.md` 8절). 스스로 우회하지 않습니다.
- 오래 걸리는 명령은 `scripts/bg.sh start`로 돌리고 `scripts/bg.sh wait`로 기다립니다. 부하가 도는 동안 클러스터를 건드리는 다른 명령을 실행하지 않습니다.
- 사용자가 분명히 지시하지 않았으면 하지 않습니다: `sudo`, 시스템·Docker·프록시 설정 변경, TLS 검증 끄기, 이 작업이 만들지 않은 컨테이너나 클러스터를 지우기, `git commit`/`git push`, `scripts/99_teardown.sh`, `src/substrate/` 수정.
- `scripts/env.sh`를 직접 `source`하지 않습니다. `scripts/` 안의 스크립트를 실행합니다.
- 계획표(`scripts/stage.sh plan`)에 없는 조건을 지어내서 실행하지 않습니다.

## 문서

| 문서 | 내용 |
|---|---|
| `docs/handoff/HANDOFF.md` | 서버 검증 작업 지시서 (진행, 판정, 문제 대응, 보고 형식) |
| `README.md` | 절차 설명, 결과 파일 읽는 법, Mac 결과 |
| `docs/workload-patterns.md` | 부하 조절값의 뜻, 결과를 어디까지 믿을 수 있는가 |
| `docs/origin.md` | Agent Substrate가 기본 제공하는 것과 이 저장소가 추가한 것의 구분 |
| `docs/agent-memory/` | 사용자가 앞에서 한 질문과 그 답의 기록. 이미 정해진 것을 다시 묻지 않도록 먼저 읽고, 새 질문과 답은 그 폴더의 `README.md` 규칙대로 이어서 적음 |
