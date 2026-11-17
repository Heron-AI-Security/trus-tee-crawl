#!/usr/bin/env bash
# Rehearsal of build step 3, seal-images (ops/kits/run-kit/steps/03-seal-images.sh), run through the REAL run-kit.sh and the real step.
#   bash run-kit-step3-rehearse.sh TREE        (TREE holds ops/; no cloud: a fake image driver and a fake gcloud that tracks VM status, disks and images; a throwaway HOME)
# Checked: both builders are stopped and the sealing session is checked first; each build is locked, cleaned and sealed in ONE driver call with the settings that the driver reads
# (its builder and zone, its image, its folder, its helper VM, test VM and disk copy, the kernel from the committed packages) and nothing else of this run in the environment; the
# images are made and the helper VMs and disk copies are deleted; and the step decides by itself what an earlier attempt left behind: a sealed disk is never sealed twice, a builder
# that was locked is never started again, leftovers of a killed attempt stop the step with the exact command that removes them (and after that only the sealing of the disk runs),
# an image that is READY is not made again, and every failure says what happened.
# Mutants of the step (each check removed in turn) must all be caught by the same cases.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W="$(mktemp -d)"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1${3:+ | $3}"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
[ -f "$K/steps/03-seal-images.sh" ] || { echo "RUN-KIT-STEP3-REHEARSAL-FAIL: step 3 is missing in $K"; exit 1; }
COMMIT_FULL=0123456789abcdef0123456789abcdef01234567; C9=${COMMIT_FULL:0:9}; BA="tc-b-$C9-a"; BB="tc-b-$C9-b"; IA="tc-img-$C9-1"; IB="tc-img-$C9-2"

mkdir -p "$W/fakebin"
cat > "$W/fakebin/gcloud" <<'EOG'
#!/bin/sh
echo "$*" >> "$CTL/gcloud.log"
case "$*" in
  "compute instances stop "*) [ -e "$CTL/nostop-$4" ] || { mkdir -p "$CTL/status"; echo TERMINATED > "$CTL/status/$4"; } ;;
  "compute instances describe "*"--format=value(status)"*) if [ -e "$CTL/status/$4" ]; then cat "$CTL/status/$4"; else echo RUNNING; fi ;;
  "compute instances list --filter="*"--format=value(name)"*) for n in $(echo "$*" | sed 's/.*--filter=//; s/ --format.*//; s/name=//g; s/ OR / /g'); do [ -e "$CTL/vms/$n" ] && echo "$n"; done ;;
  "compute disks list --filter=name="*) n="${*#*--filter=name=}"; n="${n%% *}"; [ -e "$CTL/disks/$n" ] && echo "$n" ;;
  "compute images describe "*) [ -e "$CTL/images/$4" ] && echo READY ;;
esac
exit 0
EOG
chmod +x "$W/fakebin/gcloud"
cat > "$W/fake-driver.sh" <<'EOD'
#!/usr/bin/env bash
C="$(dirname "$HOME")/ctl"; mkdir -p "$C/status" "$C/vms" "$C/disks" "$C/images"
echo "$*|BUILDER=${BUILDER:-}|ZONE=${ZONE:-}|IMG=${IMG:-}|OUT=${OUT:-}|KVER=${KVER:-}|COMMIT_FILE=${COMMIT_FILE:-}|SEAL_DISK=${SEAL_DISK:-}|SEALER=${SEALER:-}|SEAL_TEST=${SEAL_TEST:-}|CONFIRM=${CONFIRM:-}|SCRATCH=${SCRATCH_GB:-}|leak=$(env | grep -cE '^(ID|COMMIT|WORKERS|MACHINE_TYPE|DRY|RUN_ID|MASTER)=')" >> "$C/driver.log"
for st in "$@"; do
  echo "fake driver: stage $st for ${BUILDER:-}"
  [ -e "$C/fail-$st-$BUILDER" ] && { echo "the stage $st broke on $BUILDER"; exit 1; }
  case "$st" in
    builder) echo RUNNING > "$C/status/$BUILDER" ;;
    seal-locked) mkdir -p "$OUT"; echo "SEAL-DONE locked and cleaned" >> "$OUT/f4-seal-console.txt"; echo TERMINATED > "$C/status/$BUILDER" ;;
    seal-disk) touch "$C/disks/$SEAL_DISK" "$C/vms/$SEALER"; [ -e "$C/slow" ] && sleep 1.5
      if [ -e "$C/kill-seal-disk-$BUILDER" ]; then echo "killed in the middle"; exit 1; fi
      echo "NORMALIZE-OK 5 groups removed"; printf 'tmp\t.\t12\nlogs\t.\t30\n' > "$OUT/normalize-report.txt"; [ -e "$C/no-sealok-$BUILDER" ] || echo "SEAL-OK root hash abc123" ;;
    seal-image) [ -e "$C/image-fail" ] && { echo "image error"; exit 1; }; [ -e "$C/image-notready" ] || touch "$C/images/$IMG" ;;
    seal-delete) rm -f "$C/disks/$SEAL_DISK" "$C/vms/$SEALER" "$C/vms/$SEAL_TEST" ;;
  esac
