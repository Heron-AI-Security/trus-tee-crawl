#!/usr/bin/env python3
"""Build docs/perf/ for nutch-private from the raw benchmark runs of October 2026.

    python3 gen_perf_docs.py BENCH_RESULTS_DIR TRAINING_CUSTODY_REPO OUT_DIR

One folder per run (docs/perf/<run-id>/) with derived, non-sensitive files only:
  summary.json   every measured value of the run, with its source
  jobs.csv       one row per Hadoop job: phase, start, finish, seconds, YARN CPU ms
  receipts.json  counts of receipts and per-URL outcomes by status (receipt runs only)
  hostcpu.json   whole-node CPU by category, when /proc snapshots exist
and README.md with one row per run. No raw logs, WARCs, project ids, IP addresses or credentials are copied.
VM-hours count the crawl only (nodes x crawl wall clock); cost is VM-hours x the c3-standard-4 list price, without the
TDX surcharge (not in Google's price catalog) or disks."""
import collections, datetime, glob, json, os, re, subprocess, sys

BENCH, TC_REPO, OUT = sys.argv[1:4]
PRICE = 0.2016  # USD per c3-standard-4 hour, us-central1 list price: 4 x 0.03465 + 16 x 0.003938 (billing catalog, 31 Oct 2026)
NUTCH_CC = "3270a761e"  # commoncrawl/nutch, branch cc
FLEET = {"commit": "a98cedea5", "base": "20267a68d", "image": "tc-img-perf1k-1"}
PHASES9 = ["inject", "generate", "generate", "fetch", "parse", "updatedb", "linkdb", "dedup", "dedup"]

# run directory -> (config, nodes, TDX?, notes)
CATALOG = [
    ("vanilla-1k-r1", "plain", 2, True, "1 master + 1 worker"), ("vanilla-1k-r2", "plain", 2, True, "1 master + 1 worker"),
    ("vanilla-1k-r3", "plain", 2, True, "1 master + 1 worker"), ("vanilla-10k-r1", "plain", 2, True, "1 master + 1 worker"),
    ("vanilla-10k-r2", "plain", 2, True, "1 master + 1 worker"), ("vanilla-10k-r3", "plain", 2, True, "1 master + 1 worker"),
    ("vanilla-100k-r1", "plain", 2, True, "1 master + 1 worker"),
    ("plain2w-1k-r1", "plain", 3, False, "non-TDX VMs"), ("plain2w-1k-r2", "plain", 3, False, "non-TDX VMs"),
    ("plain2w-1k-r3", "plain", 3, False, "non-TDX VMs"), ("plain2w-10k-r1", "plain", 3, False, "non-TDX VMs"),
    ("plain2w-10k-r2", "plain", 3, False, "non-TDX VMs"), ("plain2w-10k-r3", "plain", 3, False, "non-TDX VMs"),
    ("plain2w-100k-r1", "plain", 3, False, "non-TDX VMs"),
    ("tdx2w-1k-r1", "plain", 3, True, ""), ("tdx2w-1k-r2", "plain", 3, True, ""), ("tdx2w-1k-r3", "plain", 3, True, ""),
    ("tdx2w-10k-r1", "plain", 3, True, ""), ("tdx2w-10k-r2", "plain", 3, True, ""), ("tdx2w-10k-r3", "plain", 3, True, ""),
    ("tdx2w-100k-r1", "plain", 3, True, ""),
    ("plain-replay-1k-r1", "plain", 2, True, "recorded web (replay proxy)"), ("plain-replay-1k-r2", "plain", 2, True, "recorded web (replay proxy)"),
    ("plain-replay-10k-r1", "plain", 2, True, "recorded web (replay proxy)"), ("plain-replay-10k-r2", "plain", 2, True, "recorded web (replay proxy)"),
    ("plain-replay-10k-r3", "plain", 2, True, "recorded web (replay proxy)"),
    ("plain-replay2-10k-r1", "plain", 2, True, "recorded web, second series"), ("plain-replay2-10k-r2", "plain", 2, True, "recorded web, second series"),
    ("receipts-replay-1k-r1", "receipts", 2, True, "recorded web (replay proxy)"),
    ("receipts-replay-10k-r1", "receipts", 2, True, "recorded web (replay proxy)"), ("receipts-replay-10k-r2", "receipts", 2, True, "recorded web (replay proxy)"),
    ("receipts-replay-10k-r3", "receipts", 2, True, "recorded web (replay proxy)"),
    ("receipts-replay2-10k-r1", "receipts", 2, True, "recorded web, second series"), ("receipts-replay2-10k-r2", "receipts", 2, True, "recorded web, second series"),
    ("receipts-replay2-10k-r3", "receipts", 2, True, "recorded web, second series"),
    ("receipts-live-10k-r1", "receipts", 2, True, ""),
    ("receipts-2round-10k-r1", "receipts", 3, True, "two rounds; round 2 fetches discovered links"),
    ("perf908-plain-r1", "plain", 3, True, "A in the A/B/C series"), ("perf908-plain-r2", "plain", 3, True, "A in the A/B/C series"),
    ("perf908-plain-r3", "plain", 3, True, "A in the A/B/C series"),
    ("perf908-receipts-r1", "receipts", 3, True, "B in the A/B/C series"), ("perf908-receipts-r2", "receipts", 3, True, "B in the A/B/C series"),
    ("perf908-receipts-r3", "receipts", 3, True, "B in the A/B/C series"),
    ("prof908-plain-r1", "plain", 3, True, "async-profiler in every map task (adds CPU)"),
    ("prof908-receipts-r1", "receipts", 3, True, "async-profiler in every map task (adds CPU)"),
    ("perf908-fleet-r1", "full custody", 3, True, "C in the A/B/C series; mutual attestation not in this image"),
    ("perf908-fleet-r2", "full custody", 3, True, "C in the A/B/C series; mutual attestation not in this image"),
    ("perf908-fleet-r3", "full custody", 3, True, "C in the A/B/C series; mutual attestation not in this image"),
]

