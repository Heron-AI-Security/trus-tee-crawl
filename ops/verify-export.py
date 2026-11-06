#!/usr/bin/env python3
"""Steps P5.1 and P5.4: the verifier from the quotes of a run to the records of its export. One command, the checks in order, one verdict line for each.
   python3 ops/verify-export.py EVIDENCE_DIR (--published DIR | --reference FILE) (--commit COMMIT | --no-commit-pin) [--export DIR] [--endorsement FILE --google-root FILE [--ram-gib N]]
EVIDENCE_DIR is the folder of a run: fleet.tsv, announce-NODE.txt and final-NODE.txt of every node, export-MASTER.txt (quote C) and the export folder EVIDENCE_DIR/export (or --export DIR).
  --published DIR   the files of a release made by ops/ci/publish-ref.sh; step 1 checks them for COMMIT (part A of ops/verify-reference.sh), and DIR/reference.json is the reference of step 2.
  --reference FILE  a reference file only (for a run without a published release); step 1 is then NOT CHECKED.
  --commit COMMIT   the commit that the run must be built from (rule E9). --no-commit-pin leaves the pin out for an older reference that names no commit; E9 is then NOT APPLIED and the line says so.
The steps:  1 the reference is the published reference of the commit   2 the quotes of every node equal the reference (rules E1 to E7 and E9 of ops/image/test/f1-fleet.py)
            3 the TD attributes of every quote: the debug bit is off (P5.4; f1-fleet.py never looks at it)   4 the export is what quote C says (rule E8)
            5 every record and folder identity of the export is signed by a key of the fleet (P5.2, ops/attested/verify_export_records.py)
            6 the Intel chain of every quote (E0)   7 the MRTD against Google's launch endorsement   8 the receipts (P5.6, part A: ops/image/test/r3-receipt-verify.py)
            9 every URL of the fetch list has exactly one outcome (P5.6, part B: ops/attested/verify_fetchlist.py; the fetch list is what the crawl script wrote from the segments' crawl_generate)   10 the Roughtime signatures.
            Steps 6 and 10 are NOT CHECKED yet (P5.3, P5.7); step 7 is NOT CHECKED unless --endorsement and --google-root are given; step 8 is NOT CHECKED for an export that holds no receipts; step 9 is NOT CHECKED for an export of a run that made no fetch list.
  --endorsement FILE --google-root FILE   Google's launch endorsement of the MRTD (https://storage.googleapis.com/gce_tcb_integrity/ovmf_x64_csm/tdx/<MRTD in hex>.binarypb) and Google's root certificate (https://pki.goog/cloud_integrity/GCE-cc-tcb-root_1.crt);
                    they make step 7 run (ops/attested/verify_endorsement.py). The MRTD is read from the quotes of the run. The RAM size comes from --ram-gib or from the machine type c3-standard-N of the reference.
Exit code 0: every check passed and none is missing. 1: a check FAILED. 3: nothing failed, but some checks are NOT CHECKED, so this is NOT a full verification. 2: wrong usage.
Read this before you trust a PASS: the TD attributes of step 3 are read from the quote bytes, and a quote is authentic only when its Intel chain verifies (step 6, not yet checked)."""
import argparse, base64, glob, json, os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); F1 = os.path.join(HERE, "image", "test", "f1-fleet.py"); VR = os.path.join(HERE, "verify-reference.sh"); RV = os.path.join(HERE, "image", "test", "r3-receipt-verify.py")
sys.path.insert(0, os.path.join(HERE, "attested"))
PASS, FAIL, NOTC = "PASS", "FAIL", "NOT CHECKED"
results = []
def report(n, status, title, lines=()):
    results.append((n, status, title)); print("[%d] %-11s %s" % (n, status, title))
    for l in lines: print("      " + l)
def run(cmd):
    try: p = subprocess.run(cmd, capture_output=True, text=True)
    except OSError as e: return 127, "STOP: could not run %s: %s" % (cmd[0], e)
    return p.returncode, (p.stdout + p.stderr)
def problems(out, limit=6):
    """The problem lines of f1-fleet.py are indented by exactly two spaces; the text of the rules that follows them is indented differently and is not a problem."""
    ls = [l.strip()[:240] for l in out.splitlines() if re.match(r"^  [^ ]", l)]; return ls[:limit] + (["... and %d more" % (len(ls) - limit)] if len(ls) > limit else [])
