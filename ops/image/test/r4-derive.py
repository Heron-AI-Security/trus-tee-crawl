#!/usr/bin/env python3
"""Step R4.1, OFFLINE, once per image: turn the ground truth of r4-manifest.sh into the RECIPE that r4-recompute.py uses, and say what the recipe cannot cover yet.
   python3 r4-derive.py --evidence DIR --repo TREE --out DIR [--allow-input DEST ...]
Every file of every measured item is traced to a source: a package (not covered here), a repository file with the same content (repo:PATH), a repository file that the hook strip of the image build rewrites (repo+strip:PATH,
verified by applying the strip, not assumed), a link, or a small text file that the build generates (input: only for the destinations in the allow-list, which is visible and changeable, so that nothing is pinned silently).
An event is covered when every one of its files is traced; the others are listed with the reason. Test fixtures and evidence folders are never taken as sources. The recipe is a file for people to review: the mentor can change any row."""
import sys; sys.dont_write_bytecode = True   # a tool that is run inside a repository must leave no __pycache__ behind (the audit refuses untracked files)
import argparse, collections, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import sha384, load_strip, stripped_bytes, parse_measured, commit_bytes
import re

ALLOW = ["/etc/tc/role", "/etc/tc/image-mode", "/etc/tc/bake-versions.txt", "/etc/tc/job-versions.txt", "/etc/tc/java-ca-fingerprints.txt", "/etc/tc/crawl/collection-policy.json"]
SKIPDIRS = {".git", "__pycache__", "node_modules", "fixtures", "evidence"}

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--evidence", required=True); ap.add_argument("--repo", required=True); ap.add_argument("--out", required=True); ap.add_argument("--allow-input", action="append")
    a = ap.parse_args(); allow = set(a.allow_input or ALLOW); E = a.evidence; R = a.repo
    events = [l.rstrip("\n").split("\t") for l in open(os.path.join(E, "events.tsv"), encoding="utf-8") if l.strip()]
    owned = set(l.rstrip("\n") for l in open(os.path.join(E, "dpkg-files.txt"), encoding="utf-8")) if os.path.exists(os.path.join(E, "dpkg-files.txt")) else set()
    def owner(p):
        if p in owned: return True
        if p.startswith("/usr/") and p[4:] in owned: return True
        return any(p.startswith(x) and "/usr" + p in owned for x in ("/bin/", "/sbin/", "/lib/", "/lib64/"))
    bysha = collections.defaultdict(list); byname = collections.defaultdict(list)
    for root, dirs, files in os.walk(R):
        dirs[:] = [d for d in dirs if d not in SKIPDIRS]
        for f in files:
            p = os.path.join(root, f)
            if os.path.islink(p): continue
            rel = os.path.relpath(p, R); bysha[sha384(open(p, "rb").read())].append(rel); byname[f].append(rel)
    pref = lambda r: (not r.startswith("ops/image/rootfs/"), not r.startswith("attest/"), r)
    strip = load_strip(R); commit_id = None; sp = os.path.join(E, "source.txt")
    if os.path.exists(sp):
        m = re.fullmatch(r"commit ([0-9a-f]{40}|[0-9a-f]{64}|none)\n", open(sp, encoding="utf-8").read())
        commit_id = m.group(1) if m else None
    rows = {}; inputs = {}; report = []; covered = []; conflicts = 0
    for ev in events:
        name, digest, count, kind, path = ev[:5]
        lines = open(os.path.join(E, "manifests", name + ".manifest"), encoding="utf-8").read().splitlines(); got = {}; why = collections.Counter()
        for line in lines:
            if line.startswith("L "):
                rel, _, tgt = line[2:].partition(" -> "); got[path.rstrip("/") + "/" + rel[2:]] = ("L", "link:" + tgt, None); continue
            _, mode, h, rel = line.split(" ", 3); full = path if kind == "file" else path.rstrip("/") + "/" + rel[2:]
            if owner(full): why["package"] += 1; continue
            if full == "/etc/tc/source.txt" and commit_id and commit_id != "none" and h == sha384(commit_bytes(commit_id)): got[full] = (mode, "commit", None); continue
            if h in bysha: got[full] = (mode, "repo:" + sorted(bysha[h], key=pref)[0], None); continue
            src = None
            for cand in sorted(byname.get(os.path.basename(full), []), key=pref):
                try: same = sha384(stripped_bytes(strip, os.path.join(R, cand))) == h
                except (OSError, UnicodeError): same = False   # a binary file of the same name
                if same: src = cand; break
            if src: got[full] = (mode, "repo+strip:" + src, None); continue
            if full in allow: got[full] = (mode, "input", h); continue
            why["not traced (" + ("a download or a build product" if full.startswith(("/opt/", "/usr/lib/")) else "unknown") + ")"] += 1
        ok = not why
        report.append((name, int(count), len(got), dict(why), ok))
        if ok:
            covered.append(name)
            for full, (mode, src, h) in got.items():
                if full in rows and rows[full][:2] != (mode, src): print("   conflict at %s: %s against %s" % (full, rows[full][:2], (mode, src))); conflicts += 1
                rows[full] = (mode, src, h)
                if h: inputs[full] = h
    os.makedirs(a.out, exist_ok=True)
    with open(os.path.join(a.out, "install-manifest.tsv"), "w", encoding="utf-8") as o:
        o.write("# destination\tmode\tsource   (source: repo:PATH | repo+strip:PATH | link:TARGET | commit | input). Generated by r4-derive.py from the ground truth of an image; reviewed by a person; changed by editing a row.\n")
        for full in sorted(rows): m, s, _ = rows[full]; o.write("%s\t%s\t%s\n" % (full, m, s))
    with open(os.path.join(a.out, "build-inputs.tsv"), "w", encoding="utf-8") as o:
        o.write("# destination\tsha384\tnote   (small text files that the build generates; R4.3 turns each into a function of pinned versions)\n")
        for full in sorted(inputs): o.write("%s\t%s\tgenerated by the build; pinned by hash from the ground truth of an image\n" % (full, inputs[full]))
    print("%-22s %8s %8s   %s" % ("event", "entries", "traced", "not traced (the reason)"))
    for name, cnt, got, why, ok in report: print("%-22s %8d %8d   %s" % (name, cnt, got, "covered" if ok else ", ".join("%s x%d" % kv for kv in why.items())))
    print("\nrecipe: %d destinations (%d repo, %d repo+strip, %d link, %d input) in %s" % (len(rows), sum(s.startswith("repo:") for _, s, _ in rows.values()), sum(s.startswith("repo+strip:") for _, s, _ in rows.values()), sum(s.startswith("link:") for _, s, _ in rows.values()), sum(s == "input" for _, s, _ in rows.values()), a.out))
    print("covered: %s\nnot covered: %s" % (", ".join(covered) or "none", ", ".join(n for n, _, _, _, ok in report if not ok) or "none"))
    print("commit recorded in the image: %s" % (commit_id or "none found") + ("   WARNING: a development build, no commit is pinned" if commit_id == "none" else ""))
    if conflicts: print("R4-DERIVE-FAILED: %d conflicting rows" % conflicts); return 1
    print("R4-DERIVE-OK covered=%d/%d" % (len(covered), len(events))); return 0

if __name__ == "__main__": sys.exit(main())
