#!/usr/bin/env python3
"""Rehearsal of ops/verify-export.py (steps P5.1 and P5.4). It takes the folder of a REAL run, runs the command on the untouched copy (it must pass every check that exists and say PARTIAL), then damages fresh copies in
many ways, one at a time, runs the WHOLE command on each and requires that the right step fails (and that the verdict is FAILED, never PARTIAL or OK). One case shows the gap that P5.4 closes: the fleet rules alone accept a TD with the debug bit set.
   python3 verify-export-rehearse.py EVIDENCE_DIR (--reference FILE | --published DIR) (--commit COMMIT | --no-commit-pin)
The folder is only read; every copy is made in a temporary folder. Needs the Python package 'cryptography' (the records check)."""
import base64, glob, hashlib, os, re, shutil, struct, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ENTRY = os.path.join(HERE, "..", "..", "verify-export.py"); F1 = os.path.join(HERE, "f1-fleet.py")
sys.path.insert(0, os.path.join(HERE, "..", "..", "attested"))
args = sys.argv[1:]
if not args or ("--reference" not in args and "--published" not in args): sys.exit(__doc__.split("\n")[3])
SRC = args[0]; REF = args[args.index("--reference") + 1] if "--reference" in args else None; PUB = args[args.index("--published") + 1] if "--published" in args else None
COMMIT = args[args.index("--commit") + 1] if "--commit" in args else None
HAS_FL = bool(glob.glob(os.path.join(SRC, "export", "tc", "crawl", "segments", "*", "tc_receipts", "fetchlist.txt")))   # a run of a build that exports fetch lists (step P5.6 part B) has them, and step 9 then PASSES on the untouched run; an older run has none, and step 9 is NOT CHECKED. What the run contains decides what is expected, not the run that this rehearsal was first written with.
HAS_SSL = bool(shutil.which("openssl"))   # step 6 (P5.3) needs the openssl command
S6 = {6} if HAS_SSL else set()   # a changed byte of a quote is also a broken Intel signature, so step 6 must fail when it can run
HAS_TIME = bool(glob.glob(os.path.join(SRC, "export", "tc", "crawl", "segments", "*", "tc_receipts", "time-*.jsonl")))   # signed Roughtime readings (step P5.7): step 10 passes on an untouched run that has them
NC = {7} | (set() if HAS_FL else {9}) | (set() if HAS_SSL else {6}) | (set() if HAS_TIME else {10})   # the steps that the untouched run, without an endorsement, cannot check (step 1 is counted apart)
def entry(evid, ref=None, commit=COMMIT, nopin=COMMIT is None, pub=None, extra=()):
    c = [sys.executable, ENTRY, evid] + (["--published", pub] if pub else ["--reference", ref]) + (["--commit", commit] if commit else (["--no-commit-pin"] if nopin else [])) + list(extra)
    p = subprocess.run(c, capture_output=True, text=True); out = p.stdout + p.stderr
    return p.returncode, dict((int(m.group(1)), m.group(2)) for m in re.finditer(r"^\[(\d+)\] (PASS|FAIL|NOT CHECKED)", out, re.M)), out
def rd(p): return open(p, "rb").read()
def wr(p, b): open(p, "wb").write(b)
def edit_quote(p, fn):
    ls = open(p).read().split("\n")
    for i, l in enumerate(ls):
        if l.startswith("quote_b64="): q = bytearray(base64.b64decode(l[10:])); fn(q); ls[i] = "quote_b64=" + base64.b64encode(bytes(q)).decode()
    open(p, "w").write("\n".join(ls))
