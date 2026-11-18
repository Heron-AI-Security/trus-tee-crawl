#!/usr/bin/env bash
# Step 13, clean-up: deletes the VMs of this run (the only thing it deletes: the images, the build record and the evidence stay) and packs the evidence of the run with a fingerprint. It refuses to delete the fleet
# before the export has been verified end to end (step 12): the consoles and the quotes of the VMs are what the verification reads. A fleet that must go anyway: bash run-kit.sh stop crawl  and the same flags.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names; . "$KD/steps/fleet-common.sh"
WD="$H/$RUN_DIR/verify-export"; fail() { echo "CLEAN-UP-FAILED: $*"; exit 1; }
grep -aqE "$RK_M_VERIFY_EXPORT_OK" "$WD/verify-export.txt" 2>/dev/null || fail "step 12 has not finished: the export is not verified, so the fleet is kept (to delete it anyway: bash run-kit.sh stop crawl and the same flags)"
echo "== 1. delete the $NVM VMs of this run (only them)"
HAVE="$(existing_vms)"
if [ -z "$HAVE" ]; then echo "   no VM of this run exists (deleted before)"
else
  fleet_drive step13 "deleting the fleet" $RK_STAGE_DELETE; RC=$?
  if [ "$RC" != 0 ]; then tail -n 8 "$OUTF/step13.log" | cut -c1-400 | sed 's/^/   | /'; fail "the fleet could not be deleted (the lines above)"; fi
  LEFT="$(existing_vms)"; [ -z "$LEFT" ] || fail "VMs of this run still exist after the deletion: $LEFT"
fi
rk_stop_poller "$RUN_LABEL"
echo "== 2. the evidence of the run, packed with its fingerprint"
tar czf "$H/${EVIDENCE}.tar.gz" -C "$H" "$EVIDENCE" || fail "the evidence could not be packed"; FP="$(sha256sum "$H/${EVIDENCE}.tar.gz" | cut -c1-64)"; echo "   $H/${EVIDENCE}.tar.gz: $FP"
rk_result "the $NVM VMs of the run $RUN_ID are deleted; the evidence is packed in $H/${EVIDENCE}.tar.gz (fingerprint ${FP:0:16}...); the images, the build record and the evidence folder stay"
