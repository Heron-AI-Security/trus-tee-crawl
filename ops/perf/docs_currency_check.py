#!/usr/bin/env python3
"""docs_currency_check.py [--root DIR] [--since REV] [--state FILE] [--strict]: are the documents up to date with the repository?
Read-only; stdlib only; run it in the root of the repository (docs/ and ops/ below it). Checks:
  C1 commits    every non-merge commit after --since (default: the newest commit that touched docs/ is NOT used: give --since) whose subject does not start with docs, chore(docs) or TEST ONLY is named (9 or 7 characters of its id) somewhere in docs/
  C2 registers  ADR sections equal the ADR index and are continuous; the rows of the limitations, the mistake log and the rules are continuous; the counts that session-start.md states equal the real last numbers
  C3 claims     lines that call a FINISHED step planned, not started, not run yet, open or next (the steps come from --state, default ops/perf/step_status.tsv); a heuristic, so these are REVIEW items for a human, not failures
  C4 perf       every folder of docs/perf holds README.md and the four result files named after the folder (NAME_analysis.md, NAME_summary.json, NAME_network_phases.txt, NAME_task_times.txt), and docs/perf/README.md names the folder
  C5 paths      every ops/kits/NAME and ops/perf/NAME named in the docs exists
  C6 state      every step or run of the state table is named in at least one document
Exit code 0 when C1, C2, C4 and C5 pass (C3 only lists); 1 otherwise; --strict makes C3 findings fail too. One line per finding, then a summary line that starts DOCS-CURRENT-OK or DOCS-STALE."""
import glob, os, re, subprocess, sys
def arg(n, d=None): a = sys.argv; return a[a.index(n) + 1] if n in a and a.index(n) + 1 < len(a) else d
def rd(p): return open(p, encoding="utf-8", errors="replace").read()
MARK = re.compile(r"\*\*(?:Status check|Status on|Status note added on|Update),? (\d{1,2}) (January|February|March|April|May|June|July|August|September|October|November|December) (\d{4})")
MONTHS = {m: i for i, m in enumerate("January February March April May June July August September October November December".split(), 1)}
def stamp(m): return (int(m.group(3)), MONTHS[m.group(2)], int(m.group(1)))
def is_history(line, filetext):
    """a paragraph that starts with a dated status marker is history when the same file has a marker with a LATER date"""
    m = MARK.match(line.lstrip())
    return bool(m) and any(stamp(x) > stamp(m) for x in MARK.finditer(filetext))
