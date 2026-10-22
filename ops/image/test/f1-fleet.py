#!/usr/bin/env python3
"""Operator side of steps F1, F4, R1 and R2 (the modes: build, final, build-mismatch, final-mismatch, report, images, reference, enforce). Any number of nodes: one master and one or more workers.
  f1-fleet.py build OUT REFERENCE|- master:NAME:IP worker:NAME:IP [worker:NAME:IP ...]   verify the announcements and write OUT/fleet.tsv (the old form  build OUT VMM IPM VMW IPW [REFERENCE]  is the same for two nodes)
  f1-fleet.py final OUT NAME [NAME ...]               verify the final quote of EVERY node of fleet.tsv and that all the logs hold the same fleet event
  f1-fleet.py report OUT KIND IMG NAME [NAME ...]     what every VM says about itself (the old form  report OUT VMM VMW KIND IMG  is the same for two nodes)
  build-mismatch, final-mismatch and images are demonstrations with a master and one worker"""
import base64, hashlib, json, os, sys

def parse(path):
    d = {}
    for line in open(path, encoding="utf-8").read().splitlines():
        if "=" in line:
            k, v = line.split("=", 1); d[k] = v
    for k in ("name", "sign", "wg", "log_sha512", "quote_b64", "log_b64"):
        if k not in d: sys.exit("STOP: %s lacks %s" % (path, k))
    return d

def verify(d):
    q = base64.b64decode(d["quote_b64"]); log = base64.b64decode(d["log_b64"])
    binding = ("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"])).encode()
    if len(q) < 632: sys.exit("STOP: %s: a quote of %d bytes is too short" % (d["name"], len(q)))
    if q[568:632] != hashlib.sha512(binding).digest(): sys.exit("STOP: %s: the quote's REPORTDATA is not the SHA-512 of its binding" % d["name"])
    if d["log_sha512"] != hashlib.sha512(log).hexdigest(): sys.exit("STOP: %s: the log does not match its hash in the binding" % d["name"])
    reg = bytes(48); events = []
    for line in log.decode().splitlines():
        name, digest, before, after = line.split("\t")
        if bytes.fromhex(before) != reg: sys.exit("STOP: %s: event %s does not follow the previous one" % (d["name"], name))
        reg = hashlib.sha384(reg + bytes.fromhex(digest)).digest()
        if reg.hex() != after: sys.exit("STOP: %s: event %s: the recorded 'after' does not match the replay" % (d["name"], name))
        events.append((name, digest))
    if q[520:568] != reg: sys.exit("STOP: %s: the RTMR3 in the quote is not the replay of the log" % d["name"])
    return events

RULES = """The rules of decision 1 of the mentor's review of 22 October 2026 (enforce the reference values for every fleet node):
 E1  every row of fleet.tsv has a quote A (announce-<node>.txt) and a quote B (final-<node>.txt); a row without both is refused
 E2  each file names the node of its row, and its signing key and its WireGuard key are the keys of that row
 E3  the quote binds name, both public keys and the log (REPORTDATA), the log's chain is consistent and replays to the RTMR3 of the quote
 E4  MRTD and RTMR0 to RTMR2 of the quote equal the reference values EXACTLY
 E5  the log of quote A has exactly the stable events of the reference, in order, and each digest equals the reference digest
 E6  the log of quote B has the same stable events, then fleet, then fleet-conf, and nothing else
 E7  the event fleet of quote B is the SHA-384 of fleet.tsv, the same for every node
 E0  (the verifier's, not this tool's) the Intel signature chain of every quote verifies"""

def load_reference(path):
    ref = json.load(open(path, encoding="utf-8"))
    for k in ("image", "machine_type", "mrtd", "rtmr0", "rtmr1", "rtmr2", "events_in_order", "stable_events", "per_run_events"):
        if k not in ref: sys.exit("STOP: the reference values lack %s" % k)
    return ref

