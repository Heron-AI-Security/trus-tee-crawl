( set -uo pipefail
ID="${ID:-A}"; IDL="${ID,,}"; if [ "$ID" = A ]; then IMGN=tc-img-k1a-1; OUTD=~/evidence-k1a-s; else IMGN=tc-img-k1a-2; OUTD=~/evidence-k1a-s2; fi
cd ~/k1awork/tree; export BUILDER=tc-k1a-$IDL ZONE="$(cat ~/evidence-k1a-$ID/zone.txt)" IMG=$IMGN OUT=$OUTD KVER=6.17.0-1022-gcp COMMIT_FILE=~/k1a-commit.txt SEAL_DISK=tc-seal-work-$IDL SEALER=tc-sealer-$IDL SEAL_TEST=tc-seal-test-$IDL; mkdir -p $OUT; LOG=$OUT/blockB-console.txt; : > $LOG
echo "== sealing build $ID: the builder $BUILDER is cleaned live, stopped, its disk is copied, and the copy is normalized and sealed offline on a helper VM (image $IMG)"
STEPS="builder ship-builder clean seal-stop seal-disk"
# GUARD (found by the first full run of this kit): a restart of this stage after the builder was cleaned and stopped must NOT run the first steps again. "builder" would start the cleaned builder, and its first boot lets cloud-init rewrite files (/etc/apt/sources.list, /etc/chrony/chrony.conf.dist): the sealed image of that build then differs from the other build in exactly those files, and the tree comparison of step P4 fails. So refuse, and say what to do instead.
if [ "${SEAL_FROM:-}" != seal-disk ] && grep -aq "CLEAN-OK" "$OUT/f03-clean-console.txt" 2>/dev/null && [ "$(gcloud compute instances describe "$BUILDER" --zone="$ZONE" --format='value(status)' 2>/dev/null)" = TERMINATED ]; then
  echo "RESTART-REFUSED: the builder $BUILDER was already cleaned (CLEAN-OK in $OUT/f03-clean-console.txt) and stopped by an earlier attempt of this stage. Starting it again would change the image (cloud-init rewrites files on a boot), so the first steps must NOT run again."
  echo "   What to do: (1) delete the leftovers of the killed attempt, by their exact names, with  CONFIRM=yes bash ops/image/test/f03-drive.sh seal-delete  (SEAL_DISK=tc-seal-work-$IDL SEALER=tc-sealer-$IDL SEAL_TEST=tc-seal-test-$IDL and the same ZONE, BUILDER, IMG, OUT as this stage, from ~/k1awork/tree), then (2) start the kit again with  SEAL_FROM=seal-disk  in front of the command."
  exit 1
fi
# RESUME: if the runner was killed (for example when Cloud Shell was recycled) AFTER the builder was cleaned and stopped, the first four steps cannot run again: the cleaning removed the ssh access of the builder, so "builder" would fail with "no ssh".
# SEAL_FROM=seal-disk skips them, but only when the evidence is there that they finished: the cleaning printed CLEAN-OK into $OUT/f03-clean-console.txt AND the builder is stopped. The leftovers of the killed attempt (the helper VM and the disk copy) must be removed first, with  f03-drive.sh seal-delete  (the stage says so).
if [ "${SEAL_FROM:-}" = seal-disk ]; then
  grep -aq "CLEAN-OK" "$OUT/f03-clean-console.txt" 2>/dev/null || { echo "RESUME-REFUSED: there is no CLEAN-OK in $OUT/f03-clean-console.txt, so the builder $BUILDER was not cleaned by an earlier attempt and the first steps must run (start without SEAL_FROM)"; exit 1; }
  [ "$(gcloud compute instances describe "$BUILDER" --zone="$ZONE" --format='value(status)' 2>/dev/null)" = TERMINATED ] || { echo "RESUME-REFUSED: the builder $BUILDER is not stopped, so its disk must not be copied"; exit 1; }
  STEPS="seal-disk"; echo "== RESUME (SEAL_FROM=seal-disk): the builder $BUILDER was cleaned (CLEAN-OK) and is stopped; only the sealing of its disk runs again"
fi
bash ops/image/test/f03-drive.sh $STEPS 2>&1 | tee -a $LOG; RC=${PIPESTATUS[0]}
if [ "$RC" = 0 ]; then echo "normalization of build $ID: $(grep -a -m1 'NORMALIZE-OK' $LOG | cut -c1-120)"; [ -s $OUT/normalize-report.txt ] && echo "   what it removed (group, entries): $(awk -F'\t' '{n[$1]+=($3+0)} END {for (g in n) printf "%s=%d ", g, n[g]}' $OUT/normalize-report.txt)"; echo BLOCK-B-DONE; else echo "BLOCK-B-FAILED (exit $RC); saved in $LOG. Last 30 lines and the cloud state:"; tail -30 $LOG | cut -c1-220; gcloud compute instances list --format="table(name,status,zone.basename())"; fi )
