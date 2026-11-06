#!/usr/bin/env python3
"""Step P5.6 part B: every URL that the crawl scheduled has exactly one outcome, and no outcome exists for a URL that it did not schedule.
   python3 verify_fetchlist.py EXPORT_DIR
For every segment of the export (tc/crawl/segments/NAME/) it reads tc_receipts/fetchlist.txt, which the measured crawl script tc-crawl.sh wrote from the segment's crawl_generate (what Nutch's generator scheduled), and every
tc_receipts/outcomes-*.jsonl of the same segment (the per-URL outcomes that the fetch tasks wrote). The fetch list has the form  '# tc-fetchlist v1 segment=NAME count=N'  and then N http(s) URLs, one per line, sorted and unique.
It reports every scheduled URL with NO outcome (the case that no other check can see), every URL with MORE THAN ONE outcome, and every outcome for a URL that was NOT scheduled. A URL that differs from an outcome only by the usual
normalization (host case, default port, an empty path, a fragment) is named as such, and is still a failure: the strings must be equal.
It does not say that the right URLs were scheduled (the choice from the crawl database is not checked), and the files themselves are trusted only as far as steps 4 and 5 of ops/verify-export.py show that they are the signed ones of the export.
Returns (status, lines) with the status PASS, FAIL or NOT CHECKED (an export without any fetch list, as the runs before this step made it). Standard library only."""
import glob, json, os, re, sys
from collections import Counter
from urllib.parse import urlsplit

HEADER = re.compile(r"^# tc-fetchlist v1 segment=(\S+) count=(\d+)$"); URL = re.compile(r"^https?://\S+$")
def canon(u):
    try: p = urlsplit(u); host = (p.hostname or "").lower(); port = p.port
    except ValueError: return u
    if port and not ((p.scheme == "http" and port == 80) or (p.scheme == "https" and port == 443)): host += ":%d" % port
    return "%s://%s%s%s" % (p.scheme.lower(), host, p.path or "/", ("?" + p.query) if p.query else "")

def read_fetchlist(path, segment):
    ls = open(path, encoding="utf-8", errors="strict").read().split("\n")
    if ls and ls[-1] == "": ls.pop()
    else: raise ValueError("the file does not end with a newline")
    if not ls: raise ValueError("the file is empty")
    m = HEADER.match(ls[0])
    if not m: raise ValueError("the first line is not '# tc-fetchlist v1 segment=NAME count=N': %r" % ls[0][:80])
    if m.group(1) != segment: raise ValueError("the header names the segment %s, but the file is in the segment %s" % (m.group(1), segment))
    urls = ls[1:]
    if int(m.group(2)) != len(urls): raise ValueError("the header says %s URLs, the file has %d" % (m.group(2), len(urls)))
    if not urls: raise ValueError("the fetch list is empty (a crawl that scheduled nothing for a segment would not have written one)")
    for i, u in enumerate(urls, 2):
        if not URL.match(u): raise ValueError("line %d is not a plain http(s) address: %r" % (i, u[:80]))
    if urls != sorted(set(urls), key=lambda x: x.encode("utf-8")): raise ValueError("the URLs are not sorted and unique, as the crawl script writes them")
    return urls

def read_outcomes(files):
    c = Counter(); st = Counter()
    for f in files:
        for n, line in enumerate(open(f, encoding="utf-8").read().split("\n"), 1):
            if not line.strip(): continue
            try: j = json.loads(line); u = j["source_url"]; s = j.get("status", "?")
            except (ValueError, KeyError, TypeError) as e: raise ValueError("%s line %d is not an outcome (%s)" % (os.path.basename(f), n, type(e).__name__))
            c[u] += 1; st[s] += 1
    return c, st

def check(export_dir):
    segs_dir = os.path.join(export_dir, "tc", "crawl", "segments")
    if not os.path.isdir(segs_dir): return "NOT CHECKED", ["the export has no tc/crawl/segments: there is no crawl to check"]
    segs = sorted(d for d in os.listdir(segs_dir) if os.path.isdir(os.path.join(segs_dir, d)))
    have = [s for s in segs if os.path.isfile(os.path.join(segs_dir, s, "tc_receipts", "fetchlist.txt"))]
    if not have: return "NOT CHECKED", ["the export carries no fetch list (tc_receipts/fetchlist.txt of a segment): the run was made before the crawl script wrote them, so a scheduled URL with no outcome cannot be seen"]
    problems = []; total = 0; allst = Counter(); lines = []
    for s in segs:
        d = os.path.join(segs_dir, s, "tc_receipts"); f = os.path.join(d, "fetchlist.txt")
        if s not in have: problems.append("segment %s has no fetch list, but %d other segment(s) have one" % (s, len(have))); continue
        try: urls = read_fetchlist(f, s); out, st = read_outcomes(sorted(glob.glob(os.path.join(d, "outcomes-*.jsonl"))))
        except (ValueError, OSError, UnicodeDecodeError) as e: problems.append("segment %s: %s" % (s, e)); continue
        sched = set(urls); none = [u for u in urls if out.get(u, 0) == 0]; many = [u for u in urls if out.get(u, 0) > 1]; extra = sorted(u for u in out if u not in sched)
        cx = {canon(u): u for u in extra}
        for u in none[:6]: problems.append("segment %s: the URL %s was scheduled and has NO outcome%s" % (s, u, ("; an outcome for %s exists and differs only by URL normalization" % cx[canon(u)]) if canon(u) in cx else ""))
        if len(none) > 6: problems.append("segment %s: ... and %d more scheduled URLs with no outcome (%d in all)" % (s, len(none) - 6, len(none)))
        for u in many[:4]: problems.append("segment %s: the URL %s has %d outcomes (it must have exactly one)" % (s, u, out[u]))
        for u in extra[:4]: problems.append("segment %s: an outcome exists for %s, which was not scheduled" % (s, u))
        if len(extra) > 4: problems.append("segment %s: ... and %d more outcomes for unscheduled URLs" % (s, len(extra) - 4))
        total += len(urls); allst.update(st); lines.append("segment %s: %d URLs scheduled, %d outcomes" % (s, len(urls), sum(out.values())))
    if problems: return "FAIL", problems[:12] + (["... and %d more problems" % (len(problems) - 12)] if len(problems) > 12 else [])
    return "PASS", lines + ["every one of the %d scheduled URLs has exactly one outcome, and no outcome is for an unscheduled URL (%s)" % (total, ", ".join("%s %d" % kv for kv in sorted(allst.items())))]

def main(argv):
    if len(argv) != 1: print(__doc__.split("\n")[1]); return 2
    st, lines = check(argv[0])
    for l in lines: print("   " + l)
    print({"PASS": "FETCHLIST-OK", "FAIL": "FETCHLIST-FAILED", "NOT CHECKED": "FETCHLIST-NOT-CHECKED"}[st]); return {"PASS": 0, "FAIL": 1, "NOT CHECKED": 3}[st]
if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
