( set -uo pipefail
cd ~/pslwork/tree; C="$(cat ~/psl-commit.txt)"; OUT=~/evidence-psl-f; [ -s $OUT/reference-values.json ] || { echo "BLOCK-D2-FAILED: no reference-values.json (run block D first)"; exit 1; }
echo "=== the sealed image's RTMR2 (the unsealed image had 7a2f21d0..., the R3 sealed image daa83af9...): $(grep -o '"rtmr2": "[0-9a-f]\{16\}' $OUT/reference-values.json)"
echo "=== audit of the export (rules of R5)"; python3 ops/image/test/r3-export-audit.py $OUT/export 2>&1 | tee $OUT/audit.txt | tail -12
echo "=== independent receipt verification (the job hash is the one of the NORMALIZED job)"; python3 ops/image/test/r3-receipt-verify.py $OUT/export ~/evidence-psl-A/f03-job-console.txt 2>&1 | tee $OUT/receipt-verify.txt | grep -E "FAIL|RECEIPT-VERIFY"
echo "=== R4 acceptance: the independent builds against the real run, the pin, and the refusals"; bash ops/image/test/r4-accept.sh $OUT $C ~/evidence-psl-A/r4 ~/evidence-psl-B/r4 2>&1 | tee $OUT/accept.txt | cut -c1-240
grep -q '^R4-ACCEPT-OK' $OUT/accept.txt && echo BLOCK-D2-DONE || echo "BLOCK-D2-FAILED: read the R4-ACCEPT-FAILED line" )
