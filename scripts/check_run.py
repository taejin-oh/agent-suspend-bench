#!/usr/bin/env python3
"""부하 실행 하나의 결과를 읽어 판정(VERDICT)을 낸다. 사람이나 에이전트가 숫자를 보고 판단하지 않아도 되게 하기 위한 것.

판정 (위에 있는 것이 먼저 적용된다):
  BROKEN    실행이 제대로 되지 않았다 (통계가 없거나 재우기 기록이 0건). 측정값이 아니다
  RESOURCE  노드 자원이 위험했다 (가용 메모리 최소값 1 GiB 미만, 또는 worker pod 재시작)
  FAILURES  실패한 요청이 있다. 값은 측정됐지만 그 조건에서 문제가 생겼다는 뜻
  LIMIT     turnover 의 실제 교체 속도가 목표의 80% 미만. 실패는 없지만 그 구성의 처리 한계에 닿았다
  OK        위의 어느 것도 아님

사용: check_run.py <실행 결과 폴더>      (결과를 화면에 찍고 <폴더>/verdict.txt 에 저장)"""
import json, os, re, sys

MIN_MEM_MIB = 1024      # 가용 메모리가 이 밑으로 내려가면 RESOURCE
LIMIT_RATIO = 0.8       # 실제 교체 속도 / 목표 속도가 이 밑이면 LIMIT
BUSY_PCT = 80           # 부하 구간 평균이 이 이상이면 주의 표시 (판정은 바꾸지 않음)


def read(path):
    try:
        return open(path, errors="replace").read()
    except OSError:
        return ""


def num(pattern, text, cast=float):
    m = re.search(pattern, text, re.M)
    return cast(m.group(1)) if m else None


