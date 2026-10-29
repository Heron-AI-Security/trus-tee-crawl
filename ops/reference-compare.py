#!/usr/bin/env python3
"""Step P1: compare a dummy run (ops/reference-run.sh) with a reference.     python3 ops/reference-compare.py RUNDIR REFERENCE_JSON
It checks the run's own announcement (the quote's REPORTDATA binds the keys and the RTMR3 log; the log replays to the quote's RTMR3), then compares WHOLE register values with the reference: MRTD, RTMR0, RTMR1 and RTMR2, and every stable RTMR3 event
(the reference is reference-values*.json of a real fleet booted from the same image, or the published reference). It also requires the TD debug bit to be off (TDATTRIBUTES, quote bytes 168 to 176, bit 0). It prints the settings used, so that a difference caused by
another machine is easy to spot, and ends with REFERENCE-COMPARE-OK or REFERENCE-COMPARE-FAIL (exit code 1)."""
import base64, hashlib, json, os, sys
OFF = {"mrtd": (184, 232), "rtmr0": (376, 424), "rtmr1": (424, 472), "rtmr2": (472, 520), "rtmr3": (520, 568)}; TDATTR = (168, 176); REPORTDATA = (568, 632)
def stop(m): print("REFERENCE-COMPARE-FAIL: " + m); sys.exit(1)
def main(argv):
    if len(argv) != 2: sys.exit("usage: reference-compare.py RUNDIR REFERENCE_JSON")
    run, refp = argv
    for p in (run + "/announce.txt", refp):
        if not os.path.isfile(p): stop("the file is missing: " + p)
    d = {}
    for line in open(run + "/announce.txt", encoding="utf-8").read().splitlines():
        if "=" in line: k, v = line.split("=", 1); d[k] = v
    for k in ("name", "sign", "wg", "log_sha512", "quote_b64", "log_b64"):
        if k not in d: stop("the announcement lacks " + k)
    ref = json.load(open(refp, encoding="utf-8")); bad = []
    q = base64.b64decode(d["quote_b64"]); log = base64.b64decode(d["log_b64"])
    if len(q) < 632: stop("a quote of %d bytes is too short" % len(q))
    binding = ("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"])).encode()
    if q[REPORTDATA[0]:REPORTDATA[1]] != hashlib.sha512(binding).digest(): stop("the quote's REPORTDATA is not the SHA-512 of its binding")
    if d["log_sha512"] != hashlib.sha512(log).hexdigest(): stop("the RTMR3 log does not match its hash in the binding")
    reg = bytes(48); events = []
    for line in log.decode().splitlines():
        name, digest, before, after = line.split("\t")
        if bytes.fromhex(before) != reg: stop("event %s does not follow the previous one" % name)
        reg = hashlib.sha384(reg + bytes.fromhex(digest)).digest()
        if reg.hex() != after: stop("event %s: the recorded 'after' does not match the replay" % name)
        events.append((name, digest))
    regs = {k: q[a:b].hex() for k, (a, b) in OFF.items()}
    if regs["rtmr3"] != reg.hex(): bad.append("RTMR3 of the quote is not the replay of its own event log")
    st = {}
    sp = run + "/settings.json"
    if os.path.isfile(sp): st = json.load(open(sp))
    print("settings of the run: " + (", ".join("%s=%s" % (k, st.get(k)) for k in ("image", "machine_type", "memory_mb", "boot_disk_gb", "scratch_disk_gb", "zone", "confidential_instance_type")) if st else "settings.json is missing"))
    print("reference: image=%s machine_type=%s commit=%s" % (ref.get("image"), ref.get("machine_type"), str(ref.get("commit"))[:12]))
    if ref.get("image") and st.get("image") and ref["image"] != st["image"]: bad.append("the run is of image %s, the reference of %s" % (st["image"], ref["image"]))
    for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2"):
        same = regs[k] == str(ref.get(k, "")).lower(); print("  %-6s %s  %s" % (k.upper(), "equal" if same else "DIFFERENT", regs[k][:24] + "..." + ("" if same else "  reference " + str(ref.get(k))[:24] + "...")))
        if not same: bad.append("%s differs" % k.upper())
    stable = ref.get("stable_events") or {}; per = set(ref.get("per_run_events") or []); mine = dict(events)
    names = [n for n, _ in events]; want = [n for n in (ref.get("events_in_order") or list(stable)) if n not in per]
    if names != want: bad.append("the events of the run (%d) are not the stable events of the reference (%d) in the same order" % (len(names), len(want)))
    for n, dg in sorted(stable.items()):
        if n not in mine: bad.append("the stable event %s is missing" % n)
        elif mine[n] != dg: bad.append("the stable event %s has another digest" % n)
    extra = [n for n in mine if n not in stable]
    if extra: bad.append("events that the reference does not know: " + ", ".join(extra))
    print("  RTMR3: %d events, %d of %d stable events equal" % (len(events), sum(1 for n, dg in stable.items() if mine.get(n) == dg), len(stable)))
    if q[TDATTR[0]:TDATTR[1]][0] & 1: bad.append("the TD debug bit is ON (TDATTRIBUTES bit 0): the host could read the memory and the keys")
    else: print("  TDATTRIBUTES debug bit: off")
    if bad:
        for b in bad: print("  - " + b)
        stop("%d difference(s)" % len(bad))
    print("REFERENCE-COMPARE-OK: the dummy run equals the reference in MRTD, RTMR0 to RTMR2 and all %d stable events, and the debug bit is off" % len(stable))
main(sys.argv[1:])
