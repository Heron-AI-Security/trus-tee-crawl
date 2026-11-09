#!/usr/bin/env python3
"""e15-report.py EXPORT_DIR SEEDS_FILE [MASTER_LOG_LINES]: one line per seed of the end to end test on 15 sites (docs/end-to-end-testing.md): what was expected, what the crawler's signed outcomes say, OK or CHECK.
The expected results are those of the document: seeds 1, 6 and 12 give no page (robots.txt closes them to our agent), seed 14 gives a recorded 403, the other eleven give a fetched page with a receipt.
A live site changes from day to day: a CHECK is a finding to read, not necessarily a bug. The report reads only the signed outcome records of the export (tc/crawl/segments/*/tc_receipts/outcomes-*.jsonl); it exits 0 whatever it finds, and 2 only when it cannot read them."""
import collections, glob, json, os, sys, urllib.parse
PAGE, REFUSED, E403 = "a fetched page", "no page (robots.txt)", "a recorded 403"
EXPECT = {"https://text.npr.org/": REFUSED, "https://ja.wikipedia.org/wiki/Main_Page": PAGE, "https://www.schneier.com/": PAGE, "https://github.com/apache/nutch": PAGE, "https://news.ycombinator.com/": PAGE,
          "https://www.reddit.com/r/programming/": REFUSED, "https://www.gutenberg.org/cache/epub/1342/pg1342.txt": PAGE, "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf": PAGE,
          "https://www.nasa.gov/feed/": PAGE, "https://archive.org/details/prelinger": PAGE, "https://ocw.mit.edu/": PAGE, "https://www.who.int/news": REFUSED,
          "https://webscraper.io/test-sites/e-commerce/static": PAGE, "https://www.nytimes.com/": E403, "https://timesofindia.indiatimes.com/": PAGE}
def key(u):
    p = urllib.parse.urlsplit(u.strip()); return (p.hostname or "").lower().removeprefix("www."), p.path.rstrip("/") or "/"
def timing(export, logfile):
    """The timing of the crawl: the round starts (the names of the segments are the times of their generate step), and, if the lines of the master are there, the cluster wait, the crawl script, the end and the export. All UTC."""
    import re, datetime as dt
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
    if not files: print("E15-REPORT-FAILED: no outcome files under %s/tc/crawl/segments/*/tc_receipts/" % export); return 2
    outs = []; attempts = set()
    for f in files:
        attempts.add(os.path.basename(f)[len("outcomes-"):-len(".jsonl")])
        for l in open(f, encoding="utf-8"):
            if l.strip(): outs.append(json.loads(l))
    seeds = [l.strip() for l in open(seeds_file, encoding="utf-8") if l.strip() and not l.lstrip().startswith("#")]
    by_url = collections.defaultdict(list); by_host = collections.defaultdict(list)
    for o in outs: k = key(o.get("source_url", "")); by_url[k].append(o); by_host[k[0]].append(o)
    seed_keys = {key(s) for s in seeds}; ok = chk = 0; chk_lines = []
    print("%-3s %-34s %-22s %-48s %s" % ("#", "seed (host)", "expected", "what the signed outcomes say", "verdict"))
    for i, s in enumerate(seeds, 1):
        exp = EXPECT.get(s); k = key(s); mine = by_url.get(k, []); st = collections.Counter(o.get("status", "?") for o in mine)
        got = ", ".join("%s x%d" % (a, n) for a, n in sorted(st.items())) or "no outcome"
        det = next((o.get("detail") for o in mine if o.get("status") != "ACCEPTED" and o.get("detail")), None)
        if det: got += " (%s)" % str(det)[:40]
        if exp is None: verdict = "-"; note = "not in the table of the document"
        elif exp == PAGE: verdict = "OK" if st.get("ACCEPTED") else "CHECK"
        elif exp == REFUSED: verdict = "OK" if not st.get("ACCEPTED") else "CHECK"
        else: verdict = "OK" if any(o.get("status") == "HTTP_STATUS" and "403" in str(o.get("detail", "")) for o in mine) else "CHECK"
        ok += verdict == "OK"; chk += verdict == "CHECK"
        if verdict == "CHECK": chk_lines.append("   seed %d %s: expected %s, got %s" % (i, k[0], exp, got))
        print("%-3d %-34s %-22s %-48s %s" % (i, k[0], (exp or "?")[:22], got[:48], verdict))
    extra = [o for o in outs if key(o.get("source_url", "")) not in seed_keys]; ex_ok = sum(1 for o in extra if o.get("status") == "ACCEPTED")
    print("outcomes in total: %d; for the seeds: %d; for links that the seeds led to (round 2): %d, of which %d fetched with a receipt" % (len(outs), len(outs) - len(extra), len(extra), ex_ok))
    print("fetch tasks that wrote outcomes: %d (the 15 seeds are spread over the fetch tasks of the fleet)" % len(attempts))
    print("E15-REPORT: %d of %d seeds as expected, %d to read%s" % (ok, len(seeds), chk, (":\n" + "\n".join(chk_lines)) if chk_lines else ""))
    timing(export, logfile)
    return 0
if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