def usable_reference(path, tmp):
    """A published reference is the reference of a DUMMY run: it has no fleet, so it names no per-run events. The fleet rules (E6) expect the two events that depend on the run, fleet and fleet-conf (the keys of the fleet),
    to be declared. They are declared here, in a temporary copy, and ONLY when the reference declares none; the stable events, in order, and every register stay exactly as published."""
    try: ref = json.load(open(path, encoding="utf-8"))
    except (OSError, ValueError): return path, []
    if ref.get("per_run_events"): return path, []
    ref["per_run_events"] = ["fleet", "fleet-conf"]; out = os.path.join(tmp, "reference-with-per-run-events.json"); json.dump(ref, open(out, "w"))
    return out, ["the reference names no per-run events (it is the reference of a dummy run, which has no fleet): fleet and fleet-conf were declared as per-run events in a temporary copy, as in the reference of a fleet; the stable events and the registers are exactly as published"]
def read_quote(path):
    d = {}
    for line in open(path, encoding="utf-8", errors="replace").read().splitlines():
        if "=" in line: k, v = line.split("=", 1); d[k] = v
    if "quote_b64" not in d: raise ValueError("no quote_b64 line")
    return base64.b64decode(d["quote_b64"])
def quote_mrtds(evid):
    out = {}
    for f in sorted(glob.glob(os.path.join(evid, "announce-*.txt")) + glob.glob(os.path.join(evid, "final-*.txt")) + glob.glob(os.path.join(evid, "export-*.txt"))):
        try: q = read_quote(f)
        except (ValueError, OSError): continue
        if len(q) >= 232: out[os.path.basename(f)] = q[184:232].hex()
    return out
def check_attributes(evid, nodes):
    """P5.4: the TD attributes (quote bytes 168 to 176, little endian; bit 0 is DEBUG) of EVERY quote file of the run: announce-*, final-* and export-*."""
    files = sorted(glob.glob(os.path.join(evid, "announce-*.txt")) + glob.glob(os.path.join(evid, "final-*.txt")) + glob.glob(os.path.join(evid, "export-*.txt"))); bad = []; attrs = {}
    for n in nodes:
        have = [f for f in ("announce-%s.txt" % n, "final-%s.txt" % n) if os.path.isfile(os.path.join(evid, f))]
        if len(have) < 2: bad.append("node %s has %d of its 2 quotes (announce and final)" % (n, len(have)))
    for f in files:
        name = os.path.basename(f)
        try: q = read_quote(f)
        except (ValueError, OSError) as e: bad.append("%s: %s" % (name, e)); continue
        if len(q) < 632: bad.append("%s: a quote of %d bytes is too short to hold the TD attributes" % (name, len(q))); continue
        a = q[168:176]; attrs[name] = a.hex()
        if a[0] & 1: bad.append("%s: the DEBUG bit is SET (TD attributes %s): the host can read this TD's memory" % (name, a.hex()))
    if len(set(attrs.values())) > 1: bad.append("the TD attributes differ between quotes: %s" % "; ".join("%s=%s" % kv for kv in sorted(attrs.items())))
    if not files: bad.append("the folder holds no quote file")
    return bad, attrs
