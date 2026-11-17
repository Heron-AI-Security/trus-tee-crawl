#!/usr/bin/env bash
# Rehearsal of crawl step 6, check-build (ops/kits/run-kit/steps/06-check-build.sh), run through the REAL run-kit.sh and the real step.
#   bash run-kit-step6-rehearse.sh TREE        (TREE holds ops/; no cloud: a fake gcloud with one switch for every refusal; a throwaway HOME)
# Checked: a good hand-over (the record is verified against its fingerprint, complete, unpacked into the folder of the run; both images READY with the label record, image A with the commit; quota with room for
# the fleet; no VM of the run; bucket and service account answer; tools in the tree) and that the step STARTS NOTHING; and every refusal says what is wrong: no finished build, a wrong commit file, a record that
# was changed after the build, an incomplete record, a record of another commit or other images, an image that is not READY, a wrong or missing label, too little quota (the number of workers counts), VMs of the run
# that exist already, an export bucket or service account that does not answer, a missing tool. Mutants of the step (each check removed in turn) must all be caught by the same cases.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W="$(mktemp -d)"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1${3:+ | $3}"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
[ -f "$K/steps/06-check-build.sh" ] || { echo "RUN-KIT-STEP6-REHEARSAL-FAIL: step 6 is missing in $K"; exit 1; }
COMMIT_FULL=0123456789abcdef0123456789abcdef01234567; C9=${COMMIT_FULL:0:9}; IA="tc-img-$C9-1"; IB="tc-img-$C9-2"; RUN=1k-s1c0p1

mkdir -p "$W/fakebin"
cat > "$W/fakebin/gcloud" <<'EOG'
#!/bin/sh
echo "$*" >> "$CTL/gcloud.log"
case "$*" in
  "compute images describe "*"--format=value(status)"*) [ -e "$CTL/notready-$4" ] || echo READY ;;
  "compute images describe "*"--format=value(labels.record)"*) if [ -e "$CTL/label-wrong" ]; then echo 00000000000000000000000000000000; else cat "$CTL/record32"; fi ;;
  "compute images describe "*"--format=value(labels.commit)"*) [ -e "$CTL/commit-label-missing" ] || cat "$CTL/commit-full" ;;
  "compute regions describe "*) if [ -e "$CTL/quota-none" ]; then echo "{}"; else read l u < "$CTL/quota"; echo "{\"quotas\":[{\"metric\":\"C2_CPUS\",\"limit\":24,\"usage\":0},{\"metric\":\"C3_CPUS\",\"limit\":$l,\"usage\":$u}]}"; fi ;;
  "compute instances list "*) [ -e "$CTL/vms" ] && cat "$CTL/vms" ;;
  "storage ls "*) [ -e "$CTL/bucket-fail" ] && exit 1 ;;
  "iam service-accounts describe "*) [ -e "$CTL/sa-missing" ] && exit 1 ;;
esac
exit 0
EOG
chmod +x "$W/fakebin/gcloud"
mkstepsdir() {  # KITDIR: a step folder whose crawl step list holds step 6 only, and whose files are links to the kit in KITDIR
  rm -rf "$W/sd"; mkdir -p "$W/sd/steps"
  for f in names.sh lib.sh record.sh tools.sh steps-build.sh; do ln -s "$1/$f" "$W/sd/$f"; done
  ln -s "$1/steps/06-check-build.sh" "$W/sd/steps/06-check-build.sh"
  printf 'RK_STEPS=("6|check-build|Check the image before using it|steps/06-check-build.sh")\n' > "$W/sd/steps-crawl.sh"
}
mkrecord() {  # COMMIT-IN-RECORD [OMIT-FILE]: packs a record into the build folder and writes its fingerprint and the label values
  local R="$W/rec"; rm -rf "$R"; mkdir -p "$R/a/measurements" "$R/b/measurements" "$R/reference"
  echo "$1" > "$R/commit.txt"; echo abcd > "$R/source.sha256"; printf '%s\n%s\n' "$IA" "$IB" > "$R/images.txt"; echo agree > "$R/compare.txt"; echo "{}" > "$R/reference/reference.json"
  for i in a b; do echo ev > "$R/$i/measurements/events.tsv"; echo us-central1-a > "$R/$i/zone.txt"; echo r > "$R/$i/seal-report.txt"; echo j > "$R/$i/job-console.txt"; done
  [ -z "${2:-}" ] || rm -f "$R/$2"
  ( . "$K/record.sh"; rk_record_pack "$R" "$B/record.tar.gz" ) > /dev/null 2>&1; FPX="$(sha256sum "$B/record.tar.gz" | cut -c1-64)"; echo "$FPX" > "$B/record.sha256"; echo "${FPX:0:32}" > "$W/ctl/record32"
}
setup() {  # a fresh home with everything that the build leaves behind, and a fake cloud in a good state
  rm -rf "$W/home" "$W/ctl"; mkdir -p "$W/home" "$W/ctl"; B="$W/home/build-$C9"; mkdir -p "$B/tree"
  echo "$COMMIT_FULL" > "$B/commit.txt"; echo "$COMMIT_FULL" > "$W/ctl/commit-full"; echo "200 136" > "$W/ctl/quota"
  for f in ops/image/test/f1-drive.sh ops/image/test/r3-export-audit.py ops/image/test/r3-receipt-verify.py ops/image/test/r4-accept.sh ops/verify-export.py; do mkdir -p "$B/tree/$(dirname "$f")"; echo "# toy" > "$B/tree/$f"; done
  mkrecord "$COMMIT_FULL"
}

