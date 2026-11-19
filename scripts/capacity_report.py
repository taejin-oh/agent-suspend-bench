#!/usr/bin/env python3
"""G 단계(자리가 모자란 환경) 실행을 표로 모으고, 갈래별로 "깨우기 기준을 지키면서 받을 수 있는 최대 세션 수"를 계산한다.
설계와 읽는 법은 docs/capacity-eval.md. 숫자를 사람이 보고 판단하지 않게 하기 위한 것.

대상: worker 메모리를 제한해 배포한 실행 (run.txt 의 deployed 줄에 worker_memory= 가 있는 것).
갈래: none = 재우지 않음, sync = 기본, async, sync+<한도> = sync 에 업로드 한도를 바꾼 것.
기준: 깨우기(TimeToWake) p95 가 SLO 초 이하이고 깨우기 실패가 0건. 깨우기 시간에는 자리가 없어 다시 시도한 시간이 들어 있다. SLO 의 기본값 2.0 초는 이 저장소가 임의로 정한 값이다.

사용: capacity_report.py [results/<HOST_LABEL> 폴더] [SLO 초]      (결과는 그 폴더의 CAPACITY.md)"""
import glob, json, os, re, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from check_run import load, read

ACTIVE_S, IDLE_S = 5.0, 30.0    # workloads/capacity-cycle.yaml 의 dwell 과 think. 대본을 바꾸면 여기도 바꾼다
UNIT = {"Ki": 1 / 1024, "Mi": 1, "Gi": 1024, "": 1 / 1048576}
root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
res = sys.argv[1] if len(sys.argv) > 1 else subprocess.run(["bash", "-c", f'source "{root}/scripts/env.sh" && echo "$RESULTS"'], capture_output=True, text=True).stdout.strip()
slo = float(sys.argv[2]) if len(sys.argv) > 2 else 2.0


def mib(s):
    m = re.match(r"([\d.]+)(Ki|Mi|Gi)?$", s)
    return float(m.group(1)) * UNIT[m.group(2) or ""] if m else 0.0


def samples(d):
    """cap_10s.txt 에서 worker 가 내준 자리의 최대값과 Actor 상태별 최대 개수를 뽑는다."""
    out = {"alloc_actors": None, "alloc_mib": None, "cap_mib": None, "suspending": 0, "running": 0}
    for l in read(f"{d}/cap_10s.txt").splitlines():
        if " workers " in l:
            a = sum(int(x) for x in re.findall(r"actors=(\d+)/", l))
            m = [(mib(u), mib(c)) for u, c in re.findall(r"mem=([\w.]+)/([\w.]+)", l)]
            if m:
                out["alloc_actors"] = max(out["alloc_actors"] or 0, a)
                out["alloc_mib"] = max(out["alloc_mib"] or 0, sum(u for u, _ in m)); out["cap_mib"] = sum(c for _, c in m)
        elif " actors " in l:
            for k, v in re.findall(r"ACTOR_STATE_(\w+)=(\d+)", l):
                if k == "SUSPENDING": out["suspending"] = max(out["suspending"], int(v))
                if k == "RUNNING": out["running"] = max(out["running"], int(v))
    return out


runs = []
for d in sorted(glob.glob(f"{res}/runs/*/")):
    if not os.path.exists(f"{d}/stats.json") or ".partial-" in d or ".old-" in d or ".bad1" in d: continue
    r = load(d)
    if "worker_memory=" not in r["deployed"]: continue
    try: rows = {x["name"]: x for x in json.load(open(f"{d}/stats.json"))["stats"]}
    except (OSError, ValueError, KeyError): rows = {}
    w = rows.get("TimeToWake") or {}
    r["wakes"], r["wake_fail"] = w.get("num_requests", 0), w.get("num_failures", 0)
    r["retries"] = (rows.get("ResumeActor") or {}).get("num_failures", 0)    # 자리가 없어 거절된 깨우기 시도 (시도마다 1건)
    r["arm"] = r["mode"] + (f"+{r['budget']}" if r["budget"] != "default" else "")
    r.update(samples(d)); runs.append(r)

