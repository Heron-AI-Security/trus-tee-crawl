#!/usr/bin/env bash
# Step R4.0 rehearsal (no cloud, seconds): the ground-truth tools on a FAKE root, against an INDEPENDENT recomputation (Python, not treehash.sh), and every deliberate fault must be caught.
#   bash r4-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; T="$K/ops/image/test"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "   ok:   $1"; P=$((P+1)); else echo "   FAIL: $1"; F=$((F+1)); fi; }
say() { echo; echo "== $*"; }
say "a fake root with a folder, a folder with a skipped part, a single file and a 'package' folder"
R="$W/root"; mkdir -p "$R/usr/local/lib/tc/units" "$R/etc/tc/crawl" "$R/etc/tc/skipme" "$R/usr/bin" "$R/opt/fake" "$R/var/lib/dpkg/info" "$R/etc"
printf '#!/bin/sh\necho a\n' > "$R/usr/local/lib/tc/a.sh"; chmod 755 "$R/usr/local/lib/tc/a.sh"; printf 'print(1)\n' > "$R/usr/local/lib/tc/b.py"; chmod 644 "$R/usr/local/lib/tc/b.py"
printf 'unit\n' > "$R/usr/local/lib/tc/units/x.service"; ln -s a.sh "$R/usr/local/lib/tc/link.sh"
printf 'conf\n' > "$R/etc/tc/c.conf"; printf 'seeds\n' > "$R/etc/tc/crawl/seeds.txt"; printf 'runtime\n' > "$R/etc/tc/skipme/state"; printf 'wg binary\n' > "$R/usr/bin/fakewg"; chmod 755 "$R/usr/bin/fakewg"
printf 'package file\n' > "$R/opt/fake/p1"; printf '/opt/fake\n/opt/fake/p1\n' > "$R/var/lib/dpkg/info/fake.list"; printf 'NAME="Fake"\n' > "$R/etc/os-release"
printf 'tc-lib\t/usr/local/lib/tc\ntc-conf\t/etc/tc\tskipme\nwg\t/usr/bin/fakewg\npkgdir\t/opt/fake\n' > "$R/measured.txt"
OUT="$W/out"; R4_ROOT="$R" R4_LIST="$R/measured.txt" R4_TREEHASH="$K/attest/measure/treehash.sh" bash "$T/r4-manifest.sh" "$OUT" > "$W/m.log" 2>&1; RC=$?
[ "$RC" = 0 ] && grep -q '^R4-MANIFEST-OK events=4 ' "$W/m.log" && chk "r4-manifest.sh runs on the fake root and reports 4 events" ok || { chk "r4-manifest.sh failed: $(tail -3 "$W/m.log" | tr '\n' ' ')" no; }
[ -s "$OUT/SHA256SUMS" ] && [ -s "$OUT/packages.tsv" ] && [ -s "$OUT/dpkg-files.txt" ] && [ -s "$OUT/os.txt" ] && chk "it also wrote the checksums, the packages, the files that packages own and the kernel and os notes" ok || chk "an expected output file is missing or empty" no
say "the digests equal an INDEPENDENT recomputation (Python; the algorithm of treehash.sh written again, and the rule of tc-extend.sh for a single file)"
python3 - "$R" "$OUT" > "$W/py.txt" 2>&1 <<'PYEOF'
import hashlib, os, stat, sys
R, OUT = sys.argv[1], sys.argv[2]
def tree(d, skips):
    ent = []
    for root, dirs, files in os.walk(d):
        for f in files:
            p = os.path.join(root, f); rel = "./" + os.path.relpath(p, d)
            if any(rel == "./" + s or rel.startswith("./" + s + "/") for s in skips): continue
            ent.append((rel, p))
    out = ""
    for rel, p in sorted(ent, key=lambda e: e[0].encode()):
        if os.path.islink(p): out += "L %s -> %s\n" % (rel, os.readlink(p))
        else: out += "F %o %s %s\n" % (stat.S_IMODE(os.stat(p).st_mode), hashlib.sha384(open(p, "rb").read()).hexdigest(), rel)
    return hashlib.sha384(out.encode()).hexdigest()