def quotes(d): return sorted(f for f in os.listdir(d) if re.match(r"(announce|final|export)-.*\.txt$", f))
def master(d): return [l.split("\t")[0] for l in open(d + "/fleet.tsv") if l.strip() and not l.startswith("#") and l.split("\t")[1] == "master"][0]
def worker(d): return [l.split("\t")[0] for l in open(d + "/fleet.tsv") if l.strip() and not l.startswith("#") and l.split("\t")[1] != "master"][0]
def setdebug(q): q[168] |= 1
def c_debug_worker(d): edit_quote(d + "/announce-%s.txt" % worker(d), setdebug)
def c_debug_c(d): edit_quote(d + "/export-%s.txt" % master(d), setdebug)
def c_debug_all(d): [edit_quote(d + "/" + f, setdebug) for f in quotes(d)]
def c_attr_differs(d): edit_quote(d + "/final-%s.txt" % worker(d), lambda q: q.__setitem__(171, q[171] ^ 0x10))
def c_mrseam(d): edit_quote(d + "/announce-%s.txt" % worker(d), lambda q: q.__setitem__(70, q[70] ^ 1))   # MRSEAM: no other step reads it
def c_attsig(d): edit_quote(d + "/final-%s.txt" % worker(d), lambda q: q.__setitem__(646, q[646] ^ 1))   # the attestation signature of the quote
def c_chain(d):
    def f(q): a = bytes(q).find(b"-----BEGIN CERTIFICATE-----") + 120; q[a] = ord("A") if q[a] != ord("A") else ord("B")
    edit_quote(d + "/final-%s.txt" % worker(d), f)   # a character of the PCK certificate chain
def tfile(d): segs = d + "/export/tc/crawl/segments"; s = sorted(x for x in os.listdir(segs) if os.path.isdir(segs + "/" + x))[0]; return sorted(glob.glob(segs + "/" + s + "/tc_receipts/time-*.jsonl"))[0]
def c_time_byte(d):   # one character of a signed Roughtime response (still valid base64)
    f = tfile(d); t = open(f).read(); i = t.index('"response":"') + 12 + 20; open(f, "w").write(t[:i] + ("A" if t[i] != "A" else "B") + t[i + 1:])
def c_time_deleted(d): os.remove(tfile(d))
def c_short(d): edit_quote(d + "/announce-%s.txt" % worker(d), lambda q: q.__delitem__(slice(100, None)))
def c_missing_final(d): os.remove(d + "/final-%s.txt" % worker(d))
def c_stray(d): shutil.copy(d + "/announce-%s.txt" % master(d), d + "/announce-stray.txt"); edit_quote(d + "/announce-stray.txt", setdebug)
def warcs(d): w = d + "/export/tc/warc/warc"; return [w + "/" + f for f in sorted(os.listdir(w)) if not f.startswith(".") and f != "_attested-folder"]
def c_warc_byte(d): f = warcs(d)[0]; b = bytearray(rd(f)); b[len(b) // 2] ^= 1; wr(f, bytes(b))
def c_del_record(d): f = warcs(d)[0]; os.remove(os.path.dirname(f) + "/." + os.path.basename(f) + ".attested")
def c_swap_records(d): a, b = warcs(d)[:2]; ra, rb = [os.path.dirname(x) + "/." + os.path.basename(x) + ".attested" for x in (a, b)]; x, y = rd(ra), rd(rb); wr(ra, y); wr(rb, x)
def c_forged_with_manifest(d):
    from cryptography.hazmat.primitives import hashes, serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    from testvectors_check import utf, key_id_of, decode_folder
    w = d + "/export/tc/warc/warc"; data = b"forged page"; wr(w + "/evil.warc.gz", data); priv = ec.generate_private_key(ec.SECP256R1())
    kid = key_id_of(priv.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)); folder = decode_folder(rd(w + "/_attested-folder"))["folder"]; nb = b"evil.warc.gz"; h = hashlib.sha256(data).digest()
    st = utf("tc-attest-file-v1") + utf(kid) + folder + struct.pack(">i", len(nb)) + nb + struct.pack(">i", 16384) + struct.pack(">q", len(data)) + hashlib.sha256(h).digest(); sig = priv.sign(st, ec.ECDSA(hashes.SHA256()))
    rec = b"ATTEST04" + struct.pack(">i", 16384) + struct.pack(">q", len(data)) + bytes([len(kid)]) + kid.encode() + folder + struct.pack(">H", len(nb)) + nb + struct.pack(">i", 1) + h + struct.pack(">H", len(sig)) + sig; wr(w + "/.evil.warc.gz.attested", rec)
    m = d + "/export/manifest.tsv"; add = ""
    for p, name in ((w + "/evil.warc.gz", "tc/warc/warc/evil.warc.gz"), (w + "/.evil.warc.gz.attested", "tc/warc/warc/.evil.warc.gz.attested")): add += "%s\t%d\t%s\n" % (hashlib.sha256(rd(p)).hexdigest(), os.path.getsize(p), name)
    open(m, "a").write(add)
