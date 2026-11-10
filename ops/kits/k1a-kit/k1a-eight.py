#!/usr/bin/env python3
"""k1a-eight.py EVIDENCE_DIR [VERIFY_LOG]: the mentor's eight tamper cases (docs/milestone-plan.md, the end-to-end verifier run) as one table, read from the output that this run saved:
rehearsal-entry.txt and rehearsal-endorsement.txt in EVIDENCE_DIR (the rehearsals damage COPIES of the real export and of the endorsement) and the log of the verify stage (the refusal of a wrong pin). Read-only; exit 0, or 1 if a line says FAIL."""
import os, re, sys
E = sys.argv[1] if len(sys.argv) > 1 else "."; V = sys.argv[2] if len(sys.argv) > 2 else ""
def lines(p): return open(p, encoding="utf-8", errors="replace").read().split("\n") if p and os.path.exists(p) else []
entry, endo, ver = lines(os.path.join(E, "rehearsal-entry.txt")), lines(os.path.join(E, "rehearsal-endorsement.txt")), lines(V)
def find(src, pat):
    for l in src:
        if re.match(r"\s*(ok:|FAIL:)", l) and re.search(pat, l): return l.strip()
CASES = [
 (1, "an image of another commit", [(ver, r"pin for another commit.*refused"), (entry, r"a reference with another MRTD")]),
 (2, "one changed file in the image", "REFERENCE"),
 (3, "a debug TD", [(entry, r"the debug bit set in one quote A"), (entry, r"the debug bit set in quote C"), (entry, r"the debug bit set in every quote")]),
 (4, "an MRTD that is not in Google's endorsement", [(endo, r"the MRTD with one bit changed")]),
 (5, "one changed byte in a WARC", [(entry, r"a changed byte in a WARC")]),
 (6, "one deleted record file", [(entry, r"a record file deleted")]),
 (7, "a receipt removed from the signed receipts file", [(entry, r"a receipt removed from the signed receipts file")]),
 (8, "a fleet key without a matching quote", [(entry, r"fleet\.tsv replaced by one with the attacker's own valid signing keys"), (entry, r"a forged file, signed by an unknown key")]),
]
rej = ref = nf = bad = 0
print("the eight tamper cases of the mentor (each is refused by the verifier on a COPY of this run's evidence):")
for n, name, spec in CASES:
    if spec == "REFERENCE":
        print("%d. %-48s REFERENCE  shown by ops/image/test/tamper-test.sh on real disks (2 November 2026: 5 cases, 10 checks; docs/tree-comparison.md section 3); not repeated in a fleet run" % (n, name)); ref += 1; continue
    got = [find(src, pat) for src, pat in spec]; found = [g for g in got if g]
    if not found: print("%d. %-48s NOT FOUND  (the saved output has no such line)" % (n, name)); nf += 1; continue
    if any(g.startswith("FAIL") for g in found): print("%d. %-48s FAILED     %s" % (n, name, [g for g in found if g.startswith("FAIL")][0][:110])); bad += 1; continue
    print("%d. %-48s REFUSED    %d of %d evidence lines: %s" % (n, name, len(found), len(spec), found[0][:96])); rej += 1
print("EIGHT-CASES: %d refused in this run, %d by reference, %d not found, %d failed" % (rej, ref, nf, bad))
sys.exit(1 if bad else 0)