want = {"tc-lib": tree(R + "/usr/local/lib/tc", []), "tc-conf": tree(R + "/etc/tc", ["skipme"]), "wg": hashlib.sha384(open(R + "/usr/bin/fakewg", "rb").read()).hexdigest(), "pkgdir": tree(R + "/opt/fake", [])}
got = {l.split("\t")[0]: l.split("\t")[1] for l in open(OUT + "/events.tsv")}
for k, v in want.items(): print("MATCH" if got.get(k) == v else "DIFF", k)
PYEOF
[ "$(grep -c '^MATCH' "$W/py.txt")" = 4 ] && chk "all 4 digests (a folder with a link, a folder with a skip, a single file, a plain folder) equal the independent recomputation" ok || chk "a digest differs from the independent recomputation: $(grep -v '^MATCH' "$W/py.txt" | tr '\n' ' ')" no
grep -q 'state' "$OUT/manifests/tc-conf.manifest" && chk "the skipped part is in the manifest" no || chk "the skipped part (skipme) is not in the manifest" ok
say "the comparison against a reference built from the right digests"
python3 - "$OUT" "$W/ref.json" <<'PYEOF'
import json, sys
ev = [l.rstrip("\n").split("\t") for l in open(sys.argv[1] + "/events.tsv")]
json.dump({"image": "fake", "events_in_order": [e[0] for e in ev] + ["fleet", "fleet-conf"], "stable_events": {e[0]: e[1] for e in ev}, "per_run_events": ["fleet", "fleet-conf"]}, open(sys.argv[2], "w"))
PYEOF
python3 "$T/r4-compare.py" "$OUT" --reference "$W/ref.json" > "$W/c.txt" 2>&1; RC=$?
[ "$RC" = 0 ] && grep -q 'GROUND-TRUTH-OK: 4 of 4' "$W/c.txt" && grep -q '^R4-COMPARE-OK' "$W/c.txt" && chk "the comparison passes: GROUND-TRUTH-OK: 4 of 4 stable events equal" ok || { chk "the comparison should pass: $(tail -4 "$W/c.txt" | tr '\n' ' ')" no; }
say "deliberate faults: each must be caught"
mut() { rm -rf "$W/m"; cp -r "$OUT" "$W/m"; }
mut; python3 - "$W/ref.json" "$W/ref2.json" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1])); r["stable_events"]["wg"] = "0" * 96; json.dump(r, open(sys.argv[2], "w"))
PYEOF
python3 "$T/r4-compare.py" "$OUT" --reference "$W/ref2.json" > "$W/c.txt" 2>&1; [ $? = 1 ] && grep -q 'wg: the image gives' "$W/c.txt" && chk "fault 1: a digest that the cluster did not report is refused (and named)" ok || chk "fault 1 not caught" no
python3 - "$W/ref.json" "$W/ref3.json" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1])); r["events_in_order"].insert(0, "ghost"); r["stable_events"]["ghost"] = "1" * 96; json.dump(r, open(sys.argv[2], "w"))
PYEOF
python3 "$T/r4-compare.py" "$OUT" --reference "$W/ref3.json" > "$W/c.txt" 2>&1; [ $? = 1 ] && grep -q 'ghost: the reference has it' "$W/c.txt" && chk "fault 2: an event that the reference has and the image's list lacks is refused" ok || chk "fault 2 not caught" no
python3 - "$W/ref.json" "$W/ref4.json" <<'PYEOF'
import json, sys
r = json.load(open(sys.argv[1])); r["events_in_order"].remove("pkgdir"); del r["stable_events"]["pkgdir"]; json.dump(r, open(sys.argv[2], "w"))
PYEOF
python3 "$T/r4-compare.py" "$OUT" --reference "$W/ref4.json" > "$W/c.txt" 2>&1; [ $? = 1 ] && grep -q 'events that the reference lacks: pkgdir' "$W/c.txt" && chk "fault 3: an event in the image's list that the reference lacks is refused" ok || chk "fault 3 not caught" no
mut; head -n 1 "$W/m/manifests/tc-lib.manifest" > "$W/m/x" && mv "$W/m/x" "$W/m/manifests/tc-lib.manifest"; python3 "$T/r4-compare.py" "$W/m" --reference "$W/ref.json" > "$W/c.txt" 2>&1; [ $? = 1 ] && grep -q 'tc-lib: the SHA-384 of the manifest is not the digest' "$W/c.txt" && chk "fault 4: a truncated manifest is refused (it no longer hashes to its digest)" ok || chk "fault 4 not caught" no
mut; echo x >> "$W/m/os.txt"; python3 "$T/r4-compare.py" "$W/m" > "$W/c.txt" 2>&1; [ $? = 1 ] && grep -q 'os.txt differs from its checksum' "$W/c.txt" && chk "fault 5: a file changed in transfer is refused (SHA256SUMS)" ok || chk "fault 5 not caught" no
mut; rm "$W/m/manifests/wg.manifest"; python3 "$T/r4-compare.py" "$W/m" > "$W/c.txt" 2>&1; [ $? = 1 ] && grep -q 'wg: no manifest' "$W/c.txt" && chk "fault 6: a missing manifest is refused" ok || chk "fault 6 not caught" no
say "where the files come from: a repository folder with one equal file and one file of the same name with other content"
mkdir -p "$W/repo/x"; cp "$R/usr/local/lib/tc/a.sh" "$W/repo/x/a.sh"; printf 'print(2)\n' > "$W/repo/x/b.py"
python3 "$T/r4-compare.py" "$OUT" --reference "$W/ref.json" --repo "$W/repo" --candidates "$W/cand.tsv" > "$W/c.txt" 2>&1; RC=$?
[ "$RC" = 0 ] && chk "the comparison with the repository passes" ok || chk "the comparison with the repository failed: $(tail -3 "$W/c.txt" | tr '\n' ' ')" no
grep -E '^   tc-lib ' "$W/c.txt" | awk '{ if ($2==4 && $3==0 && $4==1 && $5==1 && $6==1 && $7==1) exit 0; else exit 1 }' && chk "tc-lib: 4 entries = 1 equal to the repository (a.sh), 1 of the same name with other content (b.py), 1 other (x.service), 1 link" ok || chk "tc-lib classification wrong: $(grep -E '^   tc-lib ' "$W/c.txt")" no
grep -E '^   pkgdir ' "$W/c.txt" | awk '{ if ($3==1 && $2==1) exit 0; else exit 1 }' && chk "pkgdir: the file that a package owns is classified as a package's" ok || chk "pkgdir classification wrong" no
grep -q "b.py (644) same name as x/b.py, other content" "$W/c.txt" && chk "the file of the same name is named with its mode and the repository file" ok || chk "the same-name hint is missing" no
grep -qP '^tc-lib\t/usr/local/lib/tc/a.sh\t755\tx/a.sh$' "$W/cand.tsv" && chk "the install candidates name a.sh with its destination, mode 755 and its repository path" ok || chk "the candidates file is wrong: $(cat "$W/cand.tsv" | tr '\n' '|')" no
say "the driver stages (a dry run prints the commands; nothing is created)"
D="$(DRY=1 IMG=tc-img-seal-5 OUT="$W/outd" REFERENCE="$W/ref.json" timeout 60 bash "$T/f03-drive.sh" manifest manifest-compare 2>&1 | sed 's/\\//g')"
for k in 'r4-manifest.sh /tmp/r4-out' 'gcloud compute scp tc-seal-test:/tmp/r4-out.tgz' 'r4-compare.py' '--candidates' 'F03-DRIVE-DONE'; do grep -qF -- "$k" <<<"$D" && chk "the dry run has: $k" ok || chk "the dry run lacks: $k" no; done
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4-REHEARSAL-PASS" || { echo "R4-REHEARSAL-FAIL"; exit 1; }