def swap_fleet_keys(d, mk):
    for f in (d + "/fleet.tsv", d + "/export/fleet.tsv"):
        out = []
        for l in open(f).read().split("\n"):
            p = l.split("\t")
            if len(p) >= 6 and not l.startswith("#"): p[4] = base64.b64encode(mk(base64.b64decode(p[4]))).decode()
            out.append("\t".join(p))
        open(f, "w").write("\n".join(out))
def c_damaged_fleet(d): swap_fleet_keys(d, lambda k: k[:-1] + bytes([k[-1] ^ 1]))
def c_other_fleet(d):
    from cryptography.hazmat.primitives import serialization
    from cryptography.hazmat.primitives.asymmetric import ec
    swap_fleet_keys(d, lambda k: ec.generate_private_key(ec.SECP256R1()).public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo))
def c_ref_mrtd(d):
    import json; f = d + ("/pub/reference.json" if PUB else "/ref.json"); r = json.load(open(f)); r["mrtd"] = ("0" if r["mrtd"][0] != "0" else "1") + r["mrtd"][1:]; json.dump(r, open(f, "w"))
def c_no_export(d): shutil.rmtree(d + "/export")
def run_mrtd(d): return base64.b64decode([l for l in open(d + "/announce-%s.txt" % master(d)).read().split("\n") if l.startswith("quote_b64=")][0][10:])[184:232]
def write_end(d, ms, other_root=False):
    import verify_endorsement_rehearse as ER
    open(d + "/end.bin", "wb").write(ER.endorsement(ER.golden(ER.DER(ER.leaf), ms=ms), ER.lk)); open(d + "/root.pem", "wb").write(ER.PEM(ER.aroot if other_root else ER.root))
def e_good(d): write_end(d, [(0, False, run_mrtd(d))])
def e_legacy(d): write_end(d, [(16, False, run_mrtd(d))])
def e_other_mrtd(d): m = bytearray(run_mrtd(d)); m[3] ^= 1; write_end(d, [(0, False, bytes(m))])
def e_other_root(d): write_end(d, [(0, False, run_mrtd(d))], other_root=True)
def e_legacy8(d): write_end(d, [(8, False, run_mrtd(d))])
def e_mixed(d): write_end(d, [(0, False, run_mrtd(d))]); edit_quote(d + "/announce-%s.txt" % worker(d), lambda q: q.__setitem__(184, q[184] ^ 1))
def e_missing(d): pass
def rfile(d, kind):
    segs = d + "/export/tc/crawl/segments"; s = sorted(x for x in os.listdir(segs) if os.path.isdir(segs + "/" + x))[0]; return sorted(glob.glob(segs + "/" + s + "/tc_receipts/%s-*.jsonl" % kind))[0]
def c_receipt_removed(d): f = rfile(d, "receipts"); ls = open(f).read().split("\n"); open(f, "w").write("\n".join(ls[1:]))
def flip_hex(f, pattern):
    t = open(f).read(); m = re.search(pattern, t); c = "0" if m.group(1) != "0" else "1"; open(f, "w").write(t[:m.start(1)] + c + t[m.end(1):])
def c_receipt_changed(d): flip_hex(rfile(d, "receipts"), r"sha256:([0-9a-f])")
def c_outcome_removed(d):   # remove the outcome of an ACCEPTED page (the one that carries a receipt), never a refusal or a redirect: only then does a receipt lose its outcome, which step 8 must see
    import json; f = rfile(d, "outcomes"); ls = open(f).read().split("\n"); k = next((i for i, l in enumerate(ls) if l.strip() and json.loads(l).get("receipt_sha256")), 0); open(f, "w").write("\n".join(ls[:k] + ls[k + 1:]))
def c_outcome_hash(d): flip_hex(rfile(d, "outcomes"), r'"receipt_sha256"\s*:\s*"sha256:([0-9a-f])')
def c_stable_removed(d):
    import json; f = d + ("/pub/reference.json" if PUB else "/ref.json"); r = json.load(open(f)); n = [x for x in r["events_in_order"] if x not in r["per_run_events"] and x != "source"][0]
    r["events_in_order"] = [x for x in r["events_in_order"] if x != n]; r["stable_events"].pop(n, None); json.dump(r, open(f, "w"))
