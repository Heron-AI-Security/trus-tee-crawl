#!/usr/bin/env bash
# Step 11, verify-run: checks the real run against the build. The driver checks quote C, the manifest and every exported file, and writes the reference values of the final image; then the export is audited, the receipts
# are verified independently of the fleet (the job hash is the one of the normalized job of build A, from the record), and the independent builds of the record are checked against the real run (every stable event
# agrees, the verifier accepts the pin and refuses the wrong ones). The serial consoles of all VMs are saved: a writer that the lock of the code trees stopped would say Read-only file system (information, not a stop).
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; . "$KD/record.sh"; rk_load_names; . "$KD/steps/fleet-common.sh"
REC="$H/$CRAWL_RECORD"; fail() { echo "VERIFY-RUN-FAILED: $*"; exit 1; }
[ "$(find "$OUTF/export" -type f 2>/dev/null | wc -l)" -ge 1 ] || fail "step 10 has not finished: there is no export in $OUTF/export"
rk_record_check "$REC" > /dev/null 2>&1 || fail "the verified build record is missing or incomplete in $REC (step 6 makes it)"
for f in $RK_T_EXPORT_AUDIT $RK_T_RECEIPT_VERIFY $RK_T_ACCEPT; do [ -f "$TREE/$f" ] || fail "$f is not in the commit tree $TREE"; done
echo "== 1. quote C, the manifest and every exported file (the driver), and the reference values of the final image"
fleet_drive step11-check "checking the export" $RK_STAGES_CHECK_EXPORT; RC=$?
if [ "$RC" != 0 ]; then tail -n 10 "$OUTF/step11-check.log" | cut -c1-400 | sed 's/^/   | /'; fail "the export is not accepted by the driver (the lines above; the whole log is $OUTF/step11-check.log)"; fi
[ -s "$OUTF/reference-values.json" ] || fail "the driver wrote no reference values ($OUTF/reference-values.json)"
echo "== 2. the audit of the export"
python3 "$TREE/$RK_T_EXPORT_AUDIT" "$OUTF/export" > "$OUTF/audit.txt" 2>&1; RCA=$?
if [ "$RCA" != 0 ] || ! grep -aqE "$RK_M_AUDIT_OK" "$OUTF/audit.txt"; then tail -n 12 "$OUTF/audit.txt" | cut -c1-300 | sed 's/^/   | /'; fail "the audit of the export found problems (the lines above; the whole output is $OUTF/audit.txt)"; fi
echo "   the audit found no problem"
echo "== 3. the receipts, verified independently of the fleet (against the job console of build A in the record)"
python3 "$TREE/$RK_T_RECEIPT_VERIFY" "$OUTF/export" "$REC/a/job-console.txt" > "$OUTF/receipt-verify.txt" 2>&1; RCR=$?
if [ "$RCR" != 0 ] || ! grep -aqE "$RK_M_RECEIPT_OK" "$OUTF/receipt-verify.txt"; then grep -a "FAIL\|PROBLEMS" "$OUTF/receipt-verify.txt" | head -8 | cut -c1-300 | sed 's/^/   | /'; fail "the receipts do not verify (the lines above; the whole output is $OUTF/receipt-verify.txt)"; fi
echo "   every receipt verifies"
echo "== 4. the acceptance: the independent builds of the record against the real run, the pin, and the refusals"
R4_LOCKED=1 bash "$TREE/$RK_T_ACCEPT" "$OUTF" "$COMMIT" "$REC/a/measurements" "$REC/b/measurements" > "$OUTF/accept.txt" 2>&1; RCC=$?
if [ "$RCC" != 0 ] || ! grep -aqE "$RK_M_ACCEPT_OK" "$OUTF/accept.txt"; then tail -n 8 "$OUTF/accept.txt" | cut -c1-300 | sed 's/^/   | /'; fail "the independent builds do not agree with the real run (the lines above; the whole output is $OUTF/accept.txt)"; fi
echo "   the independent builds agree with every stable event of the real fleet"
echo "== 5. the serial consoles of the $NVM VMs (information only)"
ZZ="$(tr -d ' \r\n' < "$OUTF/zone.txt" 2>/dev/null)"; [ -n "$ZZ" ] || ZZ="$ZONE"
for v in $(vm_names); do [ -s "$OUTF/serial-$v.txt" ] || gcloud compute instances get-serial-port-output "$v" --zone="$ZZ" > "$OUTF/serial-$v.txt" 2>/dev/null & done; wait
NRO="$(cat "$OUTF"/serial-tc-"$RUN_ID"-*.txt 2>/dev/null | grep -a -c "Read-only file system")"; echo "   lines with 'Read-only file system' on the consoles: $NRO"
rk_result "the run is verified against the build: the export passes the audit, the receipts verify independently of the fleet, and the independent builds of $C9 agree with every stable event of the real fleet ($NRO console lines say read-only file system: information only)"
