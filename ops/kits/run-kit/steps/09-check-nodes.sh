#!/usr/bin/env bash
# Step 9, check-nodes: what each VM says about itself is checked against what a locked image must say (early, before the crawl ends, so a wrong image is found now), then the step waits for the crawl on the master to
# finish (up to 45 minutes, it is the long part of a run), checks the reports of all nodes, proves that a login to the master fails, and that its serial console shows no login prompt but carries its own report.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names; . "$KD/steps/fleet-common.sh"
fail() { echo "CHECK-NODES-FAILED: $*"; exit 1; }
for v in $(vm_names); do [ -s "$OUTF/final-$v.txt" ] || fail "step 8 has not finished: there is no final quote of $v ($OUTF/final-$v.txt)"; done
echo "== 1. the early check of every node, then the wait for the end of the crawl (up to 45 minutes), then the reports and the proof that a login fails"
fleet_poller_start
fleet_drive step9 "checking the nodes while the crawl runs" $RK_STAGES_NODES; RC=$?
if [ "$RC" != 0 ] || ! grep -aqE "$RK_M_LOCK_OK" "$OUTF/step9.log"; then tail -n 15 "$OUTF/step9.log" | cut -c1-400 | sed 's/^/   | /'; fail "the nodes are not what a locked image must be (the lines above; the whole log is $OUTF/step9.log); the VMs are kept, their serial consoles are in $OUTF"; fi
grep -aq '^crawl_marker=crawl done' "$OUTF/report-$MASTER.txt" 2>/dev/null || fail "the report of the master does not say that the crawl is done ($OUTF/report-$MASTER.txt)"
echo "   all $NVM nodes report as a locked image must; the crawl on the master is done; a login failed, as it must"
rk_result "all $NVM nodes report what a locked image must report (no login, no failed unit, the same image), a login to the master failed as it must, and the crawl on the master has finished"