def size_of(name, seeds):
    m = re.search(r"-(1k|10k|100k)-", name)
    return m.group(1) if m else ("1k" if seeds and seeds < 1500 else "?")

def analyze(d):
    r = subprocess.run([sys.executable, os.path.join(TC_REPO, "bench", "analyze.py"), d], capture_output=True, text=True)
    lines = [l for l in r.stdout.splitlines() if l.startswith("{")]
    return json.loads(lines[-1]) if lines else {}

def jobs_bench(d):
    if not os.path.exists(os.path.join(d, "jobs.txt")): return []
    t = open(os.path.join(d, "jobs.txt")).read()
    out = []
    for block in re.split(r"^== ", t, flags=re.M)[1:]:
        jid = block.split()[0]
        s, f = re.search(r"Start-Time : (\d+)", block), re.search(r"Finish-Time : (\d+)", block)
        cpu = re.search(r"CPU time spent \(ms\)=(\d+)", block)
        if s and f:
            out.append({"job": jid, "start_ms": int(s.group(1)), "finish_ms": int(f.group(1)), "yarn_cpu_ms": int(cpu.group(1)) if cpu else None})
    return sorted(out, key=lambda j: j["start_ms"])

def jobs_fleet(perf):
    t = open(os.path.join(perf, "master.txt")).read()
    apps = t.split("### apps")[1].split("### jhist")[0]
    out = []
    for block in re.split(r"^== ", apps, flags=re.M)[1:]:
        aid = block.split()[0]
        s, f = re.search(r"Start-Time : (\d+)", block), re.search(r"Finish-Time : (\d+)", block)
        if s and f:
            out.append({"job": aid.replace("application_", "job_"), "start_ms": int(s.group(1)), "finish_ms": int(f.group(1)), "yarn_cpu_ms": None})
    jh = os.path.join(perf, "jhist.txt")
    if os.path.exists(jh):
        cpu = {l.split()[1]: int(l.split()[-1].replace(",", "")) for l in open(jh) if "CPU time" in l}
        for j in out:
            j["yarn_cpu_ms"] = cpu.get(j["job"])
    return sorted(out, key=lambda j: j["start_ms"])