def check_node(out, name, row, ref, stage, fleet_sha):
    """The rules E1 to E7 for one quote ('A' = announcement, 'B' = final); returns the list of problems (empty = the quote is accepted)."""
    fn = "%s/%s-%s.txt" % (out, "announce" if stage == "A" else "final", name)
    if not os.path.exists(fn): return ["E1 %s: there is no quote %s (%s)" % (name, stage, os.path.basename(fn))]
    try:
        d = parse(fn)
    except SystemExit as e:
        return ["E1 %s: %s" % (name, e)]
    bad = []
    if d["name"] != name: bad.append("E2 %s: the file names %s" % (name, d["name"]))
    if row and (d["sign"] != row[4] or d["wg"] != row[5]): bad.append("E2 %s: quote %s carries keys that are not the keys of its row in fleet.tsv" % (name, stage))
    try:
        ev = verify(d)
    except SystemExit as e:
        return bad + ["E3 %s: %s" % (name, e)]
    q = base64.b64decode(d["quote_b64"])
    for k, a, b in (("mrtd", 184, 232), ("rtmr0", 376, 424), ("rtmr1", 424, 472), ("rtmr2", 472, 520)):
        if q[a:b].hex() != ref[k]: bad.append("E4 %s: quote %s has %s %s... and the reference has %s..." % (name, stage, k.upper(), q[a:b].hex()[:16], ref[k][:16]))
    stable = [n for n in ref["events_in_order"] if n not in ref["per_run_events"]]
    names = [n for n, _ in ev]; want = stable if stage == "A" else stable + list(ref["per_run_events"])
    if names != want: bad.append("E%s %s: the events of quote %s are %s and must be exactly %s" % ("5" if stage == "A" else "6", name, stage, names, want))
    else:
        for n, dg in ev:
            if n in ref["stable_events"] and dg != ref["stable_events"][n]: bad.append("E%s %s: the event %s has digest %s... and the reference has %s..." % ("5" if stage == "A" else "6", name, n, dg[:16], ref["stable_events"][n][:16]))
        if stage == "B" and fleet_sha and dict(ev).get("fleet") != fleet_sha: bad.append("E7 %s: its event fleet is not the SHA-384 of fleet.tsv" % name)
    return bad

mode, out = sys.argv[1], sys.argv[2]
if mode == "build":
    if len(sys.argv) > 4 and sys.argv[4].split(":")[0] in ("master", "worker"):
        ref = load_reference(sys.argv[3]) if sys.argv[3] != "-" else None
        spec = [a.split(":", 2) for a in sys.argv[4:]]
        if any(len(x) != 3 or x[0] not in ("master", "worker") or not x[1] or not x[2] for x in spec): sys.exit("STOP: every node is given as master:NAME:IP or worker:NAME:IP")
    else:   # the old form, two nodes
        vmm, ipm, vmw, ipw = sys.argv[3:7]
        ref = load_reference(sys.argv[7]) if len(sys.argv) > 7 else None
        spec = [["master", vmm, ipm], ["worker", vmw, ipw]]
    if [x[0] for x in spec].count("master") != 1 or spec[0][0] != "master": sys.exit("STOP: a fleet has exactly one master, and it is the first node")
    if len(spec) < 2: sys.exit("STOP: a fleet has the master and at least one worker")
    if len({x[1] for x in spec}) != len(spec): sys.exit("STOP: two nodes have the same name")
    rows = []
    for k, (role, vm, ip) in enumerate(spec):
        wgip = "10.10.0.%d" % (k + 1)
        if ref:
            probs = check_node(out, vm, None, ref, "A", None)
            if probs: sys.exit("STOP: %s is refused, it does not match the reference values of %s on %s:\n  %s" % (vm, ref["image"], ref["machine_type"], "\n  ".join(probs)))
        d = parse("%s/announce-%s.txt" % (out, vm))
        if d["name"] != vm: sys.exit("STOP: the announcement of %s names %s" % (vm, d["name"]))
        ev = verify(d); print("%s: the announcement is consistent (%d events in the log, quote binds name, both keys and the log)" % (vm, len(ev)))
        rows.append("\t".join([vm, role, wgip, "%s:51820" % ip, d["sign"], d["wg"]]))
    open(out + "/fleet.tsv", "w", encoding="utf-8").write("# tc-fleet v1\n" + "\n".join(rows) + "\n")
    print("ANNOUNCEMENTS-VERIFIED; fleet.tsv written (%d nodes, sha384 %s...)" % (len(rows), hashlib.sha384(open(out + "/fleet.tsv", "rb").read()).hexdigest()[:16]))
