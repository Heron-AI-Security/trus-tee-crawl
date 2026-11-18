#!/usr/bin/env bash
# Step 7, start-fleet: makes the master and the workers (TDX VMs from the sealed image A, each labelled with this run) and waits until every node has announced itself. If all the VMs of this run exist already
# (a rerun after a stop), only the announcements are waited for; if only some exist, the step stops and says how to delete them. Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names; . "$KD/steps/fleet-common.sh"
fail() { echo "START-FLEET-FAILED: $*"; exit 1; }
{ [ -n "$COMMIT" ] && [ -d "$TREE" ]; } || fail "there is no unpacked commit (the build and step 6 come first)"
echo "== 1. the fleet of the run $RUN_ID: $NVM VMs of $MACHINE_TYPE (the master and $WORKERS workers) from $IMAGE_1"
HAVE="$(existing_vms)"; NHAVE="$(echo "$HAVE" | wc -w)"
if [ "$NHAVE" = 0 ]; then STAGES="$RK_STAGES_START"; rm -f "$OUTF/zone.txt"; echo "   none exists yet: the VMs are made now, then every node is waited for (about 5 to 10 minutes)"
elif [ "$NHAVE" = "$NVM" ]; then STAGES="${RK_STAGES_START#* }"; echo "   all $NVM VMs exist already ($HAVE): only the announcements are waited for"
else fail "$NHAVE of the $NVM VMs of this run exist ($HAVE): delete them with  bash run-kit.sh stop crawl  and the same flags, then start again"; fi
fleet_drive step7 "the fleet of $RUN_ID" $STAGES; RC=$?
if [ "$RC" != 0 ]; then tail -n 12 "$OUTF/step7.log" | cut -c1-400 | sed 's/^/   | /'; fail "the fleet did not start (the lines above; the whole log is $OUTF/step7.log); the VMs that exist are kept: delete them with  bash run-kit.sh stop crawl  and the same flags"; fi
ZF="$(tr -d ' \r\n' < "$OUTF/zone.txt" 2>/dev/null)"; [ -n "$ZF" ] || fail "the driver did not record the zone of the fleet ($OUTF/zone.txt)"
for v in $(vm_names); do [ -s "$OUTF/announce-$v.txt" ] || fail "the announcement of $v is not saved ($OUTF/announce-$v.txt)"; done
echo "   zone $ZF; the announcements of all $NVM nodes are in $OUTF"
rk_result "the fleet of $NVM VMs (a master and $WORKERS workers of $MACHINE_TYPE) runs in zone $ZF from $IMAGE_1, and every node has announced itself"
