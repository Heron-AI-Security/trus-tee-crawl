#!/usr/bin/env python3
"""Step R4.1 and R4.2, OFFLINE: recompute the measured values of an image from a COMMIT, without booting anything.
   python3 r4-recompute.py --repo TREE [--commit COMMIT] [--recipe DIR] [--reference reference-values.json] [--json OUT]
TREE is a folder with the files of the repository (for example a git archive of a commit). The recipe (default TREE/ops/image/recipe) has install-manifest.tsv (destination, mode, source: where every file
of the image comes from: repo:PATH, repo+strip:PATH (the file after the hook strip of the image build, ADR-075), link:TARGET, commit (/etc/tc/source.txt: the line 'commit ID' of the commit that the image is built from; needs --commit), or input, a small text file that the build generates) and build-inputs.tsv (the SHA-384
of every input, with a note). The list of events is read from the image's own measured list, which the manifest installs from a repository file. For every event that the manifest covers, the digest is computed
exactly as treehash.sh and tc-extend.sh do. Events that it does not cover are named, never guessed. With --reference every covered digest is compared with the value that a real cluster reported.
Exit code 0 when no covered event differs from the reference."""
import sys; sys.dont_write_bytecode = True   # a tool that is run inside a repository must leave no __pycache__ behind (the audit refuses untracked files)
import argparse, collections, json, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from r4lib import sha384, load_strip, stripped_bytes, tree_digest, parse_measured, under_skip, commit_bytes

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--repo", required=True); ap.add_argument("--recipe"); ap.add_argument("--reference"); ap.add_argument("--json"); ap.add_argument("--commit")
    a = ap.parse_args(); R = a.repo; RC = a.recipe or os.path.join(R, "ops/image/recipe"); bad = 0
    try:
        rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(RC, "install-manifest.tsv"), encoding="utf-8") if l.strip() and not l.startswith("#")]
        inputs = {l.split("\t")[0]: l.split("\t")[1] for l in open(os.path.join(RC, "build-inputs.tsv"), encoding="utf-8") if l.strip() and not l.startswith("#")}
    except FileNotFoundError as e: print("R4-RECOMPUTE-FAILED: %s" % e); return 1
    strip = load_strip(R); content = {}; print("== 1. what every destination of the recipe holds (read from the commit)")
    for dest, mode, src in rows:
        kind, _, arg = src.partition(":")
        try:
            if kind == "repo": content[dest] = (mode, sha384(open(os.path.join(R, arg), "rb").read()))
            elif kind == "repo+strip": content[dest] = (mode, sha384(stripped_bytes(strip, os.path.join(R, arg))))
            elif kind == "link": content[dest] = ("L", arg)
            elif kind == "commit":
                if not a.commit: print("   FAIL: %s is recorded from the commit: give --commit (the commit that the image is built from)" % dest); bad += 1; continue
                content[dest] = (mode, sha384(commit_bytes(a.commit)))
            elif kind == "input":
                if dest not in inputs: print("   FAIL: %s: an input with no entry in build-inputs.tsv" % dest); bad += 1; continue
                content[dest] = (mode, inputs[dest])
            else: print("   FAIL: %s: the source '%s' is not one of repo:, repo+strip:, link:, commit, input" % (dest, src)); bad += 1
        except (OSError, UnicodeError) as e: print("   FAIL: %s: cannot read %s from the commit (%s)" % (dest, src, e)); bad += 1
    kinds = collections.Counter(s.split(":")[0] for _, _, s in rows); print("   %d destinations: %s" % (len(rows), ", ".join("%s %d" % kv for kv in sorted(kinds.items()))))
    lst = [d for d in content if d == "/etc/tc/measured-paths.txt"]
    if not lst: print("R4-RECOMPUTE-FAILED: the manifest does not install /etc/tc/measured-paths.txt, so the list of events is unknown"); return 1
    src_list = [s for d, _, s in rows if d == lst[0]][0]; kind, _, arg = src_list.partition(":")
    if kind != "repo": print("R4-RECOMPUTE-FAILED: the measured list must come from a repository file (it is %s)" % src_list); return 1
    events = parse_measured(open(os.path.join(R, arg), encoding="utf-8").read()); print("   the list of events is %s: %d events" % (arg, len(events)))
    ref = None
    if a.reference: ref = json.load(open(a.reference, encoding="utf-8")); stable = ref["stable_events"]
    print("\n== 2. the events, recomputed from the commit" + (" and compared with %s" % os.path.basename(a.reference) if ref else ""))
    done = collections.OrderedDict(); uncovered = []
    for name, path, skips in events:
        if path in content:
            m, h = content[path]; digest = h if m != "L" else None; ent = 1
        else:
            ents = []
            for d, (m, h) in content.items():
                if d.startswith(path.rstrip("/") + "/"):
                    rel = d[len(path.rstrip("/")) + 1:]
                    if not under_skip(rel, skips): ents.append((rel, m, h))
            if not ents: uncovered.append(name); continue
            digest = tree_digest(ents); ent = len(ents)
        done[name] = digest
        if ref is None: print("   %-22s %s... (%d entries)" % (name, digest[:16], ent))
        elif name not in stable: print("   FAIL: %-22s is not in the reference" % name); bad += 1
        elif stable[name] != digest: print("   FAIL: %-22s recomputed %s..., the cluster reported %s..." % (name, digest[:16], stable[name][:16])); bad += 1
        else: print("   ok:   %-22s %s... equals the cluster's value (%d entries)" % (name, digest[:16], ent))
    if uncovered: print("\n   not covered by the recipe yet (named, never guessed): %s" % ", ".join(uncovered))
    if a.json: json.dump({"commit": a.commit, "stable_events": done, "not_covered": uncovered}, open(a.json, "w"), indent=1)
    print()
    if bad: print("R4-RECOMPUTE-FAILED (%d)" % bad); return 1
    print("R4-RECOMPUTE-OK: %d of %d events recomputed from the commit%s; %d not covered yet" % (len(done), len(events), " and equal to the cluster's values" if ref else "", len(uncovered))); return 0

if __name__ == "__main__": sys.exit(main())