elif mode == "final":
    names = sys.argv[3:]; want = hashlib.sha384(open(out + "/fleet.tsv", "rb").read()).hexdigest(); got = {}
    listed = [l.split("\t")[0] for l in open(out + "/fleet.tsv", encoding="utf-8").read().splitlines() if l and not l.startswith("#") and "\t" in l]
    if listed and sorted(listed) != sorted(names): sys.exit("STOP: fleet.tsv lists %s, and the final quotes given are those of %s: every node of the fleet must be checked" % (", ".join(listed), ", ".join(names)))
    for vm in names:
        d = parse("%s/final-%s.txt" % (out, vm)); ev = verify(d)
        fl = [dg for n, dg in ev if n == "fleet"]; fc = [n for n, _ in ev][-2:]
        if len(fl) != 1 or fl[0] != want: sys.exit("STOP: %s: the fleet event is %s, not the SHA-384 of fleet.tsv" % (vm, fl))
        if fc != ["fleet", "fleet-conf"]: sys.exit("STOP: %s: the log does not end with fleet and fleet-conf: %s" % (vm, fc))
        got[vm] = fl[0]; print("%s: the final quote is consistent; its log holds the fleet event %s..." % (vm, fl[0][:16]))
    assert len(set(got.values())) == 1
    print("FLEET-DIGEST-EQUAL: all %d nodes measured the same fleet list (SHA-384 %s...)" % (len(names), want[:16]))

elif mode == "build-mismatch":
    # F4: two nodes that are given DIFFERENT fleet lists (each list holds the node's own keys, so each node joins); the worker's list has one more row, a node that does not exist
    import os, subprocess
    vmm, ipm, vmw, ipw = sys.argv[3:7]
    rows = []
    for vm, ip, role, wgip in ((vmm, ipm, "master", "10.10.0.1"), (vmw, ipw, "worker", "10.10.0.2")):
        d = parse("%s/announce-%s.txt" % (out, vm)); verify(d)
        rows.append("\t".join([vm, role, wgip, "%s:51820" % ip, d["sign"], d["wg"]]))
    priv = subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey", "-noout"], capture_output=True, check=True).stdout
    pub = subprocess.run(["openssl", "ec", "-pubout", "-outform", "DER"], input=priv, capture_output=True, check=True).stdout
    ghost = "\t".join(["ghost", "worker", "10.10.0.3", "10.128.0.250:51820", base64.b64encode(pub).decode(), base64.b64encode(os.urandom(32)).decode()])
    open(out + "/fleet.tsv", "w", encoding="utf-8").write("# tc-fleet v1\n" + "\n".join(rows) + "\n")
    open(out + "/fleet-w.tsv", "w", encoding="utf-8").write("# tc-fleet v1\n" + "\n".join(rows + [ghost]) + "\n")
    print("MISMATCH-LISTS-WRITTEN: the master's list has 2 nodes (sha384 %s...), the worker's has 3 (sha384 %s...)" % (hashlib.sha384(open(out + "/fleet.tsv", "rb").read()).hexdigest()[:16], hashlib.sha384(open(out + "/fleet-w.tsv", "rb").read()).hexdigest()[:16]))
elif mode == "final-mismatch":
    vmm, vmw = sys.argv[3:5]; seen = {}
    for vm, lst in ((vmm, "fleet.tsv"), (vmw, "fleet-w.tsv")):
        d = parse("%s/final-%s.txt" % (out, vm)); ev = verify(d)
        fl = [dg for n, dg in ev if n == "fleet"]
        want = hashlib.sha384(open("%s/%s" % (out, lst), "rb").read()).hexdigest()
        if fl != [want]: sys.exit("STOP: %s: its fleet event %s is not the SHA-384 of the list that it was given (%s)" % (vm, fl, lst))
        seen[vm] = (fl[0], base64.b64decode(d["quote_b64"])[520:568].hex())
        print("%s: the final quote is consistent; its fleet event is %s... and its RTMR3 %s..." % (vm, fl[0][:16], seen[vm][1][:16]))
    if seen[vmm][0] == seen[vmw][0] or seen[vmm][1] == seen[vmw][1]: sys.exit("STOP: the two nodes show the same fleet event or the same RTMR3: the mismatch was not visible")
    print("FLEET-LISTS-DIFFER: the RTMR3 logs of the two nodes show a mismatch (fleet events %s... and %s..., final RTMR3 %s... and %s...)" % (seen[vmm][0][:16], seen[vmw][0][:16], seen[vmm][1][:16], seen[vmw][1][:16]))
