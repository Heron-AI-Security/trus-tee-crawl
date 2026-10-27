#!/usr/bin/env python3
"""Step R4.4: make the sealed initramfs REPRODUCIBLE, so that two builds of one commit give the same bytes.
   python3 tc-initrd-normalize.py IN OUT [--sde SECONDS]
mkinitramfs is reproducible by itself when SOURCE_DATE_EPOCH is set (it fixes the file times, uses cpio --reproducible and gzip -n). The experiment of step R4 compared the initramfs of two builds of one
commit and found exactly three differing entries, all written by HOOKS of other packages: .random-seed (the overlayroot hook copies up to 4 KB of /dev/random of the build machine into it) and
etc/mdadm/mdadm.conf and mdadm.conf.tmp (mdadm's mkconf writes the current time into a comment). This tool patches those entries IN PLACE and with the SAME LENGTH, so that no header and no offset changes:
the seed becomes zeros (it is a public, measured file and gives no secrecy; the keys of the scratch disk come from the kernel's own RNG in the initramfs), and the time in the mdadm comment becomes the
time of SOURCE_DATE_EPOCH. It then compresses with the same command as mkinitramfs (gzip -n). Before it writes anything it checks that the result has the same names and headers, that every body is
equal except the patched ones, and that a second run changes nothing. An entry that is not there is not an error (the hook may not exist); an mdadm comment of another length is.
Standard library only (and the gzip program). Exit code 0 only when everything held."""
import sys; sys.dont_write_bytecode = True
import argparse, gzip, hashlib, os, re, subprocess

STAMP = re.compile(rb"(# This configuration was auto-generated on )([A-Z][a-z]{2}, \d\d [A-Z][a-z]{2} \d{4} \d\d:\d\d:\d\d [+-]\d{4})( by mkconf)")
SEED = ".random-seed"
MDADM = re.compile(r"^etc/mdadm/mdadm\.conf(\.tmp)?$")
DAYS = ("Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"); MONTHS = ("Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec")

def rfc2822(sde):
    import time
    t = time.gmtime(sde)   # the names come from tables, not from the locale: the result must not depend on the machine
    return ("%s, %02d %s %04d %02d:%02d:%02d +0000" % (DAYS[t.tm_wday], t.tm_mday, MONTHS[t.tm_mon - 1], t.tm_year, t.tm_hour, t.tm_min, t.tm_sec)).encode()

def split(raw):
    off = 0
    if raw[:2] != b"\x1f\x8b":
        off = raw.find(b"\x1f\x8b\x08")
        if off <= 0: raise ValueError("no gzip stream in the file")
    return raw[:off], gzip.decompress(raw[off:])

def entries(dec):
    out = []; p = 0
    while True:
        if dec[p:p + 6] not in (b"070701", b"070702"): raise ValueError("not a cpio newc archive at byte %d" % p)
        f = [int(dec[p + 6 + 8 * i:p + 14 + 8 * i], 16) for i in range(13)]; size, nsize = f[6], f[11]
        name = dec[p + 110:p + 110 + nsize - 1].decode("utf-8", "replace"); q = (p + 110 + nsize + 3) & ~3
        out.append((name, p, q, size, tuple(f))); p = (q + size + 3) & ~3
        if name == "TRAILER!!!": return out

def patch(dec, sde):
    buf = bytearray(dec); notes = {"seed": 0, "stamps": 0}; fixed = rfc2822(sde)
    for name, p, q, size, f in entries(dec):
        if name == SEED and size:
            buf[q:q + size] = bytes(size); notes["seed"] += size
        elif MDADM.match(name) and size:
            body = bytes(buf[q:q + size]); m = STAMP.search(body)
            if m:
                if len(m.group(2)) != len(fixed): raise ValueError("the time in %s has another length than the fixed time" % name)
                new = body[:m.start(2)] + fixed + body[m.end(2):]; buf[q:q + size] = new; notes["stamps"] += 1
    return bytes(buf), notes

def gz(data):
    r = subprocess.run(["gzip", "-n", "-c"], input=data, capture_output=True)
    if r.returncode != 0: raise ValueError("gzip failed")
    return r.stdout

def problems(orig, new, sde):
    p = []; eo, en = entries(orig), entries(new)
    if [e[0] for e in eo] != [e[0] for e in en]: return ["the names or their order changed"]
    fixed = rfc2822(sde)
    for a, b in zip(eo, en):
        if a[4] != b[4]: p.append("%s: a header field changed" % a[0])
        ba, bb = orig[a[2]:a[2] + a[3]], new[b[2]:b[2] + b[3]]
        if a[0] == SEED: ok = bb == bytes(len(bb))
        elif MDADM.match(a[0]):
            m = STAMP.search(ba); ok = bb == (ba if not m else ba[:m.start(2)] + fixed + ba[m.end(2):])
        else: ok = ba == bb
        if not ok: p.append("%s: the content differs from what the rules allow" % a[0])
    if orig[:entries(orig)[0][1]] != new[:entries(new)[0][1]]: p.append("the start changed")
    return p

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("inp"); ap.add_argument("out"); ap.add_argument("--sde", type=int, default=1767225600)
    a = ap.parse_args()
    def stop(m): print("INITRD-NORMALIZE-FAILED: " + m); return 1
    if a.sde < 315532800: return stop("--sde must be a time since 1980 in seconds")
    try: raw = open(a.inp, "rb").read()
    except OSError as e: return stop("cannot read %s (%s)" % (a.inp, e))
    try:
        early, dec = split(raw); new, notes = patch(dec, a.sde)
        bad = problems(dec, new, a.sde)
        if bad: return stop("the patched archive is not what the rules allow: " + "; ".join(bad[:3]))
        again, _ = patch(new, a.sde)
        if again != new: return stop("a second run changes the result (not stable)")
        out = early + gz(new)
        e2, d2 = split(out)
        if d2 != new: return stop("the compressed result does not unpack to the patched archive")
    except (ValueError, OSError, EOFError, gzip.BadGzipFile) as e: return stop(str(e))
    tmp = a.out + ".part"
    with open(tmp, "wb") as f: f.write(out)
    os.replace(tmp, a.out)
    print("INITRD-NORMALIZED: %d entries; .random-seed zeroed (%d bytes); %d mdadm time stamp(s) set to the time of SOURCE_DATE_EPOCH; %d -> %d bytes; sha256 %s" % (len(entries(new)) - 1, notes["seed"], notes["stamps"], len(raw), len(out), hashlib.sha256(out).hexdigest()))
    return 0

if __name__ == "__main__": sys.exit(main())
