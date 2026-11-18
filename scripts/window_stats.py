#!/usr/bin/env python3
"""부하가 실제로 걸린 구간만 잘라 쓰기량·사용률·처리량을 요약한다.
구간: run.txt 의 start~end. turnover 실행이면 boomer 로그의 "turnover fill done" 시각부터(등록과 1분 대기를 뺀다).
사용: window_stats.py <실행 결과 폴더>"""
import datetime as dt, json, re, statistics as st, sys

d = sys.argv[1]
ts = lambda s: dt.datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=dt.timezone.utc).timestamp()  # 로그 시각은 모두 UTC
run = open(f"{d}/run.txt").read()
start = ts(re.search(r"^start=(\S+)", run, re.M).group(1)); end = ts(re.search(r"^end=(\S+)", run, re.M).group(1))
kind = "start..end"
try:
    m = re.search(r'"time":"([^"]+)"[^\n]*turnover fill done', open(f"{d}/boomer_worker.log", errors="replace").read())
    if m: start = ts(m.group(1)); kind = "turnover fill done..end"
except OSError: pass

samples = []; cur = None; sec = None
for line in open(f"{d}/proc_1s.txt", errors="replace"):
    p = line.split()
    if not p: continue
    if p[0] == "T": cur = {"t": float(p[1]), "disk": {}}; samples.append(cur); sec = "D"; continue
    if p[0] in ("M", "P", "C"): sec = p[0]; continue
    if sec == "D" and len(p) >= 14: cur["disk"][p[2]] = (int(p[9]), int(p[12]))
    elif sec == "C" and p[0] == "cpu": cur["cpu"] = [int(x) for x in p[1:9]]
whole = lambda k: not re.search(r"\d$", k) or re.fullmatch(r"(nvme\d+n\d+|vd[a-z]|sd[a-z]|dm-\d+|md\d+)", k)
tot = {k: samples[-1]["disk"][k][0] - samples[0]["disk"][k][0] for k in samples[0]["disk"] if whole(k) and k in samples[-1]["disk"]}
dev = sys.argv[2] if len(sys.argv) > 2 else max(tot, key=tot.get)
X = [s for s in samples if start <= s["t"] <= end and dev in s["disk"]]
if len(X) < 3: sys.exit("not enough samples in the load window")
dur = X[-1]["t"] - X[0]["t"]
mib = (X[-1]["disk"][dev][0] - X[0]["disk"][dev][0]) * 512 / 2**20
util = [min(100.0, (b["disk"][dev][1] - a["disk"][dev][1]) / ((b["t"] - a["t"]) * 10)) for a, b in zip(X, X[1:]) if b["t"] > a["t"]]
q = lambda xs, p: sorted(xs)[min(len(xs) - 1, int(len(xs) * p))]
print(f"window={kind} duration_s={dur:.0f} device={dev}")
print(f"written_MiB={mib:.0f} write_MiB_per_s_mean={mib/dur:.0f}")
print(f"disk_util_pct: mean={100*(X[-1]['disk'][dev][1]-X[0]['disk'][dev][1])/(dur*1000):.0f} p95={q(util,.95):.0f} peak_1s={max(util):.0f}")
if "cpu" in X[0] and "cpu" in X[-1]:
    dv = [b - a for a, b in zip(X[0]["cpu"], X[-1]["cpu"])]; t = sum(dv)
    print(f"cpu_pct_all_cores: busy_mean={100*(t-dv[3]-dv[4])/t:.0f} iowait_mean={100*dv[4]/t:.1f}")
try:
    rows = {r["name"]: r for r in json.load(open(f"{d}/stats.json"))["stats"]}
    s = rows.get("SuspendActor") or rows.get("SuspendActorAsync")  # sync / async 재우기 행
    if s and s["num_requests"]:
        n = s["num_requests"]; med = s["median_response_time"] / 1000
        print(f"suspends={n} suspends_per_s={n/dur:.2f} written_MiB_per_suspend={mib/n:.0f} suspend_p50_s={med:.2f} suspends_in_flight_mean(rate*p50)={n/dur*med:.1f}")
except (OSError, KeyError, ValueError): pass
