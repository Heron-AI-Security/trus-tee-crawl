#!/usr/bin/env python3
"""Rehearsal of verify_fetchlist.py (step P5.6 part B). It takes a REAL export, makes the fetch lists that the crawl script would have written from the outcomes that the fetch tasks really wrote (so the control is exact),
requires the control to pass, and damages fresh copies in many ways: a scheduled URL with no outcome, an outcome for an unscheduled URL, a duplicate outcome, a segment without a fetch list, and every way in which the file itself can be wrong.
Each damage must be rejected, and the report must NAME the URL or the fault.
   python3 verify_fetchlist_rehearse.py EXPORT_DIR          (EXPORT_DIR holds tc/crawl/segments/*/tc_receipts/outcomes-*.jsonl; it is only read, every copy is made in a temporary folder)"""
import glob, json, os, shutil, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_fetchlist import check
def segs(root): d = root + "/tc/crawl/segments"; return sorted(x for x in os.listdir(d) if os.path.isdir(d + "/" + x))
def rec(root, s): return root + "/tc/crawl/segments/%s/tc_receipts" % s
def outs(root, s): return sorted(glob.glob(rec(root, s) + "/outcomes-*.jsonl"))
def urls_of(root, s): return sorted({json.loads(l)["source_url"] for f in outs(root, s) for l in open(f).read().split("\n") if l.strip()}, key=lambda x: x.encode())
def write_fl(root, s, urls, count=None, header=True, name=None, newline=True):
    t = (("# tc-fetchlist v1 segment=%s count=%d\n" % (name or s, len(urls) if count is None else count)) if header else "") + "\n".join(urls) + ("\n" if newline and urls else "")
    open(rec(root, s) + "/fetchlist.txt", "w").write(t)
def strip(root):   # an export "of an older run": remove the fetch lists (and their records) that a run of this build really carries, so that the case does not depend on what the export given to the rehearsal happens to contain
    for s in segs(root):
        for f in (rec(root, s) + "/fetchlist.txt", rec(root, s) + "/.fetchlist.txt.attested"):
            if os.path.exists(f): os.remove(f)
def build(root):
    for s in segs(root): write_fl(root, s, urls_of(root, s))
def first(root): return segs(root)[0]
def ed(root, fn): s = first(root); fn(root, s)
def drop_outcome(r, s): f = outs(r, s)[0]; ls = [l for l in open(f).read().split("\n") if l.strip()]; open(f, "w").write("\n".join(ls[1:]) + "\n")
def dup_outcome(r, s): f = outs(r, s)[0]; t = open(f).read().rstrip("\n"); open(f, "w").write(t + "\n" + t.split("\n")[0] + "\n")
def add_url(r, s): write_fl(r, s, sorted(urls_of(r, s) + ["https://never-fetched.example/x"], key=lambda x: x.encode()))
def drop_url(r, s): u = urls_of(r, s); write_fl(r, s, u[1:])
def no_fl(r, s): os.remove(rec(r, segs(r)[-1]) + "/fetchlist.txt")
def bad_count(r, s): write_fl(r, s, urls_of(r, s), count=len(urls_of(r, s)) + 1)
def bad_name(r, s): write_fl(r, s, urls_of(r, s), name="19990101000000")
def unsorted(r, s): u = urls_of(r, s); write_fl(r, s, u[::-1] if len(u) > 1 else u + u)
def dup_url(r, s): u = urls_of(r, s); write_fl(r, s, sorted(u + [u[0]], key=lambda x: x.encode()))
def ftp(r, s): u = urls_of(r, s); write_fl(r, s, sorted(u + ["ftp://a.example/x"], key=lambda x: x.encode()))
def empty(r, s): write_fl(r, s, [])
def nohdr(r, s): write_fl(r, s, urls_of(r, s), header=False)
def nonl(r, s): write_fl(r, s, urls_of(r, s), newline=False)
def badjson(r, s): f = outs(r, s)[0]; open(f, "a").write("this is not json\n")
def normhint(r, s):
    u = urls_of(r, s); i = next(k for k, x in enumerate(u) if x.endswith("/")); u[i] = u[i][:-1]; write_fl(r, s, sorted(u, key=lambda x: x.encode()))
def no_outcome_files(r, s): [os.remove(f) for f in outs(r, s)]
def two_files(r, s):
    f = outs(r, s)[0]; ls = [l for l in open(f).read().split("\n") if l.strip()]; open(f, "w").write(ls[0] + "\n")
    if len(ls) > 1: open(os.path.dirname(f) + "/outcomes-attempt_999_0001_m_000001_0.jsonl", "w").write("\n".join(ls[1:]) + "\n")