def phases(jobs, rounds=1):
    names = PHASES9 * rounds + ["readdb"] * max(0, len(jobs) - 9 * rounds)
    rows, agg = [], collections.OrderedDict()
    for i, j in enumerate(jobs):
        ph = names[i] if i < len(names) else "other"
        if rounds > 1: ph = "r%d-%s" % (i // 9 + 1, ph) if i < 9 * rounds else ph
        rows.append(dict(j, phase=ph, seconds=round((j["finish_ms"] - j["start_ms"]) / 1000, 1)))
        a = agg.setdefault(ph, [j["start_ms"], j["finish_ms"]]); a[0] = min(a[0], j["start_ms"]); a[1] = max(a[1], j["finish_ms"])
    return rows, {k: round((v[1] - v[0]) / 1000) for k, v in agg.items()}

def receipt_counts(tcdir, seeds_n, rounds):
    if not tcdir or not os.path.isdir(tcdir): return None
    rec = sum(1 for f in glob.glob(os.path.join(tcdir, "**", "receipts-*.jsonl"), recursive=True) for l in open(f) if l.strip())
    st, urls = collections.Counter(), set()
    for f in glob.glob(os.path.join(tcdir, "**", "outcomes-*.jsonl"), recursive=True):
        for l in open(f):
            if not l.strip(): continue
            o = json.loads(l); st[o.get("status")] += 1; urls.add(o.get("source_url"))
    return {"receipts": rec, "outcomes": sum(st.values()), "outcomes_by_status": dict(st), "distinct_urls_with_outcome": len(urls),
            "seed_urls_without_outcome": (seeds_n - len(urls)) if rounds == 1 and seeds_n else None}

def patch_commit(date):
    r = subprocess.run(["git", "-C", TC_REPO, "log", "-1", "--before=%sT23:59" % date, "--format=%h", "--", "ccbot/patches/source-receipt.patch"], capture_output=True, text=True)
    return r.stdout.strip() or "?"

def hostcpu(d):
    snap = d if glob.glob(os.path.join(d, "snap-pre-*.json")) else os.path.join(d, "hostcpu")
    if not glob.glob(os.path.join(snap, "snap-pre-*.json")): return None
    r = subprocess.run([sys.executable, os.path.join(TC_REPO, "bench", "hostcpu.py"), snap], capture_output=True, text=True)
    m = re.search(r"ALL\s+busy\s+([\d.]+) s: user\s+([\d.]+), system\s+([\d.]+), softirq\s+([\d.]+)", r.stdout)
    if not m or float(m.group(1)) < 0: return None
    return {"busy_s": float(m.group(1)), "user_s": float(m.group(2)), "system_s": float(m.group(3)), "softirq_s": float(m.group(4)),
            "idle_corrected": "corrected to the crawl's end" in r.stdout}

rows = []
for name, cfg, nodes, tdx, note in CATALOG:
    d = os.path.join(BENCH, name)
    if not os.path.isdir(d): print("skip (missing):", name); continue
    if not name.startswith("perf908-fleet") and not os.path.exists(os.path.join(d, "times")):
        print("skip (run did not complete, no data):", name); continue
    fleet = name.startswith("perf908-fleet")
    rounds = 2 if "2round" in name else 1
    if fleet:
        ev = (glob.glob(os.path.join(d, "evidence-perf-r*")) + glob.glob(os.path.join(d, "full", "evidence-perf-f")))[0]
        perf = os.path.join(d, "evidence-perf-f", "perf") if name.endswith("r1") else os.path.join(ev, "perf")
        jobs = jobs_fleet(perf)
        t = open(os.path.join(perf, "master.txt")).read()
        log = [l for l in t.splitlines() if "tc-crawl:" in l]
        ts = lambda l: datetime.datetime.strptime(l.split()[0], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=datetime.timezone.utc).timestamp()
        start = [ts(l) for l in log if "running Nutch's crawl script" in l][0]; end = [ts(l) for l in log if " done:" in l][0]
        ready = re.search(r"\(after (\d+) s\)", t)
        seeds_n, fetched = 908, int(re.search(r"(\d+) urls fetched", t).group(1))
        a = {"wall_s": round(end - start), "db_fetched": fetched}
        date = datetime.datetime.fromtimestamp(start, datetime.timezone.utc).strftime("%Y-%m-%d")
        commit, image = "%s (on %s)" % (FLEET["commit"], FLEET["base"]), FLEET["image"]
        rc = receipt_counts(os.path.join(ev, "export"), seeds_n, 1)
        hc = hostcpu(ev)
        posts = [json.load(open(f))["t"] for f in glob.glob(os.path.join(ev, "snap-post-*.json")) if os.path.getsize(f)]
        de = os.path.join(ev, "crawl-done.epoch")
        late = (max(posts) - float(open(de).read())) if posts and os.path.exists(de) else 0
        if hc and late > 2 * 3600:
            hc = None; note += "; host CPU discarded: the after-crawl snapshot came %.1f h late" % (late / 3600)
        elif hc and hc.get("idle_corrected"):
            note += "; host CPU corrected for a snapshot %.0f min late" % (late / 60)
        note += "; crawl total includes the fleet's own readdb -stats job"
        extra = {"hdfs_ready_after_start_s": int(ready.group(1)) if ready else None}
    else:
        a = analyze(d); jobs = jobs_bench(d)
        tl = open(os.path.join(d, "times")).read().split()
        start = int(tl[1]); seeds_n = int(tl[3]); fetched = a.get("db_fetched")
        date = datetime.datetime.fromtimestamp(start, datetime.timezone.utc).strftime("%Y-%m-%d")
        commit = "commoncrawl/nutch %s" % NUTCH_CC + (" + training-custody %s receipt patch" % patch_commit(date) if cfg == "receipts" else "")
        image = "stock Ubuntu 22.04 VM image (benchmark cluster, ../bench/setup.sh)"
        rc = receipt_counts(os.path.join(d, "tc_receipts"), seeds_n, rounds) if cfg == "receipts" else None
        hc = hostcpu(d); extra = {}
    jrows, ph = phases(jobs, rounds)
    yarn = sum(j["yarn_cpu_ms"] or 0 for j in jrows[:9 * rounds]) / 1000 if jrows and all(j["yarn_cpu_ms"] is not None for j in jrows[:9 * rounds]) else None
    if not jrows: note = (note + "; " if note else "") + "per-job timings not collected"
    size = size_of(name, seeds_n)
    short = (FLEET["commit"] if fleet else NUTCH_CC)
    series = ("abc" if name.startswith("perf908") else "prof" if name.startswith("prof908") else "replay2" if "replay2" in name
              else "replay" if "replay" in name else "2round" if "2round" in name else "live" if name.startswith(("receipts-live", "vanilla"))
              else "scale")
    rid = "%s-%s-%s-%s-%s%dw-%s-%s" % (date, size, {"plain": "plain", "receipts": "receipts", "full custody": "custody"}[cfg],
                                     series, "tdx" if tdx else "vm", nodes - 1, name.split("-")[-1], short)
    vmh = round(nodes * a["wall_s"] / 3600, 3) if a.get("wall_s") else None
    summary = {"run_id": rid, "source_run": name, "date": date, "config": cfg, "commit": commit, "image": image,
               "nodes": nodes, "machine_type": "c3-standard-4" + (" (Intel TDX)" if tdx else " (no TDX)"), "seed_urls": seeds_n,
               "fetched": fetched, "rounds": rounds, "crawl_wall_s": a.get("wall_s"), "phase_wall_s": ph,
               "yarn_cpu_s_9_jobs": yarn if yarn is not None else a.get("yarn_cpu_s"), "host_cpu": hc, "receipts": rc,
               "vm_hours_crawl": vmh, "cost_usd_crawl_list_price": round(vmh * PRICE, 3) if vmh else None, "notes": note,
               "measured": {k: v for k, v in a.items() if k not in ("run",)}, **extra}
    od = os.path.join(OUT, rid); os.makedirs(od, exist_ok=True)
    json.dump(summary, open(os.path.join(od, "summary.json"), "w"), indent=1)
    with open(os.path.join(od, "jobs.csv"), "w") as f:
        f.write("job,phase,start_utc,finish_utc,seconds,yarn_cpu_ms\n")
        for j in jrows:
            iso = lambda ms: datetime.datetime.fromtimestamp(ms / 1000, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
            f.write("%s,%s,%s,%s,%s,%s\n" % (j["job"].split("_")[-1], j["phase"], iso(j["start_ms"]), iso(j["finish_ms"]), j["seconds"], "" if j["yarn_cpu_ms"] is None else j["yarn_cpu_ms"]))
    if rc: json.dump(rc, open(os.path.join(od, "receipts.json"), "w"), indent=1)
    if hc: json.dump(hc, open(os.path.join(od, "hostcpu.json"), "w"), indent=1)
    assert not any(r["run_id"] == rid for r in rows), "duplicate run id " + rid
    rows.append(summary)

def fmt_ph(ph):
    order = ["inject", "generate", "fetch", "parse", "updatedb", "linkdb", "dedup"]
    keys = [k for k in order if k in ph] + [k for k in ph if k not in order]
    return ", ".join("%s %d" % (k, ph[k]) for k in keys)

rows.sort(key=lambda r: (r["date"], r["run_id"]))
hdr = ["run id", "date", "commit", "image", "nodes, machine", "seed URLs", "fetched", "receipts", "outcomes", "URLs with no outcome",
       "wall time per phase (s)", "VM-hours", "cost (USD)", "notes"]
lines = ["| " + " | ".join(hdr) + " |", "|" + "---|" * len(hdr)]
for r in rows:
    rc = r["receipts"] or {}
    lines.append("| [%s](%s/) | %s | %s | %s | %d x %s | %s | %s | %s | %s | %s | %s | %s | %s | %s |" % (
        r["run_id"], r["run_id"], r["date"], r["commit"], r["image"].split(" (")[0], r["nodes"], r["machine_type"], f"{r['seed_urls']:,}",
        f"{r['fetched']:,}" if r["fetched"] is not None else "—", f"{rc['receipts']:,}" if rc else "—", f"{rc['outcomes']:,}" if rc else "—",
        (f"{rc['seed_urls_without_outcome']:,}" if rc.get("seed_urls_without_outcome") is not None else "—") if rc else "—",
        "total %s: %s" % (r["crawl_wall_s"], fmt_ph(r["phase_wall_s"])), r["vm_hours_crawl"], r["cost_usd_crawl_list_price"], r["notes"] or ""))
open(os.path.join(OUT, "TABLE.md"), "w").write("\n".join(lines) + "\n")
print("runs written:", len(rows))