CASES = [("the debug bit set in one quote A", c_debug_worker, {3} | S6, {3, 6}), ("the debug bit set in quote C", c_debug_c, {3} | S6, {3, 6}), ("the debug bit set in every quote", c_debug_all, {3} | S6, {3, 6}),
 ("one quote with other TD attributes (a bit cleared)", c_attr_differs, {3} | S6, {3, 6}), ("a quote cut to 100 bytes", c_short, {3} | S6, {2, 3, 4, 6}), ("a node without its final quote", c_missing_final, {2, 3}, {2, 3, 4}),
 ("a stray quote file with the debug bit set", c_stray, {3} | S6, {3, 6}), ("a changed byte in a WARC", c_warc_byte, {4, 5}, {4, 5, 8}), ("a record file deleted", c_del_record, {4, 5}, {4, 5}),
 ("the records of two files swapped", c_swap_records, {4, 5}, {4, 5}), ("a forged file, signed by an unknown key, with the manifest updated to list it", c_forged_with_manifest, {4, 5}, {4, 5, 8}),
 ("fleet.tsv with a damaged signing key", c_damaged_fleet, {2, 5}, {2, 4, 5}), ("fleet.tsv replaced by one with the attacker's own valid signing keys", c_other_fleet, {2, 5}, {2, 4, 5}), ("a reference with another MRTD", c_ref_mrtd, {2}, {1, 2, 4}), ("the export folder missing", c_no_export, {4, 5, 8, 9, 10}, {4, 5, 8, 9, 10}), ("a stable event removed from the reference (the completion of per-run events must not hide it)", c_stable_removed, {2}, {1, 2, 4}),
 ("a receipt removed from the signed receipts file", c_receipt_removed, {8}, {4, 5, 8}), ("a receipt of the signed receipts file changed (one digit of a hash): step 10 also sees it, no end reading names the changed receipt", c_receipt_changed, {8}, {4, 5, 8, 10}),
 *([("step P5.3: one byte of the quote body that no other step reads (MRSEAM): ONLY the Intel signature sees it", c_mrseam, {6}, {6}), ("step P5.3: the attestation signature of a quote damaged: ONLY the Intel signature sees it", c_attsig, {6}, {6}), ("step P5.3: a character of the PCK certificate chain changed: ONLY the Intel signature sees it", c_chain, {6}, {6})] if HAS_SSL else []),
 *([("step P5.7: one character of a signed Roughtime response changed", c_time_byte, {10}, {4, 5, 8, 10}), ("step P5.7: the time file of a task deleted", c_time_deleted, {10}, {4, 5, 10})] if HAS_TIME else []),
 ("an outcome removed from the outcomes file", c_outcome_removed, ({8, 9} if HAS_FL else {8}), {4, 5, 8, 9}), ("the receipt_sha256 of an outcome changed", c_outcome_hash, {8}, {4, 5, 8})]
def prep(d):
    shutil.copytree(SRC, d, symlinks=True)
    if REF: shutil.copy(REF, d + "/ref.json")
    if PUB: shutil.copytree(PUB, d + "/pub")
