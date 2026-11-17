#!/usr/bin/env bash
# Step 2, compare-builds: the two builds of the same commit must agree. Nothing is started in the cloud; this step reads the evidence of the two builds (~/build-<commit>/a and /b).
# Checked: every measured event is identical; the package lists and the initramfs are equal; both builds installed exactly the committed packages (and nothing was downloaded);
# both recorded the commit as their source although they were built from two different archives; both give the same install recipe; and the stable measurements can be
# recomputed from the commit alone. The plain result is written to compare.txt (a part of the build record). Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names
H="$HOME"; TREE="$H/$BUILD_TREE"; CF="$H/$BUILD_COMMIT_FILE"; BD="$H/$BUILD_DIR"; COMMIT="$(cat "$CF" 2>/dev/null)"
MIN_RECOMPUTED=8   # the proven kit could recompute 8 of the 15 events from the commit alone; fewer would be a step back
fail() { echo "COMPARE-FAILED: $*"; exit 1; }
[ -n "$COMMIT" ] && [ -d "$TREE" ] || fail "there is no unpacked commit (step 0 has not run)"
for i in a b; do [ -s "$BD/$i/r4/events.tsv" ] && [ -s "$BD/$i/console.txt" ] || fail "build ${i^^} has no measurements yet (step 1 has not finished for it): run the same command without --until"; done
cd "$TREE" || exit 1
NEV="$(grep -c . "$BD/a/r4/events.tsv")"

echo "== 1. the two builds of commit ${COMMIT:0:9}, compared event by event"
python3 -B "$TREE/$RK_T_COMPARE_BUILDS" "$BD/a/r4" "$BD/b/r4" --show 20 --out "$BD/diff.txt" > "$BD/compare-tool.out" 2>&1
grep -E "commit recorded|operating|packages:|initrd|vmlinuz" "$BD/compare-tool.out" | cut -c1-190 | sed 's/^/   /'
grep -Eq "$RK_M_EVENTS_EQUAL" "$BD/compare-tool.out" || { grep -E "$RK_M_DIFF_LINE" "$BD/compare-tool.out" | head -2 | sed 's/^/   the tool says: /'; fail "the two builds are not identical in every event ($BD/diff.txt says which differ)"; }
N="$(sed -nE "s/$RK_M_DIFF_COUNT/\1/p" "$BD/compare-tool.out" | head -1)"; [ "$N" = "$NEV" ] || fail "the comparison covered $N events but build A measured $NEV"
echo "   all $NEV events are identical"
grep -q "$RK_M_PACKAGES_EQUAL" "$BD/compare-tool.out" || fail "the package versions of the two builds differ"
grep -q "$RK_M_INITRD_SAME" "$BD/compare-tool.out" || fail "the initramfs of the two builds differ"

echo; echo "== 2. both builds must have installed exactly the committed packages, and nothing may have been downloaded"
#DEBS-COMPARE-BEGIN
WANT="$(sha256sum "$TREE/ops/image/debs/SHA256SUMS" | cut -c1-12)"; NP="$(grep -c . "$TREE/ops/image/debs/SHA256SUMS")"
for i in a b; do L="$(grep -a -m1 '^DEBS-OK snapshot=' "$BD/$i/console.txt" 2>/dev/null)"; [ -n "$L" ] || fail "build ${i^^} has no DEBS-OK in its log"; echo "   [${i^^}] $L" | cut -c1-170
  case "$L" in *" packages=$NP sums=$WANT "*) ;; *) fail "build ${i^^} did not install the committed set (expected packages=$NP sums=$WANT)";; esac; done
echo "   both builds installed exactly the committed set: $NP packages, sums=$WANT"
for i in a b; do LA="$(grep -a -m1 '^DEBS-AUDIT-OK ' "$BD/$i/console.txt" 2>/dev/null)"; [ -n "$LA" ] || fail "build ${i^^} has no DEBS-AUDIT-OK (the audit of apt after the build: no download, one source, the committed versions)"; echo "   [${i^^}] $LA" | cut -c1-170; if [ "$i" = a ]; then AU_A="$LA"; else AU_B="$LA"; fi; done
[ "$AU_A" = "$AU_B" ] || fail "the audits of the two builds differ (A: $AU_A | B: $AU_B)"
echo "   both builds: nothing was downloaded, one source, the committed versions installed, and the same audit"
#DEBS-COMPARE-END

