#!/usr/bin/env bash
# Rehearsal of build step 5, build-record (ops/kits/run-kit/steps/05-build-record.sh), run through the REAL run-kit.sh and the real step.
#   bash run-kit-step5-rehearse.sh TREE        (TREE holds ops/; no cloud: a fake gcloud that stores and reads back the labels; a throwaway HOME)
# Checked: the record holds exactly what a crawl needs (the commit, the SHA-256 of the source archive, the two image names in order, the comparison, the measurements, zone, seal report and job
# console of each build, and the published reference), is complete, is packed so that the same inputs always give the same fingerprint and another input another one, and its first 32
# characters are written on BOTH images as the label record and read back; and every failure says what is missing: no commit file, no reference, no comparison, no seal report, incomplete
# evidence of a build, a label that cannot be set, a label that reads back differently. Mutants of the step (each check removed in turn) must all be caught by the same cases.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W="$(mktemp -d)"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1${3:+ | $3}"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
[ -f "$K/steps/05-build-record.sh" ] || { echo "RUN-KIT-STEP5-REHEARSAL-FAIL: step 5 is missing in $K"; exit 1; }
COMMIT_FULL=0123456789abcdef0123456789abcdef01234567; C9=${COMMIT_FULL:0:9}; IA="tc-img-$C9-1"; IB="tc-img-$C9-2"

mkdir -p "$W/fakebin"
cat > "$W/fakebin/gcloud" <<'EOG'
#!/bin/sh
echo "$*" >> "$CTL/gcloud.log"
case "$*" in
  "compute images add-labels "*) [ -e "$CTL/label-fail" ] && { echo "ERROR: label failed"; exit 1; }; mkdir -p "$CTL/labels"; v="${*#*--labels=record=}"; echo "${v%% *}" > "$CTL/labels/$4" ;;
  "compute images describe "*"--format=value(labels.record)"*) if [ -e "$CTL/readback-wrong" ]; then echo 00000000000000000000000000000000; else cat "$CTL/labels/$4" 2>/dev/null; fi ;;
esac
exit 0
EOG
chmod +x "$W/fakebin/gcloud"
mkstepsdir() {  # KITDIR: a step folder whose step list holds step 5 only, and whose files are links to the kit in KITDIR
  rm -rf "$W/sd"; mkdir -p "$W/sd/steps"
  for f in names.sh lib.sh record.sh tools.sh steps-crawl.sh; do ln -s "$1/$f" "$W/sd/$f"; done
  ln -s "$1/steps/05-build-record.sh" "$W/sd/steps/05-build-record.sh"
  printf 'RK_STEPS=("5|build-record|Write the build record|steps/05-build-record.sh")\n' > "$W/sd/steps-build.sh"
}
setup() {  # a fresh home with everything that steps 0 to 4 leave behind
  rm -rf "$W/home" "$W/ctl"; mkdir -p "$W/home" "$W/ctl"; B="$W/home/build-$C9"
  echo "$COMMIT_FULL" > "$B.tmp" 2>/dev/null; mkdir -p "$B"; mv "$B.tmp" "$B/commit.txt"; head -c 3000 /dev/urandom > "$W/home/src-$C9.tgz"
  for i in a b; do mkdir -p "$B/$i/r4" "$B/seal-$i"; for n in $(seq 1 15); do printf 'ev%s\tdigest-%s-%s\n' $n $n $i; done > "$B/$i/r4/events.tsv"; echo "extra $i" > "$B/$i/r4/source.txt"; echo us-central1-a > "$B/$i/zone.txt"; echo "job console $i" > "$B/$i/f03-job-console.txt"; echo "roothash=$i$i$i" > "$B/seal-$i/seal-report.txt"; done
  echo "the two builds of commit $COMMIT_FULL agree" > "$B/compare.txt"; mkdir -p "$B/cross-check/pub/publish"; echo "{}" > "$B/cross-check/pub/publish/reference.json"; echo "release" > "$B/cross-check/pub/publish/release.json"
}

