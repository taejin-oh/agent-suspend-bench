# 부하 실행 결과 요약

- 결과 폴더: `results/darwin-arm64`
- server=29.4.0 os=OrbStack kernel=7.0.14-orbstack-00380-ga7e0a2dc9535 arch=aarch64 cpus=10 mem_bytes=8393289728 cgroup=v2 driver=cgroupfs
- substrate: substrate d283af4ebaa9aba0bac571a827d3fbc954e2ec9a Tue Nov 17 08:23:52 2026 +0000
- 이 파일은 `scripts/report.py` 가 만든다. 손으로 고치지 않는다. 숫자의 원본은 각 실행 폴더의 `summary.txt`.

## 1. substrate 기본 제공 시나리오 (S 단계)

`S_glutton_*` 는 substrate 야간 시험 목록(`benchmarking/automation/tests.yaml`)의 gVisor glutton 항목과 이름·사용자 수·worker 수·Actor 메모리·실행 시간·옵션이 같다.
`S_coding_*` 는 문서의 기본 실행(내장 대본 `coding-session`, Actor 메모리 1Gi, 옵션 없음)이고, 세션 수와 실행 시간만 이 저장소가 정했다.
실행 방법(Locust HTTP API 호출)과 디스크·CPU·메모리 수집, 판정은 이 저장소의 것이다.

| 실행 | 세션 | 조건 | 재우기 p50 / p95 (초) | 기준 대비 | 깨우기 p50 / p95 (초) | 실패 | 초당 재우기 (목표) | 디스크 쓰기 MiB/s | 디스크 사용률 % 평균 / 최대 | CPU % | 가용 메모리 최소 MiB | persist p50 (초) | snapshot MiB | 판정 | 주의 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| S_coding_1 | 1 | async, 내장 coding-session, worker 1, Actor 1Gi | 0.43 / 0.59 | - | 0.22 / 0.83 | 0 | 0.19 | 70 | 9 / 57 | 8 | 2741 | 0.00 | 356 | OK | - |
| S_coding_4 | 4 | async, 내장 coding-session, worker 1, Actor 1Gi | 0.58 / 1.00 | - | 0.51 / 1.60 | 0 | 0.68 | 239 | 24 / 82 | 23 | 1992 | 0.00 | 351 | OK | - |
| S_glutton_baseline_10_users | 10 | sync, glutton, worker 10, Actor 256Mi | 0.38 / 0.63 | - | 0.09 / 0.21 | 0 | 5.96 | 59 | 42 / 67 | 23 | 3448 | 0.16 | 1 | OK | - |
| S_glutton_baseline_10_users_pause | 10 | async, glutton, worker 10, Actor 256Mi | 0.05 / 0.08 | - | 0.06 / 0.10 | 0 | 8.00 | 42 | 14 / 58 | 15 | 3514 | 0.00 | 6 | OK | - |
| S_glutton_baseline_1_user | 1 | sync, glutton, worker 1, Actor 256Mi | 0.16 / 0.22 | 1.0배 | 0.07 / 0.08 | 0 | 0.76 | 9 | 12 / 63 | 6 | 4219 | 0.05 | 1 | OK | - |
| S_glutton_baseline_1_user_pause | 1 | async, glutton, worker 1, Actor 256Mi | 0.04 / 0.07 | - | 0.07 / 0.09 | 0 | 0.86 | 5 | 6 / 48 | 5 | 4156 | 0.00 | 6 | OK | - |
| S_glutton_baseline_5_users | 5 | sync, glutton, worker 5, Actor 256Mi | 0.26 / 0.41 | - | 0.07 / 0.12 | 0 | 3.33 | 36 | 30 / 67 | 15 | 3822 | 0.10 | 1 | OK | - |
| S_glutton_baseline_5_users_pause | 5 | async, glutton, worker 5, Actor 256Mi | 0.06 / 0.08 | - | 0.09 / 0.13 | 0 | 3.94 | 22 | 11 / 61 | 10 | 3677 | 0.00 | 6 | OK | - |
| S_glutton_mem_1gi_gvisor | 1 | sync, glutton, worker 1, Actor 1536Mi | 5.10 / 5.50 | 1.0배 | 0.91 / 1.00 | 0 | 0.08 | 175 | 37 / 76 | 21 | 2156 | 3.15 | 1025 | OK | - |
| S_glutton_mem_1gi_gvisor_pause | 1 | async, glutton, worker 1, Actor 1536Mi | 1.30 / 1.70 | - | 0.17 / 1.10 | 0 | 0.23 | 240 | 29 / 77 | 12 | 2120 | 0.00 | 1030 | OK | - |
| S_glutton_oversubscribe_15_users | 15 | async, glutton, worker 10, Actor 256Mi | 0.05 / 0.10 | - | 0.07 / 0.13 | 0 | 15.45 | 94 | 24 / 73 | 27 | 3448 | 0.00 | 6 | OK | - |

## 2. 이 저장소가 정한 조건 (자체 대본, T 이하 단계)