def main(argv):
    ap = argparse.ArgumentParser(add_help=False); ap.add_argument("evidence"); g = ap.add_mutually_exclusive_group(required=True); g.add_argument("--published"); g.add_argument("--reference")
    c = ap.add_mutually_exclusive_group(required=True); c.add_argument("--commit"); c.add_argument("--no-commit-pin", action="store_true"); ap.add_argument("--export"); ap.add_argument("--endorsement"); ap.add_argument("--google-root"); ap.add_argument("--ram-gib", type=int)
    try: a = ap.parse_args(argv)
    except SystemExit: print(__doc__.split("\n")[1]); return 2
    if a.published and not a.commit: print("usage: --published needs --commit (the release is checked for that commit)"); return 2
    if bool(a.endorsement) != bool(a.google_root): print("usage: --endorsement and --google-root go together (the endorsement is checked against the root that you pin)"); return 2
    evid = a.evidence.rstrip("/"); exp = a.export or os.path.join(evid, "export")
    for p, what in ((os.path.join(evid, "fleet.tsv"), "fleet.tsv in the evidence folder"),):
        if not os.path.isfile(p): print("usage: there is no %s (%s)" % (what, p)); return 2
    rows = [l.split("\t") for l in open(os.path.join(evid, "fleet.tsv"), encoding="utf-8").read().splitlines() if l.strip() and not l.startswith("#")]
    nodes = [r[0] for r in rows]; masters = [r[0] for r in rows if len(r) > 1 and r[1] == "master"]
    ref = os.path.join(a.published, "reference.json") if a.published else a.reference
    print("verify-export: run %s, %d node(s) (%s), reference %s, %s\n" % (evid, len(nodes), ", ".join(nodes), ref, ("commit " + a.commit) if a.commit else "NO COMMIT PIN (rule E9 not applied)"))
    # 1
    if a.published:
        w = tempfile.mkdtemp(prefix="verify-export-"); rc, out = run(["bash", VR, a.commit, "--published", a.published, "--work", w])
        ok = rc == 0 and "VERIFY-REFERENCE-OK" in out; last = [l for l in out.splitlines() if l.strip()][-1:] 
        report(1, PASS if ok else FAIL, "the reference is the published reference of the commit (part A of ops/verify-reference.sh)", last if ok else [l.strip() for l in out.splitlines() if "FAIL" in l or "fail" in l][:5] or last)
    else: report(1, NOTC, "the reference is the published reference of the commit", ["only --reference was given: nothing shows that this file is the published reference of any commit"])
    # 2
    if not os.path.isfile(ref): report(2, FAIL, "the quotes of every node equal the reference (rules E1 to E7, and E9 when a commit is given)", ["there is no reference file %s" % ref]); eref = ref
    else:
        tmpd = tempfile.mkdtemp(prefix="verify-export-ref-"); eref, notes = usable_reference(ref, tmpd)
        rc, out = run([sys.executable, F1, "enforce", evid, eref] + ([a.commit] if a.commit else []))
        ok = rc == 0 and "ENFORCE-OK" in out; extra = [l for l in out.splitlines() if l.startswith("PINNED")] if ok else problems(out) or [l for l in out.splitlines() if l.startswith("STOP")][:3]
        if ok and not a.commit: extra.append("E9 NOT APPLIED: no commit pin was given, so nothing ties this run to a commit")
        report(2, PASS if ok else FAIL, "the quotes of every node equal the reference (rules E1 to E7, and E9 when a commit is given)", extra + notes)
    # 3
    try: bad, attrs = check_attributes(evid, nodes)
    except Exception as e: bad, attrs = ["the check crashed (%s: %s): this is a FAIL, not a pass" % (type(e).__name__, e)], {}
    if bad: report(3, FAIL, "TD attributes: the debug bit is off in every quote (P5.4)", bad[:6])
    else: report(3, PASS, "TD attributes: the debug bit is off in every quote (P5.4)", ["%d quote(s), TD attributes %s in all, debug bit 0 in all (read from the quote bytes: authentic only once step 6 is checked)" % (len(attrs), sorted(set(attrs.values()))[0])])
    # 4
    if len(masters) != 1: report(4, FAIL, "the export is what quote C says (rule E8)", ["fleet.tsv has %d master row(s); exactly one is needed" % len(masters)])
    elif not os.path.isdir(exp): report(4, FAIL, "the export is what quote C says (rule E8)", ["there is no export folder %s" % exp])
    else:
        rc, out = run([sys.executable, F1, "export-check", evid, exp, masters[0]] + ([eref] if os.path.isfile(eref) else []))
        ok = rc == 0 and "EXPORT-OK" in out; report(4, PASS if ok else FAIL, "the export is what quote C says (rule E8)", [out.strip().splitlines()[-1][:170]] if ok else problems(out) or [l for l in out.splitlines() if l.startswith("STOP")][:3])
    # 5
    if not os.path.isdir(exp): report(5, FAIL, "every record and folder identity of the export is signed by a key of the fleet (P5.2)", ["there is no export folder %s" % exp])
    else:
        from verify_export_records import verify_export
        try: rep = verify_export(exp, os.path.join(evid, "fleet.tsv"))
        except (SystemExit, Exception) as e: report(5, FAIL, "every record and folder identity of the export is signed by a key of the fleet (P5.2)", ["the check could not run (%s: %s): this is a FAIL, not a pass" % (type(e).__name__, e)])
        else:
            if rep.problems: report(5, FAIL, "every record and folder identity of the export is signed by a key of the fleet (P5.2)", ["%s %s: %s" % p for p in rep.problems[:6]] + (["... and %d more" % (len(rep.problems) - 6)] if len(rep.problems) > 6 else []))
            else: report(5, PASS, "every record and folder identity of the export is signed by a key of the fleet (P5.2)", ["%d folder identities and %d files (%d chunks) verified against the keys of the fleet.tsv that the quotes measured" % (rep.folders, rep.files, rep.chunks)])
    report(6, NOTC, "the Intel signature chain of every quote (E0)", ["step P5.3: it needs the teammate's tc-peer-verify.py; today it is done by hand with go-tdx-guest"])
    # 7
    T7 = "the MRTD is in Google's signed launch endorsement (P5.5)"
    if not a.endorsement: report(7, NOTC, T7, ["give --endorsement FILE (https://storage.googleapis.com/gce_tcb_integrity/ovmf_x64_csm/tdx/<MRTD in hex>.binarypb) and --google-root FILE (https://pki.goog/cloud_integrity/GCE-cc-tcb-root_1.crt)"])
    else:
        try:
            from verify_endorsement import check as check_endorsement, ram_gib_of
            mr = quote_mrtds(evid)
            if not mr: raise ValueError("no quote with an MRTD in the evidence folder")
            if len(set(mr.values())) != 1: raise ValueError("the quotes show different MRTDs: " + "; ".join("%s=%s..." % (k, v[:12]) for k, v in sorted(mr.items())))
            mrtd = next(iter(mr.values()))
            try: mt = json.load(open(ref)).get("machine_type")
            except (OSError, ValueError): mt = None
            ram = a.ram_gib or ram_gib_of(mt); end = open(a.endorsement, "rb").read(); roots = open(a.google_root, "rb").read()
            ok, lines = check_endorsement(end, roots, mrtd, ram)
            report(7, PASS if ok else FAIL, T7, (lines + ["the MRTD is read from the bytes of %d quote(s): authentic only once step 6 is checked" % len(mr)] + ([] if ram else ["the RAM size is not known (machine type %s): only a RAM-independent entry can match" % mt])) if ok else lines[:3])
        except (OSError, ValueError) as e: report(7, FAIL, T7, [str(e)])
        except Exception as e: report(7, FAIL, T7, ["the check crashed (%s: %s): this is a FAIL, not a pass" % (type(e).__name__, e)])
    # 8
    T8 = "the receipts: every receipt in the WARCs is in the signed receipts files, and each describes its response (P5.6, part A)"
    if not os.path.isdir(exp): report(8, FAIL, T8, ["there is no export folder %s" % exp])
    else:
        rc, out = run([sys.executable, RV, exp]); inp = next((l for l in out.splitlines() if l.startswith("== inputs:")), ""); m = re.search(r"(\d+) receipts in the receipts files, (\d+) receipt records in the WARC", inp)
        if rc == 0 and m and m.group(1) == "0" and m.group(2) == "0": report(8, NOTC, T8, ["the export holds no receipts (the run was made without them): there is nothing to verify, and an empty pass would say more than is true"])
        else:
            ok = rc == 0 and "RECEIPT-VERIFY-OK" in out; fails = [l.strip()[:230] for l in out.splitlines() if l.strip().startswith("FAIL:")]
            report(8, PASS if ok else FAIL, T8, [inp.replace("== inputs: ", "")[:200]] if ok else (fails[:6] or [l.strip()[:200] for l in out.splitlines() if "Traceback" in l or "Error" in l][:3] or ["the check ended with exit code %d and no verdict" % rc]))
    # 9
    T9 = "every URL of the fetch list has exactly one outcome, and no outcome is for an unscheduled URL (P5.6, part B)"
    if not os.path.isdir(exp): report(9, FAIL, T9, ["there is no export folder %s" % exp])
    else:
        try:
            from verify_fetchlist import check as check_fetchlist
            st9, l9 = check_fetchlist(exp)
        except Exception as e: st9, l9 = FAIL, ["the check crashed (%s: %s): this is a FAIL, not a pass" % (type(e).__name__, e)]
        report(9, st9, T9, l9)
    report(10, NOTC, "the Roughtime signatures", ["step P5.7: it needs the teammate's verify_time.py and the pinned keys (step 8 checks only the structure and the time window of the readings)"])
    failed = [n for n, s, _ in results if s == FAIL]; missing = [n for n, s, _ in results if s == NOTC]; passed = [n for n, s, _ in results if s == PASS]
    print()
    if failed: print("VERIFY-EXPORT-FAILED: check(s) %s failed; %d passed, %d not checked" % (", ".join(map(str, failed)), len(passed), len(missing))); return 1
    if missing: print("VERIFY-EXPORT-PARTIAL: the %d checks that exist passed (%s); %d are NOT CHECKED (%s): this is NOT a full verification" % (len(passed), ", ".join(map(str, passed)), len(missing), ", ".join(map(str, missing)))); return 3
    print("VERIFY-EXPORT-OK: all %d checks passed" % len(passed)); return 0
if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