suite() {  # DIR: all the checks against the kit in DIR
  local D="$1" o rc FP
  mkstepsdir "$D"
  rk() { env HOME="$W/home" CTL="$W/ctl" PATH="$W/fakebin:$PATH" RK_STEPS_DIR="$W/sd" bash "$D/run-kit.sh" build --commit "$COMMIT_FULL" --until build-record "$@" 2>&1; }
  refused() { [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "^STEP 5 FAILED" && printf '%s' "$o" | grep -qF -- "BUILD-RECORD-FAILED: $1"; }
  t() { o="$(rk)"; rc=$?; refused "$2" && chk "$1" ok || chk "$1" bad "exit $rc: $(printf '%s' "$o" | grep -E 'BUILD-RECORD-FAILED' | head -2 | tr '\n' ' ' | cut -c1-260)"; }
  setup; o="$(rk)"; rc=$?; FP="$(cat "$B/record.sha256" 2>/dev/null)"
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 5 DONE: the build record of commit $C9 is written: 16 files, fingerprint ${FP:0:16}..., written on both images as the label record" && chk "a good run: STEP 5 DONE, with the number of files and the start of the fingerprint" ok || chk "a good run: STEP 5 DONE (exit $rc)" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  R="$B/record"; [ "$(cat "$R/commit.txt")" = "$COMMIT_FULL" ] && [ "$(cat "$R/images.txt" | tr '\n' ' ')" = "$IA $IB " ] && [ "$(cat "$R/source.sha256")" = "$(sha256sum "$W/home/src-$C9.tgz" | cut -c1-64)" ] && chk "the record names the full commit, the two images in order (A, then B) and the SHA-256 of the source archive" ok || chk "the record names the full commit, the two images in order (A, then B) and the SHA-256 of the source archive" bad
  cmp -s "$R/a/measurements/events.tsv" "$B/a/r4/events.tsv" && cmp -s "$R/b/measurements/events.tsv" "$B/b/r4/events.tsv" && [ -s "$R/a/measurements/source.txt" ] && cmp -s "$R/a/job-console.txt" "$B/a/f03-job-console.txt" && cmp -s "$R/b/seal-report.txt" "$B/seal-b/seal-report.txt" && cmp -s "$R/reference/reference.json" "$B/cross-check/pub/publish/reference.json" && [ -s "$R/reference/release.json" ] && cmp -s "$R/compare.txt" "$B/compare.txt" && chk "the record holds the whole measurement folder of each build, the job console, the seal report, the comparison and every published reference file" ok || chk "the record holds the whole measurement folder of each build, the job console, the seal report, the comparison and every published reference file" bad
  ( . "$D/record.sh"; rk_record_check "$R" ) > /dev/null 2>&1 && tar tzf "$B/record.tar.gz" | grep -q "reference/reference.json" && chk "the record passes its own completeness check and is packed" ok || chk "the record passes its own completeness check and is packed" bad
  [ "$(cat "$W/ctl/labels/$IA" 2>/dev/null)" = "${FP:0:32}" ] && [ "$(cat "$W/ctl/labels/$IB" 2>/dev/null)" = "${FP:0:32}" ] && chk "the first 32 characters of the fingerprint are written on BOTH images as the label record" ok || chk "the first 32 characters of the fingerprint are written on BOTH images as the label record" bad "A: $(cat "$W/ctl/labels/$IA" 2>/dev/null) B: $(cat "$W/ctl/labels/$IB" 2>/dev/null) fp ${FP:0:32}"
  [ "$(sha256sum "$B/record.tar.gz" | cut -c1-64)" = "$FP" ] && chk "record.sha256 is the SHA-256 of the packed record" ok || chk "record.sha256 is the SHA-256 of the packed record" bad
  o="$(rk --restart)"; rc=$?; [ "$rc" = 0 ] && [ "$(cat "$B/record.sha256")" = "$FP" ] && chk "the same inputs give the same fingerprint again (the record does not depend on the time it was made)" ok || chk "the same inputs give the same fingerprint again (the record does not depend on the time it was made)" bad "exit $rc"
  echo "the two builds of commit differ" > "$B/compare.txt"; o="$(rk --restart)"; rc=$?; [ "$rc" = 0 ] && [ "$(cat "$B/record.sha256")" != "$FP" ] && chk "another comparison gives another fingerprint" ok || chk "another comparison gives another fingerprint" bad "exit $rc"
  setup; rm "$B/commit.txt"; t "a missing commit file is refused" "there is no commit file"
  setup; rm "$B/cross-check/pub/publish/reference.json"; t "a missing published reference is refused, and step 4 is named" "the published reference is missing"
  setup; rm "$B/compare.txt"; t "a missing comparison is refused, and step 2 is named" "the comparison of the two builds is missing"
  setup; rm "$B/seal-b/seal-report.txt"; t "a missing seal report is refused, and step 3 is named" "the seal reports are missing"
  setup; rm "$B/b/f03-job-console.txt"; t "an incomplete evidence of a build is refused, and the build is named" "the evidence of build B is incomplete"
  setup; rm "$B/a/r4/events.tsv"; t "a build without measurements is refused" "the evidence of build A is incomplete"
  setup; touch "$W/ctl/label-fail"; t "a label that cannot be set is refused" "the label record of $IA could not be set"
  setup; touch "$W/ctl/readback-wrong"; t "a label that reads back differently from what was written is refused" "the label record of $IA reads back differently"
}

echo "== the checks of step 5 with a fake cloud that stores and reads back the labels"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== the mutants (each check removed in turn; each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME OLD NEW: replaces the exact text OLD of the step by NEW
  local name="$1"; rm -rf "$W/m"; mkdir -p "$W/m/steps"; cp "$K"/*.sh "$W/m/"; cp "$K"/steps/*.sh "$W/m/steps/"
  python3 - "$W/m/steps/05-build-record.sh" "$2" "$3" <<'PY' || { echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PY
  PASS=0; FAIL=0; suite "$W/m"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
mutant "the commit file is not required"             '[ -s "$CF" ] || fail'                                                        'true || fail'
mutant "the published reference is not required"     '[ -s "$PUB/reference.json" ] || fail'                                        'true || fail'
mutant "the comparison is not required"              '[ -s "$BD/compare.txt" ] || fail'                                            'true || fail'
mutant "the seal reports are not required"           '[ -s "$H/$SEAL_OUT_A/seal-report.txt" ] && [ -s "$H/$SEAL_OUT_B/seal-report.txt" ] || fail'  'true || fail'
mutant "the evidence of a build is not required"     '[ -s "$BD/$i/r4/events.tsv" ] && [ -s "$BD/$i/zone.txt" ] && [ -s "$BD/$i/$RK_JOB_CONSOLE_FILE" ] || fail'  'true || fail'
mutant "the measurements are not copied"             'cp -r "$BD/$i/r4/." "$REC/$i/measurements/"; '                                ''
mutant "the images are listed in the wrong order"    "printf '%s\\n%s\\n' \"\$IMAGE_1\" \"\$IMAGE_2\""                              "printf '%s\\n%s\\n' \"\$IMAGE_2\" \"\$IMAGE_1\""
mutant "the source archive is not fingerprinted"     'sha256sum "$H/$SOURCE_TGZ" | cut -c1-64 > "$REC/source.sha256"'              'echo 0000 > "$REC/source.sha256"'
mutant "the record is not packed"                    'rk_record_pack "$REC" "$H/$RECORD_TGZ"'                                         'true "$H/$RECORD_TGZ"'
mutant "the reference files are not copied"          'cp -r "$PUB/." "$REC/reference/"'                                              'cp "$PUB/reference.json" "$REC/reference/"'
mutant "the fingerprint is not written"              'FP="$(rk_record_fingerprint "$H/$RECORD_TGZ")"; echo "$FP" > "$H/$RECORD_SHA"'  'FP="$(rk_record_fingerprint "$H/$RECORD_TGZ")"'
mutant "only image A gets the label"                 'for img in "$IMAGE_1" "$IMAGE_2"; do
  gcloud compute images add-labels'                                                       'for img in "$IMAGE_1"; do
  gcloud compute images add-labels'
mutant "a label failure is ignored"                  '> "$BD/label-record.txt" 2>&1 || fail "the label record of $img could not be set'  '> "$BD/label-record.txt" 2>&1 || : "the label record of $img could not be set'
mutant "the label is not read back"                  '[ "$(gcloud compute images describe "$img" --format='"'"'value(labels.record)'"'"' 2>/dev/null)" = "${FP:0:32}" ] || fail "the label record of $img reads back differently from ${FP:0:32}"'  'true'
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of step 5: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-STEP5-REHEARSAL-OK"; else echo "RUN-KIT-STEP5-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
