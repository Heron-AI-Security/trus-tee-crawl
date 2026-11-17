#!/usr/bin/env bash
# Step 6, check-build: the hand-over from a build to a crawl. It checks that the build record is the one the build wrote (its fingerprint) and complete, unpacks it into the folder of THIS run so that every later
# step reads exactly the verified copy, checks that both sealed images are READY and carry the label record of that fingerprint and that image A carries the commit, that the quota of the region has room for the
# whole fleet, that no VM of this run exists yet, that the export bucket and its service account answer, and that the tools of the crawl are in the commit tree. It starts nothing.
# Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; . "$KD/record.sh"; rk_load_names
H="$HOME"; BD="$H/$BUILD_DIR"; CF="$BD/commit.txt"; TREE="$H/$BUILD_TREE"; R="$H/$CRAWL_RECORD"
fail() { echo "CHECK-BUILD-FAILED: $*"; exit 1; }
echo "== 1. the build record of $C9 (written by the build, fingerprint on both images)"
{ [ -s "$CF" ] && [ -s "$H/$RECORD_TGZ" ] && [ -s "$H/$RECORD_SHA" ]; } || fail "the build $C9 is not finished in this home folder ($BD has no commit file or no build record): run  bash run-kit.sh build --commit $C9"
COMMIT="$(cat "$CF")"; { [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] && [ "${COMMIT:0:9}" = "$C9" ]; } || fail "the commit file $CF does not hold the full commit of $C9"
FP="$(tr -d ' \r\n' < "$H/$RECORD_SHA")"; [[ "$FP" =~ ^[0-9a-f]{64}$ ]] || fail "the fingerprint file $H/$RECORD_SHA does not hold 64 hexadecimal digits"
rk_record_verify "$H/$RECORD_TGZ" "${FP:0:32}" || fail "the packed build record does not match its fingerprint ${FP:0:16}... (it was changed after the build)"
rm -rf "$R"; mkdir -p "$R" && tar xzf "$H/$RECORD_TGZ" -C "$R" || fail "the build record could not be unpacked into $R"
rk_record_check "$R" || fail "the build record is incomplete (the missing files are named above)"
[ "$(cat "$R/commit.txt")" = "$COMMIT" ] || fail "the record is for another commit ($(cut -c1-12 "$R/commit.txt")...) than the build $C9"
[ "$(tr '\n' ' ' < "$R/images.txt")" = "$IMAGE_1 $IMAGE_2 " ] || fail "the record names other images than $IMAGE_1 and $IMAGE_2"
echo "   complete, fingerprint ${FP:0:16}..., unpacked into $R"

echo "== 2. the two sealed images"
for img in "$IMAGE_1" "$IMAGE_2"; do
  [ "$(gcloud compute images describe "$img" --format='value(status)' 2>/dev/null)" = READY ] || fail "the image $img is not READY"
  [ "$(gcloud compute images describe "$img" --format='value(labels.record)' 2>/dev/null)" = "${FP:0:32}" ] || fail "the image $img does not carry the label record=${FP:0:32} (it is not the image of this build record)"
done
[ "$(gcloud compute images describe "$IMAGE_1" --format='value(labels.commit)' 2>/dev/null)" = "$COMMIT" ] || fail "the image $IMAGE_1 does not carry the label commit=$COMMIT"
echo "   $IMAGE_1 and $IMAGE_2: READY, record=${FP:0:32}; $IMAGE_1 carries the commit"

echo "== 3. the quota of the region, and VMs of this run that exist already"
REGION="${ZONE%-*}"; VC="${MACHINE_TYPE##*-}"; FAM="${MACHINE_TYPE%%-*}"; [[ "$VC" =~ ^[0-9]+$ ]] || fail "the vCPU count cannot be read from the machine type $MACHINE_TYPE"
NEED=$((VC * (WORKERS + 1))); METRIC="$(echo "$FAM" | tr a-z A-Z)_CPUS"
Q="$(gcloud compute regions describe "$REGION" --format=json 2>/dev/null | python3 -c 'import sys, json
m = sys.argv[1]; q = [x for x in json.load(sys.stdin).get("quotas", []) if x.get("metric") == m]
print("%d %d" % (q[0]["limit"], q[0]["usage"])) if q else print("")' "$METRIC" 2>/dev/null)"
[[ "$Q" =~ ^[0-9]+\ [0-9]+$ ]] || fail "the quota $METRIC of the region $REGION cannot be read"
LIMIT="${Q% *}"; USED="${Q#* }"; FREE=$((LIMIT - USED)); echo "   $METRIC $USED of $LIMIT in use; this fleet needs $NEED vCPUs ($((WORKERS + 1)) VMs of $MACHINE_TYPE)"
[ "$FREE" -ge "$NEED" ] || fail "the quota has room for $FREE vCPUs only, the fleet needs $NEED: other VMs of the project are running (never stop other people's VMs); use fewer workers, or wait"
LEFT="$(gcloud compute instances list --filter="labels.tc-run=$RUN_LABEL" --format='value(name)' 2>/dev/null | tr '\n' ' ')"
[ -z "$LEFT" ] || fail "VMs of this run exist already: $LEFT (a run of the same configuration was started before): delete them with  bash run-kit.sh stop crawl  and the same flags, or give this run another --tag"

echo "== 4. the export bucket and its service account, and the tools of the crawl"
gcloud storage ls "gs://$RK_EXPORT_BUCKET/" > /dev/null 2>&1 || fail "the export bucket gs://$RK_EXPORT_BUCKET cannot be listed with your account"
gcloud iam service-accounts describe "$RK_EXPORT_SA" > /dev/null 2>&1 || fail "the export service account $RK_EXPORT_SA does not exist or cannot be read"
for f in $RK_CRAWL_TOOLS; do [ -f "$TREE/$f" ] || fail "$f is not in the commit tree $TREE"; done
echo "   gs://$RK_EXPORT_BUCKET answers, $RK_EXPORT_SA exists, $(echo $RK_CRAWL_TOOLS | wc -w) tools are in the tree"
rk_result "the build $C9 is ready for the crawl $RUN_ID: the images $IMAGE_1 and $IMAGE_2 carry the build record ${FP:0:16}..., the quota has room for the $NEED vCPUs of the fleet ($FREE free), no VM of this run exists, and the export bucket and its service account answer"
