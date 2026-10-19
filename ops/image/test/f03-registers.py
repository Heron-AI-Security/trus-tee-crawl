#!/usr/bin/env python3
"""Print the five measurement registers of a TDX quote (version 4), or compare the registers of several VMs.

  f03-registers.py QUOTE LABEL           one line:  LABEL MRTD <hex> RTMR0 <hex> RTMR1 <hex> RTMR2 <hex> RTMR3 <hex>   (the full 96 hex digits of each)
  f03-registers.py --compare FILE        read such lines (one per VM) and say, for each register, EQUAL or DIFFERENT across them

The offsets are the ones that rtmr3_replay.py already proved on real quotes (RTMR3 at bytes 520 to 568, REPORTDATA right after it):
a TDX quote has a 48-byte header, and its report body holds, from byte 184 on, MRTD, then (after three fields that we do not use) RTMR0 to RTMR3 at 376, 424, 472 and 520, 48 bytes each.
"""
import sys

OFF = {"MRTD": 184, "RTMR0": 376, "RTMR1": 424, "RTMR2": 472, "RTMR3": 520}


def registers(path):
    q = open(path, "rb").read()
    if len(q) < 632:
        sys.exit("not a TDX quote: %d bytes, at least 632 are needed" % len(q))
    return {k: q[o:o + 48].hex() for k, o in OFF.items()}


def compare(path):
    rows = []
    for line in open(path, encoding="utf-8"):
        f = line.split()
        if not f:
            continue
        if len(f) != 11:
            sys.exit("a line is not 'LABEL MRTD x RTMR0 x RTMR1 x RTMR2 x RTMR3 x': %r" % line)
        rows.append((f[0], {f[i]: f[i + 1] for i in range(1, 11, 2)}))
    if len(rows) < 2:
        sys.exit("need the registers of at least two VMs, have %d" % len(rows))
    print("compared: " + ", ".join(r[0] for r in rows))
    for k in OFF:
        vals = {r[1].get(k) for r in rows}
        print("  %-5s %s  %s" % (k, "EQUAL    " if len(vals) == 1 else "DIFFERENT", " ".join(r[1][k][:12] for r in rows)))


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--compare":
        compare(sys.argv[2])
    elif len(sys.argv) == 3:
        r = registers(sys.argv[1])
        print(sys.argv[2], *("%s %s" % (k, r[k]) for k in OFF))
    else:
        sys.exit(__doc__)