| 실행 | 세션 | 조건 | 재우기 p50 / p95 (초) | 기준 대비 | 깨우기 p50 / p95 (초) | 실패 | 초당 재우기 (목표) | 디스크 쓰기 MiB/s | 디스크 사용률 % 평균 / 최대 | CPU % | 가용 메모리 최소 MiB | persist p50 (초) | snapshot MiB | 판정 | 주의 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| h_D_s1_r1 | 1 | sync, agent-1g | 4.50 / 5.30 | 1.0배 | 2.10 / 3.20 | 0 | 0.06 | 111 | 24 / 74 | 14 | 1890 | 2.78 | 1025 | OK | - |
| h_D_s1_r2 | 1 | sync, agent-1g | 4.40 / 5.80 | 1.0배 | 2.30 / 4.00 | 0 | 0.06 | 103 | 24 / 79 | 14 | 2012 | 2.67 | 1023 | OK | - |
| h_T_s1 | 1 | sync | 0.86 / 1.00 | 1.0배 | 0.16 / 0.46 | 0 | 0.32 | 106 | 16 / 58 | 12 | 2518 | 0.59 | 168 | OK | - |
| h_T_turn6 | 6 | sync, 활성 2 | 2.80 / 4.70 | 3.3배 | 1.10 / 3.00 | 0 | 0.78 (1) | 247 | 51 / 89 | 41 | 2691 | 1.57 | 152 | LIMIT | 실제 교체 초당 0.78회 < 목표 1회의 80% |
| h_X_turn8_awake4_rps2 | 8 | sync, 활성 4 | 5.40 / 12.00 | 6.3배 | 1.80 / 3.80 | 0 | 0.61 (2) | 179 | 54 / 88 | 42 | 2310 | 3.65 | 134 | LIMIT | 실제 교체 초당 0.61회 < 목표 2회의 80% |
| k1_async_implicit_think05 | 2 | async | 0.18 / 0.55 | - | 0.12 / 0.28 | 0 | 1.27 | 239 | 21 / 76 | 15 | 3269 | 0.00 | 170 | OK | - |
| k2_resident_8on4 | 8 | none | - / - | - | - / - | 0 | - | 16 | 6 / 33 | 14 | 2465 | - | 0 | OK | - |
| r2_s1_sync | 1 | sync | 0.83 / 1.20 | 1.0배 | 0.14 / 0.58 | 0 | 0.31 | 104 | 15 / 54 | 12 | 2405 | 0.57 | 164 | OK | - |
| r2_s4_sync | 4 | sync | 2.70 / 3.70 | 3.3배 | 0.46 / 1.30 | 0 | 0.77 | 232 | 33 / 63 | 28 | 2381 | 2.16 | 153 | OK | - |
| r2_turnover_12_awake3 | 12 | sync, 활성 3 | 8.90 / 16.00 | 10.7배 | 1.60 / 3.20 | 0 | 0.72 (1) | 231 | 63 / 94 | 39 | 2610 | 7.18 | 152 | LIMIT | 실제 교체 초당 0.72회 < 목표 1회의 80% |
| r3_upload2g_s4_sync | 4 | sync, 한도 2Gi | 1.60 / 2.70 | 1.9배 | 0.50 / 2.30 | 0 | 0.85 | 278 | 51 / 84 | 42 | 1760 | 0.85 | 163 | OK | - |
| r3_upload2g_turnover_12_awake3 | 12 | sync, 활성 3, 한도 2Gi | 2.30 / 7.10 | 2.8배 | 2.20 / 4.70 | 0 | 0.77 (1) | 240 | 61 / 85 | 52 | 1862 | 0.84 | 152 | LIMIT | 실제 교체 초당 0.77회 < 목표 1회의 80% |
| r4_default_turnover_12_awake3 | 12 | sync, 활성 3 | 11.00 / 15.00 | 13.3배 | 1.60 / 2.90 | 0 | 0.72 (1) | 227 | 64 / 85 | 39 | 2771 | 8.93 | 152 | LIMIT | 실제 교체 초당 0.72회 < 목표 1회의 80% |
| r5_upload2g_turnover_12_awake3 | 12 | sync, 활성 3, 한도 2Gi | 3.80 / 18.00 | 4.6배 | 2.40 / 4.90 | 0 | 0.67 (1) | 210 | 67 / 90 | 58 | 1520 | 1.54 | 148 | LIMIT | 실제 교체 초당 0.67회 < 목표 1회의 80% |
| s4_sync | 4 | sync | 2.80 / 4.90 | 3.4배 | 0.37 / 1.40 | 0 | 0.70 | 220 | 38 / 100 | - | 2477 | - | - | OK | - |
| turnover_12_awake3 | 12 | sync, 활성 3 | 9.80 / 16.00 | 11.8배 | 1.60 / 3.00 | 0 | 0.73 (1) | 234 | 64 / 90 | - | 2721 | - | - | LIMIT | 실제 교체 초당 0.73회 < 목표 1회의 80% |

기준값(세션 1개, sync, 판정 OK 인 실행들의 재우기 중앙값): user_class=glutton script=builtin actor_memory=256Mi worker_count=1 → 0.16초, user_class=glutton script=builtin actor_memory=1536Mi worker_count=1 → 5.10초, script=agent-1g.yaml actor_memory=1536Mi worker_count=4 → 4.45초, script=smoke-5step.yaml actor_memory=512Mi worker_count=4 → 0.86초, 배포 기록 없음 → 0.83초

열 설명: 재우기 = `SuspendActor`(sync) 또는 `SuspendActorAsync`(async) 행. 깨우기 = `TimeToWake` 행. 초당 재우기부터 CPU 까지는 부하가 걸린 구간만의 값(`load window only`).
snapshot MiB = 정지 직전 객체 저장소에 있던 Actor 하나의 snapshot 크기(중앙값).
`.bad1` 로 끝나는 실행은 멈춤 판정을 받아 한 번 다시 돌린 것의 1차 시도다.
