#!/usr/bin/env python3
"""Step P4 of the mentor's plan: verify a published reference.
    python3 ops/verify-reference.py --published DIR --commit COMMIT [--own-run RUNDIR]
DIR holds the files of a release made by ops/ci/publish-ref.sh (reference.json, release.json, publication.json, quote-run1.bin, quote-run2.bin, announce-run1.txt, rtmr3-events.tsv,
ccel.bin, boot-tables.md, settings.json and SHA256SUMS). COMMIT is the commit (9 to 40 hexadecimal digits) that the image was built from.
Part A needs no cloud. It checks that the published evidence is consistent with itself and with the commit: the SHA-256 of every file, the commit and its `source` event, both quotes
(binding, RTMR3 replay, debug bit off), the registers of the reference, the replay of the boot event log against the quote, the root hash against the kernel command line, and the tables.
Part B needs RUNDIR, the folder that ops/reference-run.sh makes from YOUR OWN build of the commit. It compares your dummy run with the published reference: MRTD, RTMR0, RTMR1 and
every RTMR3 event must be equal. RTMR2 must be equal too, or differ only in events that carry the root hash of the disk or a partition UUID (two builds of one commit seal two different
disks); each such difference is listed, and a difference in any other event fails. Whether the two disks hold the same files is the file-tree diff (step P4.2).
--image-run RUNDIR is YOUR OWN dummy run of the PUBLISHED image: it must be exactly equal to the published reference (no explained difference), which proves that the image you compare is the image of the release.
--tree-result FILE holds the verdict line of ops/tree-diff.sh (TREE-DIFF-IDENTICAL ... verity=checked) for the published image against your build: it must be identical AND both disks must have been opened through dm-verity against their root hash, and then a difference in RTMR2 that only the root hash explains is settled by the files.
--verity-of DIR prints "ROOTHASH BLOCKS SALT PARTUUID", the dm-verity parameters of the image whose boot log is in DIR (a release folder, or a folder made by ops/reference-run.sh). The log must replay to its quote, and the values are read only from the grub and kernel command events whose text hashes to its digest.
Ends with VERIFY-REFERENCE-OK or VERIFY-REFERENCE-FAILED (n) (exit code 1). The OK line ends with trees=n/a|not-needed|identical|not-compared and image-run=none|exact."""
import argparse, base64, hashlib, importlib.util, json, os, re, shutil, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__))
OFF = {"mrtd": (184, 232), "rtmr0": (376, 424), "rtmr1": (424, 472), "rtmr2": (472, 520), "rtmr3": (520, 568)}; TDATTR = (168, 176); REPORTDATA = (568, 632)
FILES = ("reference.json", "release.json", "publication.json", "quote-run1.bin", "quote-run2.bin", "announce-run1.txt", "rtmr3-events.tsv", "ccel.bin", "boot-tables.md", "settings.json", "SHA256SUMS")
fails = 0
def ok(m): print("  ok:   " + m)
def no(m):
    global fails; fails += 1; print("  FAIL: " + m)
def chk(cond, good, bad):
    (ok if cond else no)(good if cond else bad); return bool(cond)
sha = lambda b: hashlib.sha256(b).hexdigest()
def rd(p):
    with open(p, "rb") as f: return f.read()
def js(p):
    try: return json.load(open(p, encoding="utf-8"))
    except (OSError, ValueError) as e: no("%s cannot be read as JSON: %s" % (os.path.basename(p), str(e)[:70])); return None
def announce(path):
    d = {}
    for line in open(path, encoding="utf-8").read().splitlines():
        if "=" in line: k, v = line.split("=", 1); d[k] = v
    return d
