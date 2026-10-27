#!/usr/bin/env python3
"""Step R4.0, OFFLINE: check the ground truth that r4-manifest.sh wrote on a VM, and show where the files of every measured item come from.
   python3 r4-compare.py EXTRACTED_DIR [--reference reference-values.json] [--repo DIR] [--candidates FILE] [--show N]
Section 1: the copy is whole (SHA256SUMS). Section 2: every manifest is the one that its digest names. Section 3 (with --reference): the digest of every STABLE event equals the value that the
real cluster reported, the list has no other event, and the order is the same. Section 4 (with --repo, a folder with the files of the repository): every file of every manifest is classified as
owned by a package, equal in content to a file of the repository, a file of the same name with other content (for example a script that the image build rewrote), or other (made or downloaded
at build time); --candidates writes the files that equal a repository file, with their destination and mode, which is the seed of the install list of step R4.1.
Standard library only. Exit code 0 when no check failed."""
import sys; sys.dont_write_bytecode = True   # a tool that is run inside a repository must leave no __pycache__ behind (the audit refuses untracked files)
import argparse, collections, hashlib, json, os, sys

def sha(path, algo):
    h = hashlib.new(algo)
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("dir"); ap.add_argument("--reference"); ap.add_argument("--repo"); ap.add_argument("--candidates"); ap.add_argument("--show", type=int, default=12)
    a = ap.parse_args(); D = a.dir; bad = [0]
    def ok(m): print("   ok:   " + m)
    def no(m): bad[0] += 1; print("   FAIL: " + m)
    def say(m): print("\n== " + m)
    ev_file = os.path.join(D, "events.tsv")
    if not os.path.exists(ev_file): print("R4-COMPARE-FAILED: no events.tsv in %s" % D); return 1
    events = collections.OrderedDict()
    for line in open(ev_file, encoding="utf-8"):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 5: events[p[0]] = dict(digest=p[1], count=int(p[2]), kind=p[3], path=p[4], skips=p[5] if len(p) > 5 else "")
    say("1. the copy is whole (SHA256SUMS)")
    sums = os.path.join(D, "SHA256SUMS"); n = 0
    if not os.path.exists(sums): no("no SHA256SUMS")
    else:
        for line in open(sums, encoding="utf-8"):
            h, _, f = line.rstrip("\n").partition("  "); f = f[2:] if f.startswith("./") else f; n += 1
            if not os.path.exists(os.path.join(D, f)): no("missing file %s" % f)
            elif sha(os.path.join(D, f), "sha256") != h: no("%s differs from its checksum" % f)
        if not bad[0]: ok("%d files, every one equals its checksum" % n)
    say("2. every manifest is the one that its digest names")
    b0 = bad[0]; manifests = {}
    for name, e in events.items():
        mf = os.path.join(D, "manifests", name + ".manifest")
        if not os.path.exists(mf): no("%s: no manifest" % name); continue
        lines = open(mf, encoding="utf-8").read().splitlines(); manifests[name] = lines
        if e["kind"] == "dir":
            if sha(mf, "sha384") != e["digest"]: no("%s: the SHA-384 of the manifest is not the digest of the event" % name)
            elif len(lines) != e["count"]: no("%s: %d lines, the event says %d" % (name, len(lines), e["count"]))
        else:
            parts = lines[0].split(" ", 3) if lines else []
            if len(parts) != 4 or parts[2] != e["digest"]: no("%s: the file line does not hold the digest of the event" % name)
    if bad[0] == b0: ok("%d manifests, each hashes to the digest of its event" % len(manifests))
    if a.reference:
        say("3. against the reference values of the real cluster (%s)" % os.path.basename(a.reference))
        ref = json.load(open(a.reference, encoding="utf-8")); st = ref["stable_events"]; per_run = set(ref.get("per_run_events", [])); b0 = bad[0]; good = 0
        order_ref = [x for x in ref["events_in_order"] if x not in per_run]
        for name in order_ref:
            e = events.get(name)
            if e is None: no("%s: the reference has it, the image's list does not" % name)
            elif e["digest"] != st[name]: no("%s: the image gives %s..., the cluster reported %s..." % (name, e["digest"][:16], st[name][:16]))
            else: good += 1; ok("%-22s %s... equals the cluster's value" % (name, e["digest"][:16]))
        extra = [x for x in events if x not in st]
        if extra: no("the image's list has events that the reference lacks: %s" % ", ".join(extra))
        if list(events) != order_ref and not extra and all(x in events for x in order_ref): no("the order of the list is not the order of the reference")
        print("   GROUND-TRUTH-%s: %d of %d stable events equal" % ("OK" if bad[0] == b0 else "FAILED", good, len(order_ref)))
    if a.repo:
        say("4. where the files come from (the repository folder: %s)" % a.repo)
        bysha = collections.defaultdict(list); byname = collections.defaultdict(list)
        for root, dirs, files in os.walk(a.repo):
            dirs[:] = [d for d in dirs if d not in (".git", "__pycache__", "node_modules")]
            for f in files:
                p = os.path.join(root, f); rel = os.path.relpath(p, a.repo)
                if os.path.islink(p): continue
                bysha[sha(p, "sha384")].append(rel); byname[f].append(rel)
        dp = os.path.join(D, "dpkg-files.txt"); owned = set(l.rstrip("\n") for l in open(dp, encoding="utf-8")) if os.path.exists(dp) else set()
        if not owned: print("   note: no dpkg-files.txt, so nothing is classified as owned by a package")
        def owner(p):
            if p in owned: return True
            if p.startswith("/usr/") and p[4:] in owned: return True
            return any(p.startswith(x) and "/usr" + p in owned for x in ("/bin/", "/sbin/", "/lib/", "/lib64/"))
        rows = []; others = {}; cands = []
        for name, e in events.items():
            c = collections.Counter(); modes = collections.Counter(); oth = []
            for line in manifests.get(name, []):
                if line.startswith("L "):
                    c["link"] += 1; continue
                _, mode, h, rel = line.split(" ", 3)
                full = e["path"] if e["kind"] == "file" else e["path"].rstrip("/") + "/" + rel[2:]
                if owner(full): c["package"] += 1
                elif h in bysha:
                    c["repo"] += 1; modes[mode] += 1; cands.append((name, full, mode, ",".join(sorted(bysha[h])[:3])))
                elif os.path.basename(full) in byname: c["same-name"] += 1; oth.append("%s (%s) same name as %s, other content" % (full, mode, byname[os.path.basename(full)][0]))
                else: c["other"] += 1; oth.append("%s (%s)" % (full, mode))
            rows.append((name, sum(c.values()), c["package"], c["repo"], c["same-name"], c["other"], c["link"], dict(modes))); others[name] = oth
        print("   %-22s %8s %8s %6s %10s %7s %6s" % ("event", "entries", "package", "repo", "same-name", "other", "links"))
        for r in rows:
            note = ("modes of the repository files: " + ", ".join("%s x%d" % kv for kv in sorted(r[7].items()))) if r[7] else ""
            print("   %-22s %8d %8d %6d %10d %7d %6d   %s" % (r[0], r[1], r[2], r[3], r[4], r[5], r[6], note))
        for name, oth in others.items():
            if oth:
                print("\n   %s: %d file(s) that are neither a package's nor equal to a repository file (first %d):" % (name, len(oth), min(a.show, len(oth))))
                for x in oth[:a.show]: print("      " + x)
        if a.candidates:
            with open(a.candidates, "w", encoding="utf-8") as o:
                o.write("event\tdestination\tmode\trepo_path\n")
                for t in cands: o.write("\t".join(t) + "\n")
            ok("%d files that equal a repository file, with their destination and mode, are in %s" % (len(cands), a.candidates))
    print()
    if bad[0]: print("R4-COMPARE-FAILED (%d)" % bad[0]); return 1
    print("R4-COMPARE-OK"); return 0

if __name__ == "__main__": sys.exit(main())
