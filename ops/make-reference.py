#!/usr/bin/env python3
"""Step P3.2: make the reference values from TWO dummy runs of the same image (no fleet is involved).
    python3 ops/make-reference.py --run RUN1 --run RUN2 --commit COMMIT40 --image IMAGE --out reference.json
Each RUN is a folder made by ops/reference-run.sh. For each run it checks the announcement (the REPORTDATA of the quote binds the keys and the RTMR3 log, the log replays
to the RTMR3 of the quote) and that the TD debug bit is off. The two runs must agree on MRTD, RTMR0 to RTMR2, every RTMR3 event and the settings (machine type, disks, zone,
image): a difference means that the dummy run is not reproducible, and no reference is made. The `source` event must be the SHA-384 of "commit <COMMIT40>" followed by a
newline (the image was built from this commit). reference.json has the format that ops/reference-compare.py and ops/make-release.py read. It ends with REFERENCE-MADE or
REFERENCE-FAILED (exit code 1)."""
import argparse, base64, hashlib, json, os, re, sys, time
OFF = {"mrtd": (184, 232), "rtmr0": (376, 424), "rtmr1": (424, 472), "rtmr2": (472, 520), "rtmr3": (520, 568)}; TDATTR = (168, 176); REPORTDATA = (568, 632)
KEYS = ("image", "image_id", "machine_type", "memory_mb", "boot_disk_gb", "scratch_disk_gb", "zone", "confidential_instance_type")
def stop(m): print("REFERENCE-FAILED: " + m); sys.exit(1)
def load(run, n):
    for f in ("announce.txt", "settings.json"):
        if not os.path.isfile(os.path.join(run, f)): stop("run %d: the file is missing: %s/%s" % (n, run, f))
    d = {}
    for line in open(os.path.join(run, "announce.txt"), encoding="utf-8").read().splitlines():
        if "=" in line: k, v = line.split("=", 1); d[k] = v
    for k in ("name", "sign", "wg", "log_sha512", "quote_b64", "log_b64"):
        if k not in d: stop("run %d: the announcement lacks %s" % (n, k))
    q = base64.b64decode(d["quote_b64"]); log = base64.b64decode(d["log_b64"])
    if len(q) < 632: stop("run %d: a quote of %d bytes is too short" % (n, len(q)))
    binding = ("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"])).encode()
    if q[REPORTDATA[0]:REPORTDATA[1]] != hashlib.sha512(binding).digest(): stop("run %d: the REPORTDATA of the quote is not the SHA-512 of its binding" % n)
    if d["log_sha512"] != hashlib.sha512(log).hexdigest(): stop("run %d: the RTMR3 log does not match its hash in the binding" % n)
    reg = bytes(48); events = []
    for line in log.decode().splitlines():
        parts = line.split("\t")
        if len(parts) != 4: stop("run %d: a line of the RTMR3 log has %d fields, not 4" % (n, len(parts)))
        name, digest, before, after = parts
        if bytes.fromhex(before) != reg: stop("run %d: the event %s does not follow the previous one" % (n, name))
        reg = hashlib.sha384(reg + bytes.fromhex(digest)).digest()
        if reg.hex() != after: stop("run %d: the event %s: the recorded 'after' does not match the replay" % (n, name))
        events.append((name, digest))
    regs = {k: q[a:b].hex() for k, (a, b) in OFF.items()}
    if regs["rtmr3"] != reg.hex(): stop("run %d: the RTMR3 of the quote is not the replay of its own event log" % n)
    if q[TDATTR[0]:TDATTR[1]][0] & 1: stop("run %d: the TD debug bit is ON (TDATTRIBUTES bit 0): the host could read the memory and the keys" % n)
    try: st = json.load(open(os.path.join(run, "settings.json"), encoding="utf-8"))
    except ValueError: stop("run %d: settings.json is not JSON" % n)
    return {"regs": regs, "events": events, "st": st, "quote_sha256": hashlib.sha256(q).hexdigest()}
def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--run", action="append", required=True); ap.add_argument("--commit", required=True); ap.add_argument("--image", required=True); ap.add_argument("--out", required=True); a = ap.parse_args()
    if len(a.run) != 2: stop("exactly two --run folders are needed, got %d" % len(a.run))
    if not re.fullmatch(r"[0-9a-f]{40}", a.commit): stop("--commit must be a full commit id (40 lowercase hexadecimal digits)")
    r1, r2 = load(a.run[0], 1), load(a.run[1], 2)
    for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2"):
        if r1["regs"][k] != r2["regs"][k]: stop("the two runs differ in %s (%s... and %s...): the dummy run is not reproducible" % (k.upper(), r1["regs"][k][:16], r2["regs"][k][:16]))
    n1, n2 = [n for n, _ in r1["events"]], [n for n, _ in r2["events"]]
    if n1 != n2: stop("the two runs have different RTMR3 events (%d and %d): %s" % (len(n1), len(n2), sorted(set(n1) ^ set(n2))[:6]))
    for (n, d1), (_, d2) in zip(r1["events"], r2["events"]):
        if d1 != d2: stop("the two runs differ in the RTMR3 event %s (%s... and %s...): it is not stable" % (n, d1[:16], d2[:16]))
    for k in KEYS:
        if r1["st"].get(k) != r2["st"].get(k): stop("the two runs differ in the setting %s (%r and %r)" % (k, r1["st"].get(k), r2["st"].get(k)))
    if r1["st"].get("image") != a.image: stop("the runs are of image %s, not of %s" % (r1["st"].get("image"), a.image))
    ev = dict(r1["events"])
    want = hashlib.sha384(("commit %s\n" % a.commit).encode()).hexdigest()
    if ev.get("source") != want: stop("the `source` event is not the SHA-384 of 'commit %s': the image was not built from this commit" % a.commit[:12])
    ref = {"schema": 1, "kind": "dummy-run-reference", "commit": a.commit, "image": a.image, "image_id": r1["st"].get("image_id"), "machine_type": r1["st"].get("machine_type"), "memory_mb": r1["st"].get("memory_mb"),
           "boot_disk_gb": r1["st"].get("boot_disk_gb"), "scratch_disk_gb": r1["st"].get("scratch_disk_gb"), "zone": r1["st"].get("zone"), "confidential_instance_type": r1["st"].get("confidential_instance_type"),
           "mrtd": r1["regs"]["mrtd"], "rtmr0": r1["regs"]["rtmr0"], "rtmr1": r1["regs"]["rtmr1"], "rtmr2": r1["regs"]["rtmr2"], "stable_events": ev, "per_run_events": [], "events_in_order": n1, "tdattributes_debug_bit": "off",
           "runs": [{"quote_sha256": r["quote_sha256"], "vm": r["st"].get("vm"), "run_utc": r["st"].get("run_utc")} for r in (r1, r2)], "made_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    open(a.out, "w", encoding="utf-8").write(json.dumps(ref, indent=2) + "\n")
    print("REFERENCE-MADE commit=%s image=%s registers=4 events=%d out=%s" % (a.commit[:12], a.image, len(n1), a.out))
main()
