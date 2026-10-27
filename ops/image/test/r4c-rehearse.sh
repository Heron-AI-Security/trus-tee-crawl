#!/usr/bin/env bash
# Step R4.2 and the experiment, rehearsal (no cloud, seconds): the archive of a named commit (a REAL git archive), the commit recorded in the image and in the recipe, the diff of two builds, and the driver's new settings.
#   bash r4c-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; T="$K/ops/image/test"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "   ok:   $1"; P=$((P+1)); else echo "   FAIL: $1"; F=$((F+1)); fi; }
say() { echo; echo "== $*"; }
say "the archive of a named commit (a real git archive)"
( cd "$W" && git init -q -b main r && cd r && git config user.email t@t && git config user.name t && mkdir -p ops/image && echo a > ops/image/a.txt && ln -s a.txt ops/image/link && git add -A && git commit -q -m one ) || { echo "git is needed for this rehearsal"; exit 1; }
C="$(git -C "$W/r" rev-parse HEAD)"; TR="$(git -C "$W/r" rev-parse 'HEAD^{tree}')"; git -C "$W/r" archive --format=tar.gz -o "$W/c.tar.gz" "$C"; git -C "$W/r" archive --format=tar.gz -o "$W/t.tar.gz" "$TR"; SHA="$(sha256sum "$W/c.tar.gz" | cut -d' ' -f1)"
out="$(python3 "$T/r4-archive.py" "$W/c.tar.gz" --sha256 "$SHA" --expect "$C" --extract "$W/x" --commit-file "$W/COMMIT" 2>&1)"; [ $? = 0 ] && grep -q "^ARCHIVE-OK commit=$C" <<<"$out" && [ "$(cat "$W/COMMIT")" = "$C" ] && [ -f "$W/x/ops/image/a.txt" ] && chk "a good archive: the commit id is read from its header, the files are unpacked, the COMMIT file holds the id" ok || chk "a good archive failed: $out" no
python3 "$T/r4-archive.py" "$W/c.tar.gz" --sha256 "$(printf '0%.0s' $(seq 64))" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'the SHA-256 of the file is' "$W/o.txt" && chk "fault: a file whose SHA-256 is not the expected one is refused" ok || chk "fault sha not caught" no
python3 "$T/r4-archive.py" "$W/c.tar.gz" --expect "$(printf '1%.0s' $(seq 40))" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'expected 1111' "$W/o.txt" && chk "fault: an archive of another commit than the expected one is refused" ok || chk "fault commit not caught" no
out="$(python3 "$T/r4-archive.py" "$W/c.tar.gz" --expect "${C:0:9}" --commit-file "$W/COMMIT2" 2>&1)"; [ $? = 0 ] && [ "$(cat "$W/COMMIT2")" = "$C" ] && chk "the expected commit may be given as its first 9 characters; the COMMIT file still holds the full id from the header" ok || chk "a 9-character expectation failed: $out" no
python3 "$T/r4-archive.py" "$W/c.tar.gz" --expect "${C:0:8}" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'at least its first 9 hex characters' "$W/o.txt" && chk "fault: an expectation shorter than 9 characters is refused" ok || chk "short expectation not refused" no
WP="$([ "${C:0:1}" = 0 ] && echo 1 || echo 0)${C:1:8}"; python3 "$T/r4-archive.py" "$W/c.tar.gz" --expect "$WP" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'expected' "$W/o.txt" && chk "fault: a 9-character expectation that does not match is refused" ok || chk "wrong prefix not refused" no
python3 "$T/r4-archive.py" "$W/t.tar.gz" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'has no commit id in its header' "$W/o.txt" && chk "fault: an archive of a tree (no commit in its header) is refused" ok || chk "fault tree not caught" no
python3 - "$W" <<'PYEOF'
import tarfile, io, sys
t = tarfile.open(sys.argv[1] + "/evil.tar", "w", format=tarfile.PAX_FORMAT, pax_headers={"comment": "a" * 40}); i = tarfile.TarInfo("../escape.txt"); i.size = 1; t.addfile(i, io.BytesIO(b"x")); t.close()
PYEOF
python3 "$T/r4-archive.py" "$W/evil.tar" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q "has an absolute path or '..'" "$W/o.txt" && chk "fault: an archive with a path that escapes is refused" ok || chk "fault traversal not caught" no
python3 "$T/r4-archive.py" "$W/c.tar.gz" --extract "$W/x" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'is not empty' "$W/o.txt" && chk "fault: unpacking into a folder that is not empty is refused" ok || chk "fault non-empty not caught" no
say "the commit in the image (tc-image-source.sh) and in the recipe"
mkimg() { # $1 name, $2 commit line ; builds a small fake image that is installed from a fake repo
  local I="$W/$1"; rm -rf "$I"; mkdir -p "$I/etc/tc" "$I/usr/local/lib/tc" "$I/var/lib/dpkg/info" "$I/etc"; printf 'conf\n' > "$I/etc/tc/c.conf"; printf '#!/bin/sh\necho a\n' > "$I/usr/local/lib/tc/a.sh"; chmod 755 "$I/usr/local/lib/tc/a.sh"; printf 'NAME="Fake"\nVERSION="1"\n' > "$I/etc/os-release"
  printf 'source\t/etc/tc/source.txt\nlib\t/usr/local/lib/tc\nconf\t/etc/tc\n' > "$I/etc/tc/measured-paths.txt"; mkdir -p "$W/kit-$1"; [ -z "$2" ] || echo "$2" > "$W/kit-$1/COMMIT"; }
