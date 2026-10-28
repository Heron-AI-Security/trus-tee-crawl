( set -uo pipefail
ID="${ID:-A}"; K=~/fin2work/tree; IDL="${ID,,}"
[ -s ~/fin2-commit.txt ] && [ -s ~/r4-base-image.txt ] && [ -d "$K" ] || { echo "BUILD-FAILED: run block B2 first (it unpacks the new source archive)"; exit 1; }
COMMIT="$(cat ~/fin2-commit.txt)"; ARCH=~/src-final2.tgz; ARCH_SHA=$(sha256sum $ARCH | cut -c1-64)
export BASE_IMAGE="$(cat ~/r4-base-image.txt)" BUILDER=tc-fin-$IDL MANIFEST_VM=tc-fin-$IDL OUT=~/evidence-fin2-$ID COMMIT_FILE=~/fin2-commit.txt SRC_TGZ=$ARCH SRC_SHA=$ARCH_SHA HADOOP_ALLOW_SLOW=1 KVER=6.17.0-1022-gcp
mkdir -p $OUT; DONE=$OUT/done.txt; touch $DONE
[ -s $DONE ] || { [ -s ~/evidence-fin-$ID/zone.txt ] || { echo "BUILD-FAILED: no ~/evidence-fin-$ID/zone.txt (the builder of the first pair)"; exit 1; }; printf 'builder\nprep\nseed-hadoop\n' > $DONE; cp ~/evidence-fin-$ID/zone.txt $OUT/zone.txt; echo "reusing the builder $BUILDER of the first pair: its preparation and its Hadoop tarball are there, so the stages start at ship-builder"; }
 LOG=$OUT/console.txt; cd $K
exec 9>$OUT/lock; flock -n 9 || { echo "BUILD-FAILED: another step 3 run for build $ID is already active in this Cloud Shell (two runs of the same stage delete each other's work). Wait for it: look at its tab, or run the status block. Do not paste it again"; exit 1; }
echo "build $ID of commit ${COMMIT:0:9}; base image $BASE_IMAGE; builder $BUILDER"
KITID=$(cat ~/fin2-commit.txt)
if [ "$(cat $OUT/kit.sha 2>/dev/null)" != "$KITID" ]; then
  if [ -s $OUT/kit.sha ] || grep -qx ship-builder $DONE; then
    echo "the kit changed since the last run: every stage after prep runs again on the SAME builder (the builder, the kernel and the Hadoop tarball are kept)"
    [ -d $OUT/r4 ] && mv $OUT/r4 $OUT/r4-before-$(date +%H%M) && echo "the ground truth of the earlier kit is kept in $OUT/r4-before-*"
    grep -xE 'builder|prep|seed-hadoop' $DONE > $DONE.n; mv $DONE.n $DONE
  fi
  echo "$KITID" > $OUT/kit.sha
fi
echo "== the builder (the zones a, b, c, f in turn, but only when a zone has no capacity; any other error stops here)"
if ! grep -qx builder $DONE; then
  GOT=""; for z in us-central1-a us-central1-b us-central1-c us-central1-f; do
    echo "--- builder in $z" | tee -a $LOG
    ZONE=$z bash ops/image/test/f03-drive.sh builder 2>&1 | tee $OUT/builder-$z.txt | cut -c1-200; rc=${PIPESTATUS[0]}; cat $OUT/builder-$z.txt >> $LOG
    if [ "$rc" = 0 ]; then GOT=$z; break; fi
    if [ -n "$(gcloud compute instances list --filter="name=$BUILDER" --format='value(name)')" ]; then echo "BUILD-FAILED: the builder was created in $z but its start failed (it is kept; paste the output)"; exit 1; fi
    if grep -qE 'ZONE_RESOURCE_POOL_EXHAUSTED|does not have enough resources|is currently unavailable|resource_availability' $OUT/builder-$z.txt; then echo "   no capacity in $z: trying the next zone"; continue; fi
    echo "BUILD-FAILED: the builder could not be created in $z for a reason other than capacity (the error is above; nothing was created, no other zone is tried)"; exit 1
  done
  [ -n "$GOT" ] || { echo "BUILD-FAILED: no zone had capacity (nothing was created)"; exit 1; }
  echo "$GOT" > $OUT/zone.txt; echo builder >> $DONE
fi
export ZONE="$(cat $OUT/zone.txt)"; echo "the builder is in $ZONE"
SEED=~/hadoop-3.4.3.tar.gz; if [ "$ID" = A ]; then OTHER=B; else OTHER=A; fi
for st in ship-builder prep seed-hadoop bake ship-source job bake-crawl bake-fleet bake-seal manifest; do
  if grep -qx "$st" $DONE; then echo "== $st: done before, skipped"; continue; fi
  if [ "$st" = seed-hadoop ]; then
    echo; echo "##### step seed-hadoop: reuse the Hadoop tarball of the other build (the bake still verifies it against the official SHA-512, so it is the same input as a download)" | tee -a $LOG
    ZOLD="$(cat ~/evidence-r4-B/zone.txt 2>/dev/null)"
    if [ -s "$SEED" ]; then
      { gcloud compute ssh $BUILDER --zone=$ZONE --quiet --command='mkdir -p ~/bake' </dev/null && gcloud compute scp "$SEED" "$BUILDER:~/bake/" --zone=$ZONE --quiet; } 2>&1 | tail -2 && echo "   the tarball is on $BUILDER (copied from Cloud Shell)" || echo "   note: the copy failed; the bake will download it itself"
    elif [ -n "$ZOLD" ]; then
      echo "   no tarball in Cloud Shell: copying it from the old builder tc-r4-b to $BUILDER over the internal network (a few minutes)"
      [ "$(gcloud compute instances describe tc-r4-b --zone=$ZOLD --format='value(status)' 2>/dev/null)" = RUNNING ] || { gcloud compute instances start tc-r4-b --zone=$ZOLD --quiet 2>&1 | tail -1; sleep 20; }
      gcloud compute ssh $BUILDER --zone=$ZONE --quiet --command='mkdir -p ~/bake' </dev/null 2>&1 | tail -1
      eval "$(ssh-agent -s)" >/dev/null; ssh-add ~/.ssh/google_compute_engine 2>&1 | tail -1
      gcloud compute ssh tc-r4-b --zone=$ZOLD --quiet --ssh-flag='-A' --command="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=20 ~/bake/hadoop-3.4.3.tar.gz $BUILDER:~/bake/ && echo COPIED" </dev/null 2>&1 | tail -2 | grep -q COPIED && echo "   the tarball is on $BUILDER (copied from tc-r4-b)" || echo "   note: the copy failed; the bake will download it itself (about an hour on a slow server)"
    else echo "   no tarball to reuse: the bake will download it itself (about an hour on a slow server)"; fi
    echo seed-hadoop >> $DONE; continue
  fi
  echo; echo "##### stage $st ($(date -u +%H:%M:%S) UTC)" | tee -a $LOG
  bash ops/image/test/f03-drive.sh $st 2>&1 | tee -a $LOG | cut -c1-200; rc=${PIPESTATUS[0]}
  [ "$rc" = 0 ] || { echo; echo "BUILD-FAILED at stage $st (the builder $BUILDER is kept; paste the output above)"; exit 1; }
  echo "$st" >> $DONE
done
echo; echo "== what build $ID recorded"
echo "source.txt: $(cat $OUT/r4/source.txt)"; [ "$(cat $OUT/r4/source.txt)" = "commit $COMMIT" ] || { echo "BUILD-FAILED: the image records another commit than the archive's"; exit 1; }
echo "events measured: $(cut -f1 $OUT/r4/events.tsv | tr '\n' ' ')"
tar czf ~/evidence-fin2-$ID.tar.gz -C ~ evidence-fin2-$ID; echo "evidence fingerprint: $(sha256sum ~/evidence-fin2-$ID.tar.gz | cut -c1-64)"
echo; echo "BUILD-DONE (build $ID)" )
