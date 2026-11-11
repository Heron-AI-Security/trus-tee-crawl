#!/usr/bin/env python3
"""Rehearsal of verify_intel_chain.py (step P5.3) on the folder of a REAL run: the untouched run passes, then fresh copies are damaged one at a time and each damage must be refused for its own reason.
   python3 verify_intel_chain_rehearse.py EVIDENCE_DIR [PUBLISHED_DIR]
Every damage is a change that Intel's signature covers; the three marked ONLY are in bytes that no other step of verify-export.py reads, so that only this step can see them."""
import base64, glob, os, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
import verify_intel_chain as V
if len(sys.argv) < 2: sys.exit(__doc__.split("\n")[1])
SRC = sys.argv[1].rstrip("/"); PUB = sys.argv[2].rstrip("/") if len(sys.argv) > 2 else None
BODY_END = 632
def edit_quote(p, fn):
    ls = open(p).read().split("\n")
    for i, l in enumerate(ls):
        if l.startswith("quote_b64="): q = bytearray(base64.b64decode(l[10:])); fn(q); ls[i] = "quote_b64=" + base64.b64encode(bytes(q)).decode()
    open(p, "w").write("\n".join(ls))
def first(d, pre): return sorted(glob.glob(os.path.join(d, pre + "-*.txt")))[0]
def flip(i): return lambda q: q.__setitem__(i, q[i] ^ 1)
def chain_byte(q):
    a = bytes(q).find(b"-----BEGIN CERTIFICATE-----") + 120; q[a] = ord("A") if q[a] != ord("A") else ord("B")
def wrong_type(q): q[0] = 3
def cut(q): del q[100:]
CASES = [("a byte of the quote body that no other step reads (MRSEAM), ONLY the Intel signature sees it", lambda d: edit_quote(first(d, "announce"), flip(70)), "attestation key"),
 ("the debug bit of the TD attributes set in a quote (a changed signed byte)", lambda d: edit_quote(first(d, "announce"), flip(168)), "attestation key"),
 ("the attestation signature of the quote damaged, ONLY the Intel signature sees it", lambda d: edit_quote(first(d, "final"), flip(BODY_END + 4 + 10)), "attestation key"),
 ("a character of the PCK certificate chain changed, ONLY the Intel signature sees it", lambda d: edit_quote(first(d, "final"), chain_byte), None),
 ("a quote cut to 100 bytes", lambda d: edit_quote(first(d, "announce"), cut), "malformed"),
 ("a quote of another type (version 3)", lambda d: edit_quote(first(d, "announce"), wrong_type), "not a TDX v4"),
 ("a quote file without a quote_b64 line", lambda d: open(first(d, "announce"), "w").write("name=x\n"), "no quote_b64"),
 ("a quote_b64 line that is not base64", lambda d: open(first(d, "announce"), "w").write("quote_b64=!!!not base64!!!\n"), "cannot be read")]
bad = 0; tmp = tempfile.mkdtemp(prefix="p53-")
def show(ok, n, name, got):
    global bad; bad += 0 if ok else 1; print("%s %2d. %-92s -> %s" % ("ok:  " if ok else "FAIL:", n, name, got))
try:
    st, lines = V.check(SRC, PUB); show(st == V.PASS and "not checked here" in " ".join(lines), 1, "control: the untouched run (and its published release) passes, and says what it does not check", "%s: %s" % (st, lines[0][:60]))
    n = 1
    for name, fn, want in CASES:
        n += 1; d = os.path.join(tmp, "c%d" % n); shutil.copytree(SRC, d, symlinks=True); fn(d); st, lines = V.check(d, None); txt = " ".join(lines)
        show(st == V.FAIL and (want is None or want in txt) and "Traceback" not in txt, n, name, "%s: %s" % (st, lines[0][:70]))
    if PUB:
        n += 1; p = os.path.join(tmp, "pub"); shutil.copytree(PUB, p); f = sorted(glob.glob(os.path.join(p, "quote-run*.bin")))[0]; b = bytearray(open(f, "rb").read()); b[70] ^= 1; open(f, "wb").write(bytes(b))
        st, lines = V.check(SRC, p); show(st == V.FAIL and "published" in " ".join(lines), n, "a byte of a published quote of the release changed", "%s: %s" % (st, lines[0][:70]))
    n += 1; e = os.path.join(tmp, "empty"); os.makedirs(e); st, lines = V.check(e, None); show(st == V.NOTC and "no quote file" in " ".join(lines), n, "a folder with no quote at all is NOT CHECKED, not a pass", st)
    n += 1; noexe = os.path.join(tmp, "nobin"); os.makedirs(noexe); env = dict(os.environ, PATH=noexe); r = subprocess.run([sys.executable, "-c", "import sys; sys.path.insert(0, %r); import verify_intel_chain as V; print(V.check(%r)[0])" % (HERE, SRC)], capture_output=True, text=True, env=env)
    show(r.stdout.strip() == V.NOTC, n, "without the openssl command the check is NOT CHECKED and says why", r.stdout.strip() or r.stderr.strip()[:60])
    n += 1; r1 = subprocess.run([sys.executable, os.path.join(HERE, "verify_intel_chain.py"), SRC] + ([PUB] if PUB else []), capture_output=True, text=True); r2 = subprocess.run([sys.executable, os.path.join(HERE, "verify_intel_chain.py"), os.path.join(tmp, "c2")], capture_output=True, text=True)
    show(r1.returncode == 0 and r1.stdout.strip().endswith("INTEL-CHAIN-OK") and r2.returncode == 1 and r2.stdout.strip().endswith("INTEL-CHAIN-FAILED"), n, "the command line: exit 0 and INTEL-CHAIN-OK on the real run, exit 1 and INTEL-CHAIN-FAILED on a damaged copy", "exit %d / %d" % (r1.returncode, r2.returncode))
finally: shutil.rmtree(tmp, ignore_errors=True)
if bad: sys.exit("P5.3-REHEARSAL-FAILED: %d of %d cases went wrong" % (bad, n))
print("P5.3-REHEARSAL-OK: the untouched run passes, and all %d damages are refused for their own reason (3 of them are in bytes that only the Intel signature covers)" % (len(CASES) + (1 if PUB else 0)))