elif mode == "report":
    # F0.4 and F0.5: what the VM says about itself (guest attribute tc/report), checked against what each kind of image must say
    if sys.argv[3] in ("locked", "debug"):
        kind, img, names = sys.argv[3], sys.argv[4], sys.argv[5:]
    else:   # the old form, two nodes
        vmm, vmw, kind, img = sys.argv[3:7]; names = [vmm, vmw]
    bad = []
    fleet_sha = hashlib.sha384(open(out + "/fleet.tsv", "rb").read()).hexdigest()
    role_of = {n: ("master" if i == 0 else "worker") for i, n in enumerate(names)}
    for l in open(out + "/fleet.tsv", encoding="utf-8").read().splitlines():
        c = l.split("\t")
        if len(c) > 2 and not l.startswith("#") and c[0] in role_of: role_of[c[0]] = c[1]
    for vm in names:
        r = {}
        for line in open("%s/report-%s.txt" % (out, vm), encoding="utf-8").read().splitlines():
            if "=" in line: k, v = line.split("=", 1); r[k] = v
        def need(k, ok, why):
            if not ok(r.get(k, "")): bad.append("%s: %s is '%s' (%s)" % (vm, k, r.get(k, "(missing)"), why))
        need("hostname", lambda v: v == r.get("name") and v != "", "the host name must be the instance name (cloud-init is off, tc-fleet.sh sets it)"); need("mode", lambda v: v == kind, "expected " + kind); need("image", lambda v: v == img, "expected " + img)
        need("input_policy", lambda v: v == "policy drop", "the firewall must drop what it does not allow"); need("nft_rules_sha", lambda v: len(v) == 16 and v != hashlib.sha256(b"").hexdigest()[:16], "the firewall must be loaded")
        need("failed_units", lambda v: v == "", "no unit may have failed"); need("unit_tc-measure", lambda v: v == "active/success", "the measurement"); need("unit_tc-fleet", lambda v: v == "active/success", "the fleet unit")
        need("fleet_done", lambda v: v != "", "the fleet is joined"); need("fleet_event", lambda v: v == fleet_sha, "the fleet event must equal the SHA-384 of fleet.tsv"); need("wg_peers", lambda v: v == str(len(names) - 1), "the mesh: every other node of the fleet is a peer")
        if kind == "locked":
            need("openssh_server_installed", lambda v: v == "no", "no sshd"); need("guest_agent_installed", lambda v: v == "no", "no guest agent"); need("oslogin_installed", lambda v: v == "no", "no OS Login")
            need("port22_listening", lambda v: v == "0", "nothing listens on 22"); need("serial_getty", lambda v: v in ("masked", "masked-runtime"), "no login on the serial console")
        else:
            need("openssh_server_installed", lambda v: v == "yes", "the debug image keeps its login"); need("port22_listening", lambda v: v.isdigit() and int(v) >= 1, "sshd listens")
        roles = (("unit_tc-namenode", "unit_tc-resourcemanager") if role_of[vm] == "master" else ("unit_tc-datanode", "unit_tc-nodemanager"))
        for u in roles: need(u, lambda v: v == "active/success", "a daemon of this role")
        if role_of[vm] == "master": need("crawl_marker", lambda v: v.startswith("crawl done"), "the crawl ran by itself and succeeded")
        print("%s: %d facts checked%s" % (vm, len(r), "; crawl: " + r.get("crawl_marker", "").strip() if role_of[vm] == "master" else ""))
    if bad: sys.exit("STOP: the report differs from what a %s image must say:\n  " % kind + "\n  ".join(bad))
    print("REPORT-OK: all %d nodes say what a %s image must say" % (len(names), kind))
elif mode == "images":
    # F0.6: two images, two measurements. Usage: images OUT_A OUT_B VM [EVENT that must differ ...]
    out_b, vm = sys.argv[3:5]; must = sys.argv[5:]
    def logs(o):
        d = parse("%s/final-%s.txt" % (o, vm)); ev = verify(d); return dict(ev), base64.b64decode(d["quote_b64"])[520:568].hex()
    ea, ra = logs(out); eb, rb = logs(out_b)
    differ = sorted(n for n in ea if n in eb and ea[n] != eb[n])
    print("events that differ between the two images: %s" % (", ".join(differ) or "none")); print("final RTMR3: %s... against %s..." % (ra[:16], rb[:16]))
    if ra == rb: sys.exit("STOP: the two final RTMR3 are equal: the images are not told apart by their measurements")
    miss = [e for e in must if e not in differ]
    if miss: sys.exit("STOP: these events must differ between the two images and do not: %s" % ", ".join(miss))
    print("IMAGES-DIFFER: the two images have different measurements (%s)" % ", ".join(must or differ))
