( set -uo pipefail
cd ~/pslwork/tree; C="$(cat ~/psl-commit.txt)"; export IMG=tc-img-psl-1 OUT=~/evidence-psl-f SCRATCH_GB=10 EXPORT_BUCKET=training-custody-export-test EXPORT_SA=tc-export@training-custody.iam.gserviceaccount.com PIN_COMMIT=$C; mkdir -p $OUT; LOG=$OUT/blockD-console.txt; : > $LOG
bash ops/image/test/f1-drive.sh fleet-vms announce-wait fleet-build final-wait fleet-check export-wait export-fetch export-check reference-values 2>&1 | tee -a $LOG; RC=${PIPESTATUS[0]}
if [ "$RC" != 0 ]; then echo "BLOCK-D-FAILED (exit $RC); saved in $LOG. Last 30 lines (do not delete the VMs):"; tail -30 $LOG | cut -c1-220; gcloud compute instances list --format="table(name,status,zone.basename())"; exit 1; fi
echo "reference values: $(python3 -c 'import json,os; d=json.load(open(os.path.expanduser("~/evidence-psl-f/reference-values.json"))); print("commit", d.get("commit","(none)")[:12], "| rtmr2", d["rtmr2"][:16], "| stable events", len(d["stable_events"]))')"
echo BLOCK-D-DONE )