echo; echo "== 3. both builds recorded the COMMIT as their source, and they were built from two DIFFERENT archives of it"
for i in a b; do grep -a -q "^source: commit $COMMIT" "$BD/$i/console.txt" 2>/dev/null && echo "   [${i^^}] source: commit ${COMMIT:0:12}..." || fail "build ${i^^} did not record 'source: commit $COMMIT' in its job stage"; done
SA="$(grep -a -m1 "ship the source archive" "$BD/a/console.txt" | grep -o "([0-9a-f]\{16\}")"; SB="$(grep -a -m1 "ship the source archive" "$BD/b/console.txt" | grep -o "([0-9a-f]\{16\}")"
[ -n "$SA" ] && [ -n "$SB" ] && [ "$SA" != "$SB" ] || fail "build A and build B shipped the same archive ($SA, $SB): the check that the result does not depend on the archive would prove nothing"
echo "   the archives shipped to A and B differ ($SA... and $SB...): the $NEV events agree although the archives do not"

echo; echo "== 4. the install recipe derived from each build must be the same, and the stable measurements must be recomputable from the commit alone"
for i in a b; do python3 -B "$TREE/$RK_T_DERIVE_RECIPE" --evidence "$BD/$i/r4" --repo "$TREE" --out "$BD/$i/recipe" > "$BD/$i/derive-tool.out" 2>&1 || fail "the recipe of build ${i^^} could not be derived (see $BD/$i/derive-tool.out)"; echo "   the recipe of build ${i^^} is derived"; done
cmp -s "$BD/a/recipe/install-manifest.tsv" "$BD/b/recipe/install-manifest.tsv" || fail "the two builds give different recipes"
echo "   both builds give the SAME recipe"
python3 - "$BD" <<'PYX'
import json, sys
bd = sys.argv[1]; ev = [l.rstrip("\n").split("\t") for l in open(bd + "/a/r4/events.tsv")]
json.dump({"events_in_order": [e[0] for e in ev], "stable_events": {e[0]: e[1] for e in ev}, "per_run_events": []}, open(bd + "/a/ref.json", "w"))
PYX
python3 -B "$TREE/$RK_T_RECOMPUTE" --repo "$TREE" --commit "$COMMIT" --recipe "$BD/a/recipe" --reference "$BD/a/ref.json" > "$BD/recompute-tool.out" 2>&1
L="$(grep -E "$RK_M_RECOMPUTE_OK" "$BD/recompute-tool.out" | head -1)"; [ -n "$L" ] || { tail -3 "$BD/recompute-tool.out" | sed 's/^/   the tool says: /'; fail "the recomputation from the commit failed (see $BD/recompute-tool.out)"; }
RN="$(echo "$L" | sed -nE "s/$RK_M_RECOMPUTE_OK.*/\1/p")"; [ "$RN" -ge "$MIN_RECOMPUTED" ] || fail "only $RN of $NEV events can be recomputed from the commit alone; the proven kit reached $MIN_RECOMPUTED"
echo "   $RN of the $NEV events are recomputed from the commit alone and equal what the image measured"

{ echo "the two builds of commit $COMMIT agree"; echo "events: all $NEV identical"; echo "packages: $NP committed packages installed by both builds (sums $WANT), same audit"; echo "source archives: A $SA, B $SB (different)"; echo "recipe: the same for both builds"; echo "recomputed from the commit alone: $RN of $NEV events"; } > "$BD/compare.txt"
rk_result "the two builds of commit ${COMMIT:0:9} agree: all $NEV events identical, the same $NP committed packages, the same recipe, $RN of $NEV events recomputed from the commit alone, and the archives differ"
