#!/usr/bin/env python3
"""Tests docs_currency_check.py (C3, table rows): a tiny docs folder is built for every case, the checker is run on it, and the C3 findings are compared with what each case must give. The cases include the two rows of the milestone plan that the checker missed on 9 November 2026 (a long row that is led by "2. P5, ..." with the status cell "not started", and "3. Bug fixes"), and controls that must stay quiet.
   python3 test_docs_currency_check.py        -> DOCS-CURRENCY-CHECK-TEST-OK: N cases   (exit 0), or a line per wrong case and ...-FAILED (exit 1)"""
import os, re, subprocess, sys, tempfile
HERE = os.path.dirname(os.path.abspath(__file__)); CHECK = os.environ.get("DCC", os.path.join(HERE, "docs_currency_check.py"))
LONG = "for each exported WARC: its wrapper record is signed by a node key, and since then every record is now checked, as it was done on 4 November 2026 and is no longer open to doubt"
CASES = [("a long row led by 2. P5 whose status cell says not started", "| 2. P5, the verifier from the records to the quote | " + LONG + " | not started |", "P5\tdone\t2026-11-06\tx", True),
         ("a row led by 3. Bug fixes whose status cell says Not started", "| 3. Bug fixes | (a) the content limit, (b) the export folder, (c) the outcomes, since now | Not started |", "Bug fixes\tdone\t2026-11-07\tx", True),
         ("a row led by the bare id P4 with a cell that begins with Planned", "| P4 | the file-tree comparison | **Planned** for next week |", "P4\tdone\t2026-11-04\tx", True),
         ("the same long row, with the status cell done", "| 2. P5, the verifier from the records to the quote | " + LONG + " | **done on 6 November 2026** |", "P5\tdone\t2026-11-06\tx", False),
         ("a row of a step that is open (not started is true)", "| F5 | The cleanup | not started |", "F5\topen\t-\tx", False),
         ("a row of P5.1 must not be read as P5 (P5 done, P5.1 open)", "| P5.1 entry point | the command | not started |", "P5\tdone\t2026-11-06\tx", False)]
def run_case(row, state):
    with tempfile.TemporaryDirectory() as t:
        os.makedirs(t + "/docs"); os.makedirs(t + "/ops/perf")
        open(t + "/docs/milestone-plan.md", "w", encoding="utf-8").write("# Plan\n\n| Item | What | Status |\n|---|---|---|\n" + row + "\n"); open(t + "/ops/perf/step_status.tsv", "w", encoding="utf-8").write(state + "\n")
        r = subprocess.run([sys.executable, "-B", CHECK, "--root", t], capture_output=True, text=True); return [l for l in r.stdout.split("\n") if re.search(r"\bC3 [\w./-]+\.md:\d+:", l)]
def main():
    bad = 0
    for name, row, state, flagged in CASES:
        got = run_case(row, state); ok = bool(got) == flagged; bad += 0 if ok else 1
        print("%s %-74s -> %s" % ("ok:  " if ok else "FAIL:", name, "flagged" if got else "quiet") + ("" if ok else "   (expected %s)" % ("a C3 finding" if flagged else "no C3 finding")))
    print(("DOCS-CURRENCY-CHECK-TEST-OK: %d cases" % len(CASES)) if not bad else "DOCS-CURRENCY-CHECK-TEST-FAILED: %d case(s) went wrong" % bad); return 1 if bad else 0
if __name__ == "__main__": sys.exit(main())