mkimg a "$C"; mkdir -p "$W/kit-a"; out="$(TC_ROOT="$W/a" TC_SUDO="" bash "$K/ops/image/build/tc-image-source.sh" "$W/kit-a" 2>&1)"; [ $? = 0 ] && [ "$(cat "$W/a/etc/tc/source.txt")" = "commit $C" ] && grep -q '^SOURCE-OK' <<<"$out" && chk "tc-image-source.sh writes 'commit <id>' into /etc/tc/source.txt" ok || chk "tc-image-source.sh failed: $out" no
mkimg b ""; out="$(TC_ROOT="$W/b" TC_SUDO="" bash "$K/ops/image/build/tc-image-source.sh" "$W/kit-b" 2>&1)"; [ $? != 0 ] && grep -q 'SOURCE-STOP: no COMMIT file' <<<"$out" && chk "fault: no COMMIT file stops the build (fail closed)" ok || chk "no-commit not refused" no
# the ground truth of the fake image, the recipe, and the recomputation with and without the commit
RP="$W/repo"; mkdir -p "$RP/ops/image/build" "$RP/ops/image/rootfs/etc/tc" "$RP/ops/image/rootfs/usr/local/lib/tc" "$RP/attest/measure"; cp "$K/ops/image/build/tc-strip-hooks.py" "$RP/ops/image/build/"; cp "$K/attest/measure/treehash.sh" "$RP/attest/measure/"
printf 'conf\n' > "$RP/ops/image/rootfs/etc/tc/c.conf"; printf '#!/bin/sh\necho a\n' > "$RP/ops/image/rootfs/usr/local/lib/tc/a.sh"; cp "$W/a/etc/tc/measured-paths.txt" "$RP/ops/image/rootfs/etc/tc/measured-paths-f1.txt"; cp "$W/a/etc/tc/measured-paths.txt" "$W/a/etc/tc/measured-paths-x.txt"; rm "$W/a/etc/tc/measured-paths-x.txt"
EVA="$W/eva"; R4_ROOT="$W/a" R4_LIST="$W/a/etc/tc/measured-paths.txt" R4_TREEHASH="$K/attest/measure/treehash.sh" bash "$T/r4-manifest.sh" "$EVA" > "$W/m.log" 2>&1; [ -s "$EVA/source.txt" ] && [ -s "$EVA/files-meta.tsv" ] && chk "r4-manifest.sh also records the commit file and the size and time of every file" ok || chk "source.txt or files-meta.tsv missing" no
python3 - "$EVA" "$W/ref.json" <<'PYEOF'
import json, sys
ev = [l.rstrip("\n").split("\t") for l in open(sys.argv[1] + "/events.tsv")]
json.dump({"events_in_order": [e[0] for e in ev], "stable_events": {e[0]: e[1] for e in ev}, "per_run_events": []}, open(sys.argv[2], "w"))
PYEOF
# the measured list of the fake image is a repo file in the recipe (as in the real one)
python3 "$T/r4-derive.py" --evidence "$EVA" --repo "$RP" --out "$RP/ops/image/recipe" > "$W/d.txt" 2>&1; M="$RP/ops/image/recipe/install-manifest.tsv"
grep -qP '^/etc/tc/source.txt\t644\tcommit$' "$M" && grep -q "commit recorded in the image: $C" "$W/d.txt" && chk "the derivation traces /etc/tc/source.txt to the kind 'commit' and prints the commit" ok || chk "source.txt not traced as commit: $(grep source.txt "$M"; tail -3 "$W/d.txt" | tr '\n' ' ')" no
python3 "$T/r4-recompute.py" --repo "$RP" --commit "$C" --reference "$W/ref.json" > "$W/r.txt" 2>&1; [ $? = 0 ] && grep -q 'R4-RECOMPUTE-OK: 3 of 3 events' "$W/r.txt" && chk "recomputed from the commit: all 3 events (source, lib, conf) equal the ground truth" ok || chk "recompute with the commit failed: $(tail -4 "$W/r.txt" | tr '\n' ' ')" no
python3 "$T/r4-recompute.py" --repo "$RP" --reference "$W/ref.json" > "$W/r.txt" 2>&1; [ $? = 1 ] && grep -q 'give --commit' "$W/r.txt" && chk "fault: a recipe with a commit row and no --commit is refused" ok || chk "missing --commit not refused" no
python3 "$T/r4-recompute.py" --repo "$RP" --commit "$(printf '2%.0s' $(seq 40))" --reference "$W/ref.json" > "$W/r.txt" 2>&1; [ $? = 1 ] && grep -q 'FAIL: source ' "$W/r.txt" && grep -q 'FAIL: conf ' "$W/r.txt" && chk "fault: another commit gives another source digest, and tc-conf (which contains source.txt) differs too" ok || chk "wrong commit not caught: $(tail -4 "$W/r.txt" | tr '\n' ' ')" no
say "the diff of two builds of the same commit"
mkimg c "$C"; TC_ROOT="$W/c" TC_SUDO="" bash "$K/ops/image/build/tc-image-source.sh" "$W/kit-c" > /dev/null 2>&1; EVB="$W/evb"; R4_ROOT="$W/c" R4_LIST="$W/c/etc/tc/measured-paths.txt" R4_TREEHASH="$K/attest/measure/treehash.sh" bash "$T/r4-manifest.sh" "$EVB" > /dev/null 2>&1
python3 "$T/r4-diff.py" "$EVA" "$EVB" > "$W/df.txt" 2>&1; [ $? = 0 ] && grep -q 'R4-DIFF: 3 of 3 events identical; different: none' "$W/df.txt" && grep -q 'commit recorded:.*SAME' "$W/df.txt" && chk "two identical builds: all 3 events identical, the same commit" ok || chk "identical builds not reported identical: $(tail -3 "$W/df.txt" | tr '\n' ' ')" no
# two builds of the same commit that differ: a script of the same size with another content, a package file with another content, and an extra file in the second build
for n in d1 d2; do mkimg $n "$C"; TC_ROOT="$W/$n" TC_SUDO="" bash "$K/ops/image/build/tc-image-source.sh" "$W/kit-$n" > /dev/null 2>&1; printf '/usr/local/lib/tc/pkg.bin\n' > "$W/$n/var/lib/dpkg/info/x.list"; done
printf 'p1\n' > "$W/d1/usr/local/lib/tc/pkg.bin"; printf 'p2\n' > "$W/d2/usr/local/lib/tc/pkg.bin"; printf '#!/bin/sh\necho b\n' > "$W/d2/usr/local/lib/tc/a.sh"; chmod 755 "$W/d2/usr/local/lib/tc/a.sh"; printf 'extra\n' > "$W/d2/usr/local/lib/tc/new.jar"
for n in d1 d2; do R4_ROOT="$W/$n" R4_LIST="$W/$n/etc/tc/measured-paths.txt" R4_TREEHASH="$K/attest/measure/treehash.sh" bash "$T/r4-manifest.sh" "$W/ev$n" > /dev/null 2>&1; done
python3 "$T/r4-diff.py" "$W/evd1" "$W/evd2" --out "$W/report.txt" > "$W/df.txt" 2>&1
grep -q 'DIFFERENT  lib ' "$W/df.txt" && grep -q 'identical  conf ' "$W/df.txt" && chk "a changed build: lib is DIFFERENT and conf stays identical" ok || chk "event comparison wrong: $(grep -E 'DIFFERENT|identical' "$W/df.txt" | tr '\n' '|' | cut -c1-200)" no
grep -q 'a.sh .*same size (.* bytes), other content: a timestamp or an ordering inside' "$W/df.txt" && chk "a changed file of the same size is explained as a timestamp or an ordering" ok || chk "same-size hint missing: $(grep 'a.sh' "$W/df.txt" | head -2)" no
grep -q 'pkg.bin .*a package file' "$W/df.txt" && chk "a changed file that a package owns is explained as a package file" ok || chk "package hint missing: $(grep 'pkg.bin' "$W/df.txt" | head -2)" no
grep -q 'new.jar .*only in B' "$W/df.txt" && chk "an extra file in the second build is named" ok || chk "added file not named" no
grep -q 'R4-DIFF: 2 of 3 events identical; different: lib' "$W/df.txt" && [ -s "$W/report.txt" ] && chk "the summary line and the report file are written" ok || chk "summary wrong: $(tail -1 "$W/df.txt")" no
mkdir -p "$W/evd2"; cp -r "$EVB"/. "$W/evd2"/; printf 'commit %s\n' "$(printf '3%.0s' $(seq 40))" > "$W/evd2/source.txt"; python3 "$T/r4-diff.py" "$EVA" "$W/evd2" > "$W/df2.txt" 2>&1; grep -q 'commit recorded:.*DIFFERENT OR MISSING' "$W/df2.txt" && chk "another recorded commit is flagged in the inputs" ok || chk "commit difference not flagged" no
say "the driver: pinned base image, the commit shipped with the kit, per-VM temp files, the manifest of a builder"
D="$(DRY=1 BUILDER=tc-r4-a OUT="$W/outd" BASE_IMAGE=ubuntu-2204-jammy-v20261015 COMMIT_FILE="$W/COMMIT" timeout 60 bash "$T/f03-drive.sh" builder ship-builder 2>&1 | sed 's/\\//g')"
for k in '--image=ubuntu-2204-jammy-v20261015' '--image-project=ubuntu-os-cloud' '/tmp/f03-ship-tc-r4-a.tgz' "$W/COMMIT" 'tc-r4-a:~/f03/COMMIT'; do grep -qF -- "$k" <<<"$D" && chk "the dry run has: $k" ok || chk "the dry run lacks: $k" no; done
DB="$(DRY=1 BUILDER=tc-r4-A OUT="$W/outd" timeout 60 bash "$T/f03-drive.sh" builder 2>&1)"; rcb=$?
[ "$rcb" != 0 ] && grep -q "is not a valid VM name" <<<"$DB" && ! grep -q "gcloud compute instances create" <<<"$DB" && chk "fault: a builder name with an upper-case letter is refused locally, before any cloud call (the cloud refused 'tc-r4-A')" ok || chk "an upper-case builder name was not refused locally" no
DB="$(DRY=1 BUILDER=tc-r4-a OUT="$W/outd" timeout 60 bash "$T/f03-drive.sh" builder 2>&1)"; grep -q "gcloud compute instances create tc-r4-a" <<<"$DB" && chk "a lower-case builder name goes through to the create command" ok || chk "a valid builder name was refused" no
D="$(DRY=1 BUILDER=tc-r4-a MANIFEST_VM=tc-r4-a OUT="$W/outd" timeout 60 bash "$T/f03-drive.sh" manifest 2>&1 | sed 's/\\//g')"
grep -qF 'ssh tc-r4-a: sudo bash ~/f03/ops/image/test/r4-manifest.sh' <<<"$D" && grep -qF 'scp tc-r4-a:/tmp/r4-out.tgz' <<<"$D" && chk "the manifest stage runs on the builder when MANIFEST_VM names it" ok || chk "MANIFEST_VM not honoured: $(grep -c DRY <<<"$D") dry lines" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4C-REHEARSAL-PASS" || { echo "R4C-REHEARSAL-FAIL"; exit 1; }