elif mode == "reference":
    # "produce the reference values from the final baked image". Usage: reference OUT IMAGE MACHINE_TYPE NODE [NODE ...]   (any number of nodes; the values belong to the image and the machine type)
    img, mtype, nodes = sys.argv[3], sys.argv[4], sys.argv[5:]
    if len(nodes) < 1: sys.exit("STOP: name at least one node")
    got = {}
    for vm in nodes:
        d = parse("%s/final-%s.txt" % (out, vm)); ev = verify(d); q = base64.b64decode(d["quote_b64"])
        got[vm] = {"mrtd": q[184:232].hex(), "rtmr0": q[376:424].hex(), "rtmr1": q[424:472].hex(), "rtmr2": q[472:520].hex(), "events": ev}
    first = got[nodes[0]]
    for vm in nodes[1:]:
        for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2"):
            if got[vm][k] != first[k]: sys.exit("STOP: %s and %s disagree on %s (%s... and %s...)" % (nodes[0], vm, k, first[k][:16], got[vm][k][:16]))
    PER_RUN = ("fleet", "fleet-conf"); sa = [(n, dg) for n, dg in first["events"] if n not in PER_RUN]
    for vm in nodes[1:]:
        if [(n, dg) for n, dg in got[vm]["events"] if n not in PER_RUN] != sa: sys.exit("STOP: %s and %s disagree on an event that does not depend on the run" % (nodes[0], vm))
    ref = {"image": img, "machine_type": mtype, "note": "MRTD and RTMR0 to RTMR2 are measured by the platform and belong to the image and the machine type; the events are what the image measures into RTMR3 at boot; fleet and fleet-conf depend on the run (the keys of the fleet), so RTMR3 itself differs per run and is rebuilt from the events", "mrtd": first["mrtd"], "rtmr0": first["rtmr0"], "rtmr1": first["rtmr1"], "rtmr2": first["rtmr2"], "events_in_order": [n for n, _ in first["events"]], "stable_events": dict(sa), "per_run_events": list(PER_RUN)}
    open(out + "/reference-values.json", "w", encoding="utf-8").write(json.dumps(ref, indent=2) + "\n")
    print(json.dumps(ref, indent=2)); print("REFERENCE-OK: all %d nodes agree on MRTD, RTMR0 to RTMR2 and %d stable events; written to %s/reference-values.json" % (len(nodes), len(sa), out))
elif mode == "enforce":
    # Decision 1: every row of fleet.tsv needs a quote A and a quote B that match the reference values exactly. Usage: enforce OUT REFERENCE.json
    if not os.path.exists(out + "/fleet.tsv"): sys.exit("STOP: there is no fleet.tsv in %s (it must be the folder of a run)" % out)
    if not os.path.exists(sys.argv[3]): sys.exit("STOP: there is no reference values file %s" % sys.argv[3])
    ref = load_reference(sys.argv[3]); fl = open(out + "/fleet.tsv", "rb").read(); fleet_sha = hashlib.sha384(fl).hexdigest()
    rows = [l.split("\t") for l in fl.decode().splitlines() if l.strip() and not l.startswith("#")]
    if not rows: sys.exit("STOP: fleet.tsv has no rows")
    for r in rows:
        if len(r) != 6: sys.exit("STOP: a row of fleet.tsv does not have 6 columns: %s" % r[:1])
    bad = []
    for r in rows:
        pa = check_node(out, r[0], r, ref, "A", None); pb = check_node(out, r[0], r, ref, "B", fleet_sha); bad += pa + pb
        print("%s: quote A %s, quote B %s" % (r[0], "accepted" if not pa else "REFUSED", "accepted" if not pb else "REFUSED"))
    if bad: sys.exit("ENFORCE-FAILED (%d problems): the fleet is not accepted\n  %s\n%s" % (len(bad), "\n  ".join(bad), RULES))
    print("ENFORCE-OK: all %d nodes of fleet.tsv have a quote A and a quote B that match the reference values of %s on %s exactly (rules E1 to E7; E0, the Intel chain, is the verifier's)" % (len(rows), ref["image"], ref["machine_type"]))
else:
    sys.exit("unknown mode " + mode)
