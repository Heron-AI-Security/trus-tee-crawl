#!/usr/bin/env bash
# Rehearsal of build step 4, cross-check (ops/kits/run-kit/steps/04-cross-check.sh), run through the REAL run-kit.sh and the real step.
#   bash run-kit-step4-rehearse.sh TREE        (TREE holds ops/; no cloud: fake publish and verify tools and a fake gcloud that records every label; a throwaway HOME)
# Checked: the two root hashes are read from the seal reports; image A gets the commit and its root hash as labels and image B gets ITS root hash and build=second but NOT the commit (the publish tool
# finds the image by the commit label, and exactly one image may carry it); the reference is made with the 9-character commit into the right folder; the verify tool gets the full commit, the published
# files, image A as the published image and image B as the own build; the step prints plain sentences (no marker of an older tool); and every failure says what happened: a bad root hash, a missing tool
# file, an image that is not READY, labels that cannot be set, a reference that cannot be made (also when the tool exits 0 without its success line), and two builds that are not the same (with the
# differences by kind). Mutants of the step (each check removed in turn) must all be caught by the same cases.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W="$(mktemp -d)"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1${3:+ | $3}"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
[ -f "$K/steps/04-cross-check.sh" ] || { echo "RUN-KIT-STEP4-REHEARSAL-FAIL: step 4 is missing in $K"; exit 1; }
COMMIT_FULL=0123456789abcdef0123456789abcdef01234567; C9=${COMMIT_FULL:0:9}; IA="tc-img-$C9-1"; IB="tc-img-$C9-2"
RA=aaaaaaaaaaaaaaaabbbbbbbbbbbbbbbbccccccccccccccccdddddddddddddddd; RB=1111111111111111222222222222222233333333333333334444444444444444

mkdir -p "$W/fakebin"
cat > "$W/fakebin/gcloud" <<'EOG'
#!/bin/sh
echo "$*" >> "$CTL/gcloud.log"
case "$*" in
  "compute images describe "*"--format=value(status)"*) [ -e "$CTL/notready-$4" ] || echo READY ;;
  "compute images add-labels "*) [ -e "$CTL/labels-fail" ] && { echo "ERROR: label failed"; exit 1; } ;;
