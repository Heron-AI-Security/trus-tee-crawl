#!/usr/bin/env python3
"""Compare the RTMR3 event logs of two boots of the same image (step F0.1/F0.2).
  f01-compare.py LOG_A LOG_B same             every event, every digest and the final RTMR3 must be equal (the measurement is reproducible)
  f01-compare.py LOG_A LOG_B changed NAME     exactly the event NAME may differ, and the final RTMR3 must differ (the measurement notices a change)
Prints F01-COMPARE-OK or F01-COMPARE-FAILED."""
import sys
def load(p):
    ev = []
    for line in open(p):
        f = line.rstrip("\n").split("\t")
        if len(f) != 4: sys.exit("F01-COMPARE-FAILED: %s: a line without 4 fields: %r" % (p, line[:60]))
        ev.append(f)
    return ev
if len(sys.argv) < 4 or sys.argv[3] not in ("same", "changed") or (sys.argv[3] == "changed" and len(sys.argv) != 5):
    sys.exit(__doc__)
a, b, mode = load(sys.argv[1]), load(sys.argv[2]), sys.argv[3]; name = sys.argv[4] if mode == "changed" else None
bad = []
if [e[0] for e in a] != [e[0] for e in b]: bad.append("the two logs have different events: %s against %s" % ([e[0] for e in a], [e[0] for e in b]))
else:
    diff = [x[0] for x, y in zip(a, b) if x[1] != y[1]]
    last_a, last_b = (a[-1][3] if a else ""), (b[-1][3] if b else "")
    print("events:", ", ".join(e[0] for e in a)); print("digests that differ:", diff or "none")
    print("final RTMR3: %s... and %s..." % (last_a[:12], last_b[:12]), "(equal)" if last_a == last_b else "(different)")
    if mode == "same":
        if diff: bad.append("digests differ for %s" % diff)
        if last_a != last_b: bad.append("the final RTMR3 differs although every digest is equal")
    else:
        if diff != [name]: bad.append("expected exactly %s to differ, but %s differ" % (name, diff or "nothing"))
        if last_a == last_b: bad.append("the final RTMR3 did not change")
if bad:
    print("F01-COMPARE-FAILED: " + "; ".join(bad)); sys.exit(1)
print("F01-COMPARE-OK (%s)" % ("reproducible" if mode == "same" else "the change of %s is seen and nothing else changed" % name))
