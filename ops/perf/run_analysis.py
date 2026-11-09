#!/usr/bin/env python3
"""run_analysis.py EVIDENCE_DIR [options]: the analysis report of one crawl run of any size (what was run, why and how it was measured, the numbers with their units, what looks wrong).
Read-only: it reads the evidence folder and, best effort, Google Cloud Monitoring; it changes nothing except that it writes EVIDENCE_DIR/analysis.md (and time-check.txt when that is missing and the tools are there). Exit 0 whatever it finds.
Options: --label L (default: taken from the folder name evidence-L-f)  --kit DIR (profile-params.env, profile-seeds.txt; default ~/L-kit)  --run-dir DIR (timings.txt; default ~/L-run)  --p56 DIR (verify-export.txt; default ~/L-p56)
         --run-name NAME (identifier-style, e.g. Test_Run_15_URL_2026_11_07_Run_2: names the output files NAME_analysis.md and NAME_summary.json)  --tools DIR (ops/attested of a clone, default ~/nutch-check/ops/attested)  --project P  --price USD_PER_VM_HOUR (default 0.2016, a LIST price: no TDX surcharge, disks, egress, idle time or builds)  --no-monitoring  --title TEXT
One run is one run: no median, no range."""
import base64, collections, datetime as dt, glob, hashlib, json, os, re, statistics, subprocess, sys, urllib.parse, urllib.request
def arg(n, d=None): a = sys.argv; return a[a.index(n) + 1] if n in a and a.index(n) + 1 < len(a) else d
def rd(p, d=""):
    try: return open(p, encoding="utf-8", errors="replace").read()
    except OSError: return d
def key(u): p = urllib.parse.urlsplit(u.strip()); return ((p.hostname or "").lower(), p.path.rstrip("/") or "/")
def klass(o):
    st = o.get("status", "?"); d = str(o.get("detail", "") or "")
    if st == "ACCEPTED": return "ACCEPTED: fetched, with a receipt" if o.get("receipt_sha256") else "ACCEPTED: no receipt hash"
    if st == "HTTP_STATUS": m = re.search(r"(\d{3})", d); return "HTTP_STATUS %s (a redirect or an error status, no page stored)" % (m.group(1) if m else "?")
    d2 = re.sub(r"lastModified=\d*:?\s*", "", re.sub(r"\(\d+\)", "(n)", d)).strip()[:60]; return ("%s: %s" % (st, d2)) if d2 else st
T = lambda z: dt.datetime.strptime(z, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc); iso = lambda t: t.strftime("%Y-%m-%dT%H:%M:%SZ")
fmt_s = lambda s: "%d s = %.1f min" % (round(s), s / 60.0)
def signed_windows(export, segs, tools):
    """{segment: (start, end)} of the SIGNED readings of the tasks of that segment (verified with the pinned keys like verify_time_export.py does)."""
    try:
        sys.path.insert(0, tools); import verify_time_export as V; canonical, roughtime, sr = V._modules(); pinned = json.load(open(V.PINNED))["servers"]
    except Exception: return {}
    out = {}
    for s in segs:
        st = []; en = []
        for f in sorted(glob.glob(os.path.join(export, "tc", "crawl", "segments", s, "tc_receipts", "time-*.jsonl"))):
            for l in V.lines(f):
                try:
                    t = canonical.decode(l)
                    want = hashlib.sha512((b"tc/time-start/v1\x00" + canonical.encode({"attempt": t["attempt"], "nonce": t["nonce"], "seed": t["seed"]})) if t["phase"] == "start" else (b"tc/time-end/v1\x00" + canonical.encode(t["receipts"]))).digest()[:32]
                    m, r = roughtime.verify(base64.b64decode(t["response"]), want, base64.b64decode(pinned[t["server"]]))
                except Exception: continue
                (st if t["phase"] == "start" else en).append(m - r if t["phase"] == "start" else m + r)
        if st and en: out[s] = (dt.datetime.fromtimestamp(min(st), dt.timezone.utc), dt.datetime.fromtimestamp(max(en), dt.timezone.utc))
    return out
