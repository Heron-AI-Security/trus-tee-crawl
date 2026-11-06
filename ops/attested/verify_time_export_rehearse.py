#!/usr/bin/env python3
"""Rehearsal of verify_time_export.py (step P5.7) on the folder of a REAL export: the untouched export passes, then fresh copies are damaged one at a time and each damage must be refused for its own reason.
   python3 verify_time_export_rehearse.py EXPORT_DIR
Only the tc_receipts/*.jsonl files are copied (the check reads nothing else), so every case is quick. The first four damages are the four attacks of the teammate's own `verify_time.py --negative`."""
import base64, glob, json, os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import verify_time_export as V
if len(sys.argv) != 2: sys.exit(__doc__.split("\n")[1])
SRC = sys.argv[1].rstrip("/"); canonical, roughtime, sr = V._modules()
def slim(src, dst):
    for f in glob.glob(os.path.join(src, "tc", "crawl", "segments", "*", "tc_receipts", "*.jsonl")):
        t = os.path.join(dst, os.path.relpath(f, src)); os.makedirs(os.path.dirname(t), exist_ok=True); shutil.copy(f, t)
def tfiles(d): return sorted(glob.glob(os.path.join(d, "tc", "crawl", "segments", "*", "tc_receipts", "time-*.jsonl")))
def rfiles(d): return sorted(glob.glob(os.path.join(d, "tc", "crawl", "segments", "*", "tc_receipts", "receipts-*.jsonl")))
def edit(path, fn):
    ls = [canonical.decode(l) for l in open(path, "rb").read().split(b"\n") if l]; ls = fn(ls)
    open(path, "wb").write(b"\n".join(canonical.encode(t) for t in ls) + b"\n")
def flip_response(d):
    def fn(ls):
        r = bytearray(base64.b64decode(ls[0]["response"])); r[-70] ^= 1; ls[0]["response"] = base64.b64encode(bytes(r)).decode(); return ls
    edit(tfiles(d)[0], fn)
def swap_tasks(d):
    a, b = tfiles(d)[:2]; x, y = open(a, "rb").read(), open(b, "rb").read(); open(a, "wb").write(y); open(b, "wb").write(x)
def drop_receipt_from_end(d):
    def fn(ls):
        for t in ls:
            if t["phase"] == "end": t["receipts"] = t["receipts"][1:]
        return ls
    edit(tfiles(d)[0], fn)
def unpinned(d):
    def fn(ls): ls[0]["server"] = "time.example:2002"; return ls
    edit(tfiles(d)[0], fn)
def bad_nonce(d):
    def fn(ls): ls[0]["request_nonce"] = ("0" if ls[0]["request_nonce"][0] != "0" else "1") + ls[0]["request_nonce"][1:]; return ls
    edit(tfiles(d)[0], fn)
def no_start(d): edit(tfiles(d)[0], lambda ls: [t for t in ls if t["phase"] != "start"])
def add_receipt(d):
    f = rfiles(d)[0]; l = [x for x in open(f, "rb").read().split(b"\n") if x][0]; r = json.loads(l); r["source_url"] = "https://never-covered.example/"
    open(f, "ab").write(canonical.encode(r) + b"\n")
def no_time_file(d): os.remove(tfiles(d)[0])
def bad_version(d):
    def fn(ls): ls[0]["version"] = "tc-time-evidence/9"; return ls
    edit(tfiles(d)[0], fn)
def other_nonce(d):
    def fn(ls): ls[0]["nonce"] = "x"; return ls
    edit(tfiles(d)[0], fn)
def no_time_at_all(d): [os.remove(f) for f in tfiles(d)]
def other_key(d):
    p = os.path.join(d, "pinned.json"); s = json.load(open(V.PINNED))["servers"]; s["roughtime.cloudflare.com:2003"] = s["roughtime.int08h.com:2002"]; json.dump({"servers": s}, open(p, "w"))