done
exit 0
EOD

mkstepsdir() {  # KITDIR: a step folder whose step list holds step 3 only, and whose files are links to the kit in KITDIR
  rm -rf "$W/sd"; mkdir -p "$W/sd/steps"
  for f in names.sh lib.sh record.sh tools.sh steps-crawl.sh; do ln -s "$1/$f" "$W/sd/$f"; done
  ln -s "$1/steps/03-seal-images.sh" "$W/sd/steps/03-seal-images.sh"
  printf 'RK_STEPS=("3|seal-images|Seal both images|steps/03-seal-images.sh")\n' > "$W/sd/steps-build.sh"
}
setup() {  # a fresh home with the unpacked tree and two finished builds, as steps 0 and 1 leave them
  rm -rf "$W/home" "$W/ctl"; mkdir -p "$W/home" "$W/ctl"; B="$W/home/build-$C9"; TR="$B/tree"
  mkdir -p "$TR/ops/image/debs" "$TR/ops/image/test" "$B/a" "$B/b"; echo k > "$TR/ops/image/debs/linux-image-6.17.0-1022-gcp_6.17.0-1022.25_amd64.deb"
  echo "$COMMIT_FULL" > "$B/commit.txt"; echo us-central1-a > "$B/a/zone.txt"; echo us-central1-b > "$B/b/zone.txt"; printf 'builder\nmanifest\n' > "$B/a/done.txt"; printf 'builder\nmanifest\n' > "$B/b/done.txt"
  cp "$W/fake-driver.sh" "$TR/ops/image/test/f03-drive.sh"
  cat > "$TR/ops/image/test/r3-preflight.sh" <<'EOP'
#!/usr/bin/env bash
C="$(dirname "$HOME")/ctl"; echo "BUILDER=${BUILDER:-}|ZONE=${ZONE:-}|IMG=${IMG:-}|OUT=${OUT:-}|BASE_IMAGE=${BASE_IMAGE:-}|tree=$1" >> "$C/preflight.log"
[ -e "$C/preflight-fail" ] && { echo "   FAIL: the base image tc-img-dbg-1 does not exist"; exit 1; }; echo "preflight ok"; exit 0
EOP
}