def monitoring(project, w0, w1, windows):
    fake = os.environ.get("K1A_FAKE_MONITORING")
    def series(metric, al):
        if fake: return {n: [(t, v) for t, v in pts] for n, pts in json.load(open(fake)).get(metric, {}).items()}
        tok = subprocess.check_output(["gcloud", "auth", "print-access-token"], stderr=subprocess.DEVNULL).decode().strip()
        p = {"filter": 'metric.type="%s" AND metric.labels.instance_name=starts_with("tc-f1-")' % metric, "interval.startTime": iso(w0), "interval.endTime": iso(w1), "aggregation.alignmentPeriod": "60s", "aggregation.perSeriesAligner": al}
        base = "https://monitoring.googleapis.com/v3/projects/%s/timeSeries?" % project; url, out = base + urllib.parse.urlencode(p), []
        while url:
            r = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"Authorization": "Bearer " + tok}), timeout=60)); out += r.get("timeSeries", [])
            url = (base + urllib.parse.urlencode(dict(p, pageToken=r["nextPageToken"]))) if r.get("nextPageToken") else None
        return {s["metric"]["labels"]["instance_name"]: [(pt["interval"]["endTime"], pt["value"].get("doubleValue", float(pt["value"].get("int64Value", 0)))) for pt in s["points"]] for s in out}
    try:
        cpu = series("compute.googleapis.com/instance/cpu/utilization", "ALIGN_MEAN"); rx = series("compute.googleapis.com/instance/network/received_bytes_count", "ALIGN_SUM"); tx = series("compute.googleapis.com/instance/network/sent_bytes_count", "ALIGN_SUM")
    except Exception as e: return None, "Cloud Monitoring was not available (%s: %s)" % (type(e).__name__, str(e)[:120])
    if not cpu: return None, "Cloud Monitoring returned no series for the VMs (deleted VMs keep their metrics only for the retention time, or the API is not enabled)"
    res = {}
    for wn, (a, b) in windows.items():
        rows = {}
        for n in sorted(cpu):
            c = [v for t, v in cpu[n] if iso(a) < t <= iso(b)]; r = sum(v for t, v in rx.get(n, []) if iso(a) < t <= iso(b)) / 1e6; s = sum(v for t, v in tx.get(n, []) if iso(a) < t <= iso(b)) / 1e6
            rows[n] = {"cpu_mean": 100 * sum(c) / max(1, len(c)), "cpu_max": 100 * max(c or [0]), "vcpu_s": sum(c) * 4 * 60, "mb_in": r, "mb_out": s}
        res[wn] = rows
    wk = [n for n in cpu if not n.endswith("-m")]; a0, b0 = windows[next(iter(windows))]; tss = sorted({t for n in wk for t, _ in cpu[n] if iso(a0) < t <= iso(b0)}); idle = 0
    for t in tss:
        vals = [v for n in wk for tt, v in cpu[n] if tt == t]
        if vals and sum(vals) / len(vals) < 0.05: idle += 1
    res["__idle__"] = (idle, len(tss))
    return res, ""
