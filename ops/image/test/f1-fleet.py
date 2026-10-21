#!/usr/bin/env python3
"""Operator side of steps F1 and F4 (the modes: build, final, build-mismatch, final-mismatch, report, images).  f1-fleet.py build OUT VMM IPM VMW IPW   verify the two announcements and write OUT/fleet.tsv
                               f1-fleet.py final OUT VMM VMW        verify the two final quotes and that both logs hold the same fleet event"""
import base64, hashlib, sys

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

mode, out = sys.argv[1], sys.argv[2]
if mode == "build":
    vmm, ipm, vmw, ipw = sys.argv[3:7]
    rows = []
    for vm, ip, role, wgip in ((vmm, ipm, "master", "10.10.0.1"), (vmw, ipw, "worker", "10.10.0.2")):
        d = parse("%s/announce-%s.txt" % (out, vm))
        if d["name"] != vm: sys.exit("STOP: the announcement of %s names %s" % (vm, d["name"]))
        ev = verify(d); print("%s: the announcement is consistent (%d events in the log, quote binds name, both keys and the log)" % (vm, len(ev)))
        rows.append("\t".join([vm, role, wgip, "%s:51820" % ip, d["sign"], d["wg"]]))
    open(out + "/fleet.tsv", "w", encoding="utf-8").write("# tc-fleet v1\n" + "\n".join(rows) + "\n")
    print("ANNOUNCEMENTS-VERIFIED; fleet.tsv written (%d nodes, sha384 %s...)" % (len(rows), hashlib.sha384(open(out + "/fleet.tsv", "rb").read()).hexdigest()[:16]))
elif mode == "final":
    vmm, vmw = sys.argv[3:5]; want = hashlib.sha384(open(out + "/fleet.tsv", "rb").read()).hexdigest(); got = {}
    for vm in (vmm, vmw):
        d = parse("%s/final-%s.txt" % (out, vm)); ev = verify(d)
        fl = [dg for n, dg in ev if n == "fleet"]; fc = [n for n, _ in ev][-2:]
        if len(fl) != 1 or fl[0] != want: sys.exit("STOP: %s: the fleet event is %s, not the SHA-384 of fleet.tsv" % (vm, fl))
        if fc != ["fleet", "fleet-conf"]: sys.exit("STOP: %s: the log does not end with fleet and fleet-conf: %s" % (vm, fc))
        got[vm] = fl[0]; print("%s: the final quote is consistent; its log holds the fleet event %s..." % (vm, fl[0][:16]))
    assert len(set(got.values())) == 1
    print("FLEET-DIGEST-EQUAL: both nodes measured the same fleet list (SHA-384 %s...)" % want[:16])

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
    vmm, vmw, kind, img = sys.argv[3:7]; bad = []
    fleet_sha = hashlib.sha384(open(out + "/fleet.tsv", "rb").read()).hexdigest()
    for vm in (vmm, vmw):
        r = {}
        for line in open("%s/report-%s.txt" % (out, vm), encoding="utf-8").read().splitlines():
            if "=" in line: k, v = line.split("=", 1); r[k] = v
        def need(k, ok, why):
            if not ok(r.get(k, "")): bad.append("%s: %s is '%s' (%s)" % (vm, k, r.get(k, "(missing)"), why))
        need("hostname", lambda v: v == r.get("name") and v != "", "the host name must be the instance name (cloud-init is off, tc-fleet.sh sets it)"); need("mode", lambda v: v == kind, "expected " + kind); need("image", lambda v: v == img, "expected " + img)
        need("input_policy", lambda v: v == "policy drop", "the firewall must drop what it does not allow"); need("nft_rules_sha", lambda v: len(v) == 16 and v != hashlib.sha256(b"").hexdigest()[:16], "the firewall must be loaded")
        need("failed_units", lambda v: v == "", "no unit may have failed"); need("unit_tc-measure", lambda v: v == "active/success", "the measurement"); need("unit_tc-fleet", lambda v: v == "active/success", "the fleet unit")
        need("fleet_done", lambda v: v != "", "the fleet is joined"); need("fleet_event", lambda v: v == fleet_sha, "the fleet event must equal the SHA-384 of fleet.tsv"); need("wg_peers", lambda v: v == "1", "the mesh")
        if kind == "locked":
            need("openssh_server_installed", lambda v: v == "no", "no sshd"); need("guest_agent_installed", lambda v: v == "no", "no guest agent"); need("oslogin_installed", lambda v: v == "no", "no OS Login")
            need("port22_listening", lambda v: v == "0", "nothing listens on 22"); need("serial_getty", lambda v: v in ("masked", "masked-runtime"), "no login on the serial console")
        else:
            need("openssh_server_installed", lambda v: v == "yes", "the debug image keeps its login"); need("port22_listening", lambda v: v.isdigit() and int(v) >= 1, "sshd listens")
        roles = (("unit_tc-namenode", "unit_tc-resourcemanager") if vm == vmm else ("unit_tc-datanode", "unit_tc-nodemanager"))
        for u in roles: need(u, lambda v: v == "active/success", "a daemon of this role")
        if vm == vmm: need("crawl_marker", lambda v: v.startswith("crawl done"), "the crawl ran by itself and succeeded")
        print("%s: %d facts checked%s" % (vm, len(r), "; crawl: " + r.get("crawl_marker", "").strip() if vm == vmm else ""))
    if bad: sys.exit("STOP: the report differs from what a %s image must say:\n  " % kind + "\n  ".join(bad))
    print("REPORT-OK: both nodes say what a %s image must say" % kind)
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
    # the handoff: "produce the reference values from the final baked image so they can be locked in later". Usage: reference OUT VMM VMW IMAGE
    vmm, vmw, img = sys.argv[3:6]; got = {}
    for vm in (vmm, vmw):
        d = parse("%s/final-%s.txt" % (out, vm)); ev = verify(d); q = base64.b64decode(d["quote_b64"])
        got[vm] = {"mrtd": q[184:232].hex(), "rtmr0": q[376:424].hex(), "rtmr1": q[424:472].hex(), "rtmr2": q[472:520].hex(), "events": ev}
    a, b = got[vmm], got[vmw]
    for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2"):
        if a[k] != b[k]: sys.exit("STOP: the two nodes disagree on %s (%s... and %s...)" % (k, a[k][:16], b[k][:16]))
    PER_RUN = ("fleet", "fleet-conf"); sa = [(n, dg) for n, dg in a["events"] if n not in PER_RUN]; sb = [(n, dg) for n, dg in b["events"] if n not in PER_RUN]
    if sa != sb: sys.exit("STOP: the two nodes disagree on an event that does not depend on the run")
    import json
    ref = {"image": img, "note": "MRTD and RTMR0 to RTMR2 are measured by the platform; the events are what the image measures into RTMR3 at boot; fleet and fleet-conf depend on the run (the keys of the fleet), so RTMR3 itself differs per run and is rebuilt from the events", "mrtd": a["mrtd"], "rtmr0": a["rtmr0"], "rtmr1": a["rtmr1"], "rtmr2": a["rtmr2"], "events_in_order": [n for n, _ in a["events"]], "stable_events": dict(sa), "per_run_events": list(PER_RUN)}
    open(out + "/reference-values.json", "w", encoding="utf-8").write(json.dumps(ref, indent=2) + "\n")
    print(json.dumps(ref, indent=2)); print("REFERENCE-OK: both nodes agree on MRTD, RTMR0 to RTMR2 and %d stable events; written to %s/reference-values.json" % (len(sa), out))
else:
    sys.exit("unknown mode " + mode)
