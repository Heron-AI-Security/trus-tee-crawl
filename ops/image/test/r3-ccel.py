#!/usr/bin/env python3
"""Read the TDX boot event log (the CC event log, /sys/firmware/acpi/tables/data/CCEL) and say which register each event went into and what the events say.
Decision 2 of the mentor's review needs to know whether the kernel command line (where dm-mod.create= would carry the dm-verity root hash) is measured, and into which register.
The log is the TCG crypto-agile format: a first event in the old format that names the digest algorithms (Spec ID Event03), then one event per entry: the register index
(for a CC log: 0 is MRTD and 1 to 4 are RTMR0 to RTMR3), the event type, the digests, and the event data.   Usage: r3-ccel.py [PATH]"""
import struct, sys
TYPES = {0x1: "EV_POST_CODE", 0x3: "EV_NO_ACTION", 0x4: "EV_SEPARATOR", 0x5: "EV_ACTION", 0x6: "EV_EVENT_TAG", 0x7: "EV_S_CRTM_CONTENTS", 0x8: "EV_S_CRTM_VERSION", 0xA: "EV_PLATFORM_CONFIG_FLAGS", 0xD: "EV_IPL",
         0x80000001: "EV_EFI_VARIABLE_DRIVER_CONFIG", 0x80000002: "EV_EFI_VARIABLE_BOOT", 0x80000003: "EV_EFI_BOOT_SERVICES_APPLICATION", 0x80000004: "EV_EFI_BOOT_SERVICES_DRIVER", 0x80000006: "EV_EFI_GPT_EVENT",
         0x80000007: "EV_EFI_ACTION", 0x80000008: "EV_EFI_PLATFORM_FIRMWARE_BLOB", 0x80000009: "EV_EFI_HANDOFF_TABLES", 0x800000E0: "EV_EFI_VARIABLE_AUTHORITY"}
KEYWORDS = ("cmdline", "initrd", "kernel", "grub", "shim", "vmlinuz", "root=", "dm-mod", "verity", "linux ")

def parse(b):
    """returns the list of (mr_index, type, text) of the events after the Spec ID event"""
    if len(b) < 32: raise ValueError("the log is too short")
    pcr, typ, dig, size = struct.unpack_from("<II20sI", b, 0); ev = b[32:32 + size]
    if not ev.startswith(b"Spec ID Event03"): raise ValueError("the first event is not a Spec ID Event03")
    n = struct.unpack_from("<I", ev, 16 + 8)[0]; sizes = {}; o = 16 + 8 + 4          # signature (16), platformClass (4), versions (4), then the number of algorithms
    for _ in range(n): alg, ds = struct.unpack_from("<HH", ev, o); sizes[alg] = ds; o += 4
    i = 32 + size; events = []
    while i + 12 <= len(b):
        pcr, typ, cnt = struct.unpack_from("<III", b, i)
        if pcr == 0xFFFFFFFF or cnt > 8: break
        i += 12
        for _ in range(cnt):
            alg = struct.unpack_from("<H", b, i)[0]
            if alg not in sizes: raise ValueError("an event uses an unknown digest algorithm %#x" % alg)
            i += 2 + sizes[alg]
        esz = struct.unpack_from("<I", b, i)[0]; i += 4; data = b[i:i + esz]; i += esz
        data = data.rstrip(b"\x00")   # grub writes its commands as text with a trailing NUL
        txt = data.decode("ascii", "replace") if data and all(32 <= c < 127 or c in (9, 10) for c in data[:200]) else (data.decode("utf-16-le", "replace") if len(data) > 2 and data[1:2] == b"\0" else "")
        events.append((pcr, typ, txt.strip()))
    return events

def main(path):
    ev = parse(open(path, "rb").read()); per = {}
    for mr, t, _ in ev: per[mr] = per.get(mr, 0) + 1
    print("events in the log: %d" % len(ev))
    for mr in sorted(per): print("  MR index %d (%s): %d events" % (mr, "MRTD" if mr == 0 else "RTMR%d" % (mr - 1), per[mr]))
    print("every grub command and every file that grub or the firmware measured about the kernel, its command line or an initrd (RTMR2 holds the grub events):")
    hits = 0
    for mr, t, txt in ev:
        if any(k in txt.lower() for k in KEYWORDS):
            hits += 1; print("  MR index %d (RTMR%d)  %s  %s" % (mr, mr - 1, TYPES.get(t, hex(t)), txt[:240].replace("\n", " ")))
    if not hits: print("  (none: the log holds no event that names the kernel or its command line)")
    print("CCEL-PARSED")

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "/sys/firmware/acpi/tables/data/CCEL")
