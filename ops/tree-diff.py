#!/usr/bin/env python3
"""Step P4.2: compare the manifests of two file trees (made by ops/tree-manifest.py).
    python3 ops/tree-diff.py A.manifest B.manifest [--ignore FILE] [--report FILE] [--max N]
It names every path that is only in A, only in B, or in both with another type, content (SHA-256), link target, mode or owner. Times are never compared. --ignore FILE holds one pattern per line
(a path with * and ? that match any characters, # starts a comment); an ignored difference is still counted and listed by pattern, so that nothing is hidden. --max N limits the lines printed per
category (default 40); --report FILE writes every difference. A manifest must be complete (its last line counts what it holds) and must report no read error.
Ends with  TREE-DIFF-IDENTICAL files=N ...  (exit code 0),  TREE-DIFF-DIFFERENT differences=N ignored=K  (exit code 1), or  TREE-DIFF-FAILED: <reason>  (exit code 2)."""
import fnmatch, sys
def fail(m): print("TREE-DIFF-FAILED: " + m); sys.exit(2)
def load(path):
    try: lines = open(path, encoding="utf-8", errors="surrogateescape").read().split("\n")
    except OSError as e: fail("%s cannot be read: %s" % (path, e))
    if lines and lines[-1] == "": lines.pop()
    if not lines or lines[0] != "# tc-tree-manifest v1": fail("%s is not a tc-tree-manifest v1 file" % path)
    label = ""; recs = {}; summary = None; counts = {"D": 0, "F": 0, "L": 0, "O": 0}
    for l in lines[1:]:
        if l.startswith("# label: "): label = l[9:]
        elif l.startswith("# summary: "): summary = l[11:]
        elif l.startswith("#"): continue
        else:
            f = l.split("\t"); t = f[0]
            need = {"D": 5, "F": 7, "L": 6, "O": 6}.get(t)
            if need is None or len(f) != need: fail("%s: a line is malformed: %r" % (path, l[:80]))
            if f[1] in recs: fail("%s: the path %r is listed twice" % (path, f[1][:80]))
            recs[f[1]] = tuple(f); counts[t] += 1
    if summary is None: fail("%s has no summary line: it is truncated" % path)
    kv = dict(x.split("=") for x in summary.split())
    if (int(kv["dirs"]), int(kv["files"]), int(kv["symlinks"]), int(kv["other"])) != (counts["D"], counts["F"], counts["L"], counts["O"]): fail("%s: its summary does not match its lines: it is damaged or truncated" % path)
    if int(kv["errors"]) != 0 or any("ERROR:" in "\t".join(r) for r in recs.values()): fail("%s reports read errors (%s): a tree that could not be read completely cannot be compared" % (path, kv["errors"]))
    return label, recs, counts
def main(argv):
    pos = []; ignore = None; report = None; maxn = 40; i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--ignore" and i + 1 < len(argv): ignore = argv[i + 1]; i += 2
        elif a == "--report" and i + 1 < len(argv): report = argv[i + 1]; i += 2
        elif a == "--max" and i + 1 < len(argv): maxn = int(argv[i + 1]); i += 2
        elif a.startswith("--"): fail("unknown option " + a)
        else: pos.append(a); i += 1
    if len(pos) != 2: print(__doc__.splitlines()[0]); sys.exit(64)
    pats = []
    if ignore:
        try: pats = [l.strip() for l in open(ignore, encoding="utf-8").read().splitlines() if l.strip() and not l.strip().startswith("#")]
        except OSError as e: fail("the ignore file cannot be read: %s" % e)
    la, A, ca = load(pos[0]); lb, B, cb = load(pos[1]); na = la or "A"; nb = lb or "B"
    print("A: %s  (%d dirs, %d files, %d symlinks, %d other)" % (na, ca["D"], ca["F"], ca["L"], ca["O"])); print("B: %s  (%d dirs, %d files, %d symlinks, %d other)" % (nb, cb["D"], cb["F"], cb["L"], cb["O"]))
    diffs = []
    for p in sorted(set(A) | set(B)):
        a, b = A.get(p), B.get(p)
        if a is None: diffs.append(("only in B", p, "")); continue
        if b is None: diffs.append(("only in A", p, "")); continue
        if a[0] != b[0]: diffs.append(("type differs", p, "%s -> %s" % (a[0], b[0]))); continue
        if a[0] == "F" and a[6] != b[6]: diffs.append(("content differs", p, "size %s -> %s" % (a[5], b[5]))); continue
        if a[0] == "L" and a[5] != b[5]: diffs.append(("link target differs", p, "%s -> %s" % (a[5], b[5]))); continue
        if a[0] == "O" and a[5] != b[5]: diffs.append(("special file differs", p, "%s -> %s" % (a[5], b[5]))); continue
        if a[2] != b[2]: diffs.append(("mode differs", p, "%s -> %s" % (a[2], b[2]))); continue
        if (a[3], a[4]) != (b[3], b[4]): diffs.append(("owner differs", p, "%s:%s -> %s:%s" % (a[3], a[4], b[3], b[4])))
    kept = []; ign = {}
    for d in diffs:
        hit = next((pt for pt in pats if fnmatch.fnmatchcase(d[1], pt)), None)
        if hit: ign[hit] = ign.get(hit, 0) + 1
        else: kept.append(d)
    nign = sum(ign.values())
    if report:
        with open(report, "w", encoding="utf-8", errors="surrogateescape") as f:
            for k, p, x in diffs: f.write("%s\t%s\t%s\t%s\n" % ("IGNORED" if any(fnmatch.fnmatchcase(p, pt) for pt in pats) else "DIFF", k, p, x))
    if ign:
        print("ignored by your patterns (%d differences):" % nign)
        for pt, n in sorted(ign.items()): print("  %5d  %s" % (n, pt))
    if not kept:
        print("TREE-DIFF-IDENTICAL files=%d dirs=%d symlinks=%d ignored=%d" % (ca["F"], ca["D"], ca["L"], nign)); sys.exit(0)
    by = {}
    for k, p, x in kept: by.setdefault(k, []).append((p, x))
    print("%d differences:" % len(kept))
    for k in ("only in A", "only in B", "type differs", "content differs", "link target differs", "special file differs", "mode differs", "owner differs"):
        if k in by:
            print("  %s: %d" % (k, len(by[k])))
            for p, x in by[k][:maxn]: print("      %s%s" % (p, ("   (" + x + ")") if x else ""))
            if len(by[k]) > maxn: print("      ... and %d more (use --report FILE for all)" % (len(by[k]) - maxn))
    top = {}
    for k, p, x in kept:
        above = p.split("/")[1:-1]; key = "/" + "/".join(above[:2]) if above else "/"; top[key] = top.get(key, 0) + 1
    print("by directory (the first two levels above each difference):")
    for key, n in sorted(top.items(), key=lambda kv: (-kv[1], kv[0]))[:15]: print("  %5d  %s" % (n, key))
    print("TREE-DIFF-DIFFERENT differences=%d ignored=%d" % (len(kept), nign)); sys.exit(1)
main(sys.argv[1:])
