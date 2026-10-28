( set -uo pipefail
cd ~; K=~/fin2work/tree; COMMIT="$(cat ~/fin2-commit.txt 2>/dev/null)"; [ -n "$COMMIT" ] || { echo "COMPARE-FAILED: no ~/fin2-commit.txt"; exit 1; }
for i in A B; do [ -s ~/evidence-fin2-$i/r4/events.tsv ] || { echo "COMPARE-FAILED: build $i has no ground truth"; exit 1; }; done
echo "== the two NEW builds of the same commit, compared"
O1="$(python3 -B $K/ops/image/test/r4-diff.py ~/evidence-fin2-A/r4 ~/evidence-fin2-B/r4 --show 20 --out ~/evidence-fin2-diff.txt 2>&1)"; echo "$O1" | grep -E "commit recorded|operating|packages:|initrd|vmlinuz|^R4-DIFF" | cut -c1-190
echo "$O1" | grep -q '^R4-DIFF: 15 of 15 events identical; different: none' || { echo "COMPARE-FAILED: the two new builds are not identical in all 15 events (the file ~/evidence-fin2-diff.txt says which differ)"; exit 1; }
echo "$O1" | grep -q 'packages: A [0-9]*, B [0-9]*; all versions equal' || { echo "COMPARE-FAILED: the package versions of the two builds differ"; exit 1; }
echo "$O1" | grep -q 'initrd.img-tc  *same' || { echo "COMPARE-FAILED: the initramfs of the two builds differ"; exit 1; }
echo; echo "== the NEW build of A against the OLD build of A (before the policy fix): only source, tc-lib and tc-conf may differ"
O2="$(python3 -B $K/ops/image/test/r4-diff.py ~/evidence-fin-A/r4 ~/evidence-fin2-A/r4 --show 6 --out ~/evidence-fin2-vs-old.txt 2>&1)"; echo "$O2" | grep -E "^R4-DIFF" | cut -c1-190
S="$(echo "$O2" | sed -n 's/^R4-DIFF: .*different: //p')"; [ -n "$S" ] || { echo "COMPARE-FAILED: the new against old comparison printed no verdict"; exit 1; }
for e in $(echo "$S" | tr -d ','); do case "$e" in source|tc-lib|tc-conf|none) ;; *) echo "COMPARE-FAILED: the event $e differs between the old and the new build, which the policy fix must not do"; exit 1;; esac; done
echo "$S" | grep -q 'source' || { echo "COMPARE-FAILED: the source event did not change although the commit did"; exit 1; }
echo "$S" | grep -q 'tc-lib' || { echo "COMPARE-FAILED: tc-lib did not change although tc-policy.py did (is the fix in this build?)"; exit 1; }
echo; echo "== R4.2 end to end: the recipe derived from each build, and the values recomputed from the commit"
for i in A B; do python3 -B $K/ops/image/test/r4-derive.py --evidence ~/evidence-fin2-$i/r4 --repo $K --out ~/evidence-fin2-$i/recipe 2>&1 | grep -E "^R4-DERIVE" | cut -c1-120 | sed "s/^/   [$i] /"; done
cmp -s ~/evidence-fin2-A/recipe/install-manifest.tsv ~/evidence-fin2-B/recipe/install-manifest.tsv && echo "   both builds give the SAME recipe" || { echo "COMPARE-FAILED: the two builds give different recipes"; exit 1; }
python3 - <<'PYEOF'
import json, os
h = os.path.expanduser("~"); ev = [l.rstrip("\n").split("\t") for l in open(h + "/evidence-fin2-A/r4/events.tsv")]
json.dump({"events_in_order": [e[0] for e in ev], "stable_events": {e[0]: e[1] for e in ev}, "per_run_events": []}, open(h + "/evidence-fin2-A/ref.json", "w"))
PYEOF
O3="$(python3 -B $K/ops/image/test/r4-recompute.py --repo $K --commit "$COMMIT" --recipe ~/evidence-fin2-A/recipe --reference ~/evidence-fin2-A/ref.json 2>&1)"; echo "$O3" | grep -E "^R4-RECOMPUTE" | cut -c1-170
echo "$O3" | grep -q '^R4-RECOMPUTE-OK: 8 of 15' || { echo "COMPARE-FAILED: the recompute from the commit does not give 8 of 15 equal events"; exit 1; }
tar czf ~/evidence-fin2-experiment.tar.gz -C ~ evidence-fin2-A evidence-fin2-B evidence-fin2-diff.txt evidence-fin2-vs-old.txt; echo "evidence fingerprint: $(sha256sum ~/evidence-fin2-experiment.tar.gz | cut -c1-64)"
echo "STAGE-OK compare" )
