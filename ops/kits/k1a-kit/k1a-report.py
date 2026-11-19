#!/usr/bin/env python3
"""k1a-report.py EXPORT_DIR SEEDS_FILE [MASTER_LOG_LINES]: the report of the 1K run (docs/perf): what the crawler's signed outcome records say about the seeds (counts by class, receipts, seeds without an outcome, the spread over the fetch tasks) and the timing of the crawl.
It reads only the signed outcome records of the export (tc/crawl/segments/*/tc_receipts/outcomes-*.jsonl) and the segment names; it exits 0 whatever it finds, and 2 only when it cannot read them. EXPORT_DIR is the export folder of the evidence."""
import collections, glob, json, os, re, sys, urllib.parse, datetime as dt
def key(u):
    p = urllib.parse.urlsplit(u.strip()); return ((p.hostname or "").lower(), p.path.rstrip("/") or "/")
def klass(o):
    st = o.get("status", "?"); d = str(o.get("detail", "") or "")
    if st == "ACCEPTED": return "ACCEPTED, fetched, with a receipt" if o.get("receipt_sha256") else "ACCEPTED, no receipt hash"
    if st == "HTTP_STATUS": m = re.search(r"(\d{3})", d); return "HTTP_STATUS %s" % (m.group(1) if m else "?")
    d2 = re.sub(r"\(\d+\)", "(n)", d).strip()[:46]; return ("%s: %s" % (st, d2)) if d2 else st
def timing(export, logfile):
    T = lambda z: dt.datetime.strptime(z, "%Y-%m-%dT%H:%M:%SZ"); m = lambda a, b: "%d s = %.1f min" % ((b - a).total_seconds(), (b - a).total_seconds() / 60)
    segdir = os.path.join(export, "tc", "crawl", "segments"); segs = sorted(x for x in os.listdir(segdir) if re.fullmatch(r"\d{14}", x)) if os.path.isdir(segdir) else []
    st = [dt.datetime.strptime(x, "%Y%m%d%H%M%S") for x in segs]; ev = {}
    if logfile and os.path.exists(logfile):
        for l in open(logfile, encoding="utf-8", errors="replace"):
            mm = re.search(r"(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ) (tc-crawl|tc-export): (.*)", l)
            if not mm: continue
            t, who, txt = T(mm.group(1)), mm.group(2), mm.group(3)
            for k, w, pre in (("start", "tc-crawl", "start:"), ("cluster", "tc-crawl", "HDFS has its DataNodes"), ("script", "tc-crawl", "the seeds are in HDFS"), ("done", "tc-crawl", "done:"), ("x_done", "tc-export", "done:")):
                if who == w and txt.startswith(pre) and (k not in ev or (k == "x_done" and t > ev[k])): ev[k] = t
    print("timing (UTC):")
    for i, t in enumerate(st):
        end = st[i + 1] if i + 1 < len(st) else ev.get("done")
        print("  round %d starts at %s (segment %s)%s" % (i + 1, t.strftime("%H:%M:%S"), segs[i], ("; takes " + m(t, end) + (" (to the next round)" if i + 1 < len(st) else " (to the done marker)")) if end else ""))
    if st and "done" in ev: print("  first segment to the done marker: %s" % m(st[0], ev["done"]))
    got = 0
    for a, b, label in (("start", "cluster", "  cluster wait (tc-crawl start to HDFS ready)"), ("script", "done", "  Nutch crawl script (seeds in HDFS to done)"), ("start", "done", "  the whole tc-crawl (start to done)"), ("done", "x_done", "  the export (crawl done to export done)")):
        if a in ev and b in ev: print("%s: %s" % (label, m(ev[a], ev[b]))); got += 1
    if not got: print("  (no lines of the master in %s: the timing of the crawl script and of the export is not available)" % (logfile or "-"))
def main(argv):
    if len(argv) not in (2, 3): print(__doc__.split("\n")[0]); return 2
    export, seeds_file = argv[0], argv[1]; logfile = argv[2] if len(argv) == 3 else None
    files = sorted(glob.glob(os.path.join(export, "tc", "crawl", "segments", "*", "tc_receipts", "outcomes-*.jsonl")))
    if not files: print("K1A-REPORT-FAILED: no outcome files under %s/tc/crawl/segments/*/tc_receipts/" % export); return 2
    outs = []; per_task = collections.Counter()
    for f in files:
        for l in open(f, encoding="utf-8"):
            if l.strip(): o = json.loads(l); outs.append(o); per_task[os.path.basename(f)] += 1
    seeds = [l.strip() for l in open(seeds_file, encoding="utf-8") if l.strip() and not l.lstrip().startswith("#")]
    seed_keys = {key(s) for s in seeds}; out_keys = collections.Counter(key(o.get("source_url", "")) for o in outs)
    mine = [o for o in outs if key(o.get("source_url", "")) in seed_keys]; extra = len(outs) - len(mine)
    missing = [s for s in seeds if key(s) not in out_keys]; multi = sum(1 for k, n in out_keys.items() if k in seed_keys and n > 1)
    cl = collections.Counter(klass(o) for o in mine); n = len(seeds)
    print("%-52s %6s %7s" % ("what the signed outcomes say about the %d seeds" % n, "count", "share"))
    for c, k in sorted(cl.items(), key=lambda x: -x[1]): print("%-52s %6d %6.1f%%" % (c, k, 100.0 * k / n))
    fetched = cl.get("ACCEPTED, fetched, with a receipt", 0)
    print("seeds in the file: %d | outcomes for seeds: %d | outcomes for other URLs: %d | seeds with more than one outcome: %d | seeds WITHOUT an outcome: %d" % (n, len(mine), extra, multi, len(missing)))
    for s in missing[:5]: print("   no outcome: %s" % s)
    if per_task: v = sorted(per_task.values()); print("fetch tasks that wrote outcomes: %d (outcomes per task: smallest %d, median %d, largest %d)" % (len(v), v[0], v[len(v) // 2], v[-1]))
    order = ["ACCEPTED", "NOT_FETCHED", "HTTP_STATUS", "NOT_HTTPS", "TRUNCATED", "NOT_ATTEMPTED"]; bs = collections.Counter(o.get("status", "?") for o in outs)
    print("outcomes_by_status (the form of teammate S receipts.json): " + ", ".join("%s %d" % (k, bs[k]) for k in order + sorted(set(bs) - set(order)) if bs.get(k)))
    tc = os.path.join(os.path.dirname(export.rstrip("/")), "time-check.txt"); win = None
    if os.path.exists(tc):
        mm = re.search(r"signed window (\S+ \S+)Z \.\. (\S+ \S+)Z \((\d+) s\)", open(tc, encoding="utf-8", errors="replace").read())
        if mm: win = (mm.group(1), mm.group(2), int(mm.group(3)))
    print("signed fetch window (the time server's clock, first task start to last task end): %s" % (("%s .. %s UTC = %d s = %.1f min" % (win[0][11:], win[1][11:], win[2], win[2] / 60.0)) if win else "not available (no time-check.txt next to the export)"))
    print("K1A-REPORT: %d seeds, %d fetched with a receipt (%.1f%% of the seeds), %d seeds without an outcome" % (n, fetched, 100.0 * fetched / n if n else 0, len(missing)))
    timing(export, logfile)
    return 0
if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