def go(d, **kw): return entry(d, ref=(d + "/ref.json") if REF else None, pub=(d + "/pub") if PUB else None, **kw)
tmp = tempfile.mkdtemp(prefix="p5rehearse-"); bad = 0
def show(ok, n, name, got): print("%s %2d. %-76s -> %s" % ("ok:  " if ok else "FAIL:", n, name, got))
try:
    c = os.path.join(tmp, "control"); prep(c); rc, st, out = go(c)
    nc = {n for n, s in st.items() if s == "NOT CHECKED"}; ok = rc == 3 and "FAIL" not in st.values() and (nc - {1}) == NC and st.get(8) == "PASS" and (st.get(9) == "PASS") == HAS_FL and "VERIFY-EXPORT-PARTIAL" in out and "NOT a full verification" in out
    print("control: the untouched run (%s) -> exit %d, %s" % ("the export has real fetch lists: step 9 must PASS" if HAS_FL else "the export has no fetch lists: step 9 must be NOT CHECKED", rc, ", ".join("%d %s" % (n, s) for n, s in sorted(st.items())))); 
    if not ok: print(out); print("STOP: the untouched run does not give PARTIAL with every existing check passing"); sys.exit(1)
    if REF:
        import json; r = json.load(open(REF)); pl = {k: v for k, v in r.items()}; pl["events_in_order"] = [x for x in r["events_in_order"] if x not in r["per_run_events"]]; pl["stable_events"] = {k: v for k, v in r["stable_events"].items() if k not in r["per_run_events"]}; pl["per_run_events"] = []
        d = os.path.join(tmp, "pl"); shutil.copytree(SRC, d, symlinks=True); json.dump(pl, open(d + "/pl.json", "w")); p = subprocess.run([sys.executable, F1, "enforce", d, d + "/pl.json"] + ([COMMIT] if COMMIT else []), capture_output=True, text=True)
        rc, st, out = entry(d, ref=d + "/pl.json"); ok = p.returncode != 0 and rc == 3 and st.get(2) == "PASS" and "per-run events" in out; bad += 0 if ok else 1
        print("%s     the published form of a reference (a dummy run: no per-run events): the fleet rules alone %s it, the entry point %s it and says so" % ("ok:  " if ok else "FAIL:", "REFUSE" if p.returncode != 0 else "accept", "accepts" if st.get(2) == "PASS" else "refuses"))
    for n, (name, fn, must, may) in enumerate(CASES, 1):
        d = os.path.join(tmp, "m%d" % n); prep(d); fn(d); rc, st, out = go(d); failed = {k for k, s in st.items() if s == "FAIL"}
        ok = rc == 1 and must <= failed and failed <= may and "VERIFY-EXPORT-FAILED" in out and "VERIFY-EXPORT-OK" not in out and "PARTIAL" not in out; bad += 0 if ok else 1; show(ok, n, name, "exit %d, failed steps %s" % (rc, sorted(failed)))
        if n == 1:
            import json; rj = json.load(open((d + "/pub/reference.json") if PUB else (d + "/ref.json")))
            if not rj.get("per_run_events"): rj["per_run_events"] = ["fleet", "fleet-conf"]   # the same completion as the entry point, so that ONLY the debug bit is left for the fleet rules to judge
            json.dump(rj, open(d + "/ref-completed.json", "w")); p = subprocess.run([sys.executable, F1, "enforce", d, d + "/ref-completed.json"] + ([COMMIT] if COMMIT else []), capture_output=True, text=True); g = p.returncode == 0 and "ENFORCE-OK" in p.stdout
            print("      the gap that P5.4 closes: the fleet rules alone (f1-fleet.py enforce) %s this TD with the debug bit set" % ("ACCEPT" if g else "refuse")); bad += 0 if g else 1
    ex = lambda d: ["--endorsement", d + "/end.bin", "--google-root", d + "/root.pem"]
    for nm, fn in (("control: with a Google-shaped endorsement of the run's MRTD (RAM-independent)", e_good), ("control: with an endorsement that lists the MRTD for exactly 16 GiB, the RAM of c3-standard-4", e_legacy)):
        d = os.path.join(tmp, "e" + str(abs(hash(nm)))); prep(d); fn(d); rc, st, out = go(d, extra=ex(d)); nc = {k for k, s_ in st.items() if s_ == "NOT CHECKED"}; ok = rc == (3 if nc else 0) and ("VERIFY-EXPORT-OK" in out if not nc else True) and "FAIL" not in st.values() and st.get(7) == "PASS" and (nc - {1}) == (NC - {7}); bad += 0 if ok else 1   # with every step run (published mode, an endorsement, Intel chain and signed time present) nothing is NOT CHECKED, so the exit code is 0
        print("%s     %-86s -> exit %d, step 7 %s" % ("ok:  " if ok else "FAIL:", nm, rc, st.get(7)))
    for nm, fn, must, may in (("an endorsement for another MRTD", e_other_mrtd, {7}, {7}), ("an endorsement chained to a root that is not the pinned one", e_other_root, {7}, {7}), ("an endorsement that lists the MRTD only for 8 GiB, the VM has 16", e_legacy8, {7}, {7}),
                              ("the quotes show two different MRTDs (one quote changed)", e_mixed, {2, 7}, {2, 4, 6, 7}), ("the endorsement file does not exist", e_missing, {7}, {7})):
        d = os.path.join(tmp, "e" + str(abs(hash(nm)))); prep(d); fn(d); rc, st, out = go(d, extra=ex(d)); failed = {k for k, s_ in st.items() if s_ == "FAIL"}; ok = rc == 1 and must <= failed <= may and "VERIFY-EXPORT-FAILED" in out and "Traceback" not in out; bad += 0 if ok else 1
        print("%s     %-86s -> exit %d, failed steps %s" % ("ok:  " if ok else "FAIL:", nm, rc, sorted(failed)))
    import verify_fetchlist_rehearse as FR
    FLC = (("fetch lists added to the export (no record, not in the manifest): steps 4 and 5 refuse them, and step 9 judges them on its own, here PASS", lambda d: FR.build(d + "/export"), {4, 5}), ("the same, with one URL that was scheduled but never fetched (no WARC record, no outcome): step 8 passes, ONLY step 9 sees the gap", lambda d: (FR.build(d + "/export"), FR.ed(d + "/export", FR.add_url)), {4, 5, 9}))
    if HAS_FL: FLC = (("a URL removed from the REAL fetch list of the first segment: steps 4 and 5 refuse the changed file, and step 9 sees an outcome for a URL that was never scheduled", lambda d: FR.ed(d + "/export", FR.drop_url), {4, 5, 9}), ("the real fetch lists, and one URL that was scheduled but never fetched (no WARC record, no outcome): step 8 passes, ONLY step 9 sees the gap", lambda d: FR.ed(d + "/export", FR.add_url), {4, 5, 9}))   # the real lists are already there: adding derived ones would change nothing
    for nm, fn, must in FLC:
        d = os.path.join(tmp, "f" + str(abs(hash(nm)))); prep(d); fn(d); rc, st, out = go(d); failed = {k for k, s_ in st.items() if s_ == "FAIL"}; ok = rc == 1 and failed == must and (9 in failed or st.get(9) == "PASS") and st.get(8) == "PASS" and "Traceback" not in out; bad += 0 if ok else 1
        print("%s     %-98s -> exit %d, failed steps %s, step 9 %s" % ("ok:  " if ok else "FAIL:", nm, rc, sorted(failed), st.get(9)))
    d = os.path.join(tmp, "eonly"); prep(d); e_good(d); rc, st, out = go(d, extra=["--endorsement", d + "/end.bin"]); ok = rc == 2; bad += 0 if ok else 1; print("%s     %-86s -> exit %d" % ("ok:  " if ok else "FAIL:", "--endorsement without --google-root (the root must be pinned by you)", rc))
    n = len(CASES) + 1; d = os.path.join(tmp, "pin"); prep(d)
    other = (COMMIT[:-1] + ("0" if COMMIT[-1] != "0" else "1")) if COMMIT else "abcdef123"; rc, st, out = go(d, commit=other, nopin=False)
    ok = rc == 1 and 2 in {k for k, s in st.items() if s == "FAIL"}; bad += 0 if ok else 1; show(ok, n, "a commit pin that is not the commit of the reference" if COMMIT else "a commit pin for a reference that names no commit", "exit %d, failed steps %s" % (rc, sorted(k for k, s in st.items() if s == "FAIL")))
    n += 1; rc, st, out = go(d, commit=None, nopin=False); ok = rc == 2; bad += 0 if ok else 1; show(ok, n, "neither --commit nor --no-commit-pin (a run must say how it is pinned)", "exit %d" % rc)
    n += 1; e = os.path.join(tmp, "notarelease"); os.makedirs(e); rc, st, out = entry(d, commit=COMMIT or "abcdef123", nopin=False, pub=e); ok = rc == 1 and 1 in {k for k, s in st.items() if s == "FAIL"}; bad += 0 if ok else 1; show(ok, n, "--published a folder that is not a release", "exit %d, failed steps %s" % (rc, sorted(k for k, s in st.items() if s == "FAIL")))
    total = n + 10
finally: shutil.rmtree(tmp, ignore_errors=True)
if bad: sys.exit("P5.1-REHEARSAL-FAILED: %d of %d cases went wrong" % (bad, total))
print("P5.1-REHEARSAL-OK: the untouched run gives PARTIAL with every existing check passing, the 2 controls with an endorsement pass, and all %d damages are rejected at the step that belongs to them, with the verdict FAILED" % (total - 2))
