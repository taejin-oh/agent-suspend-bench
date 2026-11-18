#!/usr/bin/env python3
"""재우기(suspend)의 업로드 구간을 "예산 대기"와 "실제 압축·전송"으로 나눠 본다.

입력 (06_run_load.sh 가 실행 폴더에 남기는 원본 기록):
  uploads_raw.jsonl  objectstore-plugin 의 파일별 "Compressed zstd upload" 기록.
                     total 은 업로드 메모리 예산을 얻은 뒤부터 잰 시간이라 대기가 들어 있지 않다.
  phases_raw.jsonl   atelet 의 재우기별 "Checkpoint timing breakdown" 기록. persist 는 대기 + 실제 작업.
파일별 예약 크기는 substrate 소스(pkg/objectstorage/upload.go planStream, S3 경로)의 식으로 계산한다.

사용: analyze_uploads.py <실행 폴더> <예산 MiB: 512 또는 2048> [GOMAXPROCS=10]"""
import datetime as dt, json, re, statistics as st, sys

d, budget = sys.argv[1], int(sys.argv[2]); procs = int(sys.argv[3]) if len(sys.argv) > 3 else 10
MiB = 1 << 20
ts = lambda s: dt.datetime.strptime(s[:19], "%Y-%m-%dT%H:%M:%S").replace(tzinfo=dt.timezone.utc).timestamp() + float("0." + (s[20:].rstrip("Z") or "0"))

def reservation(populated):  # MiB. S3: 버퍼 (4+1)x32 MiB + 압축 worker 수 x (8 x chunk)
    workers = min(procs, (budget - 160) // 64, populated // (8 * MiB) + 1)
    chunk = MiB
    while chunk < 8 * MiB and chunk < populated: chunk <<= 1
    return 160 + workers * 8 * chunk / MiB, workers

run = open(f"{d}/run.txt").read()
start = ts(re.search(r"^start=(\S+)", run, re.M).group(1)); end = ts(re.search(r"^end=(\S+)", run, re.M).group(1)) + 25
m = re.search(r'"time":"([^"]+)"[^\n]*turnover fill done', open(f"{d}/boomer_worker.log", errors="replace").read())
if m: start = ts(m.group(1))

ups = []
for l in open(f"{d}/uploads_raw.jsonl"):
    r = json.loads(l); mm = re.search(r"actors/([^/]+)/snapshots/([^/]+)/(.+)\.zstd$", r["object"])
    if not mm: continue
    e = ts(r["time"]); svc = r["total"] / 1e9
    if not (start <= e <= end): continue
    res, w = reservation(r["populated_bytes"])
    ups.append(dict(actor=mm.group(1), snap=mm.group(2), file=mm.group(3), end=e, begin=e - svc, svc=svc, pop=r["populated_bytes"] / MiB, res=res, workers=w))
cks = []
for l in open(f"{d}/phases_raw.jsonl"):
    r = json.loads(l)
    if not r["msg"].startswith("Checkpoint") or "error.type" in r: continue
    e = ts(r["time"]); k = "ate.actor.checkpoint.duration."
    if start <= e <= end: cks.append(dict(actor=r["ate.actor.uid"], end=e, persist=r.get(k + "persist", 0), dump=r.get(k + "worker_checkpoint", 0), total=r[k + "total"]))

q = lambda xs, p: sorted(xs)[min(len(xs) - 1, int(len(xs) * p))] if xs else float("nan")
print(f"budget={budget}MiB GOMAXPROCS={procs} window_s={end-start:.0f} uploads={len(ups)} suspends={len(cks)}")

print("\n## 파일별 (한 snapshot 은 아래 파일들을 따로 올리고, 파일마다 예산을 따로 예약한다)")
print(f"{'file':28} {'n':>4} {'populated_MiB':>13} {'reserve_MiB':>11} {'workers':>7} {'service_p50_s':>13} {'service_p95_s':>13}")
by = {}
for u in ups: by.setdefault(u["file"], []).append(u)
for f, xs in sorted(by.items(), key=lambda kv: -st.median(x["pop"] for x in kv[1])):
    print(f"{f[:28]:28} {len(xs):>4} {st.median(x['pop'] for x in xs):>13.1f} {st.median(x['res'] for x in xs):>11.0f} {st.median(x['workers'] for x in xs):>7.0f} {q([x['svc'] for x in xs],.5):>13.3f} {q([x['svc'] for x in xs],.95):>13.3f}")

# 재우기별: persist 를 자기 파일의 실제 작업 시간과 그 나머지(대기)로 나눈다
rows = []
for c in cks:
    mine = [u for u in ups if u["actor"] == c["actor"] and c["end"] - c["persist"] - 0.5 <= u["end"] <= c["end"] + 0.05]
    if not mine: continue
    rows.append(dict(persist=c["persist"], dump=c["dump"], files=len(mine), sum_svc=sum(u["svc"] for u in mine), max_svc=max(u["svc"] for u in mine), sum_res=sum(u["res"] for u in mine)))
md = lambda k: st.median(r[k] for r in rows)
print(f"\n## 재우기별 (자기 파일 기록과 이어진 {len(rows)}건, 중앙값)")
print(f"dump_s={md('dump'):.2f} persist_s={md('persist'):.2f} files_per_snapshot={md('files'):.0f} reserve_sum_MiB={md('sum_res'):.0f}")
print(f"own_work_s: longest_file={md('max_svc'):.2f} all_files_one_by_one={md('sum_svc'):.2f}")
w_lo = [max(0.0, r["persist"] - r["sum_svc"]) for r in rows]; w_hi = [max(0.0, r["persist"] - r["max_svc"]) for r in rows]
print(f"waiting_s (persist - 자기 작업): at_least={st.median(w_lo):.2f} at_most={st.median(w_hi):.2f}")
print(f"waiting_share_of_persist: at_least={100*sum(w_lo)/sum(r['persist'] for r in rows):.0f}% at_most={100*sum(w_hi)/sum(r['persist'] for r in rows):.0f}%")

# 시간에 따라: 실제로 작업 중인 파일 수와 예약 합계
ev = sorted([(u["begin"], 1, u["res"]) for u in ups] + [(u["end"], -1, -u["res"]) for u in ups])
t0 = ev[0][0]; n = 0; res = 0.0; last = t0; area_n = area_r = busy = 0.0; mx_n = 0; mx_r = 0.0; near = 0.0
for t, dn, dr in ev:
    dtm = t - last; area_n += n * dtm; area_r += res * dtm
    if n > 0: busy += dtm
    if res > budget - 168: near += dtm  # 가장 작은 파일(168 MiB)도 더 못 받는 상태
    n += dn; res += dr; last = t; mx_n = max(mx_n, n); mx_r = max(mx_r, res)
span = last - t0
print("\n## 시간에 따라 (작업 중인 업로드)")
print(f"files_in_service: mean={area_n/span:.2f} max={mx_n} | reserved_MiB: mean={area_r/span:.0f} max={mx_r:.0f} (budget {budget})")
print(f"time_with_any_upload={100*busy/span:.0f}% time_budget_exhausted(더 못 받는 상태)={100*near/span:.0f}%")
print(f"uploaded_MiB_per_s={sum(u['pop'] for u in ups)/span:.0f} (populated 기준)")
