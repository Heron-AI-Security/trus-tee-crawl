( set -uo pipefail
ID="${ID:-A}"; K=~/r47work/tree; IDL="${ID,,}"
[ -s ~/r47-commit.txt ] && [ -s ~/r4-base-image.txt ] && [ -d "$K" ] || { echo "BUILD-FAILED: the prepare stage has not run (it unpacks the source archive)"; exit 1; }
COMMIT="$(cat ~/r47-commit.txt)"; ARCH=~/src-r47-${EXPECT:?give the commit id in the command (EXPECT=...)}.tgz; [ "$ID" = B ] && ARCH=~/src-r47-${EXPECT}-alt.tgz; [ -f "$ARCH" ] || { echo "BUILD-FAILED: no archive $ARCH (the prepare stage makes it)"; exit 1; }; ARCH_SHA=$(sha256sum $ARCH | cut -c1-64)
export BASE_IMAGE="$(cat ~/r4-base-image.txt)" BUILDER=tc-r47-$IDL MANIFEST_VM=tc-r47-$IDL OUT=~/evidence-r47-$ID COMMIT_FILE=~/r47-commit.txt SRC_TGZ=$ARCH SRC_SHA=$ARCH_SHA HADOOP_ALLOW_SLOW=1 KVER=6.17.0-1022-gcp
mkdir -p $OUT; DONE=$OUT/done.txt; touch $DONE; LOG=$OUT/console.txt; cd $K
exec 9>$OUT/lock; flock -n 9 || { echo "BUILD-FAILED: another step 3 run for build $ID is already active in this Cloud Shell (two runs of the same stage delete each other's work). Wait for it: look at its tab, or run the status block. Do not paste it again"; exit 1; }
echo "build $ID of commit ${COMMIT:0:9}; base image $BASE_IMAGE; builder $BUILDER"
KITID=$(cat ~/r47-commit.txt)
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
for st in ship-builder aptpin prep seed-hadoop bake ship-source job bake-crawl bake-fleet bake-seal manifest; do
  if grep -qx "$st" $DONE; then echo "== $st: done before, skipped"; continue; fi
  if [ "$st" = seed-hadoop ]; then
    echo; echo "##### step seed-hadoop: the Hadoop tarball from tc-fin-b, builder to builder (the bake still checks it against the official SHA-512)" | tee -a $LOG
    ZS="$(cat ~/evidence-fin-B/zone.txt)"; GOTIT=0
    gcloud compute ssh $BUILDER --zone=$ZONE --quiet --command='mkdir -p ~/bake' </dev/null 2>&1 | tail -1
    eval "$(ssh-agent -s 8>&- 9>&-)" >/dev/null; ssh-add ~/.ssh/google_compute_engine 2>&1 | tail -1
    for try in 1 2 3; do
      RES="$(gcloud compute ssh tc-fin-b --zone=$ZS --quiet --ssh-flag='-A' --command="scp -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=20 ~/bake/hadoop-3.4.3.tar.gz $BUILDER:~/bake/ && echo COPIED" </dev/null 2>&1 | tail -4)"
      echo "$RES" | grep -q COPIED && { GOTIT=1; break; }; echo "   attempt $try failed: $(echo "$RES" | tr '\n' ' ' | cut -c1-220)"; sleep 20
    done
    [ -n "${SSH_AGENT_PID:-}" ] && kill "$SSH_AGENT_PID" 2>/dev/null; true
    if [ $GOTIT = 1 ]; then echo "   the tarball is on $BUILDER (copied from tc-fin-b)"
    elif [ "${ALLOW_DOWNLOAD:-0}" = 1 ]; then echo "   no copy: the bake will download it (about two hours): allowed by ALLOW_DOWNLOAD=1"
    else echo "BUILD-FAILED: the Hadoop copy from tc-fin-b failed 3 times (see above) and nothing was downloaded. Run again with ALLOW_DOWNLOAD=1 to accept the 2-hour download"; exit 1; fi
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
tar czf ~/evidence-r47-$ID.tar.gz -C ~ evidence-r47-$ID; echo "evidence fingerprint: $(sha256sum ~/evidence-r47-$ID.tar.gz | cut -c1-64)"
echo; echo "BUILD-DONE (build $ID)" )
