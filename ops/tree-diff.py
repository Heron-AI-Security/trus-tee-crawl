#!/usr/bin/env python3
"""Step P4.2: compare the manifests of two file trees (made by ops/tree-manifest.py).
    python3 ops/tree-diff.py A.manifest B.manifest [--require-verity] [--ignore FILE] [--report FILE] [--max N]
It names every path that is only in A, only in B, or in both with another type, content (SHA-256), link target, mode, owner or extended attributes (capabilities and ACLs included). Times are never compared.
--require-verity refuses a manifest that was not made from a disk that was opened through dm-verity against a root hash (its header has no # verity line). --ignore FILE holds one pattern per line
(a path with * and ? that match any characters, # starts a comment); an ignored difference is still counted and listed by pattern, so that nothing is hidden. --max N limits the lines printed per
category (default 40); --report FILE writes every difference. A manifest must be complete (its last line counts what it holds) and must report no read error.
Ends with  TREE-DIFF-IDENTICAL files=N ... verity=checked|unchecked  (exit code 0),  TREE-DIFF-DIFFERENT differences=N ignored=K  (exit code 1), or  TREE-DIFF-FAILED: <reason>  (exit code 2)."""
import fnmatch, sys
def fail(m): print("TREE-DIFF-FAILED: " + m); sys.exit(2)
def load(path):
    try: lines = open(path, encoding="utf-8", errors="surrogateescape").read().split("\n")
    except OSError as e: fail("%s cannot be read: %s" % (path, e))
    if lines and lines[-1] == "": lines.pop()
    if not lines or lines[0] != "# tc-tree-manifest v2": fail("%s is not a tc-tree-manifest v2 file" % path)
    label = ""; verity = ""; recs = {}; summary = None; counts = {"D": 0, "F": 0, "L": 0, "O": 0}
    for l in lines[1:]:
        if l.startswith("# label: "): label = l[9:]
        elif l.startswith("# summary: "): summary = l[11:]
        elif l.startswith("# verity: "): verity = l[10:]
        elif l.startswith("#"): continue
        else:
            f = l.split("\t"); t = f[0]
            need = {"D": 6, "F": 8, "L": 7, "O": 7}.get(t)
            if need is None or len(f) != need: fail("%s: a line is malformed: %r" % (path, l[:80]))
            if f[1] in recs: fail("%s: the path %r is listed twice" % (path, f[1][:80]))
            recs[f[1]] = tuple(f); counts[t] += 1
    if summary is None: fail("%s has no summary line: it is truncated" % path)
    kv = dict(x.split("=") for x in summary.split())
    if (int(kv["dirs"]), int(kv["files"]), int(kv["symlinks"]), int(kv["other"])) != (counts["D"], counts["F"], counts["L"], counts["O"]): fail("%s: its summary does not match its lines: it is damaged or truncated" % path)
    if int(kv["errors"]) != 0 or any("ERROR:" in "\t".join(r) for r in recs.values()): fail("%s reports read errors (%s): a tree that could not be read completely cannot be compared" % (path, kv["errors"]))
    return label, recs, counts, verity
def xdesc(x, y):
    """Which extended attributes differ: name: value in A -> value in B (the file capability is security.capability)."""
    dx = dict(kv.rsplit("=", 1) for kv in x.split(";")) if x != "-" else {}; dy = dict(kv.rsplit("=", 1) for kv in y.split(";")) if y != "-" else {}
    out = ["%s: %s -> %s" % (n, (dx.get(n) or "(none)")[:24], (dy.get(n) or "(none)")[:24]) for n in sorted(set(dx) | set(dy)) if dx.get(n) != dy.get(n)]
    return "; ".join(out[:3]) + ("; ..." if len(out) > 3 else "")
