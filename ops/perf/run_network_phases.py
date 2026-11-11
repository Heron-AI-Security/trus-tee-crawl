#!/usr/bin/env python3
"""run_network_phases.py EVIDENCE_DIR [options]: network and CPU of the master and the workers per minute and per phase of a crawl, for a run of any size and any number of rounds (Cloud Monitoring, host side, 60 s steps).
The phases are taken from the evidence: crawl driver start, HDFS ready, seeds in HDFS, each round's segment (generate), each round's SIGNED fetch window (when the time readings and the tools are there), crawl done, export manifest, export done.
Read-only (it writes nothing; use tee). Options: --tools DIR (ops/attested of a clone, default ~/nutch-check/ops/attested)  --project P  --prefix tc-f1-  Answers: when does the traffic happen, how much of it is in each phase, and how busy are the workers then."""
import base64, datetime as dt, glob, hashlib, json, os, re, statistics, subprocess, sys, urllib.parse, urllib.request
def arg(n, d=None): a = sys.argv; return a[a.index(n) + 1] if n in a and a.index(n) + 1 < len(a) else d
T = lambda z: dt.datetime.strptime(z, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc); iso = lambda t: t.strftime("%Y-%m-%dT%H:%M:%SZ")
def signed_windows(export, segs, tools):
    """{segment: (start, end)} from the signed Roughtime readings of the tasks of that segment (verified with the pinned keys like verify_time_export.py does)."""
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
def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("--"): print(__doc__.split("\n")[0]); return 2
    E = os.path.expanduser(sys.argv[1]).rstrip("/"); project = arg("--project", "training-custody"); prefix = arg("--prefix", "tc-f1-"); tools = os.path.expanduser(arg("--tools", "~/nutch-check/ops/attested")); export = os.path.join(E, "export")
    log = open(os.path.join(E, "master-log-lines.txt"), encoding="utf-8", errors="replace").read() if os.path.exists(os.path.join(E, "master-log-lines.txt")) else ""; ev = {}
    for l in log.split("\n"):
        m = re.search(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) (tc-crawl|tc-export): (.*)", l)
        if not m: continue
        t, who, txt = T(m.group(1)), m.group(2), m.group(3)
        for k, w, pre in (("start", "tc-crawl", "start:"), ("hdfs", "tc-crawl", "HDFS has its DataNodes"), ("seeds", "tc-crawl", "the seeds are in HDFS"), ("done", "tc-crawl", "done:"), ("manifest", "tc-export", "manifest:"), ("x_done", "tc-export", "done:")):
            if who == w and txt.startswith(pre): ev.setdefault(k, t)
    segroot = os.path.join(export, "tc", "crawl", "segments"); segs = sorted(x for x in os.listdir(segroot) if re.fullmatch(r"\d{14}", x)) if os.path.isdir(segroot) else []
    need = ["start", "hdfs", "seeds", "done", "manifest", "x_done"]
    if not segs or any(k not in ev for k in need): print("NETPHASES-FAILED: missing in the evidence: %s" % ([k for k in need if k not in ev] + ([] if segs else ["segments"]))); return 2
    seg_t = [dt.datetime.strptime(x, "%Y%m%d%H%M%S").replace(tzinfo=dt.timezone.utc) for x in segs]; win = signed_windows(export, segs, tools)
    phases = [("before the crawl driver (4 min)", ev["start"] - dt.timedelta(minutes=4), ev["start"]), ("driver start to HDFS ready", ev["start"], ev["hdfs"]), ("HDFS ready to seeds in HDFS", ev["hdfs"], ev["seeds"]), ("seeds in HDFS to first segment (inject, generate)", ev["seeds"], seg_t[0])]
    for i, s in enumerate(segs):
        nxt = seg_t[i + 1] if i + 1 < len(segs) else ev["done"]; we = win[s][1] if s in win else None
        if we and seg_t[i] < we < nxt: phases += [("round %d fetch job (segment to end of signed window)" % (i + 1), seg_t[i], we), ("round %d later jobs (to %s)" % (i + 1, "next segment" if i + 1 < len(segs) else "crawl done"), we, nxt)]
        else: phases += [("round %d, segment to %s" % (i + 1, "next segment" if i + 1 < len(segs) else "crawl done"), seg_t[i], nxt)]
    phases += [("crawl done to export manifest", ev["done"], ev["manifest"]), ("export manifest to export done (upload)", ev["manifest"], ev["x_done"])]
    w0 = phases[0][1].replace(second=0, microsecond=0); w1 = (ev["x_done"] + dt.timedelta(minutes=2)).replace(second=0, microsecond=0); fake = os.environ.get("K1A_FAKE_MONITORING")
    def series(metric, al):
        if fake: return {n: {t: v for t, v in pts} for n, pts in json.load(open(fake)).get(metric, {}).items()}
        tok = subprocess.check_output(["gcloud", "auth", "print-access-token"], stderr=subprocess.DEVNULL).decode().strip()
        p = {"filter": 'metric.type="%s" AND metric.labels.instance_name=starts_with("%s")' % (metric, prefix), "interval.startTime": iso(w0), "interval.endTime": iso(w1), "aggregation.alignmentPeriod": "60s", "aggregation.perSeriesAligner": al}
        base = "https://monitoring.googleapis.com/v3/projects/%s/timeSeries?" % project; url, out = base + urllib.parse.urlencode(p), []
        while url:
            r = json.load(urllib.request.urlopen(urllib.request.Request(url, headers={"Authorization": "Bearer " + tok}), timeout=60)); out += r.get("timeSeries", [])
            url = (base + urllib.parse.urlencode(dict(p, pageToken=r["nextPageToken"]))) if r.get("nextPageToken") else None
        return {s["metric"]["labels"]["instance_name"]: {pt["interval"]["endTime"]: pt["value"].get("doubleValue", float(pt["value"].get("int64Value", 0))) for pt in s["points"]} for s in out}
    try: cpu = series("compute.googleapis.com/instance/cpu/utilization", "ALIGN_MEAN"); rx = series("compute.googleapis.com/instance/network/received_bytes_count", "ALIGN_SUM"); tx = series("compute.googleapis.com/instance/network/sent_bytes_count", "ALIGN_SUM")
    except Exception as e: print("NETPHASES-FAILED: Cloud Monitoring: %s: %s" % (type(e).__name__, str(e)[:150])); return 2
    if not cpu: print("NETPHASES-FAILED: Cloud Monitoring returned no series for VMs named %s* (deleted VMs keep their metrics only for the retention time)" % prefix); return 2
    wk = sorted(n for n in cpu if not n.endswith("-m")); ms_ = [n for n in cpu if n.endswith("-m")]; m = ms_[0] if ms_ else wk[0]
    avg = lambda d, t: sum(d[n].get(t, 0.0) for n in wk) / max(1, len(wk)); minutes = []; t = w0
    while t <= w1: minutes.append(iso(t)); t += dt.timedelta(minutes=1)
    def label(ts):
        tt = T(ts)
        for name, a, b in phases:
            if a < tt <= b: return name[:46]
        return ""
    print("run_network_phases: %s | %d VMs (%s*) | phases from the evidence: %d rounds, signed fetch windows %s" % (os.path.basename(E), len(cpu), prefix, len(segs), "used" if win else "NOT available (phases per round only)"))
    print("per minute (UTC; value = the 60 s step that ENDS at that minute); worker values are the AVERAGE over %d workers" % len(wk))
    print("%-6s %9s %9s | %9s %9s %7s | %s" % ("min", "master in", "master out", "worker in", "worker out", "w cpu%", "phase")); print("%-6s %9s %9s | %9s %9s %7s |" % ("", "MB", "MB", "MB", "MB", ""))
    for ts in minutes:
        if ts not in cpu[m] and all(ts not in rx.get(n, {}) for n in wk): continue
        print("%-6s %9.1f %9.1f | %9.1f %9.1f %7.1f | %s" % (ts[11:16], rx.get(m, {}).get(ts, 0) / 1e6, tx.get(m, {}).get(ts, 0) / 1e6, avg(rx, ts) / 1e6, avg(tx, ts) / 1e6, 100 * avg(cpu, ts), label(ts)))
    print(""); print("per phase (whole fleet = master + all workers; MB = megabytes; vCPU-s = utilization x 4 vCPUs x 60 s; worker CPU = mean over workers and minutes):")
    rows = []
    for name, a, b in phases:
        mins = [x for x in minutes if a < T(x) <= b]; i = sum(rx[n].get(x, 0) for n in cpu for x in mins) / 1e6; o = sum(tx[n].get(x, 0) for n in cpu for x in mins) / 1e6; c = sum(cpu[n].get(x, 0) for n in cpu for x in mins) * 4 * 60
        wc = 100 * statistics.mean([cpu[n].get(x, 0) for n in wk for x in mins]) if mins and wk else 0.0; rows.append((name, (b - a).total_seconds(), len(mins), i, o, c, wc))
    crawl_in = sum(r[3] for r in rows if not r[0].startswith(("before", "crawl done", "export")) ) or 1.0
    print("%-62s %7s %5s %10s %10s %7s %9s %8s" % ("phase", "length", "min.", "MB in", "MB out", "share", "vCPU-s", "w cpu %")); tot_i = tot_o = 0.0
    for name, ln, nm, i, o, c, wc in rows:
        inwin = not name.startswith(("before", "crawl done", "export")); tot_i += i; tot_o += o
        print("%-62s %5.0f s %5d %10.1f %10.1f %7s %9.0f %8.1f" % (name[:62], ln, nm, i, o, ("%5.1f %%" % (100 * i / crawl_in)) if inwin else "", c, wc))
    print("%-62s %7s %5s %10.1f %10.1f" % ("total over the phases shown", "", "", tot_i, tot_o))
    print("share = MB received in the phase / MB received from the driver start to crawl done (the phases before the driver and after the crawl are not counted in it).")
    covered = sorted(x for x in minutes if any(a < T(x) <= b for _, a, b in phases)); print("check: every minute of the shown span is in exactly one phase: %s" % ("yes" if all(sum(1 for _, a, b in phases if a < T(x) <= b) == 1 for x in covered) else "NO (overlap)"))
    print("note: host-side metrics in 60 s steps; a boundary inside a minute puts that whole minute into the later phase, so each phase is good to about one minute; a phase shorter than a minute may show 0 minutes.")
    return 0
if __name__ == "__main__": sys.exit(main())