def nonutf8(r, s): open(rec(r, s) + "/fetchlist.txt", "wb").write(b"# tc-fetchlist v1 segment=%s count=1\nhttps://a.example/\xff\xfe\n" % s.encode())
def no_segments(r, s): shutil.rmtree(r + "/tc/crawl/segments")
CASES = [("control: the fetch lists made from the real outcomes, every segment", None, "PASS", ""), ("no fetch list in any segment (an export of an older run)", "none", "NOT CHECKED", "carries no fetch list"),
 ("a scheduled URL with no outcome (one outcome line removed)", drop_outcome, "FAIL", "has NO outcome"), ("a URL added to the fetch list that was never fetched", add_url, "FAIL", "https://never-fetched.example/x was scheduled and has NO outcome"),
 ("a duplicate outcome for one URL", dup_outcome, "FAIL", "has 2 outcomes"), ("an outcome for a URL that was not scheduled (one URL left out of the fetch list)", drop_url, "FAIL", "which was not scheduled"),
 ("a segment without a fetch list while the others have one", no_fl, "FAIL", "has no fetch list"), ("the header counts one URL too many", bad_count, "FAIL", "the header says"), ("the header names another segment", bad_name, "FAIL", "names the segment"),
 ("the URLs not sorted", unsorted, "FAIL", "not sorted and unique"), ("a URL twice in the fetch list", dup_url, "FAIL", "not sorted and unique"), ("a line that is not an http(s) address", ftp, "FAIL", "not a plain http(s) address"),
 ("an empty fetch list", empty, "FAIL", "empty"), ("no header line", nohdr, "FAIL", "first line is not"), ("no newline at the end of the file", nonl, "FAIL", "does not end with a newline"),
 ("an outcomes file that is not JSON", badjson, "FAIL", "is not an outcome"), ("a URL that differs from its outcome only by a trailing slash", normhint, "FAIL", "differs only by URL normalization"),
 ("a fetch list but no outcomes file at all in the segment", no_outcome_files, "FAIL", "NO outcome"), ("two outcome files in one segment, each with some of the URLs (two tasks)", two_files, "PASS", ""),
 ("a fetch list that is not UTF-8", nonutf8, "FAIL", "codec"), ("the export has no tc/crawl/segments", no_segments, "NOT CHECKED", "no crawl to check")]
def main():
    SRC = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__.split("\n")[4])
    tmp = tempfile.mkdtemp(prefix="p5fl-"); bad = 0
    try:
        for n, (name, fn, want, sub) in enumerate(CASES, 1):
            d = os.path.join(tmp, "c%d" % n); shutil.copytree(SRC, d, symlinks=True)
            if fn == "none": strip(d)
            else: build(d)
            if callable(fn): ed(d, fn)
            st, lines = check(d); ok = st == want and (sub in " | ".join(lines)); bad += 0 if ok else 1
            print("%s %2d. %-84s -> %s%s" % ("ok:  " if ok else "FAIL:", n, name, st, ("" if ok else "   (expected %s containing %r; got %s)" % (want, sub, lines[:2]))))
        e0 = os.path.join(tmp, "nofl"); shutil.copytree(SRC, e0, symlinks=True); strip(e0)
        d = os.path.join(tmp, "cli"); shutil.copytree(SRC, d, symlinks=True); build(d); cli = lambda p: subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "verify_fetchlist.py"), p], capture_output=True, text=True)
        for nm, p, want, tail in (("the command line: a good export (exit 0)", d, 0, "FETCHLIST-OK"), ("the command line: an export without fetch lists (exit 3)", e0, 3, "FETCHLIST-NOT-CHECKED")):
            r = cli(p); ok = r.returncode == want and r.stdout.strip().endswith(tail) and "Traceback" not in r.stderr; bad += 0 if ok else 1; print("%s     %-84s -> exit %d" % ("ok:  " if ok else "FAIL:", nm, r.returncode))
        drop_outcome(d, first(d)); r = cli(d); ok = r.returncode == 1 and "FETCHLIST-FAILED" in r.stdout; bad += 0 if ok else 1; print("%s     %-84s -> exit %d" % ("ok:  " if ok else "FAIL:", "the command line: a scheduled URL without an outcome (exit 1)", r.returncode))
    finally: shutil.rmtree(tmp, ignore_errors=True)
    if bad: sys.exit("FETCHLIST-VERIFY-REHEARSAL-FAILED: %d case(s) went wrong" % bad)
    nc = sum(1 for c in CASES if c[2] == "NOT CHECKED"); ct = sum(1 for c in CASES if c[2] == "PASS"); print("FETCHLIST-VERIFY-REHEARSAL-OK: %d cases (%d controls, %d without a fetch list, %d damages named exactly) and 3 command line cases" % (len(CASES), ct, nc, len(CASES) - ct - nc))


if __name__ == "__main__": main()