CASES = [("one byte of a signed response changed", flip_response, ["ROUGHTIME_"]), ("a reading that lies in the files of another task", swap_tasks, ["TIME_EVIDENCE_FOR_ANOTHER_RUN"]),
 ("a receipt removed from an end reading's list (claimed to predate it)", drop_receipt_from_end, ["TIME_REQUEST_NONCE_NOT_DERIVED"]), ("a reading attributed to a server that the verifier does not pin", unpinned, ["TIME_SERVER_NOT_PINNED"]),
 ("the pinned key of the server replaced by the key of another server", other_key, ["ROUGHTIME_"]), ("a request nonce that is not the derived one", bad_nonce, ["TIME_REQUEST_NONCE_NOT_DERIVED"]),
 ("a task with an end reading and no start reading", no_start, ["TIME_EVIDENCE_INCOMPLETE"]), ("a receipt that no end reading names", add_receipt, ["RECEIPT_NOT_COVERED_BY_END_READING"]),
 ("the time file of a task deleted while its receipts stay", no_time_file, ["TIME_EVIDENCE_MISSING"]), ("a reading of an unknown version", bad_version, ["TIME_EVIDENCE_MALFORMED"]),
 ("one record with another collection nonce", other_nonce, ["TIME_EVIDENCE_FOR_ANOTHER_RUN", "TIME_REQUEST_NONCE_NOT_DERIVED"])]
bad = 0; tmp = tempfile.mkdtemp(prefix="p57-")
def show(ok, n, name, got):
    global bad; bad += 0 if ok else 1; print("%s %2d. %-82s -> %s" % ("ok:  " if ok else "FAIL:", n, name, got))
try:
    c = os.path.join(tmp, "control"); slim(SRC, c); st, ls = V.check(c); show(st == V.PASS and "signed window" in " ".join(ls), 1, "control: the untouched export passes and prints the signed window", "%s: %s" % (st, ls[0][:56]))
    n = 1; first = None
    for name, fn, want in CASES:
        n += 1; d = os.path.join(tmp, "c%d" % n); slim(SRC, d); fn(d); pin = os.path.join(d, "pinned.json"); st, ls = V.check(d, pin if os.path.exists(pin) else None); txt = " ".join(ls)
        show(st == V.FAIL and any(w in txt for w in want) and "Traceback" not in txt, n, name, "%s: %s" % (st, ls[0][:70])); first = first or d
    n += 1; d = os.path.join(tmp, "none"); slim(SRC, d); no_time_at_all(d); st, ls = V.check(d); show(st == V.NOTC and "no signed time evidence" in " ".join(ls), n, "an export with no time evidence is NOT CHECKED, never a pass", st)
    n += 1; st, ls = V.check(os.path.join(tmp, "missing")); show(st == V.FAIL and "no export folder" in " ".join(ls), n, "a missing export folder is a FAIL", st)
    n += 1; st, ls = V.check(c, os.path.join(tmp, "nothing.json")); show(st == V.FAIL and "cannot be read" in " ".join(ls), n, "an unreadable pinned keys file is a FAIL, not a pass", st)
    n += 1; ok1 = V.validity_in_window([{"not_before": 10, "not_after": 100}], (20, 90))[0]; ok2 = V.validity_in_window([{"not_before": 10, "not_after": 100}, {"not_before": 10, "not_after": 80}], (20, 90))[0]; ok3 = V.validity_in_window([{"not_before": 30, "not_after": 100}], (20, 90))[0]
    show(ok1 and not ok2 and not ok3, n, "the certificate rule: valid across the whole window, refused if one certificate ends or starts inside it", "%s %s %s" % (ok1, ok2, ok3))
    n += 1; env = lambda *a: subprocess.run([sys.executable, os.path.join(HERE, "verify_time_export.py")] + list(a), capture_output=True, text=True)
    r1 = env(c); r2 = env(os.path.join(tmp, "c2")); r3 = env(os.path.join(tmp, "none")); show(r1.returncode == 0 and r1.stdout.strip().endswith("TIME-OK") and r2.returncode == 1 and r2.stdout.strip().endswith("TIME-FAILED") and r3.returncode == 3 and r3.stdout.strip().endswith("TIME-NOT-CHECKED"), n, "the command line: exit 0 TIME-OK, exit 1 TIME-FAILED, exit 3 TIME-NOT-CHECKED", "exit %d / %d / %d" % (r1.returncode, r2.returncode, r3.returncode))
finally: shutil.rmtree(tmp, ignore_errors=True)
if bad: sys.exit("P5.7-REHEARSAL-FAILED: %d of %d cases went wrong" % (bad, n))
print("P5.7-REHEARSAL-OK: the untouched export passes, and all %d damages are refused for their own reason (the first four are the attacks of the teammate's own verify_time.py --negative)" % len(CASES))
