#!/usr/bin/env python3
"""Audit EVERY markdown file of docs/ for the mechanical kinds of staleness and inconsistency (it cannot judge meaning; the status sweep and a reading of each file do that).

Checks, over all docs/*.md:
  links      every relative link points to a file that exists, and its #anchor is a heading of that file (GitHub's rule for anchors)
  index      docs/README.md links every other file of docs/
  contents   a file that has a '## Contents' list links every '##' and '###' heading, and every entry of the list is a heading that exists
  tables     every row of a table has as many columns as its header
  numbering  ADR sections and the ADR index agree and are continuous; the limitations rows, the mistake-log rows and the guide's rules are numbered without gaps or repeats
Usage: python3 docs_audit.py ROOT [--report]      prints each finding as FILE:LINE message, then DOCS-AUDIT-OK or DOCS-AUDIT-FAILED (n)
  --report  also prints, for every file, the date of its last commit, the newest date that it mentions, and how many lines speak of open or pending work (for a human to read: it never fails)
"""
import glob, os, re, sys
args = [a for a in sys.argv[1:] if not a.startswith("--")]
root = args[0] if args else "."
REPORT = "--report" in sys.argv
D = os.path.join(root, "docs")
files = sorted(glob.glob(os.path.join(D, "*.md")))
bad = []
def add(path, line, msg): bad.append("%s:%s %s" % (os.path.relpath(path, root), line, msg))
def slug(h):
    h = h.strip().lower()
    h = re.sub(r"[`*_]", lambda m: "_" if m.group(0) == "_" else "", h)
    h = re.sub(r"[^\w\- ]", "", h, flags=re.UNICODE)
    return h.replace(" ", "-")
def read(p): return open(p, encoding="utf-8").read().split("\n")
# Numbers that the log and the tables may miss ON PURPOSE: ops/attested/docs-known-gaps.tsv (kind, first, last, why). The older entries live in the private copy of the documents until they are restored.
# The audit tolerates exactly these numbers, still refuses every other gap and every repeated number, and refuses the list itself when one of its numbers exists (a restore must remove its line).
GAPS = {}
_gp = os.path.join(os.path.dirname(os.path.abspath(__file__)), "docs-known-gaps.tsv")
if os.path.exists(_gp):
    for _l in read(_gp):
        if _l.strip() and not _l.startswith("#"):
            _f = _l.split("\t"); GAPS.setdefault(_f[0], set()).update(range(int(_f[1]), int(_f[2]) + 1))
heads = {}   # file -> list of (line, level, text, slug)
for p in files:
    seen = {}; hs = []; fence = False
    for i, l in enumerate(read(p), 1):
        if l.startswith("```"): fence = not fence
        if fence: continue
        m = re.match(r"^(#{1,6}) +(.+?) *$", l)
        if m:
            s = slug(m.group(2)); n = seen.get(s, 0); seen[s] = n + 1
            hs.append((i, len(m.group(1)), m.group(2), s if n == 0 else "%s-%d" % (s, n)))
    heads[p] = hs
# links
for p in files:
    fence = False
    for i, l in enumerate(read(p), 1):
        if l.startswith("```"): fence = not fence
        if fence: continue
        l2 = re.sub(r"`[^`]*`", "", l)
        for m in re.finditer(r"\[[^\]]*\]\(([^)\s]+)\)", l2):
            t = m.group(1)
            if re.match(r"^(https?:|mailto:)", t): continue
            path, _, anc = t.partition("#")
            tp = os.path.normpath(os.path.join(os.path.dirname(p), path)) if path else p
            if not os.path.exists(tp): add(p, i, "link to a file that does not exist: %s" % t); continue
            if anc and tp.endswith(".md"):
                if tp not in heads: heads[tp] = []
                if anc not in [h[3] for h in heads.get(tp, [])]: add(p, i, "link to an anchor that is not a heading of %s: #%s" % (os.path.basename(tp), anc))
# index
idx = os.path.join(D, "README.md")
if os.path.exists(idx):
    txt = open(idx, encoding="utf-8").read()
    for p in files:
        b = os.path.basename(p)
        if b != "README.md" and ("(%s" % b) not in txt: add(idx, 1, "the docs index does not list %s" % b)
# contents
for p in files:
    L = read(p); start = None
    for i, l in enumerate(L):
        if re.match(r"^## Contents *$", l): start = i; break
    if start is None: continue
    end = len(L)
    for j in range(start + 1, len(L)):
        if L[j].startswith("## "): end = j; break
    toc = "\n".join(L[start + 1:end]); anchors = set(re.findall(r"\]\(#([^)]+)\)", toc)); have = {h[3] for h in heads[p]}
    for a in sorted(anchors - have): add(p, start + 1, "the contents list has an entry for a heading that does not exist: #%s" % a)
    for (i, lev, txt_, s) in heads[p]:
        if lev in (2, 3) and txt_.strip() != "Contents" and s not in anchors: add(p, i, "the contents list does not have: %s" % txt_[:70])
# tables
def cols(row):
    r = re.sub(r"`[^`]*`", "", row); r = r.replace("\\|", "")
    return r.count("|")
for p in files:
    L = read(p); i = 0; fence = False
    while i < len(L):
        if L[i].startswith("```"): fence = not fence
        if not fence and L[i].startswith("|") and i + 1 < len(L) and re.match(r"^\|[ :\-|]+\|\s*$", L[i + 1]):
            n = cols(L[i]); j = i + 2
            while j < len(L) and L[j].startswith("|"):
                if cols(L[j]) != n: add(p, j + 1, "a table row has %d columns, its header has %d: %s" % (cols(L[j]) - 1, n - 1, L[j][:60]))
                j += 1
            i = j; continue
        i += 1