def load(d):
    """실행 폴더 하나를 읽어 dict 로 돌려준다. report.py 도 이 함수를 쓴다."""
    r = {"name": os.path.basename(os.path.normpath(d)), "reasons": [], "flags": []}
    run, summ = read(f"{d}/run.txt"), read(f"{d}/summary.txt")
    r["users"] = num(r"\busers=(\d+)", run, int)
    r["duration_s"] = num(r"\bduration_s=(\d+)", run, int)
    extra = dict(kv.split("=", 1) for kv in (re.search(r"extra=(.*)", run) or [0, ""])[1].split() if "=" in kv)
    r["mode"] = extra.get("lifecycle_mode", "async")
    r["awake"] = int(extra.get("agentsession_awake", 0))
    r["target_rps"] = float(extra.get("target_rps", 0))
    r["deployed"] = (re.search(r"^deployed=(.*)", run, re.M) or [0, ""])[1].strip()
    r["budget"] = (re.search(r"--upload-memory-budget=(\w+)", run) or [0, "default"])[1]
    try:
        rows = {x["name"]: x for x in json.load(open(f"{d}/stats.json"))["stats"]}
    except (OSError, ValueError, KeyError):
        rows = {}
    pct = lambda x, k: (x.get(f"response_time_percentile_{k}") or 0) / 1000
    sus = rows.get("SuspendActor") or rows.get("SuspendActorAsync")
    wake = rows.get("TimeToWake")
    if sus:
        r["suspends"] = sus["num_requests"]
        r["suspend_p50_s"], r["suspend_p95_s"] = sus["median_response_time"] / 1000, pct(sus, "0.95")
    if wake:
        r["wake_p50_s"], r["wake_p95_s"] = wake["median_response_time"] / 1000, pct(wake, "0.95")
    r["failures"] = sum(x["num_failures"] for n, x in rows.items() if n != "Aggregated")
    r["failed_rows"] = [f"{n}={x['num_failures']}" for n, x in rows.items() if n != "Aggregated" and x["num_failures"]]
    win = summ.split("## load window only")[-1] if "## load window only" in summ else ""
    r["suspends_per_s"] = num(r"suspends_per_s=([\d.]+)", win)
    r["write_mib_s"] = num(r"write_MiB_per_s_mean=([\d.]+)", win)
    r["mib_per_suspend"] = num(r"written_MiB_per_suspend=([\d.]+)", win)
    r["disk_mean"], r["disk_peak"] = num(r"disk_util_pct: mean=([\d.]+)", win), num(r"disk_util_pct: .*peak_1s=([\d.]+)", win)
    r["cpu_mean"] = num(r"cpu_pct_all_cores: busy_mean=([\d.]+)", win)
    r["mem_min_mib"] = num(r"mem_available_MiB: .*min=(\d+)", summ)
    r["psi_io_peak"] = num(r"psi_io_some_avg10: .*peak=([\d.]+)", summ)
    r["persist_p50_s"] = (num(r"atelet +checkpoint .* persist +\d+ +([\d.]+)", summ) or 0) / 1000 or None
    r["dump_p50_s"] = (num(r"atelet +checkpoint .* worker_checkpoint +\d+ +([\d.]+)", summ) or 0) / 1000 or None
    # 객체 저장소 쪽 값을 쓴다 (벤치마크 atespace 만 센다). 노드 쪽 폴더에는 counter 데모 같은 다른 Actor 도 섞인다.
    r["snapshot_mib"] = num(r"^object: actors=\d+ median=(\d+)", summ) or num(r"^node: actors=\d+ median=(\d+)", summ)
    restarts = lambda t: sum(int(p[3]) for p in (l.split() for l in t.splitlines()) if len(p) > 3 and p[3].isdigit())
    r["worker_restarts"] = restarts(read(f"{d}/workers_after.txt")) - restarts(read(f"{d}/workers_before.txt"))

    v = "OK"
    if rows and r["mode"] == "none" and not r["failures"]:
        pass    # 재우지 않는 실행: 재우기 기록이 없는 것이 정상
    elif not rows or not sus or not sus["num_requests"]:
        v = "BROKEN"; r["reasons"].append("통계가 없거나 재우기 기록이 0건")
    elif "not enough samples" in summ:
        v = "BROKEN"; r["reasons"].append("지표 수집(proc_1s.txt)이 비어 있음")
    elif (r["mem_min_mib"] is not None and r["mem_min_mib"] < MIN_MEM_MIB) or r["worker_restarts"] > 0:
        v = "RESOURCE"
        if r["worker_restarts"] > 0: r["reasons"].append(f"worker pod 재시작 {r['worker_restarts']}회")
        if r["mem_min_mib"] is not None and r["mem_min_mib"] < MIN_MEM_MIB: r["reasons"].append(f"가용 메모리 최소 {r['mem_min_mib']:.0f} MiB (< {MIN_MEM_MIB})")
    elif r["failures"]:
        v = "FAILURES"; r["reasons"].append("실패한 요청: " + ", ".join(r["failed_rows"]))
    elif r["awake"] and r["target_rps"] and r["suspends_per_s"] is not None and r["suspends_per_s"] < LIMIT_RATIO * r["target_rps"]:
        v = "LIMIT"; r["reasons"].append(f"실제 교체 초당 {r['suspends_per_s']:.2f}회 < 목표 {r['target_rps']:g}회의 {LIMIT_RATIO:.0%}")
    r["verdict"] = v
    if r["disk_mean"] is not None and r["disk_mean"] >= BUSY_PCT: r["flags"].append("disk_busy")
    if r["cpu_mean"] is not None and r["cpu_mean"] >= BUSY_PCT: r["flags"].append("cpu_busy")
    if r["psi_io_peak"] is not None and r["psi_io_peak"] >= 20: r["flags"].append("io_pressure")
    return r


if __name__ == "__main__":
    if len(sys.argv) != 2: sys.exit(__doc__)
    d = sys.argv[1]; r = load(d)
    f = lambda k, fmt="{:.2f}": "n/a" if r.get(k) is None else fmt.format(r[k])
    out = [f"VERDICT={r['verdict']}", f"run={r['name']}", "reason=" + ("; ".join(r["reasons"]) or "-"), "flags=" + (",".join(r["flags"]) or "-"),
           f"suspend_p50_s={f('suspend_p50_s')} suspend_p95_s={f('suspend_p95_s')} wake_p50_s={f('wake_p50_s')} wake_p95_s={f('wake_p95_s')}",
           f"failures={r['failures']} suspends_per_s={f('suspends_per_s')} target_rps={r['target_rps']:g} mem_min_MiB={f('mem_min_mib', '{:.0f}')} worker_restarts={r['worker_restarts']}"]
    errs = [l for l in read(f"{d}/summary.txt").splitlines() if l.startswith("ERROR")][:5]
    text = "\n".join(out + errs) + "\n"
    open(f"{d}/verdict.txt", "w").write(text); print(text, end="")
