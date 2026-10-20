#!/usr/bin/env python3
"""Operator side of step F1.  f1-fleet.py build OUT VMM IPM VMW IPW   verify the two announcements and write OUT/fleet.tsv
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
else:
    vmm, vmw = sys.argv[3:5]; want = hashlib.sha384(open(out + "/fleet.tsv", "rb").read()).hexdigest(); got = {}
    for vm in (vmm, vmw):
        d = parse("%s/final-%s.txt" % (out, vm)); ev = verify(d)
        fl = [dg for n, dg in ev if n == "fleet"]; fc = [n for n, _ in ev][-2:]
        if len(fl) != 1 or fl[0] != want: sys.exit("STOP: %s: the fleet event is %s, not the SHA-384 of fleet.tsv" % (vm, fl))
        if fc != ["fleet", "fleet-conf"]: sys.exit("STOP: %s: the log does not end with fleet and fleet-conf: %s" % (vm, fc))
        got[vm] = fl[0]; print("%s: the final quote is consistent; its log holds the fleet event %s..." % (vm, fl[0][:16]))
    assert len(set(got.values())) == 1
    print("FLEET-DIGEST-EQUAL: both nodes measured the same fleet list (SHA-384 %s...)" % want[:16])
