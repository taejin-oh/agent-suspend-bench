#!/usr/bin/env python3
"""results/<HOST_LABEL>/runs/ 의 모든 실행을 표 하나로 모아 REPORT.md 를 만든다. 숫자를 손으로 옮겨 적지 않기 위한 것.
사용: report.py [results/<HOST_LABEL> 폴더]      (생략하면 scripts/env.sh 가 정한 폴더. 결과는 그 폴더의 REPORT.md)"""
import glob, os, statistics as st, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_run import load, read

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
res = sys.argv[1] if len(sys.argv) > 1 else subprocess.run(["bash", "-c", f'source "{root}/scripts/env.sh" && echo "$RESULTS"'], capture_output=True, text=True).stdout.strip()
runs = [load(d) for d in sorted(glob.glob(f"{res}/runs/*/")) if os.path.exists(f"{d}/stats.json") and ".partial-" not in d and ".old-" not in d]
skipped = [(os.path.basename(os.path.dirname(f)), read(f).strip()) for f in sorted(glob.glob(f"{res}/runs/*/SKIPPED.txt"))]

# 기준값: 같은 배포에서 세션 1개, sync, 판정 OK 인 실행들의 재우기 중앙값
base = {}
for r in runs:
    if r["users"] == 1 and r["mode"] == "sync" and not r["awake"] and r["verdict"] == "OK" and r.get("suspend_p50_s"):
        base.setdefault(r["deployed"], []).append(r["suspend_p50_s"])
base = {k: st.median(v) for k, v in base.items()}

f = lambda v, fmt="{:.2f}": "-" if v is None else fmt.format(v)
pair = lambda a, b, fmt="{:.2f}": f"{f(a, fmt)} / {f(b, fmt)}"
L = ["# 부하 실행 결과 요약", "", f"- 결과 폴더: `{os.path.relpath(res, root)}`"]
pre = read(f"{res}/00_preflight.txt")
for key in ("PRETTY_NAME=", "server="):
    L += [f"- {l.strip()}" for l in pre.splitlines() if l.startswith(key)][:1]
L += [f"- substrate: {read(f'{res}/01_substrate_commit.txt').strip() or '-'}",
      "- 이 파일은 `scripts/report.py` 가 만든다. 손으로 고치지 않는다. 숫자의 원본은 각 실행 폴더의 `summary.txt`."]
HEAD = ["| 실행 | 세션 | 조건 | 재우기 p50 / p95 (초) | 기준 대비 | 깨우기 p50 / p95 (초) | 실패 | 초당 재우기 (목표) | 디스크 쓰기 MiB/s | 디스크 사용률 % 평균 / 최대 | CPU % | 가용 메모리 최소 MiB | persist p50 (초) | snapshot MiB | 판정 | 주의 |",
      "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
def row(r):
    dep = dict(kv.split("=", 1) for kv in r["deployed"].split() if "=" in kv)
    cond = r["mode"] + (f", 활성 {r['awake']}" if r["awake"] else "") + (f", 한도 {r['budget']}" if r["budget"] != "default" else "")
    script = dep.get("script", "").replace(".yaml", "")
    if dep.get("user_class", "agentsession") != "agentsession": cond += f", {dep['user_class']}, worker {dep.get('worker_count')}, Actor {dep.get('actor_memory')}"
    elif script == "builtin": cond += f", 내장 coding-session, worker {dep.get('worker_count')}, Actor {dep.get('actor_memory')}"
    elif script and script != "smoke-5step": cond += f", {script}"
    b = base.get(r["deployed"]); ratio = f"{r['suspend_p50_s'] / b:.1f}배" if b and r.get("suspend_p50_s") and r["mode"] == "sync" else "-"
    rate = f(r["suspends_per_s"]) + (f" ({r['target_rps']:g})" if r["target_rps"] else "")
    return (f"| {r['name']} | {r['users']} | {cond} | {pair(r.get('suspend_p50_s'), r.get('suspend_p95_s'))} | {ratio} | {pair(r.get('wake_p50_s'), r.get('wake_p95_s'))} | {r['failures']} | {rate} | "
             f"{f(r['write_mib_s'], '{:.0f}')} | {pair(r['disk_mean'], r['disk_peak'], '{:.0f}')} | {f(r['cpu_mean'], '{:.0f}')} | {f(r['mem_min_mib'], '{:.0f}')} | {f(r['persist_p50_s'])} | {f(r['snapshot_mib'], '{:.0f}')} | {r['verdict']} | {', '.join(r['flags'] + r['reasons']) or '-'} |")
std = [r for r in runs if r["name"].startswith("S_")]; own = [r for r in runs if not r["name"].startswith("S_")]
if std:
    L += ["", "## 1. substrate 기본 제공 시나리오 (S 단계)", "",
          "`S_glutton_*` 는 substrate 야간 시험 목록(`benchmarking/automation/tests.yaml`)의 gVisor glutton 항목과 이름·사용자 수·worker 수·Actor 메모리·실행 시간·옵션이 같다.",
          "`S_coding_*` 는 문서의 기본 실행(내장 대본 `coding-session`, Actor 메모리 1Gi, 옵션 없음)이고, 세션 수와 실행 시간만 이 저장소가 정했다.",
          "실행 방법(Locust HTTP API 호출)과 디스크·CPU·메모리 수집, 판정은 이 저장소의 것이다.", ""] + HEAD + [row(r) for r in std]
if own:
    L += ["", "## 2. 이 저장소가 정한 조건 (자체 대본, T 이하 단계)" if std else "## 실행 결과", ""] + HEAD + [row(r) for r in own]
L += ["", "기준값(세션 1개, sync, 판정 OK 인 실행들의 재우기 중앙값): " + (", ".join(f"{k or '배포 기록 없음'} → {v:.2f}초" for k, v in base.items()) or "없음"), "",
      "열 설명: 재우기 = `SuspendActor`(sync) 또는 `SuspendActorAsync`(async) 행. 깨우기 = `TimeToWake` 행. 초당 재우기부터 CPU 까지는 부하가 걸린 구간만의 값(`load window only`).",
      "snapshot MiB = 정지 직전 객체 저장소에 있던 Actor 하나의 snapshot 크기(중앙값).",
      "`.bad1` 로 끝나는 실행은 멈춤 판정을 받아 한 번 다시 돌린 것의 1차 시도다."]
if skipped: L += ["", "## 건너뛴 실행", ""] + [f"- {n}: {w}" for n, w in skipped]
if os.path.exists(f"{res}/STOP.txt"): L += ["", "## 멈춤 상태", "", read(f"{res}/STOP.txt").strip()]
text = "\n".join(L) + "\n"
open(f"{res}/REPORT.md", "w").write(text); print(text, end="")
