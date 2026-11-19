#!/usr/bin/env python3
"""run_task_times.py EVIDENCE_DIR [--tools DIR]: per fetch task, the SIGNED start and end (Roughtime, verified with the pinned keys exactly as ops/attested/verify_time_export.py does), when its pages were fetched (WARC-Date: the crawler's own, UNSIGNED clock),
the dead time between the last fetch and the end of the task, the outcomes of the task, and the URLs that ended as NOT_ATTEMPTED. Read-only; changes nothing. --tools = the folder ops/attested of a clone (default ~/nutch-check/ops/attested)."""
import base64, collections, datetime as dt, glob, gzip, hashlib, json, os, re, statistics, sys
def arg(n, d=None): a = sys.argv; return a[a.index(n) + 1] if n in a and a.index(n) + 1 < len(a) else d
def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("--"): print(__doc__.split("\n")[0]); return 2
    E = os.path.expanduser(sys.argv[1]).rstrip("/"); export = os.path.join(E, "export"); tools = os.path.expanduser(arg("--tools", "~/nutch-check/ops/attested"))
    sys.path.insert(0, tools)
    try: import verify_time_export as V
    except Exception as e: print("TASKTIMES-FAILED: cannot load verify_time_export from %s (%s)" % (tools, e)); return 2
    canonical, roughtime, sr = V._modules(); pinned = json.load(open(V.PINNED))["servers"]; T = V.tasks(export)
    win = {}
    for att, v in T.items():
        s = e = None
        for f in v["time"]:
            for l in V.lines(f):
                t = canonical.decode(l)
                if t["phase"] == "start": want = hashlib.sha512(b"tc/time-start/v1\x00" + canonical.encode({"attempt": t["attempt"], "nonce": t["nonce"], "seed": t["seed"]})).digest()[:32]
                else: want = hashlib.sha512(b"tc/time-end/v1\x00" + canonical.encode(t["receipts"])).digest()[:32]
                m, r = roughtime.verify(base64.b64decode(t["response"]), want, base64.b64decode(pinned[t["server"]]))
                if t["phase"] == "start": s = m - r if s is None else min(s, m - r)
                else: e = m + r if e is None else max(e, m + r)
        if s is not None and e is not None: win[att] = (s, e)
    date = {}
    for f in glob.glob(os.path.join(export, "tc", "warc", "*", "*.warc.gz")):
        try: data = gzip.open(f).read()
        except OSError: continue
        for m in re.finditer(rb"WARC/1\.0\r\n(.*?)\r\n\r\n", data, re.S):
            h = m.group(1)
            if b"WARC-Type: response" in h:
                i = re.search(rb"WARC-Record-ID: <([^>]+)>", h); d = re.search(rb"WARC-Date: (\S+)", h)
                if i and d: date[i.group(1).decode()] = dt.datetime.strptime(d.group(1).decode(), "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=dt.timezone.utc).timestamp()
    rows = []; na = []
    for att, v in sorted(T.items()):
        outs = [json.loads(l) for f in v["outcomes"] for l in V.lines(f)]; st = collections.Counter(o.get("status") for o in outs)
        recs = [json.loads(l) for f in v["receipts"] for l in V.lines(f)]; fd = sorted(date[r["document_id"]] for r in recs if r.get("document_id") in date)
        for o in outs:
            if o.get("status") == "NOT_ATTEMPTED": na.append((att, o.get("source_url"), o.get("detail")))
        if att not in win: continue
        s, e = win[att]; rows.append((att, s, e, len(outs), st, fd))
    if not rows: print("TASKTIMES-FAILED: no task with a signed start and end reading"); return 2
    t0 = min(r[1] for r in rows)
    print("%-12s %9s %9s %8s %6s %6s %5s | %9s %9s %10s" % ("task", "start", "end", "signed s", "URLs", "pages", "N/A", "1st fetch", "last fetch", "dead tail"))
    print("%-12s %9s %9s %8s %6s %6s %5s | %9s %9s %10s" % ("", "(UTC)", "(UTC)", "", "", "", "", "after start", "after start", "end - last"))
    hh = lambda t: dt.datetime.fromtimestamp(t, dt.timezone.utc).strftime("%H:%M:%S"); dead = []; durs = []
    for att, s, e, n, st, fd in sorted(rows, key=lambda r: r[2]):
        short = re.sub(r"^attempt_\d+_\d+_", "", att); dur = e - s; durs.append(dur)
        if fd: tail = e - fd[-1]; dead.append(tail); f1, fl = "%+7.0f s" % (fd[0] - s), "%+7.0f s" % (fd[-1] - s); tl = "%7.0f s" % tail
        else: f1 = fl = tl = "       -"
        print("%-12s %9s %9s %8.0f %6d %6d %5d | %9s %9s %10s" % (short, hh(s), hh(e), dur, n, len(fd), st.get("NOT_ATTEMPTED", 0), f1, fl, tl))
    print("")
    print("tasks: %d | signed task time: smallest %.0f s, median %.0f s, largest %.0f s | tasks of 290 s or more: %d" % (len(rows), min(durs), statistics.median(durs), max(durs), sum(1 for d in durs if d >= 290)))
    if dead: print("dead tail (end of the task minus its last fetched page): smallest %.0f s, median %.0f s, largest %.0f s; tasks with a tail of 200 s or more: %d" % (min(dead), statistics.median(dead), max(dead), sum(1 for d in dead if d >= 200)))
    print("fleet signed window: %s .. %s (%.0f s)" % (hh(t0), hh(max(r[2] for r in rows)), max(r[2] for r in rows) - t0))
    print("NOT_ATTEMPTED: %d URLs%s" % (len(na), ", in tasks: " + ", ".join("%s x%d" % (re.sub(r"^attempt_\d+_\d+_", "", a), n) for a, n in collections.Counter(x[0] for x in na).items()) if na else ""))
    for a, u, d in na[:12]: print("   %-12s %s (%s)" % (re.sub(r"^attempt_\d+_\d+_", "", a), u, d))
    print("note: the start and end are SIGNED (time server); the fetch dates are the crawler's own clock (second resolution), good enough for a distribution but not evidence.")
    return 0
if __name__ == "__main__": sys.exit(main())