# numbering
dec = os.path.join(D, "decisions.md")
if os.path.exists(dec):
    L = read(dec); sec = [int(m.group(1)) for l in L for m in [re.match(r"^## ADR-(\d+):", l)] if m]
    ind = [int(m.group(1)) for l in L for m in [re.match(r"^\| (\d{3}) \|", l)] if m]
    known = GAPS.get("adr", set()); hole = set(range(min(sec), max(sec) + 1)) - set(sec); lost = sorted(hole - known); dup = sorted({n for n in sec if sec.count(n) > 1})
    if lost or dup: add(dec, 1, "ADR sections are not continuous: missing %s, repeated %s" % (lost, dup))
    if known & set(sec): add(dec, 1, "docs-known-gaps.tsv names ADR numbers that exist now: %s (remove them from the list)" % sorted(known & set(sec)))
    if hole & known: print("note: ADR %d to %d are missing on purpose (docs-known-gaps.tsv)" % (min(hole & known), max(hole & known)))
    if set(sec) != set(ind): add(dec, 1, "ADR sections and the ADR index differ: only in sections %s, only in the index %s" % (sorted(set(sec) - set(ind)), sorted(set(ind) - set(sec))))
def numbered_tables(path, header_prefix, label, kind=None):
    if not os.path.exists(path): return
    L = read(path); nums = []; i = 0
    while i < len(L):
        if L[i].startswith(header_prefix):
            j = i + 2
            while j < len(L) and L[j].startswith("|"):
                m = re.match(r"^\| (\d+) \|", L[j])
                if m: nums.append(int(m.group(1)))
                j += 1
            i = j
        else: i += 1
    if not nums: add(path, 1, "no table with the header %s was found" % header_prefix); return
    known = GAPS.get(kind, set()) if kind else set(); hole = set(range(1, max(nums) + 1)) - set(nums)
    dup = sorted({n for n in nums if nums.count(n) > 1}); gap = sorted(hole - known)
    if dup: add(path, 1, "%s: a number is used twice: %s" % (label, dup))
    if gap: add(path, 1, "%s: numbers are missing: %s" % (label, gap))
    if known & set(nums): add(path, 1, "docs-known-gaps.tsv names %s numbers that exist now: %s (remove them from the list)" % (kind, sorted(known & set(nums))))
    if hole & known: print("note: %s %d to %d are missing on purpose (docs-known-gaps.tsv)" % (label, min(hole & known), max(hole & known)))
numbered_tables(os.path.join(D, "limitations-and-trust.md"), "| # | Challenge |", "the limitations rows", "limitations")
numbered_tables(os.path.join(D, "guide-pitfalls-and-lessons.md"), "| # | Where |", "the mistake-log rows")
G = os.path.join(D, "guide-pitfalls-and-lessons.md")
rules = [int(m.group(1)) for l in (read(G) if os.path.exists(G) else []) for m in [re.match(r"^(\d+)\. \*\*", l)] if m]
if rules and rules != list(range(1, len(rules) + 1)): add(G, 1, "the guide's numbered rules are not 1..%d without gaps: %s" % (len(rules), rules[-6:]))
# numbered headings and numbered lists must run without repeats or gaps
for p in files:
    L = read(p); fence = False; prev = None
    for i, l in enumerate(L, 1):
        if l.startswith("```"): fence = not fence
        if fence: continue
    # headings of the form '## N. title' must be 1, 2, 3 ... in order
    nums = [(i, int(m.group(1))) for i, l in enumerate(L, 1) for m in [re.match(r"^## (\d+)\. ", l)] if m]
    for k in range(1, len(nums)):
        if nums[k][1] != nums[k - 1][1] + 1: add(p, nums[k][0], "section numbers jump from %d to %d" % (nums[k - 1][1], nums[k][1]))
    # a block of consecutive numbered list lines must count 1, 2, 3 ...
    block = []; fence = False
    for i, l in enumerate(L + [""], 1):
        if l.startswith("```"): fence = not fence
        m = None if fence else re.match(r"^(\d+)\. ", l)
        if m: block.append((i, int(m.group(1))))
        else:
            if len(block) >= 2:
                for k in range(1, len(block)):
                    if block[k][1] != block[k - 1][1] + 1:
                        add(p, block[k][0], "a numbered list goes from %d to %d" % (block[k - 1][1], block[k][1])); break
            block = []
if REPORT:
    import subprocess
    MON = {m: i for i, m in enumerate("January February March April May June July August September October November December".split(), 1)}
    print("info: %-40s %6s  %-10s %-12s %s" % ("file", "lines", "last commit", "newest date", "lines about open or pending work"))
    for p in files:
        t = "\n".join(read(p))
        ds = [(int(m.group(3)), MON[m.group(2)], int(m.group(1))) for m in re.finditer(r"\b(\d{1,2}) (January|February|March|April|May|June|July|August|September|October|November|December) (20\d\d)\b", t)]
        newest = "%04d-%02d-%02d" % max(ds) if ds else "-"
        try: last = subprocess.run(["git", "log", "-1", "--format=%cs", "--", os.path.relpath(p, root)], cwd=root, capture_output=True, text=True).stdout.strip() or "-"
        except Exception: last = "-"
        n = sum(1 for l in read(p) if re.search(r"not started|still open|is open|\bopen\b:|not yet|pending|to be confirmed|planned", l, re.I))
        print("info: %-40s %6d  %-10s %-12s %d" % (os.path.basename(p), len(read(p)), last, newest, n))
for b in bad: print(b)
print("%d file(s) audited" % len(files))
print("DOCS-AUDIT-OK" if not bad else "DOCS-AUDIT-FAILED (%d)" % len(bad))
sys.exit(0 if not bad else 1)
