#!/usr/bin/env bash
# Step 5, build-record: collects what a later crawl needs from this build into ONE record (~/build-<commit>/record), checks that it is complete, packs it so that the same files always give the same
# archive, and writes the first 32 characters of its fingerprint on both images as the label record. A crawl uses a sealed image only if the record is complete and its fingerprint is the one on the image.
# Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; . "$KD/record.sh"; rk_load_names
H="$HOME"; BD="$H/$BUILD_DIR"; REC="$H/$RECORD_DIR"; CF="$H/$BUILD_COMMIT_FILE"; PUB="$H/$XCHECK_DIR/pub/publish"
fail() { echo "BUILD-RECORD-FAILED: $*"; exit 1; }
[ -s "$CF" ] || fail "there is no commit file (step 0 has not run)"
[ -s "$PUB/reference.json" ] || fail "the published reference is missing ($PUB/reference.json): step 4 has not finished"
for i in a b; do [ -s "$BD/$i/r4/events.tsv" ] && [ -s "$BD/$i/zone.txt" ] && [ -s "$BD/$i/$RK_JOB_CONSOLE_FILE" ] || fail "the evidence of build ${i^^} is incomplete (step 1)"; done
[ -s "$BD/compare.txt" ] || fail "the comparison of the two builds is missing ($BD/compare.txt): step 2 has not finished"
[ -s "$H/$SEAL_OUT_A/seal-report.txt" ] && [ -s "$H/$SEAL_OUT_B/seal-report.txt" ] || fail "the seal reports are missing (step 3)"

echo "== 1. collect the record in $REC"
rm -rf "$REC"; mkdir -p "$REC/a/measurements" "$REC/b/measurements" "$REC/reference" || fail "cannot make the folder $REC"
cp "$CF" "$REC/commit.txt"; sha256sum "$H/$SOURCE_TGZ" | cut -c1-64 > "$REC/source.sha256"; printf '%s\n%s\n' "$IMAGE_1" "$IMAGE_2" > "$REC/images.txt"; cp "$BD/compare.txt" "$REC/compare.txt"
for i in a b; do
  cp -r "$BD/$i/r4/." "$REC/$i/measurements/"; cp "$BD/$i/zone.txt" "$REC/$i/zone.txt"; cp "$BD/$i/$RK_JOB_CONSOLE_FILE" "$REC/$i/job-console.txt"
  if [ "$i" = a ]; then cp "$H/$SEAL_OUT_A/seal-report.txt" "$REC/a/seal-report.txt"; else cp "$H/$SEAL_OUT_B/seal-report.txt" "$REC/b/seal-report.txt"; fi
done
cp -r "$PUB/." "$REC/reference/"
rk_record_check "$REC" || fail "the record is incomplete (the missing files are named above)"
echo "   $(find "$REC" -type f | wc -l) files, $(du -sk "$REC" | cut -f1) KB"

echo "== 2. pack it (the same files always give the same archive) and fingerprint it"
rk_record_pack "$REC" "$H/$RECORD_TGZ" || fail "the record could not be packed"
FP="$(rk_record_fingerprint "$H/$RECORD_TGZ")"; echo "$FP" > "$H/$RECORD_SHA"; echo "   fingerprint: $FP"

echo "== 3. write the first 32 characters on both images as the label record, and read them back"
for img in "$IMAGE_1" "$IMAGE_2"; do
  gcloud compute images add-labels "$img" --labels="record=${FP:0:32}" > "$BD/label-record.txt" 2>&1 || fail "the label record of $img could not be set (see $BD/label-record.txt)"
  [ "$(gcloud compute images describe "$img" --format='value(labels.record)' 2>/dev/null)" = "${FP:0:32}" ] || fail "the label record of $img reads back differently from ${FP:0:32}"
  echo "   $img carries record=${FP:0:32}"
done
rk_record_verify "$H/$RECORD_TGZ" "${FP:0:32}" || fail "the packed record does not match its own fingerprint"
rk_result "the build record of commit ${COMMIT:-$(cut -c1-9 "$CF")} is written: $(find "$REC" -type f | wc -l) files, fingerprint ${FP:0:16}..., written on both images as the label record (the record is $H/$RECORD_TGZ)"
