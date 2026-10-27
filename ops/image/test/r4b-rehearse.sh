#!/usr/bin/env bash
# Step R4.1 rehearsal (no cloud, seconds): a FAKE image is built the way the real one is (installed with modes, one script rewritten by the hook strip, one generated file, a package file, a runtime file in a skipped
# folder), its ground truth is taken, the recipe is derived from it, and the recipe is recomputed from the commit alone. Every deliberate fault must be caught, and a decoy fixture must never be trusted.
#   bash r4b-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; T="$K/ops/image/test"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "   ok:   $1"; P=$((P+1)); else echo "   FAIL: $1"; F=$((F+1)); fi; }
say() { echo; echo "== $*"; }
say "the hook strip: each rule on a sample (the same file that the image build runs)"
python3 -B - "$K" > "$W/strip.txt" 2>&1 <<'PYEOF'
import sys, importlib.util
spec = importlib.util.spec_from_file_location("s", sys.argv[1] + "/ops/image/build/tc-strip-hooks.py"); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
t = lambda a, b, n: print(("PASS " if m.strip_text(a) == b else "FAIL ") + n)
t('X=${TC_FOO:-/real}\n', 'X=/real\n', "a hook with :- becomes its default")
t('X=${TC_FOO-/real}\n', 'X=/real\n', "a hook with - becomes its default")
t('echo ${TC_LOG:-x}\n', 'echo ${TC_LOG:-x}\n', "TC_LOG is kept")
t('# TC_FOO redirects the path\nkeep\n', 'keep\n', "a comment about a hook is dropped")
t('# TC_LOG is the log\nkeep\n', '# TC_LOG is the log\nkeep\n', "a comment about TC_LOG is kept")
t('if [ -n "${TC_WRITE:-}" ]; then printf x | $TC_WRITE\nelse printf x | dd; fi\n', 'printf x | dd\n', "the command hook is removed with its branch")
t('run TC_RTMR3="$RT" cmd\n', 'run cmd\n', "TC_RTMR3 is removed")
PYEOF
[ "$(grep -c '^PASS' "$W/strip.txt")" = 7 ] && chk "all 7 strip rules behave" ok || chk "a strip rule is wrong: $(grep FAIL "$W/strip.txt" | tr '\n' ' ')" no
say "a fake repository (with a decoy fixture) and a fake image installed from it"
RP="$W/repo"; I="$W/img"; mkdir -p "$RP/ops/image/build" "$RP/ops/image/rootfs/usr/local/lib/tc" "$RP/ops/image/rootfs/etc/tc/crawl" "$RP/attest/measure" "$RP/ops/image/test/fixtures"
cp "$K/ops/image/build/tc-strip-hooks.py" "$RP/ops/image/build/"; cp "$K/attest/measure/treehash.sh" "$RP/attest/measure/"
printf '#!/bin/sh\n# TC_FOO redirects the path\nX=${TC_FOO:-/real/path}\necho ${TC_LOG:-}\n' > "$RP/ops/image/rootfs/usr/local/lib/tc/hook.sh"; printf '#!/bin/sh\necho plain\n' > "$RP/ops/image/rootfs/usr/local/lib/tc/plain.sh"
printf 'conf\n' > "$RP/ops/image/rootfs/etc/tc/c.conf"; printf 'seeds\n' > "$RP/ops/image/rootfs/etc/tc/crawl/seeds.txt"
printf 'lib\t/usr/local/lib/tc\nconf\t/etc/tc\tskipme\ngen\t/etc/tc/gen.txt\nwg\t/usr/bin/fakewg\npk\t/opt/fake\n' > "$RP/ops/image/rootfs/etc/tc/measured-paths-f1.txt"
printf 'generated v1\n' > "$RP/ops/image/test/fixtures/gen.txt"      # the decoy: the same content as the generated file, in a fixture folder
mkdir -p "$I/usr/local/lib/tc" "$I/etc/tc/crawl" "$I/etc/tc/skipme" "$I/usr/bin" "$I/opt/fake" "$I/var/lib/dpkg/info" "$I/etc"
cp "$RP/ops/image/rootfs/usr/local/lib/tc/hook.sh" "$W/h.sh"; python3 "$RP/ops/image/build/tc-strip-hooks.py" "$W/h.sh"; install -m 0755 "$W/h.sh" "$I/usr/local/lib/tc/hook.sh"
install -m 0755 "$RP/ops/image/rootfs/usr/local/lib/tc/plain.sh" "$I/usr/local/lib/tc/plain.sh"; install -m 0755 "$RP/attest/measure/treehash.sh" "$I/usr/local/lib/tc/treehash.sh"
install -m 0644 "$RP/ops/image/rootfs/etc/tc/measured-paths-f1.txt" "$I/etc/tc/measured-paths.txt"; install -m 0644 "$RP/ops/image/rootfs/etc/tc/c.conf" "$I/etc/tc/c.conf"; install -m 0644 "$RP/ops/image/rootfs/etc/tc/crawl/seeds.txt" "$I/etc/tc/crawl/seeds.txt"
printf 'generated v1\n' > "$I/etc/tc/gen.txt"; chmod 644 "$I/etc/tc/gen.txt"; printf 'runtime\n' > "$I/etc/tc/skipme/state"
printf 'wg binary\n' > "$I/usr/bin/fakewg"; chmod 755 "$I/usr/bin/fakewg"; printf 'package file\n' > "$I/opt/fake/p1"; printf '/usr/bin/fakewg\n/opt/fake\n/opt/fake/p1\n' > "$I/var/lib/dpkg/info/fake.list"; printf 'NAME="Fake"\n' > "$I/etc/os-release"
EV="$W/ev"; R4_ROOT="$I" R4_LIST="$I/etc/tc/measured-paths.txt" R4_TREEHASH="$K/attest/measure/treehash.sh" bash "$T/r4-manifest.sh" "$EV" > "$W/m.log" 2>&1 && chk "the ground truth of the fake image is taken (5 events)" ok || chk "r4-manifest.sh failed: $(tail -2 "$W/m.log" | tr '\n' ' ')" no
python3 - "$EV" "$W/ref.json" <<'PYEOF'
import json, sys
ev = [l.rstrip("\n").split("\t") for l in open(sys.argv[1] + "/events.tsv")]
json.dump({"events_in_order": [e[0] for e in ev], "stable_events": {e[0]: e[1] for e in ev}, "per_run_events": []}, open(sys.argv[2], "w"))
PYEOF
say "derive the recipe from the ground truth"
python3 "$T/r4-derive.py" --evidence "$EV" --repo "$RP" --out "$RP/ops/image/recipe" --allow-input /etc/tc/gen.txt > "$W/d.txt" 2>&1; RC=$?
[ "$RC" = 0 ] && grep -q 'R4-DERIVE-OK covered=3/5' "$W/d.txt" && chk "R4-DERIVE-OK covered=3/5: lib, conf and gen are covered; wg and pk (packages) are named as not covered" ok || chk "derive: $(tail -4 "$W/d.txt" | tr '\n' ' ')" no
grep -q '^not covered: wg, pk$' "$W/d.txt" && chk "the events of packages are listed as not covered, with their names" ok || chk "the not-covered list is wrong: $(grep '^not covered' "$W/d.txt")" no
M="$RP/ops/image/recipe/install-manifest.tsv"
grep -qP '^/usr/local/lib/tc/hook.sh\t755\trepo\+strip:ops/image/rootfs/usr/local/lib/tc/hook.sh$' "$M" && chk "the rewritten script is traced as repo+strip (verified by applying the strip, not assumed)" ok || chk "hook.sh is not repo+strip: $(grep hook.sh "$M")" no
grep -qP '^/etc/tc/gen.txt\t644\tinput$' "$M" && chk "the generated file is an input, and the decoy fixture with the same content is NOT trusted as a source" ok || chk "gen.txt row wrong: $(grep gen.txt "$M")" no
! grep -q 'fixtures' "$M" && chk "no row of the recipe points into a fixture folder" ok || chk "a row points into a fixture folder" no
! grep -q 'skipme' "$M" && chk "the runtime file in the skipped folder is not in the recipe" ok || chk "skipme is in the recipe" no
say "recompute from the commit alone"
python3 "$T/r4-recompute.py" --repo "$RP" --reference "$W/ref.json" --json "$W/out.json" > "$W/r.txt" 2>&1; RC=$?
[ "$RC" = 0 ] && grep -q 'R4-RECOMPUTE-OK: 3 of 5 events recomputed from the commit and equal to the cluster' "$W/r.txt" && chk "3 of 5 events are recomputed from the commit and equal the ground truth; 2 are not covered" ok || chk "recompute: $(tail -5 "$W/r.txt" | tr '\n' ' ')" no
grep -q 'not covered by the recipe yet (named, never guessed): wg, pk' "$W/r.txt" && chk "the two events that the recipe does not cover are named" ok || chk "the uncovered events are not named" no
say "the tools leave nothing behind in the repository (the audit refuses untracked files)"
find "$RP" -name __pycache__ -type d -prune -exec rm -rf {} + 2>/dev/null; python3 "$T/r4-recompute.py" --repo "$RP" --reference "$W/ref.json" > /dev/null 2>&1; python3 "$T/r4-derive.py" --evidence "$EV" --repo "$RP" --out "$W/recipe-x" --allow-input /etc/tc/gen.txt > /dev/null 2>&1; python3 "$T/r4-compare.py" "$EV" --repo "$RP" > /dev/null 2>&1
[ -z "$(find "$RP" "$T" -name __pycache__ -type d 2>/dev/null | head -1)" ] && chk "r4-recompute.py, r4-derive.py and r4-compare.py created no __pycache__ in the repository or beside themselves" ok || chk "a tool left a __pycache__ behind: $(find "$RP" "$T" -name __pycache__ | head -2 | tr '\n' ' ')" no
say "deliberate faults: each must be caught"
cp -r "$RP" "$W/rp0"; fault() { rm -rf "$RP"; cp -r "$W/rp0" "$RP"; }
fault; printf '#!/bin/sh\necho CHANGED\n' > "$RP/ops/image/rootfs/usr/local/lib/tc/plain.sh"; python3 "$T/r4-recompute.py" --repo "$RP" --reference "$W/ref.json" > "$W/r.txt" 2>&1; [ $? = 1 ] && grep -q 'FAIL: lib ' "$W/r.txt" && chk "fault 1: a changed repository file changes the recomputed digest and is refused" ok || chk "fault 1 not caught" no
fault; sed -i 's#^\(/usr/local/lib/tc/plain.sh\)\t755#\1\t644#' "$RP/ops/image/recipe/install-manifest.tsv"; python3 "$T/r4-recompute.py" --repo "$RP" --reference "$W/ref.json" > "$W/r.txt" 2>&1; [ $? = 1 ] && grep -q 'FAIL: lib ' "$W/r.txt" && chk "fault 2: a changed mode (755 to 644) is refused" ok || chk "fault 2 not caught" no
fault; sed -i '\#^/etc/tc/c.conf#d' "$RP/ops/image/recipe/install-manifest.tsv"; python3 "$T/r4-recompute.py" --repo "$RP" --reference "$W/ref.json" > "$W/r.txt" 2>&1; [ $? = 1 ] && grep -q 'FAIL: conf ' "$W/r.txt" && chk "fault 3: a file missing from the recipe is refused" ok || chk "fault 3 not caught" no
fault; sed -i 's#^\(/etc/tc/gen.txt\t\)[0-9a-f]*#\1'"$(printf '0%.0s' $(seq 96))"'#' "$RP/ops/image/recipe/build-inputs.tsv"; python3 "$T/r4-recompute.py" --repo "$RP" --reference "$W/ref.json" > "$W/r.txt" 2>&1; [ $? = 1 ] && grep -q 'FAIL: gen ' "$W/r.txt" && chk "fault 4: a wrong pinned hash of a generated file is refused" ok || chk "fault 4 not caught" no
fault; printf '\nimport re as _r\n_old = strip_text\ndef strip_text(s): return _old(s).replace("echo", "ECHO")\n' | python3 -c "import sys; p='$RP/ops/image/build/tc-strip-hooks.py'; s=open(p).read(); i=s.index('if __name__'); open(p,'w').write(s[:i]+sys.stdin.read()+'\n'+s[i:])"; python3 "$T/r4-recompute.py" --repo "$RP" --reference "$W/ref.json" > "$W/r.txt" 2>&1; [ $? = 1 ] && grep -q 'FAIL: lib ' "$W/r.txt" && chk "fault 5: a changed hook strip changes the recomputed digest (the strip is recomputed, not copied)" ok || chk "fault 5 not caught: $(tail -3 "$W/r.txt" | tr '\n' ' ')" no
fault; printf '/etc/tc/odd.txt\t644\tsomewhere:x\n' >> "$RP/ops/image/recipe/install-manifest.tsv"; python3 "$T/r4-recompute.py" --repo "$RP" --reference "$W/ref.json" > "$W/r.txt" 2>&1; [ $? = 1 ] && grep -q "not one of repo:, repo+strip:, link:, commit, input" "$W/r.txt" && chk "fault 6: an unknown kind of source is refused" ok || chk "fault 6 not caught" no
fault; python3 "$T/r4-derive.py" --evidence "$EV" --repo "$RP" --out "$W/recipe-noallow" --allow-input /nonexistent > "$W/d.txt" 2>&1; grep -q '^not covered: conf, gen, wg, pk$' "$W/d.txt" && chk "fault 7: without the allow-list, the generated file is NOT pinned silently: conf and gen become not covered" ok || chk "fault 7: $(grep '^not covered' "$W/d.txt")" no
say "the driver stage recipe (a dry run) and the refresh script"
D="$(DRY=1 IMG=x OUT="$W/outd" REFERENCE="$W/ref.json" timeout 60 bash "$T/f03-drive.sh" recipe 2>&1 | sed 's/\\//g')"
for k in 'r4-derive.py' '--evidence' 'r4-recompute.py' '--reference' 'F03-DRIVE-DONE'; do grep -qF -- "$k" <<<"$D" && chk "the dry run of stage recipe has: $k" ok || chk "the dry run of stage recipe lacks: $k" no; done
grep -q 'tc-strip-hooks.py' "$K/ops/image/build/tc-image-refresh.sh" && chk "tc-image-refresh.sh runs the shared tc-strip-hooks.py" ok || chk "tc-image-refresh.sh does not use the shared strip" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4B-REHEARSAL-PASS" || { echo "R4B-REHEARSAL-FAIL"; exit 1; }
