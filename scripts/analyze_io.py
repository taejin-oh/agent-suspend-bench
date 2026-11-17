#!/usr/bin/env python3
"""collect.sh 가 만든 proc_1s.txt 를 읽어 장치별 쓰기량·피크·IO pressure·CPU 사용률을 요약한다.
사용: analyze_io.py <출력폴더> [장치이름]   (장치를 생략하면 쓰기량이 가장 많은 whole-disk 를 고른다)"""
import re, sys, statistics as st
d = sys.argv[1]; want = sys.argv[2] if len(sys.argv) > 2 else None
samples = []; cur = None
for line in open(f"{d}/proc_1s.txt", errors="replace"):
    p = line.split()
    if not p: continue
    if p[0] == "T": cur = {"t": float(p[1]), "disk": {}, "mem": {}, "psi": {}}; samples.append(cur); sec = "D"; continue
    if cur is None: continue
    if p[0] in ("M", "P", "C"): sec = p[0]; continue
    if sec == "C":
        if p[0] == "cpu": cur["cpu"] = [int(x) for x in p[1:9]]  # user nice system idle iowait irq softirq steal
        continue
    if sec == "D" and len(p) >= 14: cur["disk"][p[2]] = (int(p[9]), int(p[12]), int(p[7]))  # sectors written, ms doing IO, writes
    elif sec == "M": cur["mem"][p[0].rstrip(":")] = int(p[1])
    elif sec == "P" and p[0] in ("some", "full"):
        k = "io" if f"io_{p[0]}" not in cur["psi"] else "mem"
        cur["psi"][f"{k}_{p[0]}"] = float(re.search(r"avg10=([\d.]+)", line).group(1))
if len(samples) < 3: sys.exit("not enough samples")
first, last = samples[0], samples[-1]
tot = {k: (last["disk"][k][0] - first["disk"][k][0]) * 512 / 2**20 for k in first["disk"] if k in last["disk"]}
whole = {k: v for k, v in tot.items() if not re.search(r"(p?\d+)$", k) or re.fullmatch(r"(nvme\d+n\d+|vd[a-z]|sd[a-z]|nbd\d+|dm-\d+|md\d+)", k)}
dev = want or max(whole, key=whole.get)
rate, util = [], []
for a, b in zip(samples, samples[1:]):
    dt = b["t"] - a["t"]
    if dt <= 0 or dev not in a["disk"] or dev not in b["disk"]: continue
    rate.append((b["disk"][dev][0] - a["disk"][dev][0]) * 512 / 2**20 / dt)
    util.append(min(100.0, (b["disk"][dev][1] - a["disk"][dev][1]) / (dt * 10)))
busy = [r for r in rate if r > 1]
q = lambda xs, p: sorted(xs)[min(len(xs) - 1, int(len(xs) * p))] if xs else 0
dur = last["t"] - first["t"]
print(f"duration_s={dur:.0f} samples={len(samples)} device={dev}")
print("written_MiB_by_device: " + ", ".join(f"{k}={v:.0f}" for k, v in sorted(whole.items(), key=lambda x: -x[1])[:5] if v > 0))
print(f"write_MiB_per_s: mean={tot[dev]/dur:.1f} p50={q(rate,.5):.1f} p95={q(rate,.95):.1f} p99={q(rate,.99):.1f} peak_1s={max(rate):.1f}")
print(f"write_MiB_per_s_busy_seconds_only(>1MiB/s): n={len(busy)} mean={st.mean(busy) if busy else 0:.1f}")
print(f"disk_util_pct: mean={st.mean(util):.1f} p95={q(util,.95):.1f} peak={max(util):.1f} seconds_over_90={sum(u>90 for u in util)}")
for k in ("io_some", "io_full", "mem_some", "mem_full"):
    xs = [s["psi"][k] for s in samples if k in s["psi"]]
    if xs: print(f"psi_{k}_avg10: mean={st.mean(xs):.2f} peak={max(xs):.2f}")
cb, cw = [], []
for a, b in zip(samples, samples[1:]):
    if "cpu" not in a or "cpu" not in b: continue
    dv = [y - x for x, y in zip(a["cpu"], b["cpu"])]; t = sum(dv)
    if t > 0: cb.append(100 * (t - dv[3] - dv[4]) / t); cw.append(100 * dv[4] / t)
if cb: print(f"cpu_pct_all_cores: busy_mean={st.mean(cb):.1f} busy_p95={q(cb,.95):.1f} busy_peak={max(cb):.1f} | iowait_mean={st.mean(cw):.1f} iowait_p95={q(cw,.95):.1f} iowait_peak={max(cw):.1f}")
ma = [s["mem"].get("MemAvailable", 0) / 1024 for s in samples]; di = [s["mem"].get("Dirty", 0) / 1024 for s in samples]
print(f"mem_available_MiB: start={ma[0]:.0f} min={min(ma):.0f} end={ma[-1]:.0f} | dirty_pagecache_MiB_peak={max(di):.0f}")
try:
    rows = [l.split() for l in open(f"{d}/sizes_5s.txt")]
    snap = [int(re.search(r"(\d+)=/var/lib/ate/snapshots ", " ".join(r) + " ").group(1)) for r in rows if "node" in r and "snapshots" in " ".join(r)]
    rfs = [int(r[3]) for r in rows if len(r) > 3 and r[2] == "rustfs_kb" and r[3].isdigit()]
    if snap: print(f"node_snapshots_dir_MiB: start={snap[0]/1024:.0f} peak={max(snap)/1024:.0f} end={snap[-1]/1024:.0f}")
    if rfs: print(f"object_store_atespaces_MiB: start={rfs[0]/1024:.0f} peak={max(rfs)/1024:.0f} end={rfs[-1]/1024:.0f}")
except Exception as e: print("sizes: n/a", e)
