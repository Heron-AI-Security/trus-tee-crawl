#!/usr/bin/env python3
"""Step P6: the boot events of a dummy run.    python3 ops/ccel-table.py RUNDIR [--markdown FILE]
RUNDIR is the output of ops/reference-run.sh: ccel.bin (the firmware boot event log, read from /sys/firmware/acpi/tables/data/CCEL by the node and published as guest attributes) and quote.bin.
The log is the TCG crypto-agile format: a first event in the old format that names the digest algorithms (Spec ID Event03), then one event per entry (register index, type, digests, data). For a CC log the register index 0 is MRTD and 1 to 4 are RTMR0 to RTMR3.
The tool replays the events of RTMR0 to RTMR2 (SHA-384, EV_NO_ACTION is logged but not extended) and requires the result to equal the quote's registers, then prints a table of every RTMR1 and RTMR2 event: its place in the register, its type, what it measures, and its digest.
It also names the register of the kernel, its command line and the initrd, and the dm-verity root hash that the kernel command line carries (tc.verity=).  The raw log is kept in the evidence, so a change of this parser can be tested again without a VM."""
import hashlib, os, re, struct, sys
TYPES = {0x1: "EV_POST_CODE", 0x3: "EV_NO_ACTION", 0x4: "EV_SEPARATOR", 0x5: "EV_ACTION", 0x6: "EV_EVENT_TAG", 0x7: "EV_S_CRTM_CONTENTS", 0x8: "EV_S_CRTM_VERSION", 0xA: "EV_PLATFORM_CONFIG_FLAGS", 0xD: "EV_IPL",
         0x80000001: "EV_EFI_VARIABLE_DRIVER_CONFIG", 0x80000002: "EV_EFI_VARIABLE_BOOT", 0x80000003: "EV_EFI_BOOT_SERVICES_APPLICATION", 0x80000004: "EV_EFI_BOOT_SERVICES_DRIVER", 0x80000006: "EV_EFI_GPT_EVENT",
         0x80000007: "EV_EFI_ACTION", 0x80000008: "EV_EFI_PLATFORM_FIRMWARE_BLOB", 0x80000009: "EV_EFI_HANDOFF_TABLES", 0x800000E0: "EV_EFI_VARIABLE_AUTHORITY"}
REG = {0: "MRTD", 1: "RTMR0", 2: "RTMR1", 3: "RTMR2", 4: "RTMR3"}; QOFF = {1: (376, 424), 2: (424, 472), 3: (472, 520)}; SHA384 = 0x000C
KEYWORDS = ("vmlinuz", "kernel", "linux", "initrd", "initramfs", "cmdline", "grub_cmd", "shim", "grub")
def parse(b):
    """the events after the Spec ID event: a list of dicts (mr, type, digest, data)"""
    if len(b) < 32: raise ValueError("the log is too short")
    pcr, typ, dig, size = struct.unpack_from("<II20sI", b, 0); ev = b[32:32 + size]
    if not ev.startswith(b"Spec ID Event03"): raise ValueError("the first event is not a Spec ID Event03")
    n = struct.unpack_from("<I", ev, 24)[0]; sizes = {}; o = 28
    for _ in range(n): alg, ds = struct.unpack_from("<HH", ev, o); sizes[alg] = ds; o += 4
    i = 32 + size; events = []
    while i + 12 <= len(b):
        pcr, typ, cnt = struct.unpack_from("<III", b, i)
        if pcr == 0xFFFFFFFF or cnt > 8: break
        i += 12; digest = None
        for _ in range(cnt):
            alg = struct.unpack_from("<H", b, i)[0]
            if alg not in sizes: raise ValueError("an event uses an unknown digest algorithm %#x" % alg)
            if alg == SHA384: digest = b[i + 2:i + 2 + sizes[alg]]
            i += 2 + sizes[alg]
        esz = struct.unpack_from("<I", b, i)[0]; i += 4; data = b[i:i + esz]; i += esz
        events.append({"mr": pcr, "type": typ, "digest": digest, "data": data})
    return events
