( set -uo pipefail
cd ~/pslwork/tree; export BUILDER=tc-psl-a IMG=tc-img-psl-1 OUT=~/evidence-psl-s KVER=6.17.0-1022-gcp SCRATCH_GB=10
Z0="$(cat ~/evidence-psl-A/zone.txt)"; LOG=$OUT/blockC-console.txt; mkdir -p $OUT; touch $LOG
echo "== 1. the sealed image (a re-run must not make it twice)"
if [ "$(gcloud compute images describe $IMG --format='value(status)' 2>/dev/null)" = READY ]; then echo "   $IMG exists and is READY: skipped"
else ZONE=$Z0 bash ops/image/test/f03-drive.sh seal-image 2>&1 | tee -a $LOG | tail -4; [ "${PIPESTATUS[0]}" = 0 ] || { echo "BLOCK-C-FAILED: the image could not be made (the lines above say why)"; exit 1; }; fi
echo "== 2. the boot check on a plain VM, in the zones in turn: a zone can be out of capacity, which is not a fault of the image"
OKZ=""
for z in $Z0 us-central1-b us-central1-c us-central1-f; do
  echo "--- the test VM in $z"
  ZONE=$z bash ops/image/test/f03-drive.sh seal-boot > $OUT/seal-boot-$z.txt 2>&1; rc=$?; cat $OUT/seal-boot-$z.txt >> $LOG; tail -5 $OUT/seal-boot-$z.txt | cut -c1-170
  if [ $rc = 0 ]; then OKZ=$z; break; fi
  if grep -qE 'ZONE_RESOURCE_POOL_EXHAUSTED|does not have enough resources|is currently unavailable|stockout' $OUT/seal-boot-$z.txt; then echo "   no capacity in $z: trying the next zone"; continue; fi
  echo "BLOCK-C-FAILED: the sealed boot failed in $z for a reason other than capacity (the lines above say why; the VM tc-seal-test is kept for diagnosis)"; exit 1
done
[ -n "$OKZ" ] || { echo "BLOCK-C-FAILED: no zone had capacity for the plain test VM (tried $Z0, b, c and f): run the same command again in a few minutes; the image is made and is not made again"; exit 1; }
echo "== 3. the checks inside the booted sealed VM (zone $OKZ)"
ZONE=$OKZ bash ops/image/test/f03-drive.sh seal-check 2>&1 | tee -a $LOG | tail -6; [ "${PIPESTATUS[0]}" = 0 ] || { echo "BLOCK-C-FAILED: the sealed VM did not pass its checks (the VM is kept for diagnosis)"; exit 1; }
echo "== 4. clean up the test VM and the copied disk (the image stays)"
CONFIRM=yes ZONE=$OKZ bash ops/image/test/f03-drive.sh seal-delete 2>&1 | tee -a $LOG | tail -4
echo BLOCK-C-DONE )
