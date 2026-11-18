#!/usr/bin/env bash
# Step 10, crawl-export: waits for quote C of the master (it publishes it after the crawl, the verified copy and the manifest), then for the DONE object in the export bucket (the master uploads the export AFTER it publishes
# quote C: the first run fetched too early), fetches the export, and finishes the poller that collected the console of the master. Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names; . "$KD/steps/fleet-common.sh"
fail() { echo "CRAWL-EXPORT-FAILED: $*"; exit 1; }
{ [ -s "$OUTF/fleet.tsv" ] && [ -s "$OUTF/report-$MASTER.txt" ]; } || fail "step 9 has not finished: the fleet list or the report of the master is missing in $OUTF"
echo "== 1. quote C of the master (up to 60 minutes)"
fleet_drive step10-wait "waiting for quote C of the master" $RK_STAGE_EXPORT_WAIT; RC=$?
if [ "$RC" != 0 ]; then tail -n 8 "$OUTF/step10-wait.log" | cut -c1-400 | sed 's/^/   | /'; fail "quote C of the master did not come (the lines above; the VMs are kept)"; fi
echo "== 2. the DONE object of the export in gs://$RK_EXPORT_BUCKET (up to $(( ${RK_DONE_MAX:-1800} / 60 )) minutes)"
FL="$(sha384sum "$OUTF/fleet.tsv" | cut -c1-16)"; DB="gs://$RK_EXPORT_BUCKET/export/$FL/$MASTER/DONE"; t=0; poll="${RK_DONE_POLL:-20}"; last=0
until gcloud storage cat "$DB" > /dev/null 2>&1; do
  t="$(awk -v t="$t" -v p="$poll" 'BEGIN { print t + p }')"
  if awk -v t="$t" -v m="${RK_DONE_MAX:-1800}" 'BEGIN { exit !(t > m) }'; then fail "no DONE object after $(( ${RK_DONE_MAX:-1800} / 60 )) minutes: $DB (the export is incomplete; the VMs are kept)"; fi
  if awk -v t="$t" -v l="$last" 'BEGIN { exit !(t - l >= 300) }'; then echo "   still waiting for the DONE object ($(awk -v t="$t" 'BEGIN { printf "%d", t / 60 }') min)"; last="$t"; fi
  sleep "$poll"
done
echo "   the DONE object exists"
echo "== 3. fetch the export"
fleet_drive step10-fetch "fetching the export" $RK_STAGE_EXPORT_FETCH; RC=$?
if [ "$RC" != 0 ] || ! grep -aqE "$RK_M_EXPORT_FOLDER" "$OUTF/step10-fetch.log"; then tail -n 8 "$OUTF/step10-fetch.log" | cut -c1-400 | sed 's/^/   | /'; fail "the export could not be fetched (the lines above)"; fi
NF="$(find "$OUTF/export" -type f 2>/dev/null | wc -l)"; [ "$NF" -ge 1 ] || fail "the export folder $OUTF/export is empty"
fleet_poller_stop; NL="$(wc -l < "$OUTF/master-log-lines.txt" 2>/dev/null || echo 0)"
echo "   $NF files in $OUTF/export; $NL console lines of the master saved in $OUTF/master-log-lines.txt"
rk_result "quote C of $MASTER is published and its export of $NF files is fetched from gs://$RK_EXPORT_BUCKET into $OUTF/export; the master console lines of the crawl ($NL) are saved"