def text(data):
    d = data.rstrip(b"\x00")
    if d and all(32 <= c < 127 or c in (9, 10) for c in d[:200]): return d.decode("ascii", "replace").strip()
    if len(d) > 2 and d[1:2] == b"\0":
        t = d.decode("utf-16-le", "replace").strip("\x00")
        if t and all(32 <= ord(c) < 127 for c in t[:100]): return t.strip()
    return "(binary, %d bytes: %s...)" % (len(data), data[:8].hex())
def replay(events):
    regs = {}
    for e in events:
        if e["type"] == 0x3 or e["digest"] is None: continue
        regs[e["mr"]] = hashlib.sha384(regs.get(e["mr"], bytes(48)) + e["digest"]).digest()
    return regs
def verity_hashes(events):
    """the dm-verity root hashes that RTMR2 events (the kernel command line) carry: a list of (position, hash)"""
    out = []
    for k, e in enumerate(x for x in events if x["mr"] == 3):
        for h in re.findall(r"tc\.verity=([0-9a-f]{64})", text(e["data"])): out.append((k + 1, h))
    return out
def load(run):
    for f in ("ccel.bin", "quote.bin"):
        if not os.path.isfile(os.path.join(run, f)): raise FileNotFoundError("%s is missing in %s (this image may not publish its boot event log)" % (f, run))
    return parse(open(os.path.join(run, "ccel.bin"), "rb").read()), open(os.path.join(run, "quote.bin"), "rb").read()
def esc(s, n=110): s = s.replace("|", "\\|").replace("\n", " "); return s if len(s) <= n else s[:n - 3] + "..."
def build(events, quote):
    lines = []; res = {}; ok = True
    per = {}
    for e in events: per[e["mr"]] = per.get(e["mr"], 0) + 1
    lines.append("events in the log: %d (%s)" % (len(events), ", ".join("%s %d" % (REG.get(m, "index %d" % m), per[m]) for m in sorted(per))))
    regs = replay(events)
    for m in (1, 2, 3):
        a, b = QOFF[m]; want = quote[a:b]; got = regs.get(m, bytes(48)); same = got == want; ok &= same
        lines.append("replay of %s: %s" % (REG[m], "equal to the quote" if same else "DIFFERENT (replay %s..., quote %s...)" % (got.hex()[:16], want.hex()[:16])))
    md = []
    for m in (2, 3):
        md.append("## The %s events\n" % REG[m]); md.append("| # | Event type | What it measures | Digest (SHA-384) |\n|---|---|---|---|")
        k = 0
        for e in events:
            if e["mr"] != m: continue
            k += 1; md.append("| %d | %s | %s | `%s` |" % (k, TYPES.get(e["type"], hex(e["type"])) + (" (not extended)" if e["type"] == 0x3 else ""), esc(text(e["data"])), (e["digest"] or b"").hex()[:32] + "..."))
        md.append("")
    kern = []
    for e in events:
        t = text(e["data"]).lower()
        if e["mr"] in (2, 3) and any(w in t for w in KEYWORDS): kern.append("%s: %s: %s" % (REG[e["mr"]], TYPES.get(e["type"], hex(e["type"])), esc(text(e["data"]), 120)))
    lines.append("events that name the kernel, its command line, the initrd, grub or the shim (%d):" % len(kern)); lines += ["  " + x for x in kern[:14]]
    vh = verity_hashes(events)
    lines.append("dm-verity root hash in the RTMR2 events: " + (", ".join("event %d: %s" % (k, h) for k, h in vh) if vh else "none (no event carries tc.verity=)"))
    return ok, lines, md, kern, vh
def main(argv):
    if not argv or argv[0].startswith("--"): sys.exit("usage: ccel-table.py RUNDIR [--markdown FILE]")
    run = argv[0]; mdf = argv[argv.index("--markdown") + 1] if "--markdown" in argv else None
    try: events, quote = load(run)
    except (FileNotFoundError, ValueError, struct.error) as e: print("CCEL-TABLE-FAILED: %s" % e); sys.exit(1)
    ok, lines, md, kern, vh = build(events, quote)
    print("\n".join(lines))
    if mdf: open(mdf, "w", encoding="utf-8").write("\n".join(md) + "\n"); print("the tables were written to " + mdf)
    print("CCEL-TABLE-OK" if ok else "CCEL-TABLE-FAILED: the replay of the boot log does not equal the quote"); sys.exit(0 if ok else 1)
if __name__ == "__main__": main(sys.argv[1:])
