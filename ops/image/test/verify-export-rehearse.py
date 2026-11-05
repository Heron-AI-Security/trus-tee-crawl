#!/usr/bin/env python3
"""Rehearsal of ops/verify-export.py (steps P5.1 and P5.4). It takes the folder of a REAL run, runs the command on the untouched copy (it must pass every check that exists and say PARTIAL), then damages fresh copies in
many ways, one at a time, runs the WHOLE command on each and requires that the right step fails (and that the verdict is FAILED, never PARTIAL or OK). One case shows the gap that P5.4 closes: the fleet rules alone accept a TD with the debug bit set.
   python3 verify-export-rehearse.py EVIDENCE_DIR (--reference FILE | --published DIR) (--commit COMMIT | --no-commit-pin)
The folder is only read; every copy is made in a temporary folder. Needs the Python package 'cryptography' (the records check)."""
import base64, hashlib, os, re, shutil, struct, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); ENTRY = os.path.join(HERE, "..", "..", "verify-export.py"); F1 = os.path.join(HERE, "f1-fleet.py")
sys.path.insert(0, os.path.join(HERE, "..", "..", "attested"))
args = sys.argv[1:]
if not args or ("--reference" not in args and "--published" not in args): sys.exit(__doc__.split("\n")[3])
SRC = args[0]; REF = args[args.index("--reference") + 1] if "--reference" in args else None; PUB = args[args.index("--published") + 1] if "--published" in args else None
COMMIT = args[args.index("--commit") + 1] if "--commit" in args else None
def entry(evid, ref=None, commit=COMMIT, nopin=COMMIT is None, pub=None, extra=()):
    c = [sys.executable, ENTRY, evid] + (["--published", pub] if pub else ["--reference", ref]) + (["--commit", commit] if commit else (["--no-commit-pin"] if nopin else [])) + list(extra)
    p = subprocess.run(c, capture_output=True, text=True); out = p.stdout + p.stderr
    return p.returncode, dict((int(m.group(1)), m.group(2)) for m in re.finditer(r"^\[(\d)\] (PASS|FAIL|NOT CHECKED)", out, re.M)), out
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
def c_stable_removed(d):
    import json; f = d + ("/pub/reference.json" if PUB else "/ref.json"); r = json.load(open(f)); n = [x for x in r["events_in_order"] if x not in r["per_run_events"] and x != "source"][0]
    r["events_in_order"] = [x for x in r["events_in_order"] if x != n]; r["stable_events"].pop(n, None); json.dump(r, open(f, "w"))
CASES = [("the debug bit set in one quote A", c_debug_worker, {3}, {3}), ("the debug bit set in quote C", c_debug_c, {3}, {3}), ("the debug bit set in every quote", c_debug_all, {3}, {3}),
 ("one quote with other TD attributes (a bit cleared)", c_attr_differs, {3}, {3}), ("a quote cut to 100 bytes", c_short, {3}, {2, 3, 4}), ("a node without its final quote", c_missing_final, {2, 3}, {2, 3, 4}),
 ("a stray quote file with the debug bit set", c_stray, {3}, {3}), ("a changed byte in a WARC", c_warc_byte, {4, 5}, {4, 5}), ("a record file deleted", c_del_record, {4, 5}, {4, 5}),
 ("the records of two files swapped", c_swap_records, {4, 5}, {4, 5}), ("a forged file, signed by an unknown key, with the manifest updated to list it", c_forged_with_manifest, {4, 5}, {4, 5}),
 ("fleet.tsv with a damaged signing key", c_damaged_fleet, {2, 5}, {2, 4, 5}), ("fleet.tsv replaced by one with the attacker's own valid signing keys", c_other_fleet, {2, 5}, {2, 4, 5}), ("a reference with another MRTD", c_ref_mrtd, {2}, {1, 2, 4}), ("the export folder missing", c_no_export, {4, 5}, {4, 5}), ("a stable event removed from the reference (the completion of per-run events must not hide it)", c_stable_removed, {2}, {1, 2, 4})]
def prep(d):
    shutil.copytree(SRC, d, symlinks=True)
    if REF: shutil.copy(REF, d + "/ref.json")
    if PUB: shutil.copytree(PUB, d + "/pub")
def go(d, **kw): return entry(d, ref=(d + "/ref.json") if REF else None, pub=(d + "/pub") if PUB else None, **kw)
tmp = tempfile.mkdtemp(prefix="p5rehearse-"); bad = 0
def show(ok, n, name, got): print("%s %2d. %-76s -> %s" % ("ok:  " if ok else "FAIL:", n, name, got))
try:
    c = os.path.join(tmp, "control"); prep(c); rc, st, out = go(c)
    ok = rc == 3 and not [s for s in st.values() if s == "FAIL"] and sorted(n for n, s in st.items() if s == "NOT CHECKED")[-4:] == [6, 7, 8, 9] and "VERIFY-EXPORT-PARTIAL" in out and "NOT a full verification" in out
    print("control: the untouched run -> exit %d, %s" % (rc, ", ".join("%d %s" % (n, s) for n, s in sorted(st.items())))); 
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
    n = len(CASES) + 1; d = os.path.join(tmp, "pin"); prep(d)
    other = (COMMIT[:-1] + ("0" if COMMIT[-1] != "0" else "1")) if COMMIT else "abcdef123"; rc, st, out = go(d, commit=other, nopin=False)
    ok = rc == 1 and 2 in {k for k, s in st.items() if s == "FAIL"}; bad += 0 if ok else 1; show(ok, n, "a commit pin that is not the commit of the reference" if COMMIT else "a commit pin for a reference that names no commit", "exit %d, failed steps %s" % (rc, sorted(k for k, s in st.items() if s == "FAIL")))
    n += 1; rc, st, out = go(d, commit=None, nopin=False); ok = rc == 2; bad += 0 if ok else 1; show(ok, n, "neither --commit nor --no-commit-pin (a run must say how it is pinned)", "exit %d" % rc)
    n += 1; e = os.path.join(tmp, "notarelease"); os.makedirs(e); rc, st, out = entry(d, commit=COMMIT or "abcdef123", nopin=False, pub=e); ok = rc == 1 and 1 in {k for k, s in st.items() if s == "FAIL"}; bad += 0 if ok else 1; show(ok, n, "--published a folder that is not a release", "exit %d, failed steps %s" % (rc, sorted(k for k, s in st.items() if s == "FAIL")))
    total = n
finally: shutil.rmtree(tmp, ignore_errors=True)
if bad: sys.exit("P5.1-REHEARSAL-FAILED: %d of %d cases went wrong" % (bad, total))
print("P5.1-REHEARSAL-OK: the untouched run gives PARTIAL with every existing check passing, and all %d damages are rejected at the step that belongs to them, with the verdict FAILED" % total)
