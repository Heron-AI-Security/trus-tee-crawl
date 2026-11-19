( set -uo pipefail
cd ~/k1awork/tree; C="$(cat ~/k1a-commit.txt)"; export IMG=tc-img-k1a-1 OUT=~/evidence-k1a-f SCRATCH_GB=10 WORKERS=10 EXPORT_BUCKET=training-custody-export-test EXPORT_SA=tc-export@training-custody.iam.gserviceaccount.com PIN_COMMIT=$C; mkdir -p $OUT; LOG=$OUT/blockD-console.txt; : > $LOG
RAW=$OUT/master-log-lines.raw; : > $RAW
poll() { ZZ="$(cat $OUT/zone.txt 2>/dev/null | tr -d ' \r\n')"; [ -n "$ZZ" ] || ZZ=us-central1-a; gcloud compute instances get-serial-port-output tc-f1-m --zone "$ZZ" 2>/dev/null | grep -a "tc-crawl:\|tc-export:" >> $RAW; }
# the console of a VM keeps only its last 1 MiB, so the early lines of the crawl are gone by the end of the run: this loop collects the lines of tc-crawl and tc-export of the master every 45 seconds
( while true; do poll; sleep 45; done ) & POLL=$!
trap 'kill $POLL 2>/dev/null; poll; sort -u $RAW > $OUT/master-log-lines.txt 2>/dev/null' EXIT
bash ops/image/test/f1-drive.sh fleet-vms announce-wait fleet-build final-wait fleet-check export-wait 2>&1 | tee -a $LOG; RC=${PIPESTATUS[0]}
if [ "$RC" != 0 ]; then echo "BLOCK-D-FAILED (exit $RC); saved in $LOG. Last 30 lines (do not delete the VMs):"; tail -30 $LOG | cut -c1-220; gcloud compute instances list --format="table(name,status,zone.basename())"; exit 1; fi
echo "== the master uploads the export AFTER it publishes quote C (a race in the first run: the driver fetched too early). The kit waits for the DONE object, up to 30 minutes" | tee -a $LOG
FL="$(sha384sum $OUT/fleet.tsv | cut -c1-16)"; DB="gs://$EXPORT_BUCKET/export/$FL/tc-f1-m/DONE"; t=0
until gcloud storage cat "$DB" >/dev/null 2>&1; do t=$((t+20)); if [ $t -gt 1800 ]; then echo "BLOCK-D-FAILED: no DONE object after 30 minutes: $DB (do not delete the VMs)" | tee -a $LOG; exit 1; fi; echo "   waiting for the DONE object ($t s)" | tee -a $LOG; sleep 20; done
echo "   the DONE object exists (after $t s of waiting)" | tee -a $LOG
bash ops/image/test/f1-drive.sh export-fetch export-check reference-values 2>&1 | tee -a $LOG; RC=${PIPESTATUS[0]}
if [ "$RC" != 0 ]; then echo "BLOCK-D-FAILED (exit $RC); saved in $LOG. Last 30 lines (do not delete the VMs):"; tail -30 $LOG | cut -c1-220; gcloud compute instances list --format="table(name,status,zone.basename())"; exit 1; fi
echo "reference values: $(python3 -c 'import json,os; d=json.load(open(os.path.expanduser("~/evidence-k1a-f/reference-values.json"))); print("commit", d.get("commit","(none)")[:12], "| rtmr2", d["rtmr2"][:16], "| stable events", len(d["stable_events"]))')"
echo BLOCK-D-DONE )