esac
exit 0
EOG
chmod +x "$W/fakebin/gcloud"
mkstepsdir() {  # KITDIR: a step folder whose step list holds step 4 only, and whose files are links to the kit in KITDIR
  rm -rf "$W/sd"; mkdir -p "$W/sd/steps"
  for f in names.sh lib.sh record.sh tools.sh steps-crawl.sh; do ln -s "$1/$f" "$W/sd/$f"; done
  ln -s "$1/steps/04-cross-check.sh" "$W/sd/steps/04-cross-check.sh"
  printf 'RK_STEPS=("4|cross-check|Publish the reference values and cross-check the two images|steps/04-cross-check.sh")\n' > "$W/sd/steps-build.sh"
}
setup() {  # a fresh home with the unpacked tree, the commit file and the seal reports of two sealed builds, as steps 0 to 3 leave them
  rm -rf "$W/home" "$W/ctl"; mkdir -p "$W/home" "$W/ctl"; echo "$COMMIT_FULL" > "$W/ctl/commit-full"; B="$W/home/build-$C9"; TR="$B/tree"; mkdir -p "$TR/ops/ci" "$B/seal-a" "$B/seal-b"
  echo "$COMMIT_FULL" > "$B/commit.txt"; echo "roothash=$RA" > "$B/seal-a/seal-report.txt"; echo "roothash=$RB" > "$B/seal-b/seal-report.txt"
  for f in ops/ci/publish-ref.sh ops/verify-reference.sh ops/tree-diff.sh ops/tree-helper.sh ops/tree-lib.sh ops/verify-reference.py; do echo "# toy" > "$TR/$f"; done
  cat > "$TR/ops/ci/publish-ref.sh" <<'EOP'
#!/usr/bin/env bash
C="$(dirname "$HOME")/ctl"; echo "COMMIT=${COMMIT:-}|out=$1" >> "$C/publish.log"; [ -e "$C/slow" ] && sleep 1.5
mkdir -p "$1/publish"; echo "{}" > "$1/publish/reference.json"; echo "x" > "$1/publish/release.json"; echo "publishing..."
[ -e "$C/publish-transient-once" ] && [ "$(wc -l < "$C/publish.log")" = 1 ] && { echo "REFERENCE-RUN-FAILED: could not describe tc-ref-x"; exit 1; }
[ -e "$C/publish-fail" ] && { echo "PUBLISH-REF-FAILED: no stockout wait left"; exit 1; }
[ -e "$C/publish-nomarker" ] && { echo "all done but no marker"; exit 0; }; [ -e "$C/publish-rc1" ] && { echo "PUBLISH-REF-OK commit=$(cat "$C/commit-full") image=tc-img-${COMMIT:-}-1 files=2 out=$1 by=local"; exit 1; }; [ -e "$C/marker-sleep" ] && { echo "PUBLISH-REF-OK commit=$(cat "$C/commit-full") image=tc-img-${COMMIT:-}-1 files=2 out=$1 by=local"; sleep 1.2; exit 0; }; echo "PUBLISH-REF-OK commit=$(cat "$C/commit-full") image=tc-img-${COMMIT:-}-1 files=2 out=$1 by=local"; exit 0
EOP
  cat > "$TR/ops/verify-reference.sh" <<'EOP'
#!/usr/bin/env bash
C="$(dirname "$HOME")/ctl"; echo "$*" >> "$C/verify.log"; W=""; while [ $# -gt 0 ]; do [ "$1" = --work ] && W="$2"; shift; done
echo "  ok:   the first check"
if [ -e "$C/verify-diff" ]; then mkdir -p "$W/trees"; printf 'p\tcontent\t/usr/lib/a\tsha differs\np\tmode\t/etc/b\t0644 vs 0600\np\tcontent\t/usr/lib/c\tsha differs\n' > "$W/trees/differences.tsv"; echo "VERIFY-REFERENCE-FAILED: 3 differences"; exit 1; fi
if [ -e "$C/verify-transient-always" ] || { [ -e "$C/verify-transient-once" ] && [ "$(wc -l < "$C/verify.log")" = 1 ]; }; then echo "REFERENCE-RUN-FAILED: could not describe tc-ref-y"; echo "VERIFY-REFERENCE-FAILED: your own dummy run did not finish; the end of its output: boot event log saved"; exit 1; fi
[ -e "$C/verify-long" ] && { printf 'VERIFY-REFERENCE-FAILED: your own dummy run did not finish; the end of its output: %s END-OF-THE-LONG-LINE\n' "$(printf 'x%.0s' $(seq 1 450))"; exit 1; }
[ -e "$C/verify-fail" ] && { echo "VERIFY-REFERENCE-FAILED: the disk could not be opened"; exit 1; }
[ -e "$C/verify-rc1" ] && { echo "VERIFY-REFERENCE-OK $1 trees=identical image-run=exact"; exit 1; }; echo "VERIFY-REFERENCE-OK $1 trees=identical image-run=exact"; exit 0
EOP
}

suite() {  # DIR: all the checks against the kit in DIR
  local D="$1" o rc
  mkstepsdir "$D"
  rk() { env HOME="$W/home" CTL="$W/ctl" PATH="$W/fakebin:$PATH" RK_STEPS_DIR="$W/sd" RK_HEARTBEAT_SECS=0.2 bash "$D/run-kit.sh" build --commit "$COMMIT_FULL" --until cross-check "$@" 2>&1; }
  refused() { [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "^STEP 4 FAILED" && printf '%s' "$o" | grep -qF -- "CROSS-CHECK-FAILED: $1"; }
  t() { o="$(rk)"; rc=$?; refused "$2" && chk "$1" ok || chk "$1" bad "exit $rc: $(printf '%s' "$o" | grep -E 'CROSS-CHECK-FAILED' | head -2 | tr '\n' ' ' | cut -c1-260)"; }
  setup; o="$(rk)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 4 DONE: the reference values of $IA are published and the two builds are verified as the same: root hashes A ${RA:0:16}... and B ${RB:0:16}..., file trees identical, image run exact" && chk "a good run: STEP 4 DONE, with both root hashes in the result" ok || chk "a good run: STEP 4 DONE (exit $rc)" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  grep -q "images add-labels $IA --labels=commit=$COMMIT_FULL,verity-a=${RA:0:32},verity-b=${RA:32:32}\$" "$W/ctl/gcloud.log" && chk "image A gets the commit and its root hash (two halves of 32 characters) as labels" ok || chk "image A gets the commit and its root hash (two halves of 32 characters) as labels" bad "$(grep add-labels "$W/ctl/gcloud.log" | head -1)"
  grep -q "images add-labels $IB --labels=verity-a=${RB:0:32},verity-b=${RB:32:32},build=second\$" "$W/ctl/gcloud.log" && ! grep "add-labels $IB" "$W/ctl/gcloud.log" | grep -q "commit=" && chk "image B gets ITS root hash and build=second, and NOT the commit (exactly one image may carry it)" ok || chk "image B gets ITS root hash and build=second, and NOT the commit" bad "$(grep "add-labels $IB" "$W/ctl/gcloud.log" | head -1)"
  [ "$(cat "$W/ctl/publish.log")" = "COMMIT=$C9|out=$B/cross-check/pub" ] && chk "the reference is made with the 9-character commit, into the folder of this step" ok || chk "the reference is made with the 9-character commit, into the folder of this step" bad "$(cat "$W/ctl/publish.log")"
  [ "$(cat "$W/ctl/verify.log")" = "$COMMIT_FULL --published $B/cross-check/pub/publish --published-image $IA --own-image $IB --work $B/cross-check/verify" ] && chk "the verify tool gets the full commit, the published files, image A as the published image and image B as the own build" ok || chk "the verify tool gets the full commit, the published files, image A as the published image and image B as the own build" bad "$(cat "$W/ctl/verify.log")"
  ! printf '%s' "$o" | grep -qE "PUBLISH-REF|VERIFY-REFERENCE" && [ -s "$B/cross-check.tar.gz" ] && chk "the step shows plain sentences only (no marker of an older tool) and packs its evidence" ok || chk "the step shows plain sentences only (no marker of an older tool) and packs its evidence" bad "$(printf '%s' "$o" | grep -E 'PUBLISH-REF|VERIFY-REFERENCE' | head -1)"
  setup; echo "roothash=$RA" > "$B/seal-b/seal-report.txt"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "note: the two root hashes are EQUAL: the two builds are bit-identical" && chk "two equal root hashes are noted as bit-identical builds" ok || chk "two equal root hashes are noted as bit-identical builds" bad "exit $rc"
  setup; echo "roothash=zzzz" > "$B/seal-a/seal-report.txt"; t "a root hash that is not 64 hexadecimal digits is refused" "the seal reports of the two builds have no root hash"
  setup; rm "$B/seal-b/seal-report.txt"; t "a missing seal report is refused" "the seal reports of the two builds have no root hash"
  setup; rm "$B/tree/ops/tree-diff.sh"; t "a missing tool file is refused, and the file is named" "ops/tree-diff.sh is not in the commit that was built"
  setup; touch "$W/ctl/notready-$IB"; t "an image that is not READY is refused" "the image $IB is not READY"
  setup; touch "$W/ctl/labels-fail"; t "labels that cannot be set are refused" "the labels of $IA could not be set"
  setup; touch "$W/ctl/publish-fail"; o="$(rk)"; rc=$?; refused "the reference of image A could not be published" && printf '%s' "$o" | grep -q "PUBLISH-REF-FAILED: no stockout wait left" && chk "a reference that cannot be made is refused, and the last lines of the tool are shown" ok || chk "a reference that cannot be made is refused, and the last lines of the tool are shown" bad "exit $rc"
  setup; touch "$W/ctl/publish-nomarker"; t "a publish tool that exits 0 without its success line is refused" "the reference of image A could not be published"
  setup; touch "$W/ctl/publish-rc1"; t "a publish tool that prints its success line but exits with an error is refused" "the reference of image A could not be published"
  setup; touch "$W/ctl/verify-rc1"; t "a verify tool that prints its success line but exits with an error is refused" "the two builds of one commit were NOT verified as the same"
  setup; touch "$W/ctl/verify-diff"; o="$(rk)"; rc=$?; refused "the two builds of one commit were NOT verified as the same" && printf '%s' "$o" | grep -q "the differences of the file trees, by kind:" && printf '%s' "$o" | grep -qE "^ +2 content" && printf '%s' "$o" | grep -qE "^ +1 mode" && chk "two builds that are not the same are refused, with the differences by kind" ok || chk "two builds that are not the same are refused, with the differences by kind" bad "exit $rc"
  setup; touch "$W/ctl/verify-long"; o="$(rk)"; rc=$?; refused "the two builds of one commit were NOT verified as the same" && printf '%s' "$o" | grep -q "END-OF-THE-LONG-LINE" && chk "a long failure line of a tool is shown whole (its reason is at the end of the line)" ok || chk "a long failure line of a tool is shown whole (its reason is at the end of the line)" bad "exit $rc"
  setup; touch "$W/ctl/publish-transient-once"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "trying again, attempt 2 of 3" && [ "$(wc -l < "$W/ctl/publish.log")" = 2 ] && chk "a call to the cloud that fails once while the reference is made is tried again, and the step goes on" ok || chk "a call to the cloud that fails once while the reference is made is tried again, and the step goes on" bad "exit $rc, calls $(wc -l < "$W/ctl/publish.log")"
  setup; touch "$W/ctl/verify-transient-once"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "a call to the cloud failed, which is not a verdict on the images (REFERENCE-RUN-FAILED: could not describe tc-ref-y): trying again, attempt 2 of 3" && [ "$(wc -l < "$W/ctl/verify.log")" = 2 ] && [ "$(wc -l < "$W/ctl/publish.log")" = 1 ] && chk "a call to the cloud that fails once during the comparison is tried again (the reference is not made again), and the step goes on" ok || chk "a call to the cloud that fails once during the comparison is tried again (the reference is not made again), and the step goes on" bad "exit $rc, verify calls $(wc -l < "$W/ctl/verify.log"), publish calls $(wc -l < "$W/ctl/publish.log")"
  setup; touch "$W/ctl/verify-transient-always"; o="$(rk)"; rc=$?; refused "the two builds of one commit were NOT verified as the same" && [ "$(wc -l < "$W/ctl/verify.log")" = 3 ] && printf '%s' "$o" | grep -q "attempt 3 of 3" && chk "a call that keeps failing is tried three times and then reported, never forever" ok || chk "a call that keeps failing is tried three times and then reported, never forever" bad "exit $rc, calls $(wc -l < "$W/ctl/verify.log")"
  setup; touch "$W/ctl/verify-diff"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && [ "$(wc -l < "$W/ctl/verify.log")" = 1 ] && ! printf '%s' "$o" | grep -q "trying again" && chk "a real difference between the images is NEVER tried again" ok || chk "a real difference between the images is NEVER tried again" bad "exit $rc, calls $(wc -l < "$W/ctl/verify.log")"
  setup; touch "$W/ctl/verify-fail"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && [ "$(wc -l < "$W/ctl/verify.log")" = 1 ] && chk "a failure that is no failed call to the cloud is not tried again either" ok || chk "a failure that is no failed call to the cloud is not tried again either" bad "exit $rc, calls $(wc -l < "$W/ctl/verify.log")"
  setup; touch "$W/ctl/verify-fail"; rk > /dev/null; rm -f "$W/ctl/verify-fail"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && [ "$(wc -l < "$W/ctl/publish.log")" = 1 ] && printf '%s' "$o" | grep -q "was made by an earlier attempt of this step (same commit, same image)" && chk "after a failed comparison the rerun does NOT make the reference again (it is reused: 12 minutes saved)" ok || chk "after a failed comparison the rerun does NOT make the reference again (it is reused: 12 minutes saved)" bad "exit $rc, publish calls $(wc -l < "$W/ctl/publish.log")"
  setup; touch "$W/ctl/verify-fail"; rk > /dev/null; rm -f "$W/ctl/verify-fail"; sed -i "s/image=tc-img-$C9-1/image=tc-img-other-1/" "$B/cross-check/publish.log"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && [ "$(wc -l < "$W/ctl/publish.log")" = 2 ] && chk "a reference that an earlier attempt made for ANOTHER image is not reused" ok || chk "a reference that an earlier attempt made for ANOTHER image is not reused" bad "exit $rc, publish calls $(wc -l < "$W/ctl/publish.log")"
  setup; touch "$W/ctl/verify-fail"; rk > /dev/null; rm -f "$W/ctl/verify-fail"; sed -i "s/commit=$COMMIT_FULL/commit=ffffffffffffffffffffffffffffffffffffffff/" "$B/cross-check/publish.log"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && [ "$(wc -l < "$W/ctl/publish.log")" = 2 ] && chk "a reference that an earlier attempt made for ANOTHER commit is not reused" ok || chk "a reference that an earlier attempt made for ANOTHER commit is not reused" bad "exit $rc, publish calls $(wc -l < "$W/ctl/publish.log")"
  setup; touch "$W/ctl/verify-fail"; t "a verify tool that fails is refused" "the two builds of one commit were NOT verified as the same"
  setup; touch "$W/ctl/marker-sleep"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "heartbeat .* the dummy runs" && ! printf '%s' "$o" | grep "heartbeat" | grep -q "PUBLISH-REF" && chk "a heartbeat never shows the success marker of an older tool, even when the tool prints it last" ok || chk "a heartbeat never shows the success marker of an older tool, even when the tool prints it last" bad "exit $rc: $(printf '%s' "$o" | grep heartbeat | head -2 | cut -c1-160 | tr '\n' ' ')"
  setup; touch "$W/ctl/slow"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "\[heartbeat .* the dummy runs and the reference of $IA: " && chk "while the long tools run, a heartbeat shows the last line of their log" ok || chk "while the long tools run, a heartbeat shows the last line of their log" bad "exit $rc"
}

echo "== the checks of step 4 with fake publish and verify tools and a fake cloud"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== the mutants (each check removed in turn; each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME OLD NEW: replaces the exact text OLD of the step by NEW
  local name="$1" f="${4:-steps/04-cross-check.sh}"; rm -rf "$W/m"; mkdir -p "$W/m/steps"; cp "$K"/*.sh "$W/m/"; cp "$K"/steps/*.sh "$W/m/steps/"
  python3 - "$W/m/$f" "$2" "$3" <<'PY' || { echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PY
  PASS=0; FAIL=0; suite "$W/m"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
mutant "a bad root hash is accepted"                  '{ [[ "$RA" =~ ^[0-9a-f]{64}$ ]] && [[ "$RB" =~ ^[0-9a-f]{64}$ ]]; } || fail'  'true || fail'
mutant "a missing tool file is accepted"              '[ -f "$TREE/$f" ] || fail'                                                       'true || fail'
mutant "an image that is not READY is accepted"       '= READY ] || fail "the image $img is not READY'                                  '= READY ] || : "the image $img is not READY'
mutant "image B carries the commit too"               '--labels="verity-a=${RB:0:32},verity-b=${RB:32:32},build=second"'                '--labels="commit=$COMMIT,verity-a=${RB:0:32},verity-b=${RB:32:32},build=second"'
mutant "the labels of image A are not set"            'gcloud compute images add-labels "$IMAGE_1" --labels="commit=$COMMIT,verity-a=${RA:0:32},verity-b=${RA:32:32}" > "$W/labels-a.txt" 2>&1 ||'  'true ||'
mutant "a label failure is ignored"                   '|| fail "the labels of $IMAGE_1 could not be set'                                '|| : "the labels of $IMAGE_1 could not be set'
mutant "the reference gets the full commit"           'env COMMIT="${COMMIT:0:9}" bash'                                                 'env COMMIT="$COMMIT" bash'
mutant "a publish without its success line is accepted"  '3 "$RK_TRANSIENT_RX" "$RK_M_PUBLISH_OK" env COMMIT='  '3 "$RK_TRANSIENT_RX" "." env COMMIT='
mutant "a failed publish is accepted"                 'if [ "$RC" != 0 ]; then tail -n 8 "$W/publish.log"'  'if false; then tail -n 8 "$W/publish.log"'
mutant "a long failure line is cut after 200 characters"  'grep -av "^  ok:" "$W/verify.log" | tail -n 12 | cut -c1-700'  'grep -av "^  ok:" "$W/verify.log" | tail -n 12 | cut -c1-200'
mutant "every failure of the comparison is tried again"  '3 "$RK_TRANSIENT_RX" "$RK_M_VERIFY_OK"'  '3 "." "$RK_M_VERIFY_OK"'
mutant "the comparison is tried once only"           'RK_BEFORE_RETRY=clean_verify rk_run_watched_retry "$W/verify.log" "the comparison of the two images" 3'  'RK_BEFORE_RETRY=clean_verify rk_run_watched_retry "$W/verify.log" "the comparison of the two images" 1'
mutant "the reference is made once only"             'rk_run_watched_retry "$W/publish.log" "the dummy runs and the reference of $IMAGE_1" 3'  'rk_run_watched_retry "$W/publish.log" "the dummy runs and the reference of $IMAGE_1" 1'
mutant "the reference of an earlier attempt is never reused"  'if grep -aqE "${RK_M_PUBLISH_OK}'  'if false && grep -aqE "${RK_M_PUBLISH_OK}'
mutant "a reference of another commit is reused"     'commit=${COMMIT} image=${IMAGE_1}'  'commit=.* image=${IMAGE_1}'
mutant "a reference of another image is reused"      ' image=${IMAGE_1}( |\$)'  ' image=.*'
mutant "a failed comparison is accepted"             $'if [ "$RC" != 0 ]; then\n  grep -av "^  ok:"'  $'if false; then\n  grep -av "^  ok:"'
mutant "a tool that prints its success line but exits with an error is accepted"  'if [ "$rc" = 0 ] && grep -aqE "$okrx" "$log"; then return 0; fi'  'if grep -aqE "$okrx" "$log"; then return 0; fi' lib.sh
mutant "the differences are not shown"                'if [ -f "$W/verify/$RK_VERIFY_DIFFS" ]; then'                                    'if false; then'
mutant "an old tool marker is shown to the user"      'echo "   the reference is made:'                                                   'echo "PUBLISH-REF-OK the reference is made:'
mutant "the heartbeat shows the success line of an older tool"  'grep -av -E "${RK_HIDE_FROM_HEARTBEAT:-^\$}" "$log" | '  'cat "$log" | ' lib.sh
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of step 4: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-STEP4-REHEARSAL-OK"; else echo "RUN-KIT-STEP4-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