def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("--"): print(__doc__.split("\n")[0]); return 2
    E = os.path.expanduser(sys.argv[1]).rstrip("/"); H = os.path.expanduser("~"); m = re.match(r"evidence-(.+)-f$", os.path.basename(E)); label = arg("--label", m.group(1) if m else "run")
    kit = os.path.expanduser(arg("--kit", os.path.join(H, label + "-kit"))); rundir = os.path.expanduser(arg("--run-dir", os.path.join(H, label + "-run"))); p56 = os.path.expanduser(arg("--p56", os.path.join(H, label + "-p56")))
    tools = os.path.expanduser(arg("--tools", os.path.join(H, "nutch-check", "ops", "attested"))); price = float(arg("--price", "0.2016")); project = arg("--project", "training-custody"); export = os.path.join(E, "export")
    segroot = os.path.join(export, "tc", "crawl", "segments")
    segs = sorted(x for x in os.listdir(segroot) if re.fullmatch(r"\d{14}", x)) if os.path.isdir(segroot) else []
    if not segs: print("ANALYSIS-FAILED: no segments under %s" % segroot); return 2
    seg_t = [dt.datetime.strptime(x, "%Y%m%d%H%M%S").replace(tzinfo=dt.timezone.utc) for x in segs]
    if not os.path.exists(os.path.join(E, "time-check.txt")) and os.path.exists(os.path.join(tools, "verify_time_export.py")):
        try: open(os.path.join(E, "time-check.txt"), "w").write(subprocess.run([sys.executable, "-B", os.path.join(tools, "verify_time_export.py"), export], capture_output=True, text=True, timeout=300).stdout)
        except Exception: pass
    params = dict(l.strip().split("=", 1) for l in rd(os.path.join(kit, "profile-params.env")).split("\n") if l.strip() and not l.startswith("#") and "=" in l)
    seeds = [l.strip() for l in rd(os.path.join(kit, "profile-seeds.txt")).split("\n") if l.strip() and not l.startswith("#")]
    try: ref = json.loads(rd(os.path.join(E, "reference-values.json")) or "{}")
    except ValueError: ref = {}
    commit = ref.get("commit", "?"); fleet = [l.split("\t")[0] for l in rd(os.path.join(E, "fleet.tsv")).split("\n") if l.strip() and not l.startswith("#")]
    rounds = []; outs = []; per_task = collections.Counter()
    for i, s in enumerate(segs):
        o_r = []; rc = 0
        for f in sorted(glob.glob(os.path.join(segroot, s, "tc_receipts", "outcomes-*.jsonl"))):
            for l in open(f, encoding="utf-8"):
                if l.strip(): o = json.loads(l); o["_task"] = re.sub(r"^attempt_\d+_\d+_", "", re.search(r"outcomes-(.+)\.jsonl", os.path.basename(f)).group(1)); o_r.append(o); per_task[(s, o["_task"])] += 1
        mm = re.search(r"count=(\d+)", rd(os.path.join(segroot, s, "tc_receipts", "fetchlist.txt")).split("\n")[0]); sched = int(mm.group(1)) if mm else None
        rounds.append({"seg": s, "start": seg_t[i], "sched": sched, "outs": o_r, "st": collections.Counter(o.get("status") for o in o_r), "rec": sum(1 for o in o_r if o.get("status") == "ACCEPTED" and o.get("receipt_sha256"))}); outs += o_r
    n_seed = len(seeds) or len(rounds[0]["outs"]); sk = {key(s) for s in seeds}; okc = collections.Counter(key(o.get("source_url", "")) for o in outs)
    missing = [s for s in seeds if key(s) not in okc]; extra = sum(1 for o in outs if sk and key(o.get("source_url", "")) not in sk)
    cl = collections.Counter(klass(o) for o in outs); bs = collections.Counter(o.get("status", "?") for o in outs); receipts = sum(r["rec"] for r in rounds)
    tc = rd(os.path.join(E, "time-check.txt")); mw = re.search(r"signed window (\S+ \S+)Z \.\. (\S+ \S+)Z \((\d+) s\)", tc); mr = re.search(r"(\d+) receipt\(s\).*?(\d+) authenticated, (\d+) with every certificate valid", tc); mq = re.search(r"(\d+) reading\(s\) of (\d+) task\(s\)", tc)
    log = rd(os.path.join(E, "master-log-lines.txt")); ev = {}
    for l in log.split("\n"):
        m2 = re.search(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) (tc-crawl|tc-export): (.*)", l)
        if not m2: continue
        t, who, txt = T(m2.group(1)), m2.group(2), m2.group(3)
        for k, w, pre in (("start", "tc-crawl", "start:"), ("cluster", "tc-crawl", "HDFS has its DataNodes"), ("script", "tc-crawl", "the seeds are in HDFS"), ("done", "tc-crawl", "done:"), ("manifest", "tc-export", "manifest:"), ("x_done", "tc-export", "done:")):
            if who == w and txt.startswith(pre): ev.setdefault(k, t)
    dm = re.search(r"done: (\d+) urls fetched", log); fetched_db = int(dm.group(1)) if dm else None
    tot_b = 0; nfile = 0; warc_b = 0
    for dp, _, fs in os.walk(export):
        for f in fs:
            sz = os.path.getsize(os.path.join(dp, f)); tot_b += sz; nfile += 1; warc_b += sz if "warc" in f.lower() else 0
    stages = [(m3.group(1), int(m3.group(2))) for m3 in (re.match(r"([a-z0-9-]+): (\d+) min", l) for l in rd(os.path.join(rundir, "timings.txt")).split("\n")) if m3]
    vtxt = rd(os.path.join(p56, "verify-export.txt")); checks = re.findall(r"^\[(\d+)\] (PASS|FAIL|NOT CHECKED)\s+(.*)$", vtxt, re.M)
    cs = seg_t[0]; ce = ev.get("done"); sw = int(mw.group(3)) if mw else None
    script_s = (ev["done"] - ev["script"]).total_seconds() if "script" in ev and "done" in ev else None; crawl_s = (ce - cs).total_seconds() if ce else None
    whole_s = (ev["done"] - ev["start"]).total_seconds() if "start" in ev and "done" in ev else None; exp_s = (ev["x_done"] - ev["done"]).total_seconds() if "x_done" in ev and "done" in ev else None
    for i, r in enumerate(rounds):
        end = seg_t[i + 1] if i + 1 < len(rounds) else ce; r["end"] = end; r["secs"] = (end - r["start"]).total_seconds() if end else None
    win = signed_windows(export, segs, tools); cp_rows = []
    for i, r in enumerate(rounds):
        w = win.get(r["seg"]); nxt = r["end"]
        if w and nxt and r["start"] < w[0] <= w[1] <= nxt + dt.timedelta(seconds=30): cp_rows.append((i + 1, (w[0] - r["start"]).total_seconds(), (w[1] - w[0]).total_seconds(), (nxt - w[1]).total_seconds(), r["secs"]))
    tt = ""; tt_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "run_task_times.py")
    if not os.path.exists(tt_script): tt_script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "k1a-tasktimes.py")
    if os.path.exists(tt_script) and os.path.isdir(tools):
        try: tt = subprocess.run([sys.executable, "-B", tt_script, E, "--tools", tools], capture_output=True, text=True, timeout=600).stdout
        except Exception: tt = ""
    durs = [int(m5.group(4)) for m5 in re.finditer(r"^(m_\d+_\d+)\s+(\d\d:\d\d:\d\d)\s+(\d\d:\d\d:\d\d)\s+(\d+)\s", tt, re.M)]; strag = (max(durs), statistics.median(durs)) if durs else None
    mon = None; mnote = "not requested (--no-monitoring)"
    if "--no-monitoring" not in sys.argv and ce and fleet:
        win = {"crawl (first segment to done)": (cs, ce)}
        if len(rounds) > 1:
            for i, r in enumerate(rounds):
                if r["end"]: win["round %d (segment %s to %s)" % (i + 1, r["seg"][8:], "next segment" if i + 1 < len(rounds) else "done")] = (r["start"], r["end"])
        if "x_done" in ev: win["export (crawl done to export done)"] = (ev["done"], ev["x_done"])
        mon, mnote = monitoring(project, (cs - dt.timedelta(minutes=2)).replace(second=0, microsecond=0), ((ev.get("x_done") or ce) + dt.timedelta(minutes=2)).replace(second=0, microsecond=0), win)
    L = []; P = L.append
    run_name = arg("--run-name", label); P("# %s: analysis of the run `%s` (commit `%s`)" % (arg("--title", "Run analysis"), run_name, commit[:12])); P("")
    P("Generated %s UTC by `run_analysis.py`, read-only, from `%s`. Every number says where it comes from (last section). This is **one run**: no median, no range, and the live web changes from day to day." % (dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%d %H:%M"), E)); P("")
    P("## 1. What was run"); P(""); P("| Item | Value |"); P("|---|---|")
    P("| Commit under test | `%s` |" % commit); P("| Fleet | %d VMs (%s), each `c3-standard-4` = 4 vCPUs and 16 GB RAM, Intel TDX |" % (len(fleet), ("1 master + %d worker(s)" % (len(fleet) - 1)) if fleet else "?"))
    P("| Seeds | %d URLs in `profile-seeds.txt` |" % n_seed)
    cap = (int(params["SIZE_FETCHLIST"]) // int(params["NUM_TASKS"])) if params.get("SIZE_FETCHLIST", "").isdigit() and params.get("NUM_TASKS", "").isdigit() and int(params["NUM_TASKS"]) else "?"
    P("| Crawl profile | rounds %s, fetch tasks %s, tasks %s, threads per task %s, fetch time limit %s min, fetch list size %s (cap per task = size / tasks = %s URLs) |" % (params.get("ROUNDS", "?"), params.get("NUM_FETCHERS", "?"), params.get("NUM_TASKS", "?"), params.get("NUM_THREADS", "?"), params.get("TIME_LIMIT_FETCH", "?"), params.get("SIZE_FETCHLIST", "?"), cap))
    P("| When (UTC) | crawl %s to %s; export done %s |" % (iso(cs)[:19], iso(ce)[11:19] if ce else "?", iso(ev["x_done"])[11:19] if "x_done" in ev else "?")); P("")
    P("## 2. Why and how it was measured"); P("")
    P("- **Why:** to find out, on our own branch as pushed, what a crawl of %d seeds in %d round(s) does on %d TDX VM(s): how many pages are fetched and authenticated, where the time and the resources go, and whether the whole verifier accepts the export." % (n_seed, len(rounds), len(fleet)))
    P("- **Clocks (they differ on purpose):** the *segment name* is the time of a round's generate step; the *master's log lines* mark the start and end of the crawl script and of the export; the *signed window and each task's signed start and end* come from a Roughtime server, not from the crawler's clock; *Cloud Monitoring* gives CPU and network of each VM **from the host side**, in 60 s steps; the *fetch dates* (WARC-Date) are the crawler's own unsigned clock.")
    P("- **Not measured:** per-job times of the Hadoop jobs (the sealed image has no YARN access), memory, disk I/O, the cost of builds and verification, and any plain crawl without custody on this fleet."); P("")
    P("## 3. What the crawl produced"); P(""); P("### 3.1 Rounds"); P("")
    P("| Round | Starts (UTC) | Takes | Scheduled | Outcomes | Receipts | Statuses |"); P("|---|---|---|---|---|---|---|")
    for i, r in enumerate(rounds): P("| %d | %s | %s | %s | %d | %d | %s |" % (i + 1, iso(r["start"])[11:19], fmt_s(r["secs"]) if r["secs"] else "?", r["sched"] if r["sched"] is not None else "?", len(r["outs"]), r["rec"], ", ".join("%s %d" % kv for kv in sorted(r["st"].items()))))
    P(""); P("A round takes the time from its segment (its generate step) to the next segment, and the last one to the `crawl done` marker, so it includes the jobs that follow the fetching."); P("")
    P("### 3.2 Outcomes"); P(""); P("| Class of outcome | Count | Share of %d outcomes |" % len(outs)); P("|---|---|---|")
    for c, k in sorted(cl.items(), key=lambda x: -x[1]): P("| %s | %d | %.1f %% |" % (c.replace("|", "/"), k, 100.0 * k / max(1, len(outs))))
    P(""); order = ["ACCEPTED", "NOT_FETCHED", "HTTP_STATUS", "NOT_HTTPS", "TRUNCATED", "NOT_ATTEMPTED"]; P("| Headline | Value |"); P("|---|---|")
    P("| Scheduled per round / outcomes in all rounds / seeds without an outcome | %s / %d / **%d** |" % (", ".join(str(r["sched"]) for r in rounds), len(outs), len(missing)))
    P("| Pages fetched, as counted by the crawl database | %s |" % (fetched_db if fetched_db is not None else "?"))
    P("| Receipts (ACCEPTED with a receipt) | %d (%.1f %% of the %d outcomes) |" % (receipts, 100.0 * receipts / max(1, len(outs)), len(outs)))
    if mr: P("| Receipts authenticated by the signed-time check | %s of %s; **%d not authenticated** |" % (mr.group(2), mr.group(1), int(mr.group(1)) - int(mr.group(2))))
    P("| Outcomes by status | %s |" % ", ".join("%s %d" % (k, bs[k]) for k in order + sorted(set(bs) - set(order)) if bs.get(k)))
    pt = sorted(per_task.values()); P("| Fetch tasks that wrote outcomes (all rounds); outcomes per task (smallest, median, largest) | %d; %d, %d, %d |" % (len(pt), pt[0], pt[len(pt) // 2], pt[-1]))
    P("| Size of the export | %.1f MB in %d files (WARC files %.1f MB) |" % (tot_b / 1e6, nfile, warc_b / 1e6))
    if receipts and warc_b: P("| WARC bytes per receipt | %.0f kB |" % (warc_b / 1e3 / receipts))
    P("")
    if 0 < len(seeds) <= 60:
        P("### 3.3 Each seed"); P(""); P("| # | Seed | Round-1 outcome | Task |"); P("|---|---|---|---|")
        first = {}
        for r in rounds:
            for o in r["outs"]: first.setdefault(key(o.get("source_url", "")), o)
        for i, s in enumerate(seeds, 1):
            o = first.get(key(s)); P("| %d | `%s` | %s | %s |" % (i, s[:70], klass(o).replace("|", "/") if o else "**no outcome**", o["_task"] if o else "-"))
        P("")
    P("## 4. Time"); P(""); P("| Measure | Value |"); P("|---|---|")
    if "cluster" in ev and "start" in ev: P("| Cluster wait (crawl driver start to HDFS ready) | %s |" % fmt_s((ev["cluster"] - ev["start"]).total_seconds()))
    if script_s is not None: P("| Nutch crawl script (seeds in HDFS to done) | %s |" % fmt_s(script_s))
    if crawl_s is not None: P("| First segment to the done marker | %s |" % fmt_s(crawl_s))
    if whole_s is not None: P("| The whole crawl driver (start to done) | %s |" % fmt_s(whole_s))
    if sw is not None: P("| **Signed fetch window** (first task start to last task end, all rounds, time server's clock) | %s%s |" % (fmt_s(sw), (", from %d readings of %d tasks" % (int(mq.group(1)), int(mq.group(2)))) if mq else ""))
    if exp_s is not None: P("| Export (crawl done to export done) | %s |" % fmt_s(exp_s))
    if sw and fetched_db: P("| Pages fetched per second of signed window | %.3f pages/s for the whole fleet (the window may contain idle time: see section 5) |" % (fetched_db / sw))
    P("")
    if cp_rows:
        P("**4.1 Critical path of each round** (the three parts add up to the round time; the middle part is the SIGNED window of that round's fetch tasks):"); P(""); P("| Round | Generate and fetch start-up (segment to first task start) | Fetch tasks (first start to last end, signed) | Later jobs (last task end to next segment or done) | Round |"); P("|---|---|---|---|---|")
        for n, a, b, c, tot in cp_rows: P("| %d | %s (%.0f %%) | %s (%.0f %%) | %s (%.0f %%) | %s |" % (n, fmt_s(a), 100 * a / tot, fmt_s(b), 100 * b / tot, fmt_s(c), 100 * c / tot, fmt_s(tot)))
        P("")
    if stages: P("Stages of the kit (minutes): " + ", ".join("%s %d" % s for s in stages) + ". Sum of the stages: %d min." % sum(m4 for _, m4 in stages)); P("")
    P("## 5. Each fetch task: signed time and dead tail"); P("")
    if tt.strip(): P("```"); P(tt.strip()[:6000]); P("```")
    else: P("*Not available (needs `run_task_times.py` next to this script and `--tools`).*")
    if strag: P(""); P("Straggler view: the largest task took %d s and the median task %d s (ratio %.1f). A fetch job lasts as long as its slowest task, so the signed window of a round is set by one task, not by the number of pages." % (strag[0], strag[1], strag[0] / max(1.0, strag[1])))
    P(""); P("## 6. Fleet resources (host side, Cloud Monitoring)"); P("")
    if not mon: P("*Not available: %s.*" % mnote); P("")
    else:
        for wn, rows in mon.items():
            if wn == "__idle__": continue
            P("**Window: %s**" % wn); P(""); P("| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |"); P("|---|---|---|---|---|---|"); tv = ti = to = 0.0
            for n, r in rows.items(): P("| %s | %.1f | %.1f | %.0f | %.1f | %.1f |" % (n, r["cpu_mean"], r["cpu_max"], r["vcpu_s"], r["mb_in"], r["mb_out"])); tv += r["vcpu_s"]; ti += r["mb_in"]; to += r["mb_out"]
            P("| **all %d VMs** | | | **%.0f** | **%.1f** | **%.1f** |" % (len(rows), tv, ti, to)); P("")
            if wn.startswith("crawl"):
                wk = [r["cpu_mean"] for n, r in rows.items() if not n.endswith("-m")]
                if wk: P("- Workers: CPU mean %.1f %% (smallest %.1f, largest %.1f), on average %.2f of 4 vCPUs." % (statistics.mean(wk), min(wk), max(wk), statistics.mean(wk) / 25.0))
                if fetched_db: P("- Per fetched page: %.2f vCPU-seconds and %.1f MB sent over the fleet network (web content in the WARC files: %.3f MB per page); the network volume is far above the web content, so most of it is Hadoop's own traffic (not decomposed)." % (tv / fetched_db, to / fetched_db, (warc_b / 1e6 / fetched_db) if warc_b else 0))
                vmh = len(fleet) * (ce - cs).total_seconds() / 3600.0; P("- Cost of the crawl window at the list price of %.4f USD per VM-hour: %d VMs x %.3f h = %.2f VM-hours = **%.2f USD** (no TDX surcharge, disks, egress, idle time, builds or verification)." % (price, len(fleet), (ce - cs).total_seconds() / 3600.0, vmh, vmh * price)); P("")
        P("*Method: utilization is the mean over each 60 s step times 4 vCPUs times 60 s; the window edges are rounded to whole minutes, so vCPU-seconds are good to about one minute of one VM.*"); P("")
    P("## 7. Verification"); P("")
    if checks:
        P("| Check | Result | What it checks |"); P("|---|---|---|")
        for n, r, t5 in checks: P("| [%s] | **%s** | %s |" % (n, r, t5.strip()[:150].replace("|", "/")))
        P("")
        for n, r, t5 in checks:
            if r == "FAIL":
                blk = re.search(r"^\[%s\] FAIL.*?(?=^\[\d+\] (?:PASS|FAIL|NOT CHECKED)|^VERIFY-EXPORT)" % n, vtxt, re.M | re.S)
                P("Detail of the failed check [%s]:" % n); P(""); P("```"); P("\n".join((blk.group(0) if blk else "(no detail lines found)").split("\n")[:25])[:2500]); P("```"); P("")
    else: P("*No `verify-export.txt` in `%s` (give `--p56`).*" % p56); P("")
    nvm = len(fleet); usd = lambda secs: nvm * secs / 3600.0 * price; P("## 8. Cost (list price %.4f USD per VM-hour; the fleet of %d VMs only: no TDX surcharge, disks, egress, builders or verification)" % (price, nvm)); P(""); crows = []
    if "start" in ev: crows.append(("Driver start to first segment (cluster wait, inject, generate)", (cs - ev["start"]).total_seconds()))
    for n, a, b, c, tot in cp_rows: crows += [("Round %d: generate and fetch start-up" % n, max(0.0, a)), ("Round %d: fetch tasks (signed window)" % n, max(0.0, b)), ("Round %d: later jobs" % n, max(0.0, c))]
    if not cp_rows and crawl_s is not None: crows.append(("First segment to crawl done", crawl_s))
    if exp_s is not None: crows.append(("Export (crawl done to export done)", exp_s))
    ctot = sum(x for _, x in crows) or 1.0; P("| Phase | Seconds | VM-hours | USD | Share |"); P("|---|---|---|---|---|")
    for nm, x in crows: P("| %s | %.0f | %.3f | %.3f | %.1f %% |" % (nm, x, nvm * x / 3600.0, usd(x), 100 * x / ctot))
    P("| **Total (driver start to export done)** | **%.0f** | **%.3f** | **%.2f** | |" % (ctot, nvm * ctot / 3600.0, usd(ctot))); P("")
    cost_1000 = None
    if crawl_s is not None and fetched_db: cost_1000 = usd(crawl_s) / fetched_db * 1000; P("- **Cost per 1,000 pages fetched** (crawl window, first segment to done): %.2f USD (%d pages in %.2f USD); per 1,000 receipts: %.2f USD." % (cost_1000, fetched_db, usd(crawl_s), usd(crawl_s) / max(1, receipts) * 1000))
    if "start" in ev and ce and fetched_db: P("- Including the cluster wait and inject (driver start to done): %.2f USD per 1,000 pages." % (usd((ce - ev["start"]).total_seconds()) / fetched_db * 1000))
    idle_cost = None
    if mon and "__idle__" in mon and mon["__idle__"][1]: im, it = mon["__idle__"]; idle_cost = nvm * im * 60 / 3600.0 * price; P("- **Idle time:** %d of the %d minutes of the crawl window had a worker CPU mean below 5 %%; those %d minutes cost %.2f USD (%.0f %% of the crawl window's %.2f USD)." % (im, it, im, idle_cost, 100.0 * idle_cost / max(1e-9, usd(crawl_s)), usd(crawl_s)))
    fl_min = dict(stages).get("fleet")
    if fl_min: P("- The fleet stage of the kit (boot to the end of the fetch of the export) took %d min: %d VMs x %d min = %.2f VM-hours = %.2f USD." % (fl_min, nvm, fl_min, nvm * fl_min / 60.0, nvm * fl_min / 60.0 * price))
    P("")
    P("## 9. Export and scaling model"); P("")
    mf = re.search(r"manifest: (\d+) files", log); up = re.search(r"uploaded (\d+) objects", log); exp_model = {}
    if mf and "manifest" in ev and "done" in ev:
        mfs = (ev["manifest"] - ev["done"]).total_seconds(); nf = int(mf.group(1)); exp_model["manifest_seconds"] = mfs; exp_model["manifest_files"] = nf; exp_model["manifest_seconds_per_file"] = mfs / nf
        P("- **Manifest phase** (crawl done to the export manifest): %.0f s for %d files = **%.2f s per file**; the export holds %.1f MB, so %.1f s per MB." % (mfs, nf, mfs / nf, tot_b / 1e6, mfs / max(0.001, tot_b / 1e6)))
    if up and "x_done" in ev and "manifest" in ev:
        ups = (ev["x_done"] - ev["manifest"]).total_seconds(); no = int(up.group(1)); exp_model["upload_seconds"] = ups; exp_model["upload_objects"] = no; exp_model["upload_seconds_per_object"] = ups / no; P("- **Upload** (manifest to export done): %.0f s for %d objects = %.2f s per object." % (ups, no, ups / no))
    if mon and "export (crawl done to export done)" in mon:
        mrow = [r for n, r in mon["export (crawl done to export done)"].items() if n.endswith("-m")]; wrow = [r["cpu_mean"] for n, r in mon["export (crawl done to export done)"].items() if not n.endswith("-m")]
        if mrow and wrow: P("- During the export the master's CPU mean was %.1f %% of 4 vCPUs and the workers' %.1f %%%s" % (mrow[0]["cpu_mean"], statistics.mean(wrow), ": the export runs on the master alone." if mrow[0]["cpu_mean"] > 3 * statistics.mean(wrow) else "."))
    if "manifest_seconds_per_file" in exp_model: P("- **Model, from this run:** export time is about %.1f s x the number of files, whatever their size. At this rate 1,000 files take about %.0f min. Check the model against another run before relying on it." % (exp_model["manifest_seconds_per_file"] + exp_model.get("upload_seconds_per_object", 0), (exp_model["manifest_seconds_per_file"] + exp_model.get("upload_seconds_per_object", 0)) * 1000 / 60.0))
    P("")
    P("## 10. Findings (rules applied automatically)"); P(""); F = []
    F.append("**%d seeds have no outcome**: first %s" % (len(missing), missing[0]) if missing else "Every seed has an outcome (0 seeds without an outcome).")
    if mr and int(mr.group(1)) != int(mr.group(2)): F.append("**%d of %s receipts are not authenticated** by the signed-time check." % (int(mr.group(1)) - int(mr.group(2)), mr.group(1)))
    if bs.get("NOT_ATTEMPTED"): F.append("%d URLs were NOT_ATTEMPTED (reason in the outcome: task timeout)." % bs["NOT_ATTEMPTED"])
    mt = re.search(r"tasks of 290 s or more: (\d+)", tt); mdt = re.search(r"tasks with a tail of 200 s or more: (\d+)", tt)
    if mdt and int(mdt.group(1)) > 0: F.append("**%s fetch task(s) idled for 200 s or more after their last page** (dead tail, section 5). With NOT_ATTEMPTED URLs this fits the fetcher's 300 s idle abort after a deferral; one explanation is a host whose robots.txt fails with a 5xx (deferred for 300 s by default). Check the hosts of the NOT_ATTEMPTED URLs." % mdt.group(1))
    if bs.get("TRUNCATED"): F.append("%d pages were TRUNCATED at the content limit." % bs["TRUNCATED"])
    if strag and strag[0] >= 10 * max(1.0, strag[1]) and strag[0] >= 60: F.append("**Straggler:** the slowest fetch task took %d s against a median of %d s: one task sets the length of a fetch job." % strag)
    if "manifest_seconds_per_file" in exp_model: F.append("Export: %.2f s per file for %d files (the manifest phase alone took %.0f s)." % (exp_model["manifest_seconds_per_file"], exp_model["manifest_files"], exp_model["manifest_seconds"]))
    if idle_cost is not None and mon["__idle__"][0]: F.append("%d idle minute(s) in the crawl window cost %.2f USD." % (mon["__idle__"][0], idle_cost))
    if bs.get("NOT_HTTPS"): F.append("%d seeds or links ended as NOT_HTTPS: no receipt is possible for them." % bs["NOT_HTTPS"])
    if len(rounds) > 1 and any(r["secs"] for r in rounds): F.append("Round times: " + ", ".join("round %d %s" % (i + 1, fmt_s(r["secs"]) if r["secs"] else "?") for i, r in enumerate(rounds)) + ".")
    if mon and "crawl (first segment to done)" in mon:
        wk = [r["cpu_mean"] for n, r in mon["crawl (first segment to done)"].items() if not n.endswith("-m")]
        if wk and statistics.mean(wk) < 25: F.append("The workers were mostly idle: mean CPU %.1f %% of 4 vCPUs." % statistics.mean(wk))
    if any(r == "FAIL" for _, r, _ in checks): F.append("**Verification failed:** " + ", ".join("[%s]" % n for n, r, _ in checks if r == "FAIL") + ".")
    elif checks and all(r == "PASS" for _, r, _ in checks): F.append("All %d verification checks pass." % len(checks))
    for f in F: P("- " + f)
    P(""); P("## 11. Where each number comes from"); P(""); P("| Number | Source |"); P("|---|---|")
    for a, b in (("Outcomes, receipts, per round, per seed", "signed outcome records `tc/crawl/segments/*/tc_receipts/outcomes-*.jsonl` and `fetchlist.txt`"), ("Round start", "name of the segment folder"), ("Crawl start, end, export end", "`master-log-lines.txt` (master log lines collected during the run)"),
                 ("Signed window, readings, authenticated receipts", "`time-check.txt` (`verify_time_export.py`)"), ("Each task's signed start and end, fetch dates, critical path per round", "`run_task_times.py` and the signed readings (WARC-Date is the crawler's clock)"), ("Cost, idle minutes", "VM-seconds of each phase x the list price; idle = minutes of the crawl window with a worker CPU mean below 5 % (Cloud Monitoring)"), ("Export model", "master log lines `tc-export: manifest: N files` and `uploaded M objects`"), ("CPU and network per VM", "Cloud Monitoring `instance/cpu/utilization`, `network/received_bytes_count`, `network/sent_bytes_count`"),
                 ("Stage minutes", "`%s/timings.txt`" % rundir), ("Verification checks", "`%s/verify-export.txt`" % p56)): P("| %s | %s |" % (a, b))
    out = "\n".join(L) + "\n"; f_md = os.path.join(E, run_name + "_analysis.md"); f_js = os.path.join(E, run_name + "_summary.json"); open(f_md, "w", encoding="utf-8", newline="\n").write(out)
    cw = mon.get("crawl (first segment to done)") if mon else None; wkc = [r["cpu_mean"] for n, r in cw.items() if not n.endswith("-m")] if cw else []
    summary = {"run_name": run_name, "label": label, "commit": commit, "nodes": nvm, "machine_type": "c3-standard-4 (Intel TDX)", "seeds": n_seed, "rounds": len(rounds), "scheduled_per_round": [r["sched"] for r in rounds], "outcomes_total": len(outs), "outcomes_by_status": dict(bs), "receipts": receipts,
               "authenticated_receipts": int(mr.group(2)) if mr else None, "pages_fetched_db": fetched_db, "seeds_without_outcome": len(missing), "export_files": exp_model.get("manifest_files"), "export_bytes": tot_b, "warc_bytes": warc_b, "crawl_seconds": crawl_s, "script_seconds": script_s, "whole_driver_seconds": whole_s,
               "signed_window_seconds": sw, "export_seconds": exp_s, "manifest_seconds_per_file": exp_model.get("manifest_seconds_per_file"), "upload_seconds_per_object": exp_model.get("upload_seconds_per_object"), "critical_path_seconds_per_round": [{"round": n, "startup": a, "fetch_tasks": b, "later_jobs": c, "total": tot} for n, a, b, c, tot in cp_rows],
               "largest_task_seconds": strag[0] if strag else None, "median_task_seconds": strag[1] if strag else None, "worker_cpu_mean_percent": statistics.mean(wkc) if wkc else None, "vm_hours_crawl": nvm * crawl_s / 3600.0 if crawl_s else None, "cost_usd_crawl_list_price": usd(crawl_s) if crawl_s else None,
               "cost_usd_per_1000_pages": cost_1000, "idle_minutes_crawl": mon["__idle__"][0] if mon and "__idle__" in mon else None, "idle_cost_usd": idle_cost, "list_price_usd_per_vm_hour": price, "verification": {n: r for n, r, _ in checks}}
    json.dump(summary, open(f_js, "w"), indent=1); print(out); print("ANALYSIS-DONE: %s and %s" % (f_md, f_js)); return 0
if __name__ == "__main__": sys.exit(main())