def main(argv):
    pos = []; ignore = None; report = None; maxn = 40; reqv = False; i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--ignore" and i + 1 < len(argv): ignore = argv[i + 1]; i += 2
        elif a == "--report" and i + 1 < len(argv): report = argv[i + 1]; i += 2
        elif a == "--max" and i + 1 < len(argv): maxn = int(argv[i + 1]); i += 2
        elif a == "--require-verity": reqv = True; i += 1
        elif a.startswith("--"): fail("unknown option " + a)
        else: pos.append(a); i += 1
    if len(pos) != 2: print(__doc__.splitlines()[0]); sys.exit(64)
    pats = []
    if ignore:
        try: pats = [l.strip() for l in open(ignore, encoding="utf-8").read().splitlines() if l.strip() and not l.strip().startswith("#")]
        except OSError as e: fail("the ignore file cannot be read: %s" % e)
    la, A, ca, va = load(pos[0]); lb, B, cb, vb = load(pos[1]); na = la or "A"; nb = lb or "B"
    if reqv:
        for nm, v, pth in (("A", va, pos[0]), ("B", vb, pos[1])):
            if not v: fail("the manifest %s (%s) was not made from a disk that was opened through dm-verity against a root hash: its files were not checked against any root hash" % (nm, pth))
    vstate = "checked" if (va and vb) else "unchecked"
    print("A: %s  (%d dirs, %d files, %d symlinks, %d other)%s" % (na, ca["D"], ca["F"], ca["L"], ca["O"], ("  verity root %s..." % va[:16]) if va else "  NOT verity-checked")); print("B: %s  (%d dirs, %d files, %d symlinks, %d other)%s" % (nb, cb["D"], cb["F"], cb["L"], cb["O"], ("  verity root %s..." % vb[:16]) if vb else "  NOT verity-checked"))
    diffs = []
    for p in sorted(set(A) | set(B)):
        a, b = A.get(p), B.get(p)
        if a is None: diffs.append(("only in B", p, "")); continue
        if b is None: diffs.append(("only in A", p, "")); continue
        if a[0] != b[0]: diffs.append(("type differs", p, "%s -> %s" % (a[0], b[0]))); continue
        if a[0] == "F" and a[6] != b[6]: diffs.append(("content differs", p, "size %s -> %s" % (a[5], b[5])))
        if a[0] == "L" and a[5] != b[5]: diffs.append(("link target differs", p, "%s -> %s" % (a[5], b[5])))
        if a[0] == "O" and a[5] != b[5]: diffs.append(("special file differs", p, "%s -> %s" % (a[5], b[5])))
        if a[2] != b[2]: diffs.append(("mode differs", p, "%s -> %s" % (a[2], b[2])))
        if (a[3], a[4]) != (b[3], b[4]): diffs.append(("owner differs", p, "%s:%s -> %s:%s" % (a[3], a[4], b[3], b[4])))
        if a[-1] != b[-1]: diffs.append(("xattrs differ", p, xdesc(a[-1], b[-1])))
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
        print("TREE-DIFF-IDENTICAL files=%d dirs=%d symlinks=%d ignored=%d verity=%s" % (ca["F"], ca["D"], ca["L"], nign, vstate)); sys.exit(0)
    by = {}
    for k, p, x in kept: by.setdefault(k, []).append((p, x))
    print("%d differences:" % len(kept))
    for k in ("only in A", "only in B", "type differs", "content differs", "link target differs", "special file differs", "mode differs", "owner differs", "xattrs differ"):
        if k in by:
            print("  %s: %d" % (k, len(by[k])))
            for p, x in by[k][:maxn]: print("      %s%s" % (p, ("   (" + x + ")") if x else ""))
            if len(by[k]) > maxn: print("      ... and %d more (use --report FILE for all)" % (len(by[k]) - maxn))
    top = {}
    for k, p, x in kept:
        above = p.split("/")[1:-1]; key = "/" + "/".join(above[:2]) if above else "/"; top[key] = top.get(key, 0) + 1
    print("by directory (the first two levels above each difference):")
    for key, n in sorted(top.items(), key=lambda kv: (-kv[1], kv[0]))[:15]: print("  %5d  %s" % (n, key))
    print("TREE-DIFF-DIFFERENT differences=%d ignored=%d verity=%s" % (len(kept), nign, vstate)); sys.exit(1)
main(sys.argv[1:])
