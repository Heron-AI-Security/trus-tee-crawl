#!/usr/bin/env bash
# cln-resume-fleet2.sh: finish the FLEET stage after the node-side check failed on the master ONLY in the three checks that compare the log with the FINAL quote, because the check was re-run AFTER the crawl: by then the master had extended its
# RTMR3 log with the events of the crawl and the export, so the log can no longer "end with fleet and fleet-conf" or replay to the quote that was taken right after them. In the first (lost) run these checks ran BEFORE the crawl ended.
# This script goes on ONLY IF the evidence is there: (1) the first run shows the three checks as ok for BOTH nodes and no FAIL, and (2) the failures of the re-run are exactly these three. Then it runs the remaining stages (export-wait export-fetch export-check reference-values).
set -uo pipefail
cd ~/clnwork/tree || { echo "RESUME2-FAILED: no ~/clnwork/tree"; exit 1; }
C="$(cat ~/cln-commit.txt)"; export IMG=tc-img-cln-1 OUT=~/evidence-cln-f SCRATCH_GB=10 EXPORT_BUCKET=training-custody-export-test EXPORT_SA=tc-export@training-custody.iam.gserviceaccount.com PIN_COMMIT=$C
LOG=~/cln-run/logs/fleet.log; grep -qx fleet ~/cln-run/stages.done 2>/dev/null && { echo "RESUME2: the stage fleet is already marked as done"; exit 0; }
refuse() { echo "RESUME2-REFUSED: $*"; echo "Nothing was run and nothing was marked. Paste this output."; exit 1; }
FIRST="$(awk '/^##### resume of the fleet stage/ {exit} {print}' "$LOG")"
[ -n "$FIRST" ] || refuse "the log of the first run is empty or has no first part"
for s in "the last two events of the log are fleet and fleet-conf" "the log's chain is consistent and replays to the RTMR3 of the final quote" "the final quote's REPORTDATA is the SHA-512 of a binding text"; do
  n="$(grep -a -c -F "$s" <<<"$FIRST")"; [ "$n" -ge 2 ] || refuse "the first run does not show the check '$s' as ok for BOTH nodes (found $n time(s), expected 2)"
done
! grep -a -q "FAIL:" <<<"$FIRST" || refuse "the first run already contains a FAIL line"
U="$(grep -a -h "FAIL:" ~/cln-resume-fleet.out 2>/dev/null | sed 's/^ *//' | sort -u)"
[ "$(wc -l <<<"$U")" = 3 ] && grep -qF "FAIL: the log does not end with fleet and fleet-conf" <<<"$U" && grep -qF "FAIL: the log does not replay to the final quote's RTMR3" <<<"$U" && grep -qF "FAIL: the final quote does not bind the keys and the log" <<<"$U" || refuse "the failures of the re-run are not exactly the three expected ones: $(tr '\n' '|' <<<"$U" | cut -c1-300)"
grep -a -q "F1-CHECK-OK role=worker" ~/cln-resume-fleet.out || refuse "the worker's check did not pass in the re-run"
echo "##### resume 2 of the fleet stage ($(date -u +%H:%M:%S) UTC): the evidence is in order; fleet-check is NOT run again" | tee -a "$LOG"
echo "   evidence: the first run (before the crawl ended) shows the three log checks as ok for both nodes; the re-run after the crawl fails exactly these three on the master (its log has the later events of the crawl and the export); the worker passed" | tee -a "$LOG"
bash ops/image/test/f1-drive.sh export-wait export-fetch export-check reference-values 2>&1 | tee -a "$LOG" ~/evidence-cln-f/blockD-console.txt; RC=${PIPESTATUS[0]}
if [ "$RC" != 0 ]; then echo "RESUME2-FAILED (exit $RC): the lines above say why. The VMs are NOT deleted."; tail -30 "$LOG" | cut -c1-220; exit 1; fi
echo "reference values: $(python3 -c 'import json,os; d=json.load(open(os.path.expanduser("~/evidence-cln-f/reference-values.json"))); print("commit", d.get("commit","(none)")[:12], "| rtmr2", d["rtmr2"][:16], "| stable events", len(d["stable_events"]))')" | tee -a "$LOG"
echo BLOCK-D-DONE | tee -a "$LOG"; echo fleet >> ~/cln-run/stages.done; echo "fleet: finished in two parts (see the log)" >> ~/cln-run/timings.txt
echo "RESUME2-OK: the stage fleet is marked as done. Start the runner again (with setsid nohup) to continue with verify, p4 and clean."