suite() {  # DIR: all the checks against the kit in DIR
  local D="$1" o rc
  mkstepsdir "$D"
  rk() { env HOME="$W/home" CTL="$W/ctl" PATH="$W/fakebin:$PATH" RK_STEPS_DIR="$W/sd" bash "$D/run-kit.sh" crawl --build "$COMMIT_FULL" --size 1k --storage on --comms off --provenance on --until check-build "$@" 2>&1; }
  refused() { [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "^STEP 6 FAILED" && printf '%s' "$o" | grep -qF -- "CHECK-BUILD-FAILED: $1"; }
  t() { o="$(rk)"; rc=$?; refused "$2" && chk "$1" ok || chk "$1" bad "exit $rc: $(printf '%s' "$o" | grep -E 'CHECK-BUILD-FAILED' | head -2 | tr '\n' ' ' | cut -c1-260)"; }
  setup; o="$(rk)"; rc=$?; FP="$(cat "$B/record.sha256")"
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 6 DONE: the build $C9 is ready for the crawl $RUN: the images $IA and $IB carry the build record ${FP:0:16}..., the quota has room for the 44 vCPUs of the fleet (64 free), no VM of this run exists, and the export bucket and its service account answer" && chk "a good hand-over: STEP 6 DONE, with the images, the record, the quota and the checks in one sentence" ok || chk "a good hand-over: STEP 6 DONE (exit $rc)" bad "$(printf '%s' "$o" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  ( . "$D/record.sh"; rk_record_check "$W/home/run-$RUN/record" ) > /dev/null 2>&1 && [ "$(cat "$W/home/run-$RUN/record/commit.txt")" = "$COMMIT_FULL" ] && chk "the verified record is unpacked into the folder of the run, and it is complete" ok || chk "the verified record is unpacked into the folder of the run, and it is complete" bad
  ! grep -qE "instances (create|start|stop|delete)|add-labels|images (create|delete)" "$W/ctl/gcloud.log" && chk "the step starts nothing: it only reads from the cloud" ok || chk "the step starts nothing: it only reads from the cloud" bad "$(grep -E 'create|start|delete|add-labels' "$W/ctl/gcloud.log" | head -2)"
  setup; rm "$B/record.tar.gz"; t "a build that is not finished is refused, and the command to run is named" "the build $C9 is not finished in this home folder"
  setup; echo "0123456789" > "$B/commit.txt"; t "a commit file that does not hold the full commit is refused" "the commit file $B/commit.txt does not hold the full commit"
  setup; echo "garbage" > "$B/record.sha256"; t "a fingerprint file that is not 64 hexadecimal digits is refused" "the fingerprint file"
  setup; echo "extra" >> "$B/record.tar.gz"; t "a record that was changed after the build is refused" "the packed build record does not match its fingerprint"
  setup; mkrecord "$COMMIT_FULL" compare.txt; t "an incomplete record (with a matching fingerprint) is refused" "the build record is incomplete"
  setup; mkrecord "ffffffffffffffffffffffffffffffffffffffff"; t "a record of another commit is refused" "the record is for another commit"
  setup; mkrecord "$COMMIT_FULL"; ( cd "$W/rec" && printf '%s\n%s\n' "$IB" "$IA" > images.txt && . "$D/record.sh" && rk_record_pack "$W/rec" "$B/record.tar.gz" ) > /dev/null 2>&1; FPX="$(sha256sum "$B/record.tar.gz" | cut -c1-64)"; echo "$FPX" > "$B/record.sha256"; echo "${FPX:0:32}" > "$W/ctl/record32"; t "a record that names the images in another order (or other images) is refused" "the record names other images"
  setup; touch "$W/ctl/notready-$IB"; t "an image that is not READY is refused" "the image $IB is not READY"
  setup; touch "$W/ctl/label-wrong"; t "an image whose label record is not the fingerprint is refused" "the image $IA does not carry the label record="
  setup; touch "$W/ctl/commit-label-missing"; t "image A without the label commit is refused" "the image $IA does not carry the label commit="
  setup; echo "200 190" > "$W/ctl/quota"; t "a quota without room for the fleet is refused, and other people's VMs are named as the reason" "the quota has room for 10 vCPUs only, the fleet needs 44"
  setup; o="$(rk --workers 20)"; rc=$?; refused "the quota has room for 64 vCPUs only, the fleet needs 84" && chk "the number of workers counts: 20 workers need 84 vCPUs and are refused" ok || chk "the number of workers counts: 20 workers need 84 vCPUs and are refused" bad "exit $rc: $(printf '%s' "$o" | grep -E 'CHECK-BUILD|STEP 6' | head -2 | tr '\n' ' ' | cut -c1-200)"
  setup; touch "$W/ctl/quota-none"; t "a quota that cannot be read is refused" "the quota C3_CPUS of the region us-central1 cannot be read"
  setup; printf 'tc-%s-m\ntc-%s-w1\n' "$RUN" "$RUN" > "$W/ctl/vms"; t "VMs of this run that exist already are refused, and named" "VMs of this run exist already: tc-$RUN-m tc-$RUN-w1"
  setup; touch "$W/ctl/bucket-fail"; t "an export bucket that cannot be listed is refused" "the export bucket gs://"
  setup; touch "$W/ctl/sa-missing"; t "an export service account that does not exist is refused" "the export service account"
  setup; rm "$B/tree/ops/verify-export.py"; t "a missing tool of the crawl is refused, and the tool is named" "ops/verify-export.py is not in the commit tree"
}

echo "== the checks of step 6 with a fake cloud that has one switch for every refusal"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== the mutants (each check removed in turn; each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME OLD NEW: replaces the exact text OLD of the step by NEW
  local name="$1"; rm -rf "$W/m"; mkdir -p "$W/m/steps"; cp "$K"/*.sh "$W/m/"; cp "$K"/steps/*.sh "$W/m/steps/"
  python3 - "$W/m/steps/06-check-build.sh" "$2" "$3" <<'PY' || { echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PY
  PASS=0; FAIL=0; suite "$W/m"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
mutant "an unfinished build is accepted"            '{ [ -s "$CF" ] && [ -s "$H/$RECORD_TGZ" ] && [ -s "$H/$RECORD_SHA" ]; } || fail'  'true || fail'
mutant "a short commit file is accepted"            '{ [[ "$COMMIT" =~ ^[0-9a-f]{40}$ ]] && [ "${COMMIT:0:9}" = "$C9" ]; } || fail'  'true || fail'
mutant "a changed record is accepted"               'rk_record_verify "$H/$RECORD_TGZ" "${FP:0:32}" || fail'                            'true || fail'
mutant "the record is not unpacked"                 'tar xzf "$H/$RECORD_TGZ" -C "$R" ||'                                               'true ||'
mutant "an incomplete record is accepted"           'rk_record_check "$R" || fail'                                                      'true || fail'
mutant "a record of another commit is accepted"     '[ "$(cat "$R/commit.txt")" = "$COMMIT" ] || fail'                                  'true || fail'
mutant "other images in the record are accepted"    '[ "$(tr '"'"'\n'"'"' '"'"' '"'"' < "$R/images.txt")" = "$IMAGE_1 $IMAGE_2 " ] || fail'  'true || fail'
mutant "an image that is not READY is accepted"     '= READY ] || fail "the image $img is not READY"'                                   '= READY ] || : "the image $img is not READY"'
mutant "a wrong record label is accepted"           '= "${FP:0:32}" ] || fail "the image $img does not carry'                           '= "${FP:0:32}" ] || : "the image $img does not carry'
mutant "a missing commit label is accepted"         '= "$COMMIT" ] || fail "the image $IMAGE_1 does not carry'                          '= "$COMMIT" ] || : "the image $IMAGE_1 does not carry'
mutant "too little quota is accepted"               '[ "$FREE" -ge "$NEED" ] || fail'                                                   'true || fail'
mutant "the workers do not count for the quota"     'NEED=$((VC * (WORKERS + 1)))'                                                      'NEED=$((VC * 1))'
mutant "an unreadable quota is accepted"            '[[ "$Q" =~ ^[0-9]+\ [0-9]+$ ]] || fail'                                            'true || fail'
mutant "VMs of the run that exist are accepted"     '[ -z "$LEFT" ] || fail'                                                            'true || fail'
mutant "a bucket that does not answer is accepted"  '> /dev/null 2>&1 || fail "the export bucket'                                       '> /dev/null 2>&1 || : "the export bucket'
mutant "a missing service account is accepted"      '> /dev/null 2>&1 || fail "the export service account'                              '> /dev/null 2>&1 || : "the export service account'
mutant "a missing tool is accepted"                 '[ -f "$TREE/$f" ] || fail "$f is not in the commit tree'                           '[ -f "$TREE/$f" ] || : "$f is not in the commit tree'
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of step 6: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-STEP6-REHEARSAL-OK"; else echo "RUN-KIT-STEP6-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