suite() {  # DIR: all the checks against the kit in DIR
  local D="$1" o rc
  mkstepsdir "$D"
  rk() { env HOME="$W/home" CTL="$W/ctl" PATH="$W/fakebin:$PATH" RK_STEPS_DIR="$W/sd" RK_HEARTBEAT_SECS=0.2 bash "$D/run-kit.sh" build --commit "$COMMIT_FULL" --until seal-images "$@" 2>&1; }
  dl() { cat "$W/ctl/driver.log" 2>/dev/null; }
  n() { dl | grep -c "$1"; }
  setup; o="$(rk)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 3 DONE: both images are sealed and READY" && chk "a good run: STEP 3 DONE, both images sealed and READY" ok || chk "a good run: STEP 3 DONE (exit $rc)" bad "$(printf '%s' "$o" | tail -5 | tr '\n' ' ' | cut -c1-320)"
  [ "$(grep -c "instances stop $BA --zone=us-central1-a --quiet" "$W/ctl/gcloud.log")" = 1 ] && [ "$(grep -c "instances stop $BB --zone=us-central1-b --quiet" "$W/ctl/gcloud.log")" = 1 ] && chk "both builders are stopped first, each in its own zone" ok || chk "both builders are stopped first, each in its own zone" bad
  [ "$(cat "$W/ctl/preflight.log" 2>/dev/null | wc -l | tr -d ' ')" = 1 ] && grep -q "^BUILDER=$BA|ZONE=us-central1-a|IMG=$IA|OUT=$B/seal-a|BASE_IMAGE=tc-img-dbg-1|" "$W/ctl/preflight.log" && chk "the sealing session is checked once, read-only, before anything is sealed (builder, zone, image, folder and the base image of the helper VMs)" ok || chk "the sealing session is checked once, read-only, before anything is sealed" bad "$(cat "$W/ctl/preflight.log" 2>/dev/null | head -2)"
  L="$(dl | grep "^builder ship-builder seal-locked seal-disk|BUILDER=$BA|")"
  [ "$L" = "builder ship-builder seal-locked seal-disk|BUILDER=$BA|ZONE=us-central1-a|IMG=$IA|OUT=$B/seal-a|KVER=6.17.0-1022-gcp|COMMIT_FILE=$B/commit.txt|SEAL_DISK=tc-seal-disk-$C9-a|SEALER=tc-sealer-$C9-a|SEAL_TEST=tc-seal-test-$C9-a|CONFIRM=|SCRATCH=|leak=0" ] && chk "build A: lock, clean and seal in ONE driver call, with its builder, zone, image, folder, kernel, helper VM, test VM and disk copy, and nothing else of this run" ok || chk "build A: lock, clean and seal in ONE driver call, with its own settings" bad "$L"
  L="$(dl | grep "^builder ship-builder seal-locked seal-disk|BUILDER=$BB|")"
  [ "$L" = "builder ship-builder seal-locked seal-disk|BUILDER=$BB|ZONE=us-central1-b|IMG=$IB|OUT=$B/seal-b|KVER=6.17.0-1022-gcp|COMMIT_FILE=$B/commit.txt|SEAL_DISK=tc-seal-disk-$C9-b|SEALER=tc-sealer-$C9-b|SEAL_TEST=tc-seal-test-$C9-b|CONFIRM=|SCRATCH=|leak=0" ] && chk "build B has its own names for everything (the two sealings can run at the same time without a clash)" ok || chk "build B has its own names for everything" bad "$L"
  L="$(dl | grep "^seal-image|BUILDER=$BA|")"; [ "$L" = "seal-image|BUILDER=$BA|ZONE=us-central1-a|IMG=$IA|OUT=$B/seal-a|KVER=6.17.0-1022-gcp|COMMIT_FILE=$B/commit.txt|SEAL_DISK=tc-seal-disk-$C9-a|SEALER=tc-sealer-$C9-a|SEAL_TEST=tc-seal-test-$C9-a|CONFIRM=|SCRATCH=10|leak=0" ] && chk "the image of build A is made with the scratch size that the driver needs" ok || chk "the image of build A is made with the scratch size that the driver needs" bad "$L"
  L="$(dl | grep "^seal-delete|BUILDER=$BB|")"; case "$L" in *"|CONFIRM=yes|"*) chk "the helper VM and the disk copy of build B are deleted with the confirmation given for that one call only" ok;; *) chk "the helper VM and the disk copy of build B are deleted with the confirmation given for that one call only" bad "$L";; esac
  [ -e "$W/ctl/images/$IA" ] && [ -e "$W/ctl/images/$IB" ] && [ -z "$(find "$W/ctl/disks" "$W/ctl/vms" -type f 2>/dev/null)" ] && chk "both images exist and no helper VM or disk copy is left" ok || chk "both images exist and no helper VM or disk copy is left" bad
  printf '%s' "$o" | grep -q "normalization of build A: NORMALIZE-OK" && printf '%s' "$o" | grep -q "what it removed (group, entries): " && chk "the normalization of each build is reported" ok || chk "the normalization of each build is reported" bad
  # the preflight and the conditions
  setup; touch "$W/ctl/preflight-fail"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "the preflight of the sealing session failed" && [ ! -s "$W/ctl/driver.log" ] && chk "a failed preflight stops the step before anything is sealed" ok || chk "a failed preflight stops the step before anything is sealed" bad "exit $rc"
  setup; rm "$B/b/zone.txt"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "build B is not finished (step 1)" && [ ! -s "$W/ctl/driver.log" ] && chk "a build that is not finished is refused, and nothing starts" ok || chk "a build that is not finished is refused, and nothing starts" bad "exit $rc"
  setup; touch "$W/ctl/slow"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "\[heartbeat .* sealing A: " && chk "while the sealings run, a heartbeat line shows each build's progress" ok || chk "while the sealings run, a heartbeat line shows each build's progress" bad "exit $rc"
  # a sealing that ends without SEAL-OK, and a failing stage
  setup; touch "$W/ctl/no-sealok-$BB"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$(cat "$B/seal-run-b-step.log" 2>/dev/null; cat "$B/seal-b-step.log" 2>/dev/null)$o" | grep -q "printed no SEAL-OK line" && chk "a sealing that ends with exit 0 but without SEAL-OK is a failure" ok || chk "a sealing that ends with exit 0 but without SEAL-OK is a failure" bad "exit $rc"
  setup; touch "$W/ctl/fail-seal-locked-$BA"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "1 of the 2 sealings failed" && chk "when one of the two sealings fails the step fails, and says how many" ok || chk "when one of the two sealings fails the step fails, and says how many" bad "exit $rc"
  # a killed sealing of the disk: leftovers, the exact command, and a resume that seals only the disk
  setup; touch "$W/ctl/kill-seal-disk-$BB"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && [ -e "$W/ctl/disks/tc-seal-disk-$C9-b" ] && chk "a sealing of the disk that is killed leaves the helper VM and the disk copy, and the step fails" ok || chk "a sealing of the disk that is killed leaves the helper VM and the disk copy, and the step fails" bad "exit $rc"
  o="$(rk)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "a killed attempt left this behind: tc-sealer-$C9-b tc-seal-disk-$C9-b" && printf '%s' "$o" | grep -q "cd $B/tree && env CONFIRM=yes ZONE=us-central1-b SEAL_DISK=tc-seal-disk-$C9-b SEALER=tc-sealer-$C9-b SEAL_TEST=tc-seal-test-$C9-b IMG=$IB OUT=$B/seal-b bash ops/image/test/f03-drive.sh seal-delete" && chk "a rerun refuses to reuse the leftovers, names them, and prints the exact command that removes them" ok || chk "a rerun refuses to reuse the leftovers, names them, and prints the exact command that removes them" bad "exit $rc: $(printf '%s' "$o" | grep -E 'left this behind|cd ' | head -2 | cut -c1-300)"
  n0="$(n "^builder ship-builder seal-locked seal-disk|BUILDER=$BA|")"; rm -f "$W/ctl/disks/"* "$W/ctl/vms/"* "$W/ctl/kill-seal-disk-$BB"; o="$(rk)"; rc=$?
  [ "$rc" = 0 ] && [ "$(n "^seal-disk|BUILDER=$BB|")" = 1 ] && [ "$(n "^builder ship-builder seal-locked seal-disk|BUILDER=$BB|")" = 1 ] && [ "$(n "^builder ship-builder seal-locked seal-disk|BUILDER=$BA|")" = "$n0" ] && chk "after the leftovers are removed only the sealing of the disk of build B runs; build A is not sealed again" ok || chk "after the leftovers are removed only the sealing of the disk of build B runs; build A is not sealed again" bad "exit $rc"
  # a failure in the image phase must not cost the sealing again
  setup; touch "$W/ctl/image-fail"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "the image $IA could not be made" && chk "a failing image stage is reported, with the name of the image" ok || chk "a failing image stage is reported, with the name of the image" bad "exit $rc"
  rm -f "$W/ctl/image-fail"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && [ "$(n "^builder ship-builder seal-locked seal-disk|BUILDER=$BA|")" = 1 ] && [ "$(n "^builder ship-builder seal-locked seal-disk|BUILDER=$BB|")" = 1 ] && chk "after an image failure the rerun does NOT seal the disks again: it only makes the images" ok || chk "after an image failure the rerun does NOT seal the disks again: it only makes the images" bad "exit $rc, seal calls A $(n "seal-locked seal-disk|BUILDER=$BA|") B $(n "seal-locked seal-disk|BUILDER=$BB|")"
  setup; mkdir -p "$W/ctl/images"; touch "$W/ctl/images/$IA"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && [ "$(n "^seal-image|BUILDER=$BA|")" = 0 ] && [ "$(n "^seal-image|BUILDER=$BB|")" = 1 ] && [ "$(n "^seal-delete|BUILDER=$BA|")" = 1 ] && chk "an image that is READY is not made again, but the helper VM and the disk copy are still cleaned up" ok || chk "an image that is READY is not made again, but the helper VM and the disk copy are still cleaned up" bad "exit $rc"
  setup; touch "$W/ctl/image-notready"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "the image $IA is not READY after the stage" && chk "an image that is not READY after its stage is refused" ok || chk "an image that is not READY after its stage is refused" bad "exit $rc"
  # a builder that was locked and is not stopped
  setup; printf 'SEAL-DONE locked and cleaned\n' > "$B/seal-a/f4-seal-console.txt" 2>/dev/null || { mkdir -p "$B/seal-a"; printf 'SEAL-DONE locked and cleaned\n' > "$B/seal-a/f4-seal-console.txt"; }; touch "$W/ctl/nostop-$BA"; o="$(rk)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "was locked and cleaned by an earlier attempt but is not stopped (it is RUNNING)" && ! dl | grep -q "^builder ship-builder seal-locked seal-disk|BUILDER=$BA|" && chk "a builder that was locked but is not stopped is refused, and it is never started again" ok || chk "a builder that was locked but is not stopped is refused, and it is never started again" bad "exit $rc"
}