f = lambda v, fmt="{:.2f}": "-" if v is None else fmt.format(v)
L = ["# 자리가 모자란 환경의 실행 결과 (G 단계)", "",
     f"- 결과 폴더: `{os.path.relpath(res, root)}`",
     "- 이 파일은 `scripts/capacity_report.py` 가 만든다. 손으로 고치지 않는다. 설계와 읽는 법: `docs/capacity-eval.md`",
     f"- 깨우기 기준(SLO): TimeToWake p95 {slo:g}초 이하, 깨우기 실패 0건. {slo:g}초는 이 저장소가 임의로 정한 값이다", ""]
if not runs:
    L += ["해당하는 실행이 없다 (worker 메모리를 제한한 배포의 실행이 아직 없음)."]
else:
    L += ["| 실행 | 갈래 | 세션 N | 깨우기 p50 / p95 (초) | 깨우기 횟수 / 실패 | 자리 없음 거절 | 재우기 p50 / p95 (초) | persist p50 (초) | 초당 재우기 | 내준 자리 최대 (Actor 수) | 내준 메모리 최대 / 용량 (MiB) | 재우는 중 최대 | 전체 실패 | 판정 | 기준 통과 |", "|" + "---|" * 15]
    for r in runs:
        ok = r["wakes"] > 0 and r["wake_fail"] == 0 and (r.get("wake_p95_s") or 1e9) <= slo
        r["pass"] = ok
        L.append(f"| {r['name']} | {r['arm']} | {r['users']} | {f(r.get('wake_p50_s'))} / {f(r.get('wake_p95_s'))} | {r['wakes']} / {r['wake_fail']} | {r['retries']} | {f(r.get('suspend_p50_s'))} / {f(r.get('suspend_p95_s'))} | "
                 f"{f(r['persist_p50_s'])} | {f(r['suspends_per_s'])} | {f(r['alloc_actors'], '{:d}')} | {f(r['alloc_mib'], '{:.0f}')} / {f(r['cap_mib'], '{:.0f}')} | {r['suspending']} | {r['failures']} | {r['verdict']} | {'-' if r['arm'] == 'none' else '예' if ok else '아니오'} |")
    K = max((r["alloc_actors"] or 0 for r in runs if r["arm"] == "none"), default=0)
    L += ["", "## 요약", ""]
    if K:
        L.append(f"- 자리 수 K (재우지 않는 실행에서 worker 가 동시에 내준 Actor 수의 최대): **{K}**")
        L.append(f"- 재우기가 자리를 전혀 잡지 않는다고 가정한 이상값: K × (일하는 시간 + 쉬는 시간) ÷ 일하는 시간 = {K} × ({ACTIVE_S:g} + {IDLE_S:g}) ÷ {ACTIVE_S:g} = **{K * (ACTIVE_S + IDLE_S) / ACTIVE_S:.0f}** (대본의 값으로 계산한 것이고 측정값이 아니다)")
    else:
        L.append("- 자리 수 K 를 구하지 못했다 (재우지 않는 실행 G_none_* 의 cap_10s.txt 에 worker 기록이 없음).")
    for arm in sorted({r["arm"] for r in runs if r["arm"] != "none"}):
        best, broken = None, None
        for r in sorted((x for x in runs if x["arm"] == arm), key=lambda x: x["users"]):
            if r["pass"] and broken is None: best = r["users"]
            elif broken is None: broken = r["users"]
        L.append(f"- 갈래 `{arm}`: 기준을 지킨 최대 세션 수 **{best if best is not None else '없음'}**" + (f", 처음 기준을 넘긴 세션 수 {broken}" if broken else ", 돌린 범위에서는 기준을 넘기지 않음"))
    L += ["", "읽는 법: 갈래 사이에서 달라지는 것은 재우기 한 번이 끝나는 데 걸리는 시간뿐이다. `sync` 의 최대 세션 수가 `async` 보다 작으면, 재우기가 길어진 만큼 자리가 묶여 받을 수 있는 Agent 수가 줄었다는 뜻이다.",
          "`깨우기 시간` 은 자리가 없어 다시 시도한 시간을 포함한다. `자리 없음 거절` 은 그 시도 횟수이고, 깨우기가 끝내 실패한 횟수(`깨우기 실패`)와 다르다. `전체 실패` 에는 이 거절이 들어간다.",
          "`재우는 중 최대` 는 10초마다 센 값이라 짧은 재우기는 잡히지 않는다. `내준 자리` 는 worker 가 Actor 에 예약해 준 몫이고 실제로 쓴 메모리가 아니다."]
text = "\n".join(L) + "\n"
open(f"{res}/CAPACITY.md", "w").write(text); print(text, end="")