def main():
    root = os.path.abspath(arg("--root", ".")); docs = os.path.join(root, "docs"); since = arg("--since"); strict = "--strict" in sys.argv; state_path = arg("--state", os.path.join(root, "ops", "perf", "step_status.tsv"))
    if not os.path.isdir(docs): print("DOCS-STALE: no docs folder under %s" % root); return 1
    files = sorted(glob.glob(os.path.join(docs, "*.md")) + glob.glob(os.path.join(docs, "perf", "*.md")) + glob.glob(os.path.join(docs, "perf", "*", "*.md"))); text = {f: rd(f) for f in files}; alltext = "\n".join(text.values()); bad = []; review = []; info = []
    rel = lambda f: os.path.relpath(f, docs).replace(os.sep, "/")
    # ---------------- C1 commits
    if since:
        try:
            out = subprocess.run(["git", "-C", root, "log", "--no-merges", "--format=%h\t%s", since + "..HEAD"], capture_output=True, text=True, check=True).stdout.strip().split("\n")
            n = 0
            for l in [x for x in out if x]:
                h, subj = l.split("\t", 1)
                if re.match(r"(docs|chore\(docs\)|TEST ONLY)", subj): continue
                n += 1
                if h[:9] not in alltext and h[:7] not in alltext: bad.append("C1 commit %s (%s) is not named in any document" % (h[:9], subj[:60]))
            info.append("C1 checked %d commit(s) after %s" % (n, since))
        except Exception as e: bad.append("C1 cannot read the git history: %s" % str(e)[:80])
    else: info.append("C1 skipped (give --since REV: the commit after which everything must be in the documents)")
    # ---------------- C2 registers
    def nums(path, pat, flags=re.M):
        return sorted(int(m.group(1)) for m in re.finditer(pat, rd(path), flags)) if os.path.exists(path) else []
    def contiguous(name, xs, start=1):
        if not xs: bad.append("C2 %s: no entries found" % name); return None
        missing = [i for i in range(start, max(xs) + 1) if i not in set(xs)]
        if missing: bad.append("C2 %s is not continuous: missing %s" % (name, missing[:6]))
        return max(xs)
    D = os.path.join(docs, "decisions.md"); sec = nums(D, r"^## ADR-(\d+):"); idx = nums(D, r"^\| (\d{3}) \|")
    last_adr = contiguous("ADR sections", sec)
    if sec and idx and sec != idx: bad.append("C2 the ADR index and the ADR sections differ: only in index %s, only in sections %s" % (sorted(set(idx) - set(sec))[:5], sorted(set(sec) - set(idx))[:5]))
    last_row = contiguous("limitations rows", nums(os.path.join(docs, "limitations-and-trust.md"), r"^\| (\d+) \|")); P = os.path.join(docs, "guide-pitfalls-and-lessons.md")
    last_mis = contiguous("mistake log", nums(P, r"^\| (\d+) \| ")); last_rule = contiguous("rules", nums(P, r"^(\d+)\. \*\*"))
    S = os.path.join(docs, "session-start.md")
    if os.path.exists(S):
        st = rd(S); m = re.search(r"ADR-001 to ADR-(\d+); limitations rows 1 to (\d+); mistakes 1 to (\d+); rules 1 to (\d+)", st)
        if not m: bad.append("C2 session-start.md does not state the counts in the form 'ADR-001 to ADR-N; limitations rows 1 to N; mistakes 1 to N; rules 1 to N'")
        else:
            for nm, said, real in (("ADR", int(m.group(1)), last_adr), ("limitations rows", int(m.group(2)), last_row), ("mistakes", int(m.group(3)), last_mis), ("rules", int(m.group(4)), last_rule)):
                if real is not None and said != real: bad.append("C2 session-start.md says %s up to %d but the real last number is %d" % (nm, said, real))
    # ---------------- C3 claims about finished steps
    steps = {}
    if os.path.exists(state_path):
        for l in rd(state_path).split("\n"):
            if l.strip() and not l.startswith("#"):
                p = l.split("\t")
                if len(p) >= 2: steps[p[0].strip()] = p[1].strip()
    stale = re.compile(r"(not started|not run yet|has not run|has \*\*not run|not yet|planned|Planned|is next|are next|open|waits behind|postponed|pending)")
    ok_marker = re.compile(r"(was not|were not|had not|on that day|\(Update|history|no longer|since|is done|are done|done on|was done|were done|now |ran on|was dropped|dropped)")
    for step, status in steps.items():
        if status not in ("done", "dropped"): continue
        pat = re.compile(r"(?<![\w.])" + re.escape(step) + r"(?![\w.])")
        for f in files:
            for n, l in enumerate(text[f].split("\n"), 1):
                cells = [c.strip() for c in l.split("|")] if l.lstrip().startswith("|") else None
                if is_history(l, text[f]): continue
                if cells and len(cells) > 3 and pat.fullmatch(cells[1].strip("*` ")):   # a table row that is led by the step id: read the whole row
                    if stale.search(" ".join(cells[2:])) and not ok_marker.search(l): review.append("C3 %s:%d: %s is %s, but its table row says: ...%s" % (rel(f), n, step, status, " | ".join(cells[2:])[:110]))
                    continue
                for clause in l.split(";"):   # other lines: one clause at a time
                    mm = pat.search(clause)
                    if mm and stale.search(clause[mm.end():mm.end() + 70]) and not ok_marker.search(clause):
                        review.append("C3 %s:%d: %s is %s, but the line says: ...%s" % (rel(f), n, step, status, clause.strip()[max(0, mm.start() - 20):mm.end() + 70])); break
    info.append("C3 steps in the state table: %d (%d finished)" % (len(steps), sum(1 for v in steps.values() if v in ("done", "dropped"))))
    # ---------------- C4 perf folders
    pdir = os.path.join(docs, "perf"); preadme = rd(os.path.join(pdir, "README.md")) if os.path.exists(os.path.join(pdir, "README.md")) else ""; nrun = 0
    if os.path.isdir(pdir):
        for d in sorted(x for x in os.listdir(pdir) if os.path.isdir(os.path.join(pdir, x))):
            nrun += 1; need = ["README.md", d + "_analysis.md", d + "_summary.json", d + "_network_phases.txt", d + "_task_times.txt"]
            miss = [x for x in need if not os.path.exists(os.path.join(pdir, d, x))]
            if miss: bad.append("C4 docs/perf/%s lacks %s" % (d, ", ".join(miss)))
            if d not in preadme: bad.append("C4 docs/perf/README.md does not name the run folder %s" % d)
            if not re.match(r"^[A-Za-z][A-Za-z0-9_]*$", d): bad.append("C4 the folder name %s is not an identifier (letters, digits and underscores, starting with a letter)" % d)
    info.append("C4 run folders in docs/perf: %d" % nrun)
    # ---------------- C5 paths named in the docs
    seen = set()
    for m in re.finditer(r"ops/(?:kits|perf)/[A-Za-z0-9_.\-]+", alltext):
        pth = m.group(0).rstrip(".")
        if pth in seen: continue
        seen.add(pth)
        if os.path.isdir(os.path.join(root, "ops")) and not os.path.exists(os.path.join(root, pth)): bad.append("C5 the documents name %s, which does not exist" % pth)
    info.append("C5 paths checked: %d" % len(seen))
    # ---------------- C6 every step or run of the state table is named in the documents
    for step, status in steps.items():
        if not re.search(re.escape(step), alltext, re.I): bad.append("C6 the state table has %s (%s), but no document names it" % (step, status))
    for l in info: print("info   " + l)
    for l in bad: print("STALE  " + l)
    for l in review: print("REVIEW " + l)
    fail = bool(bad) or (strict and bool(review))
    print("%s: %d problem(s), %d line(s) to review (%d documents read)" % ("DOCS-STALE" if fail else "DOCS-CURRENT-OK", len(bad), len(review), len(files)))
    return 1 if fail else 0
if __name__ == "__main__": sys.exit(main())