echo "== the checks of step 3 with a fake image driver and a fake cloud"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== the mutants (each check removed in turn; each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME OLD NEW: replaces the exact text OLD of the step by NEW
  local name="$1"; rm -rf "$W/m"; mkdir -p "$W/m/steps"; cp "$K"/*.sh "$W/m/"; cp "$K"/steps/*.sh "$W/m/steps/"
  python3 - "$W/m/steps/03-seal-images.sh" "$2" "$3" <<'PY' || { echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PY
  PASS=0; FAIL=0; suite "$W/m"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
mutant "the builders are not stopped"                  'gcloud compute instances stop "$BUILDER_A" --zone="$ZA" --quiet 2>&1 | tail -1'  'true'
mutant "a failed preflight is ignored"                 '|| fail "the preflight of the sealing session failed'                               '|| : "the preflight of the sealing session failed'
mutant "a sealed disk is sealed again"                 'if grep -aq "$RK_M_SEAL_OK" "$LOG" 2>/dev/null; then echo "build $ID: the disk is already sealed'  'if false; then echo "build $ID: the disk is already sealed'
mutant "a builder that is not stopped is accepted"     '[ "$STATUS" = TERMINATED ] || { echo "SEAL-IMAGES-FAILED: the builder'                'true || { echo "SEAL-IMAGES-FAILED: the builder'
mutant "leftovers of a killed attempt are ignored"     'if [ -n "$LEFT" ]; then'                                                              'if false; then'
mutant "a resume runs every stage again"               'STAGES="seal-disk"; echo "== RESUME'                                                  'STAGES="$RK_SEAL_STAGES"; echo "== RESUME'
mutant "a sealing without SEAL-OK is accepted"         'grep -aq "$RK_M_SEAL_OK" "$LOG" || { echo "SEAL-IMAGES-FAILED: the sealing of build $ID printed no'  'true || { echo "SEAL-IMAGES-FAILED: the sealing of build $ID printed no'
mutant "an image that is READY is made again"          '= READY ]; then echo "   $S_IMG exists and is READY: not made again"'              '= NOREADY ]; then echo "   $S_IMG exists and is READY: not made again"'
mutant "an image that is not READY is accepted"        '[ "$(gcloud compute images describe "$S_IMG" --format='"'"'value(status)'"'"' 2>/dev/null)" = READY ] || fail "the image $S_IMG is not READY after the stage"'  'true'
mutant "the helper VM and the disk copy are not deleted"  '"${DENV[@]}" CONFIRM=yes bash "$TREE/$RK_T_IMAGE_DRIVER" "$RK_SEAL_CLEAN_STAGE" 2>&1 | tee -a "$LOGI" | tail -3'  'true'
mutant "a failed sealing does not fail the step"       '[ "$BAD" = 0 ] || fail "$BAD of the 2 sealings failed'                                'true || fail "$BAD of the 2 sealings failed'
mutant "the image is made without the scratch size"    '"${DENV[@]}" SCRATCH_GB=10 bash'                                                      '"${DENV[@]}" bash'
mutant "the kernel version is fixed in the kit"        'KV="$(rk_kernel_version "$TREE")" || fail "no kernel version"'                        'KV="6.8.0-1073-gcp"'
mutant "there is no heartbeat"                         'echo "   [heartbeat $(date -u +%H:%M) UTC, $(rk_mins "$t0") min] sealing'            'echo "   [beat $(date -u +%H:%M) UTC, $(rk_mins "$t0") min] sealing'
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of step 3: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-STEP3-REHEARSAL-OK"; else echo "RUN-KIT-STEP3-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
