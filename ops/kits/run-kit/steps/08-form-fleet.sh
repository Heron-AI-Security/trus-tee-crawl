#!/usr/bin/env bash
# Step 8, form-fleet: verifies the announcements of all nodes (each quote binds the keys of the node and its log), writes the fleet list and gives it to every node as metadata, and waits until every node has published
# its final quote and all logs hold the same fleet event. The crawl starts when the fleet is formed, so the poller that collects the console of the master starts here. Run by run-kit.sh.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names; . "$KD/steps/fleet-common.sh"
fail() { echo "FORM-FLEET-FAILED: $*"; exit 1; }
for v in $(vm_names); do [ -s "$OUTF/announce-$v.txt" ] || fail "step 7 has not finished: there is no announcement of $v ($OUTF/announce-$v.txt)"; done
echo "== 1. verify the announcements, write the fleet list, wait for the final quotes of all $NVM nodes (the poller of the console of the master starts first: the crawl starts with the fleet)"
fleet_poller_start
fleet_drive step8 "forming the fleet" $RK_STAGES_FORM; RC=$?
if [ "$RC" != 0 ]; then tail -n 12 "$OUTF/step8.log" | cut -c1-400 | sed 's/^/   | /'; fail "the fleet was not formed (the lines above; the whole log is $OUTF/step8.log); the VMs are kept"; fi
[ -s "$OUTF/fleet.tsv" ] || fail "the driver wrote no fleet list ($OUTF/fleet.tsv)"
NROWS="$(awk -F'\t' '!/^#/ && ($2 == "master" || $2 == "worker")' "$OUTF/fleet.tsv" | wc -l)"; [ "$NROWS" = "$NVM" ] || fail "the fleet list has $NROWS nodes, the run has $NVM ($OUTF/fleet.tsv)"
for v in $(vm_names); do [ -s "$OUTF/final-$v.txt" ] || fail "the final quote of $v is not saved ($OUTF/final-$v.txt)"; done
FL="$(sha384sum "$OUTF/fleet.tsv" | cut -c1-16)"; echo "   fleet list $FL: $NROWS nodes"
rk_result "the fleet is formed: $NROWS nodes in the fleet list $FL; the quotes of all nodes were verified, and every node published a final quote that holds the same fleet event"
