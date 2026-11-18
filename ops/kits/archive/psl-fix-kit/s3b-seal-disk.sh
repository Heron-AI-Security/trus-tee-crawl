( set -uo pipefail
cd ~/pslwork/tree; export BUILDER=tc-psl-a ZONE="$(cat ~/evidence-psl-A/zone.txt)" IMG=tc-img-psl-1 OUT=~/evidence-psl-s KVER=6.17.0-1022-gcp COMMIT_FILE=~/psl-commit.txt; mkdir -p $OUT; LOG=$OUT/blockB-console.txt; : > $LOG
bash ops/image/test/f03-drive.sh builder ship-builder clean seal-stop seal-disk 2>&1 | tee -a $LOG; RC=${PIPESTATUS[0]}
if [ "$RC" = 0 ]; then echo BLOCK-B-DONE; else echo "BLOCK-B-FAILED (exit $RC); saved in $LOG. Last 30 lines and the cloud state:"; tail -30 $LOG | cut -c1-220; gcloud compute instances list --format="table(name,status,zone.basename())"; fi )
