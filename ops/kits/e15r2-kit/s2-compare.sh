( set -uo pipefail
cd ~; K=~/e15r2work/tree; COMMIT="$(cat ~/e15r2-commit.txt 2>/dev/null)"; [ -n "$COMMIT" ] || { echo "COMPARE-FAILED: no ~/e15r2-commit.txt"; exit 1; }
for i in A B; do [ -s ~/evidence-e15r2-$i/r4/events.tsv ] || { echo "COMPARE-FAILED: build $i has no ground truth"; exit 1; }; done
echo "== the two NEW builds of the same commit, compared"
O1="$(python3 -B $K/ops/image/test/r4-diff.py ~/evidence-e15r2-A/r4 ~/evidence-e15r2-B/r4 --show 20 --out ~/evidence-e15r2-diff.txt 2>&1)"; echo "$O1" | grep -E "commit recorded|operating|packages:|initrd|vmlinuz|^R4-DIFF" | cut -c1-190
echo "$O1" | grep -q '^R4-DIFF: 15 of 15 events identical; different: none' || { echo "COMPARE-FAILED: the two new builds are not identical in all 15 events (the file ~/evidence-e15r2-diff.txt says which differ)"; exit 1; }
echo "$O1" | grep -q 'packages: A [0-9]*, B [0-9]*; all versions equal' || { echo "COMPARE-FAILED: the package versions of the two builds differ"; exit 1; }
echo "$O1" | grep -q 'initrd.img-tc  *same' || { echo "COMPARE-FAILED: the initramfs of the two builds differ"; exit 1; }
echo; echo "== the archive pin: both builds must have built from the dated copy named in the commit"
TS="$(tr -d ' \r\n' < $K/ops/image/build/apt-snapshot.txt)"
for i in A B; do grep -a -q "APTPIN-OK snapshot=$TS" ~/evidence-e15r2-$i/console.txt 2>/dev/null && echo "   [$i] APTPIN-OK snapshot=$TS" || { echo "COMPARE-FAILED: build $i has no APTPIN-OK for $TS in its log"; exit 1; }; done
echo; echo "== step R4.7: both builds recorded the COMMIT as their source, and they were built from two DIFFERENT archives of it"
for i in A B; do grep -a -q "^source: commit $COMMIT" ~/evidence-e15r2-$i/console.txt 2>/dev/null && echo "   [$i] source: commit ${COMMIT:0:12}..." || { echo "COMPARE-FAILED: build $i did not record 'source: commit $COMMIT' in its job stage"; exit 1; }; done
SA=$(grep -a -m1 "ship the source archive" ~/evidence-e15r2-A/console.txt | grep -o "([0-9a-f]\{16\}" ); SB=$(grep -a -m1 "ship the source archive" ~/evidence-e15r2-B/console.txt | grep -o "([0-9a-f]\{16\}")
[ -n "$SA" ] && [ -n "$SB" ] && [ "$SA" != "$SB" ] && echo "   the archives shipped to A and B differ ($SA... and $SB...): the 15 events of the two builds agree although the archives do not" || { echo "COMPARE-FAILED: build A and build B shipped the same archive ($SA, $SB): the test of step R4.7 is void"; exit 1; }
echo; echo "== for information: the new build of A against the build of A of the last pair (the packages now come from the dated archive, so jdk, wg and so on may differ)"
O2="$(python3 -B $K/ops/image/test/r4-diff.py ~/evidence-psl-A/r4 ~/evidence-e15r2-A/r4 --show 6 --out ~/evidence-e15r2-vs-old.txt 2>&1)"; echo "$O2" | grep -E "^R4-DIFF|packages:" | cut -c1-190
echo; echo "== R4.2 end to end: the recipe derived from each build, and the values recomputed from the commit"
for i in A B; do python3 -B $K/ops/image/test/r4-derive.py --evidence ~/evidence-e15r2-$i/r4 --repo $K --out ~/evidence-e15r2-$i/recipe 2>&1 | grep -E "^R4-DERIVE" | cut -c1-120 | sed "s/^/   [$i] /"; done
cmp -s ~/evidence-e15r2-A/recipe/install-manifest.tsv ~/evidence-e15r2-B/recipe/install-manifest.tsv && echo "   both builds give the SAME recipe" || { echo "COMPARE-FAILED: the two builds give different recipes"; exit 1; }
python3 - <<'PYEOF'
import json, os
h = os.path.expanduser("~"); ev = [l.rstrip("\n").split("\t") for l in open(h + "/evidence-e15r2-A/r4/events.tsv")]
json.dump({"events_in_order": [e[0] for e in ev], "stable_events": {e[0]: e[1] for e in ev}, "per_run_events": []}, open(h + "/evidence-e15r2-A/ref.json", "w"))
PYEOF
O3="$(python3 -B $K/ops/image/test/r4-recompute.py --repo $K --commit "$COMMIT" --recipe ~/evidence-e15r2-A/recipe --reference ~/evidence-e15r2-A/ref.json 2>&1)"; echo "$O3" | grep -E "^R4-RECOMPUTE" | cut -c1-170
echo "$O3" | grep -q '^R4-RECOMPUTE-OK: 8 of 15' || { echo "COMPARE-FAILED: the recompute from the commit does not give 8 of 15 equal events"; exit 1; }
tar czf ~/evidence-e15r2-experiment.tar.gz -C ~ evidence-e15r2-A evidence-e15r2-B evidence-e15r2-diff.txt evidence-e15r2-vs-old.txt; echo "evidence fingerprint: $(sha256sum ~/evidence-e15r2-experiment.tar.gz | cut -c1-64)"
echo "STAGE-OK compare" )