def check_run(label, ann, extra_quote=None):
    """The announcement of a dummy run: keys, binding, RTMR3 replay, debug bit. Returns (registers, events) or None."""
    miss = [k for k in ("name", "sign", "wg", "log_sha512", "quote_b64", "log_b64") if k not in ann]
    if not chk(not miss, "%s: the announcement has all its fields" % label, "%s: the announcement lacks %s" % (label, ", ".join(miss))): return None
    q = base64.b64decode(ann["quote_b64"]); log = base64.b64decode(ann["log_b64"])
    if not chk(len(q) >= 632, "%s: the quote has %d bytes" % (label, len(q)), "%s: a quote of %d bytes is too short" % (label, len(q))): return None
    if extra_quote is not None: chk(extra_quote == q, "%s: the quote file is the quote of the announcement" % label, "%s: the quote file differs from the quote in the announcement" % label)
    binding = ("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (ann["name"], ann["sign"], ann["wg"], ann["log_sha512"])).encode()
    b1 = chk(q[REPORTDATA[0]:REPORTDATA[1]] == hashlib.sha512(binding).digest(), "%s: the REPORTDATA of the quote is the SHA-512 of the binding of the keys and the RTMR3 log" % label, "%s: the REPORTDATA of the quote is not the SHA-512 of its binding" % label)
    b2 = chk(ann["log_sha512"] == hashlib.sha512(log).hexdigest(), "%s: the RTMR3 log matches its hash in the binding" % label, "%s: the RTMR3 log does not match its hash in the binding" % label)
    reg = bytes(48); events = []; good = True
    for line in log.decode(errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) != 4: good = False; break
        name, digest, before, after = parts
        try:
            if bytes.fromhex(before) != reg: good = False; break
            reg = hashlib.sha384(reg + bytes.fromhex(digest)).digest()
        except ValueError: good = False; break
        if reg.hex() != after: good = False; break
        events.append((name, digest))
    regs = {k: q[a:b].hex() for k, (a, b) in OFF.items()}
    b3 = chk(good and regs["rtmr3"] == reg.hex(), "%s: the %d RTMR3 events replay to the RTMR3 of the quote" % (label, len(events)), "%s: the RTMR3 log does not replay to the RTMR3 of the quote" % label)
    b4 = chk(not (q[TDATTR[0]:TDATTR[1]][0] & 1), "%s: the TD debug bit is off" % label, "%s: the TD debug bit is ON: the host could read the memory and the keys" % label)
    return (regs, events) if (b1 and b2 and b3 and b4) else None
def quote_regs(q): return {k: q[a:b].hex() for k, (a, b) in OFF.items()}
def ccel_table(rundir, md_path):
    r = subprocess.run([sys.executable, os.path.join(HERE, "ccel-table.py"), rundir, "--markdown", md_path, "--full"], capture_output=True, text=True)
    return r.returncode, r.stdout
def ccel_module():
    spec = importlib.util.spec_from_file_location("ccel_table", os.path.join(HERE, "ccel-table.py")); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
def auth_events(cc, events):
    """The command events (grub_cmd and kernel_cmdline) whose displayed text hashes to the recorded digest, and those that do not. The replay of the log uses the digests only; without this check a forged text
    next to a genuine digest would be shown as if it had been measured. Only these two kinds of event measure their text; the others measure a file or a variable. A few canonical forms of the text are accepted."""
    good, bad = [], []
    for i, e in enumerate(events):
        if e["mr"] not in (1, 2, 3) or e["type"] != 0xD or e["digest"] is None: continue
        t = cc.text(e["data"])
        if not (t.startswith("grub_cmd:") or t.startswith("kernel_cmdline:")): continue
        raw = e["data"]; rest = raw.split(b": ", 1)[1] if b": " in raw else raw
        forms = {raw, raw.rstrip(b"\0"), rest, rest.rstrip(b"\0")}
        (good if any(hashlib.sha384(f).digest() == e["digest"] for f in forms) else bad).append((i, t))
    return good, bad
def verity_of(d):
    """The dm-verity parameters of an image, from the authenticated command events of its boot log. Returns the exit code; the line goes to the standard output."""
    ccel = os.path.join(d, "ccel.bin"); qn = [os.path.join(d, n) for n in ("quote.bin", "quote-run1.bin") if os.path.isfile(os.path.join(d, n))]
    if not os.path.isfile(ccel) or not qn: print("no boot event log (ccel.bin) with a quote in %s: the image does not publish one" % d, file=sys.stderr); return 1
    tmp = tempfile.mkdtemp(); shutil.copy(ccel, tmp + "/ccel.bin"); shutil.copy(qn[0], tmp + "/quote.bin")
    rc, out = ccel_table(tmp, os.path.join(tmp, "t.md"))
    if not (rc == 0 and "CCEL-TABLE-OK" in out and out.count("equal to the quote") == 3): print("the boot event log in %s does not replay to its quote" % d, file=sys.stderr); return 1
    try: cc = ccel_module(); good, bad = auth_events(cc, cc.parse(rd(ccel)))
    except (ValueError, OSError, KeyError) as e: print("the boot event log cannot be parsed: %s" % str(e)[:80], file=sys.stderr); return 1
    if bad or not good: print("the text of %d command event(s) does not hash to its digest, or there are none" % len(bad), file=sys.stderr); return 1
    vals = {}
    for k, rx in (("verity", r"[0-9a-f]{64}"), ("blocks", r"[0-9]{1,12}"), ("salt", r"[0-9a-f]{2,128}"), ("data", r"[0-9A-Fa-f-]{8,40}")):
        vals[k] = set(h for _, t in good for h in re.findall(r"(?<![\w.])tc\.%s=(%s)(?![\w-])" % (k, rx), t))
        if len(vals[k]) != 1: print("tc.%s= has %d different values in the authenticated command events (it must have exactly one): %s" % (k, len(vals[k]), ", ".join(sorted(x[:16] for x in vals[k])) or "none"), file=sys.stderr); return 1
    print("%s %s %s %s" % (next(iter(vals["verity"])), next(iter(vals["blocks"])), next(iter(vals["salt"])), next(iter(vals["data"])))); return 0
def rtmr2_rows(md):
    rows = []; on = False
    for line in md.splitlines():
        if line.startswith("## "): on = line.strip() == "## The RTMR2 events"; continue
        if on and line.startswith("| ") and not line.startswith("| #") and not line.startswith("|---"):
            c = line.rstrip().rstrip("|").strip().split(" | ")
            if len(c) >= 4: rows.append((c[0].lstrip("| ").strip(), c[1], " | ".join(c[2:-1]), c[-1].strip().strip("`")))
    return rows
VERITY = re.compile(r"tc\.verity=[0-9a-f]{64}"); UUID = re.compile(r"[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}")
norm = lambda t: UUID.sub("<UUID>", VERITY.sub("tc.verity=<ROOT>", t))
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--published"); ap.add_argument("--commit"); ap.add_argument("--own-run"); ap.add_argument("--image-run"); ap.add_argument("--tree-result"); ap.add_argument("--verity-of"); a = ap.parse_args()
    if a.verity_of: sys.exit(verity_of(a.verity_of))
    if not a.published or not a.commit: ap.error("--published and --commit are required")
    print("== A. the published evidence (no cloud is needed)")
    if not re.fullmatch(r"[0-9a-f]{9,40}", a.commit): print("VERIFY-REFERENCE-FAILED (1): the commit must be 9 to 40 lowercase hexadecimal digits"); sys.exit(1)
    P = a.published; missing = [f for f in FILES if not os.path.isfile(os.path.join(P, f))]
    if missing: print("  FAIL: the published files are missing: " + ", ".join(missing)); print("VERIFY-REFERENCE-FAILED (%d)" % (len(missing))); sys.exit(1)
    sums = {}
    for line in open(os.path.join(P, "SHA256SUMS"), encoding="utf-8").read().splitlines():
        m = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if m: sums[m.group(2)] = m.group(1)
    others = sorted(set(FILES) - {"SHA256SUMS"}); badsum = [f for f in others if sums.get(f) != sha(rd(os.path.join(P, f)))]
    chk(not badsum and set(sums) == set(others), "SHA256SUMS lists exactly the %d other files and every SHA-256 matches" % len(others), "SHA256SUMS does not match the files: %s" % (", ".join(badsum) or "the list of files differs: " + str(sorted(set(sums) ^ set(others)))[:120]))
    ref = js(os.path.join(P, "reference.json")); rel = js(os.path.join(P, "release.json")); pub = js(os.path.join(P, "publication.json")); st = js(os.path.join(P, "settings.json"))
    if not (ref and rel and pub and st): print("VERIFY-REFERENCE-FAILED (%d)" % max(fails, 1)); sys.exit(1)
    full = str(rel.get("commit", ""))
    chk(re.fullmatch(r"[0-9a-f]{40}", full) and full.startswith(a.commit), "the release is of commit %s, which you named" % full[:12], "the release is of commit %s, not of %s" % (full[:12], a.commit))
    chk(ref.get("commit") == full and pub.get("image_commit") == full, "reference.json, release.json and publication.json name the same full commit", "the three files do not name the same commit (%s, %s, %s)" % (str(ref.get("commit"))[:12], full[:12], str(pub.get("image_commit"))[:12]))
    chk(rel.get("reference_sha256") == sha(rd(os.path.join(P, "reference.json"))), "release.json records the SHA-256 of this reference.json", "the SHA-256 of reference.json is not the one that release.json records")
    want = hashlib.sha384(("commit %s\n" % full).encode()).hexdigest()
    chk((ref.get("stable_events") or {}).get("source") == want, "the `source` event is the SHA-384 of 'commit <id>': the image was built from this commit", "the `source` event is not the SHA-384 of 'commit %s'" % full[:12])
    labels = rel.get("image_labels") or {}
    chk(labels.get("commit") == full and labels.get("verity-a", "") + labels.get("verity-b", "") == rel.get("verity_root_hash"), "the image labels carry the commit and the two halves of the root hash", "the image labels do not match release.json")
    chk(st.get("image") == rel.get("image") == ref.get("image"), "the image is %s in the settings, the release and the reference" % rel.get("image"), "the image name differs between settings.json, release.json and reference.json")
    chk(all(st.get(k) == ref.get(k) for k in ("machine_type", "zone", "memory_mb", "boot_disk_gb", "scratch_disk_gb", "confidential_instance_type")), "the settings of the dummy run are the ones written in the reference (%s, %s, %s)" % (ref.get("machine_type"), ref.get("zone"), ref.get("confidential_instance_type")), "the settings of the dummy run differ from the reference")
    ann1 = announce(os.path.join(P, "announce-run1.txt")); q1 = rd(os.path.join(P, "quote-run1.bin")); q2 = rd(os.path.join(P, "quote-run2.bin"))
    r1 = check_run("run 1", ann1, q1)
    chk(len(q2) >= 632 and not (q2[TDATTR[0]:TDATTR[1]][0] & 1), "run 2: the quote has %d bytes and the TD debug bit is off" % len(q2), "run 2: the quote is too short or its TD debug bit is ON")
    regs2 = quote_regs(q2) if len(q2) >= 632 else {}
    for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2"):
        chk(r1 and r1[0][k] == ref.get(k) and regs2.get(k) == ref.get(k), "%s: both quotes and the reference agree (%s...)" % (k.upper(), str(ref.get(k))[:16]), "%s: the quotes and the reference do not agree" % k.upper())
    chk(r1 and regs2.get("rtmr3") == r1[0]["rtmr3"], "RTMR3 is the same in both quotes", "RTMR3 differs between the two quotes")
    chk(r1 and dict(r1[1]) == ref.get("stable_events") and [n for n, _ in r1[1]] == ref.get("events_in_order"), "the %d RTMR3 events of run 1 are exactly the stable events of the reference, in order" % (len(r1[1]) if r1 else 0), "the RTMR3 events of run 1 are not the stable events of the reference")
    chk(open(os.path.join(P, "rtmr3-events.tsv"), "rb").read() == base64.b64decode(ann1.get("log_b64", "")) , "rtmr3-events.tsv is the RTMR3 log of the announcement", "rtmr3-events.tsv is not the RTMR3 log of the announcement")
    tmp = tempfile.mkdtemp(); pubdir = os.path.join(tmp, "pub"); os.makedirs(pubdir); shutil.copy(os.path.join(P, "ccel.bin"), pubdir + "/ccel.bin"); shutil.copy(os.path.join(P, "quote-run1.bin"), pubdir + "/quote.bin")
    rc, out = ccel_table(pubdir, os.path.join(tmp, "pub.md"))
    chk(rc == 0 and "CCEL-TABLE-OK" in out and out.count("equal to the quote") == 3, "the boot event log replays to RTMR0, RTMR1 and RTMR2 of the quote", "the boot event log does not replay to the quote (%s)" % out.strip().splitlines()[-1][:100] if out.strip() else "the boot event log could not be read")
    try:
        cc = ccel_module(); evs = cc.parse(rd(os.path.join(P, "ccel.bin"))); good, bad = auth_events(cc, evs)
    except (ValueError, OSError, KeyError) as e: good, bad = [], [(-1, "the boot log cannot be parsed: %s" % str(e)[:60])]
    chk(good and not bad, "all %d command events (grub_cmd and kernel_cmdline) hash to their displayed text: the kernel command line shown is what was measured" % len(good), "the displayed text of %d command event(s) does not hash to its digest (first: event #%d): the text is not what was measured" % (len(bad), bad[0][0] if bad else -1) if bad else "the boot log holds no command events")
    roots = set(h for _, t in good for h in re.findall(r"tc\.verity=([0-9a-f]{64})", t)); nroot = sum(1 for _, t in good if "tc.verity=" in t)
    chk(roots == {rel.get("verity_root_hash")}, "the root hash of the release is the tc.verity= value in every authenticated command that carries one (%d)" % nroot, "the root hash of the release is not the tc.verity= value of the authenticated commands (%s)" % (", ".join(sorted(h[:12] for h in roots)) or "none found"))
    chk(os.path.isfile(os.path.join(tmp, "pub.md")) and rd(os.path.join(tmp, "pub.md")) == rd(os.path.join(P, "boot-tables.md")), "boot-tables.md is exactly what ops/ccel-table.py makes from the published log and quote", "boot-tables.md is not what ops/ccel-table.py makes from the published log and quote")
    explained = 0; rtmr2_equal = False; imgrun = "none"
    if a.image_run:
        print("== B1. the published image: your dummy run of IT against the published reference (it must be exactly equal)")
        I = a.image_run; before = fails
        for f in ("announce.txt", "quote.bin"):
            if not os.path.isfile(os.path.join(I, f)): print("  FAIL: the file is missing: %s/%s" % (I, f)); print("VERIFY-REFERENCE-FAILED (%d)" % (fails + 1)); sys.exit(1)
        r = check_run("image run", announce(os.path.join(I, "announce.txt")))
        if r:
            iregs, iev = r
            for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2"): chk(iregs[k] == ref[k], "%s of the published image equals the published value" % k.upper(), "%s of the published image differs from the published value (%s... and %s...)" % (k.upper(), iregs[k][:16], ref[k][:16]))
            chk([n for n, _ in iev] == ref.get("events_in_order") and dict(iev) == ref.get("stable_events"), "its %d RTMR3 events, the source event included, are exactly the published ones" % len(iev), "its RTMR3 events are not exactly the published ones")
            ij = os.path.join(I, "image.json")
            if os.path.isfile(ij):
                try: lab = json.load(open(ij)).get("labels") or {}
                except ValueError: lab = {}
                if "commit" in lab: chk(lab["commit"] == full, "the image labels name the commit %s" % full[:12], "the image labels name commit %s, not %s" % (str(lab["commit"])[:12], full[:12]))
                if "verity-a" in lab or "verity-b" in lab: chk(lab.get("verity-a", "") + lab.get("verity-b", "") == rel.get("verity_root_hash"), "the image labels carry the root hash of the release", "the image labels do not carry the root hash of the release")
        if fails == before: imgrun = "exact"; ok("the published image is the image of the release: your own dummy run of it reproduces the reference exactly")
    if a.own_run:
        print("== B. your own build: your dummy run against the published reference")
        O = a.own_run
        for f in ("announce.txt", "quote.bin"):
            if not os.path.isfile(os.path.join(O, f)): print("  FAIL: the file is missing: %s/%s" % (O, f)); print("VERIFY-REFERENCE-FAILED (%d)" % (fails + 1)); sys.exit(1)
        own = check_run("your run", announce(os.path.join(O, "announce.txt")))
        if own:
            ownregs, ownev = own
            for k in ("mrtd", "rtmr0", "rtmr1"): chk(ownregs[k] == ref[k], "%s equals the published value" % k.upper(), "%s differs from the published value (%s... and %s...)" % (k.upper(), ownregs[k][:16], ref[k][:16]))
            ev = dict(ownev); pe = ref.get("stable_events") or {}
            chk(ev.get("source") == pe.get("source"), "your `source` event equals the published one: your image was built from commit %s" % full[:12], "your `source` event differs: your image was not built from commit %s" % full[:12])
            chk([n for n, _ in ownev] == ref.get("events_in_order"), "your RTMR3 events are the same %d, in the same order" % len(ownev), "your RTMR3 events are not the stable events of the reference (%d and %d)" % (len(ownev), len(ref.get("events_in_order") or [])))
            bad = [n for n in pe if ev.get(n) != pe[n]]
            chk(not bad, "all %d RTMR3 event digests equal the published ones" % len(pe), "RTMR3 events with another digest: %s" % ", ".join(bad[:8]))
            if ownregs["rtmr2"] == ref["rtmr2"]: rtmr2_equal = True; ok("RTMR2 equals the published value: the boot loader, the kernel, its command line and the initrd are identical, so the root disk has the same root hash")
            else:
                owndir = os.path.join(O); mdown = os.path.join(tmp, "own.md")
                if not os.path.isfile(os.path.join(O, "ccel.bin")): no("RTMR2 differs and your run has no boot event log (ccel.bin), so the difference cannot be explained")
                else:
                    rc2, out2 = ccel_table(owndir, mdown)
                    if rc2 != 0: no("your boot event log does not replay to your quote (%s)" % (out2.strip().splitlines()[-1][:100] if out2.strip() else "no output"))
                    else:
                        a2 = rtmr2_rows(rd(mdown).decode()); b2 = rtmr2_rows(rd(os.path.join(tmp, "pub.md")).decode())
                        if len(a2) != len(b2): no("RTMR2 has %d events in your run and %d in the published log" % (len(a2), len(b2)))
                        else:
                            unexpl = []
                            for x, y in zip(a2, b2):
                                if x[3] == y[3]: continue
                                if x[1] == y[1] and norm(x[2]) == norm(y[2]): explained += 1; ok("RTMR2 event %s differs only in the root hash or a UUID (explained)" % x[0])
                                else: unexpl.append(x[0])
                            chk(not unexpl, "every difference in RTMR2 is explained: %d event(s) carry the root hash or a UUID, all other RTMR2 events are identical" % explained, "RTMR2 events that differ for another reason than the root hash or a UUID: %s" % ", ".join(unexpl[:8]))
                            if explained and not a.tree_result: print("  note: the two root disks have different root hashes; whether they hold the same files is the file-tree diff (step P4.2); it was NOT run here (give --published-image to run it)")
    trees = "n/a" if not a.own_run else ("not-needed" if rtmr2_equal else "not-compared")
    if a.tree_result:
        print("== C. the files of the published image against the files of your build")
        try: tl = [l for l in open(a.tree_result, encoding="utf-8", errors="replace").read().splitlines() if l.startswith("TREE-DIFF-")]
        except OSError: tl = []
        line = tl[-1] if tl else "(no TREE-DIFF verdict line)"
        good = line.startswith("TREE-DIFF-IDENTICAL") and "verity=checked" in line
        chk(good, "the two file trees are identical, and both disks were opened through dm-verity against their root hash: " + line[:110], ("the file trees are identical but at least one disk was NOT checked against its root hash: " if line.startswith("TREE-DIFF-IDENTICAL") else "the two file trees are NOT shown to be identical: ") + line[:150])
        trees = "identical" if good else "different"
    print()
    if fails == 0: print("VERIFY-REFERENCE-OK commit=%s image=%s own=%s explained=%d trees=%s image-run=%s" % (full, rel.get("image"), "yes" if a.own_run else "none", explained, trees, imgrun)); sys.exit(0)
    print("VERIFY-REFERENCE-FAILED (%d)" % fails); sys.exit(1)
main()
