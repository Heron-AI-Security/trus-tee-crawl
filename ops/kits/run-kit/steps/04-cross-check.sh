#!/usr/bin/env bash
# Step 4, cross-check: image A is the PUBLISHED image, image B is the second build of the same commit. Step 4 writes the commit and the root hash of each image on it as labels (image A carries
# the commit: the publish tool finds the image by that label), makes the reference values of image A from two dummy runs of it on TDX VMs and prepares the files to publish, and then checks that the
# files of the two root disks, each opened through dm-verity, are identical: the published image equals an independent build of the same commit. Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names
H="$HOME"; TREE="$H/$BUILD_TREE"; CF="$H/$BUILD_COMMIT_FILE"; W="$H/$XCHECK_DIR"; COMMIT="$(cat "$CF" 2>/dev/null)"
fail() { echo "CROSS-CHECK-FAILED: $*"; exit 1; }
[ -n "$COMMIT" ] && [ -d "$TREE" ] || fail "there is no unpacked commit (step 0 has not run)"
for f in $RK_CROSS_TOOLS; do [ -f "$TREE/$f" ] || fail "$f is not in the commit that was built: the commits that add it must come before the commit that is built"; done
RA="$(awk -F= '/^roothash=/ {print $2}' "$H/$SEAL_OUT_A/seal-report.txt" 2>/dev/null)"; RB="$(awk -F= '/^roothash=/ {print $2}' "$H/$SEAL_OUT_B/seal-report.txt" 2>/dev/null)"
{ [[ "$RA" =~ ^[0-9a-f]{64}$ ]] && [[ "$RB" =~ ^[0-9a-f]{64}$ ]]; } || fail "the seal reports of the two builds have no root hash ($H/$SEAL_OUT_A/seal-report.txt and $H/$SEAL_OUT_B/seal-report.txt): step 3 has not finished"
for img in "$IMAGE_1" "$IMAGE_2"; do [ "$(gcloud compute images describe "$img" --format='value(status)' 2>/dev/null)" = READY ] || fail "the image $img is not READY (step 3 makes it)"; done
mkdir -p "$W"; cd "$TREE" || exit 1
echo "== the two sealed images of ONE commit: A $IMAGE_1 root hash ${RA:0:16}..., B $IMAGE_2 root hash ${RB:0:16}..."
[ "$RA" != "$RB" ] || echo "   note: the two root hashes are EQUAL: the two builds are bit-identical"

echo "== 1. the labels (image A is the PUBLISHED image and carries the commit and its root hash; image B is the second build of the same commit)"
gcloud compute images add-labels "$IMAGE_1" --labels="commit=$COMMIT,verity-a=${RA:0:32},verity-b=${RA:32:32}" > "$W/labels-a.txt" 2>&1 || fail "the labels of $IMAGE_1 could not be set (see $W/labels-a.txt)"
gcloud compute images add-labels "$IMAGE_2" --labels="verity-a=${RB:0:32},verity-b=${RB:32:32},build=second" > "$W/labels-b.txt" 2>&1 || fail "the labels of $IMAGE_2 could not be set (see $W/labels-b.txt)"
echo "   $IMAGE_1: commit and root hash; $IMAGE_2: root hash and build=second"

echo "== 2. the reference of image A: two dummy runs of it, then the files to publish (about 12 minutes)"
if grep -aqE "${RK_M_PUBLISH_OK} commit=${COMMIT:0:9} image=${IMAGE_1}( |\$)" "$W/publish.log" 2>/dev/null && [ -s "$W/pub/publish/reference.json" ]; then
  echo "   the reference of $IMAGE_1 was made by an earlier attempt of this step (same commit, same image): $(ls "$W/pub/publish" | wc -l) files in $W/pub/publish; not made again"
else
  rm -rf "$W/pub"
  rk_run_watched_retry "$W/publish.log" "the dummy runs and the reference of $IMAGE_1" 3 "$RK_TRANSIENT_RX" "$RK_M_PUBLISH_OK" env COMMIT="${COMMIT:0:9}" bash "$TREE/$RK_T_PUBLISH_REFERENCE" "$W/pub"; RC=$?
  if [ "$RC" != 0 ]; then tail -n 8 "$W/publish.log" | cut -c1-700 | sed 's/^/   | /'; fail "the reference of image A could not be published (see $W/publish.log)"; fi
  echo "   the reference is made: $(ls "$W/pub/publish" 2>/dev/null | wc -l) files to publish in $W/pub/publish"
fi

echo "== 3. the published image A against the own build, image B (made from the SECOND archive of the same commit): the files of the two root disks, each opened through dm-verity (about 30 minutes)"
clean_verify() { rm -rf "$W/verify"; }; clean_verify; rm -f "$W/verify.log"
RK_BEFORE_RETRY=clean_verify rk_run_watched_retry "$W/verify.log" "the comparison of the two images" 3 "$RK_TRANSIENT_RX" "$RK_M_VERIFY_OK" bash "$TREE/$RK_T_VERIFY_REFERENCE" "$COMMIT" --published "$W/pub/publish" --published-image "$IMAGE_1" --own-image "$IMAGE_2" --work "$W/verify"; RC=$?
if [ "$RC" != 0 ]; then
  grep -av "^  ok:" "$W/verify.log" | tail -n 12 | cut -c1-700 | sed 's/^/   | /'
  if [ -f "$W/verify/$RK_VERIFY_DIFFS" ]; then echo "== the differences of the file trees, by kind:"; cut -f2 "$W/verify/$RK_VERIFY_DIFFS" | sort | uniq -c | sort -rn | sed 's/^/   /'; echo "== the differences (kind, path, detail), at most 40:"; cut -f2,3,4 "$W/verify/$RK_VERIFY_DIFFS" | sort -k2 | cut -c1-200 | head -40 | sed 's/^/   /'; fi
  fail "the two builds of one commit were NOT verified as the same (the lines above and $W/verify.log say why)"
fi
echo "   the two builds are verified as the same: the file trees are identical and the image run is exact"
tar czf "$H/$BUILD_DIR/cross-check.tar.gz" -C "$H/$BUILD_DIR" "$(basename "$XCHECK_DIR")" 2>/dev/null; echo "   evidence fingerprint: $(sha256sum "$H/$BUILD_DIR/cross-check.tar.gz" | cut -c1-64)"
rk_result "the reference values of $IMAGE_1 are published and the two builds are verified as the same: root hashes A ${RA:0:16}... and B ${RB:0:16}..., file trees identical, image run exact"
