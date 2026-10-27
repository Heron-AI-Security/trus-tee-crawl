#!/usr/bin/env python3
"""Step R4.5 (the experiment before the fixes): compare the ground truth of TWO builds of the SAME commit and say exactly what is not reproducible.
   python3 r4-diff.py A_DIR B_DIR [--show N] [--out FILE]
A_DIR and B_DIR are the folders that r4-manifest.sh wrote on two builders. Section 1: the inputs (the commit that each image records, the operating system, the packages, the kernel and the initramfs). Section 2: every
measured event, identical or different. Section 3: for every different folder event, the files that were added, removed, changed in mode or changed in content, each with a hint about the likely cause (a package file,
the same size with another hash, which points to a timestamp or an ordering inside an archive, a different size). A difference is a result, not a failure: the exit code is 0 unless a folder is unreadable.
Standard library only."""
import sys; sys.dont_write_bytecode = True
import argparse, collections, os

def load(d):
    r = {}
    ev = collections.OrderedDict()
    for l in open(os.path.join(d, "events.tsv"), encoding="utf-8"):
        p = l.rstrip("\n").split("\t")
        if len(p) >= 5: ev[p[0]] = dict(digest=p[1], count=int(p[2]), kind=p[3], path=p[4])
    r["events"] = ev; man = {}
    for name, e in ev.items():
        files = {}
        for line in open(os.path.join(d, "manifests", name + ".manifest"), encoding="utf-8").read().splitlines():
            if line.startswith("F "):
                _, mode, h, rel = line.split(" ", 3); files[e["path"] if e["kind"] == "file" else e["path"].rstrip("/") + "/" + rel[2:]] = (mode, h)
            elif line.startswith("L "):
                rel, _, t = line[2:].partition(" -> "); files[e["path"].rstrip("/") + "/" + rel[2:]] = ("L", t)
        man[name] = files
    r["man"] = man
    def rd(n, default=""):
        p = os.path.join(d, n); return open(p, encoding="utf-8").read() if os.path.exists(p) else default
    r["source"] = rd("source.txt").strip()
    r["os"] = [l for l in rd("os.txt").split("# /proc/cmdline")[0].splitlines() if l and not l.startswith("#")]
    r["pkgs"] = dict(l.split("\t")[:2] for l in rd("packages.tsv").splitlines() if "\t" in l)
    r["boot"] = {os.path.basename(l.split("  ", 1)[1]): l.split("  ", 1)[0] for l in rd("boot-files.sha256").splitlines() if "  " in l}
    r["owned"] = set(rd("dpkg-files.txt").splitlines())
    r["meta"] = {l.split("\t")[0]: l.rstrip("\n").split("\t")[1:3] for l in rd("files-meta.tsv").splitlines() if l.count("\t") >= 2}
    return r

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("a"); ap.add_argument("b"); ap.add_argument("--show", type=int, default=15); ap.add_argument("--out")
    a = ap.parse_args(); out = []
    def p(s=""): print(s); out.append(s)
    try: A = load(a.a); B = load(a.b)
    except (OSError, ValueError) as e: print("R4-DIFF-FAILED: %s" % e); return 1
    p("== 1. the inputs of the two builds")
    p("   commit recorded:  A: %s   B: %s   -> %s" % (A["source"] or "(none)", B["source"] or "(none)", "SAME" if A["source"] == B["source"] and A["source"] else "DIFFERENT OR MISSING"))
    p("   operating system: %s" % ("same (%s)" % "; ".join(A["os"][:3]) if A["os"] == B["os"] else "DIFFERENT: A %s | B %s" % (A["os"][:3], B["os"][:3])))
    pk = [n for n in sorted(set(A["pkgs"]) | set(B["pkgs"])) if A["pkgs"].get(n) != B["pkgs"].get(n)]
    p("   packages: A %d, B %d; %s" % (len(A["pkgs"]), len(B["pkgs"]), "all versions equal" if not pk else "%d differ" % len(pk)))
    for n in pk[:a.show]: p("      %-34s A %-28s B %s" % (n, A["pkgs"].get(n, "(not installed)"), B["pkgs"].get(n, "(not installed)")))
    for f in sorted(set(A["boot"]) | set(B["boot"])): p("   %-24s %s" % (f, "same" if A["boot"].get(f) == B["boot"].get(f) else "DIFFERENT (A %s... B %s...)" % ((A["boot"].get(f) or "-")[:12], (B["boot"].get(f) or "-")[:12])))
    p("\n== 2. the measured events")
    names = list(A["events"]) + [n for n in B["events"] if n not in A["events"]]; same = []; diff = []
    for n in names:
        ea, eb = A["events"].get(n), B["events"].get(n)
        if ea and eb and ea["digest"] == eb["digest"]: same.append(n); p("   identical  %-22s %s...  (%d entries)" % (n, ea["digest"][:16], ea["count"]))
        else: diff.append(n); p("   DIFFERENT  %-22s A %s... (%s)   B %s... (%s)" % (n, (ea or {"digest": "-" * 16})["digest"][:16], ea["count"] if ea else "absent", (eb or {"digest": "-" * 16})["digest"][:16], eb["count"] if eb else "absent"))
    p("\n== 3. what differs, file by file")
    hints = collections.Counter()
    for n in diff:
        fa, fb = A["man"].get(n, {}), B["man"].get(n, {}); added = sorted(set(fb) - set(fa)); removed = sorted(set(fa) - set(fb)); changed = sorted(f for f in set(fa) & set(fb) if fa[f] != fb[f])
        p("\n   %s: %d added in B, %d removed from B, %d changed" % (n, len(added), len(removed), len(changed)))
        rows = []
        for f in added: rows.append((f, "only in B"))
        for f in removed: rows.append((f, "only in A"))
        for f in changed:
            ma, mb = fa[f], fb[f]
            if ma[0] != mb[0] and ma[1] == mb[1]: h = "mode %s -> %s" % (ma[0], mb[0])
            else:
                sa, sb = A["meta"].get(f), B["meta"].get(f)
                ext = os.path.splitext(f)[1] or "(none)"
                if f in A["owned"] or f in B["owned"]: h = "a package file (see the package versions above)"
                elif sa and sb and sa[0] == sb[0]: h = "same size (%s bytes), other content: a timestamp or an ordering inside? [%s]%s" % (sa[0], ext, "; time A %s B %s" % (sa[1], sb[1]) if sa[1] != sb[1] else "")
                elif sa and sb: h = "other size (A %s, B %s bytes) [%s]" % (sa[0], sb[0], ext)
                else: h = "other content [%s]" % ext
            rows.append((f, h))
        for f, h in rows: hints[h.split(" (")[0].split(":")[0].split(" [")[0]] += 1
        for f, h in rows[:a.show]: p("      %-62s %s" % (f[-62:], h))
        if len(rows) > a.show: p("      ... and %d more (all of them are in the report file, if --out was given)" % (len(rows) - a.show))
        if a.out:
            for f, h in rows[a.show:]: out.append("      %-62s %s" % (f[-62:], h))
    if hints: p("\n   the causes, counted: " + "; ".join("%s x%d" % kv for kv in hints.most_common()))
    p()
    p("R4-DIFF: %d of %d events identical; different: %s" % (len(same), len(names), ", ".join(diff) or "none"))
    if a.out: open(a.out, "w", encoding="utf-8").write("\n".join(out) + "\n")
    return 0

if __name__ == "__main__": sys.exit(main())
