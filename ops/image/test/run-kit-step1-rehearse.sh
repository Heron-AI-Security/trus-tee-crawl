#!/usr/bin/env bash
# Rehearsal of build step 1, build-twice (ops/kits/run-kit/steps/01-build-twice.sh), run through the REAL run-kit.sh and the real step.
#   bash run-kit-step1-rehearse.sh TREE        (TREE holds ops/; no cloud: a fake image driver and a fake gcloud answer; a throwaway HOME; nothing is written outside a temporary folder)
# Checked: both builds run at the same time, each on its own builder, in the stage order of the driver, with the settings that the driver reads (builder, archive and its SHA-256,
# evidence folder, base image, kernel version taken from the committed packages) and nothing else from this run in the environment of the driver; build B uses the repacked twin
# of the archive; the Hadoop tarball is fetched from the mirror by the proven script and no seed builder is used; a failed stage is retried on the same builder and the finished
# stages are skipped; the next zone is tried only when a zone has no capacity; and every failure says what happened: another error than capacity, no zone with capacity, a builder
# that was created but did not start, another commit than the archive's, step 0 not run, no or two kernel packages, one build failing while the other succeeds.
# Mutants of the step (each check removed in turn) must all be caught by the same cases.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W="$(mktemp -d)"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1${3:+ | $3}"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
[ -f "$K/steps/01-build-twice.sh" ] && [ -f "$K/hadoop-fetch.sh" ] || { echo "RUN-KIT-STEP1-REHEARSAL-FAIL: step 1 or hadoop-fetch.sh is missing in $K"; exit 1; }
COMMIT_FULL=0123456789abcdef0123456789abcdef01234567; C9=${COMMIT_FULL:0:9}; BA="tc-b-$C9-a"; BB="tc-b-$C9-b"
DRV_STAGES="builder ship-builder debs prep bake ship-source job bake-crawl bake-fleet debs-audit bake-seal manifest"

mkdir -p "$W/fakebin"
cat > "$W/fakebin/gcloud" <<'EOG'
#!/bin/sh
echo "$*" >> "$CTL/gcloud.log"
case "$*" in
  "compute instances list --filter=name="*) n="${3#*=}"; n="${*#*--filter=name=}"; n="${n%% *}"; [ -e "$CTL/builders/$n" ] && echo "$n" ;;
  "compute ssh "*) b="$3"; cat > "$CTL/ssh-stdin-$b.sh"; if [ -e "$CTL/fetchskip" ]; then echo "HADOOP-FETCH-SKIP: the server does not do range requests"; else echo "HADOOP-FETCH-OK: hadoop-3.4.3.tar.gz in 12 s"; fi ;;
esac
exit 0
EOG
chmod +x "$W/fakebin/gcloud"
cat > "$W/fake-driver.sh" <<'EOD'
#!/usr/bin/env bash
C="$(dirname "$HOME")/ctl"; st="$1"
echo "$st|BUILDER=${BUILDER:-}|ZONE=${ZONE:-}|OUT=${OUT:-}|SRC_TGZ=${SRC_TGZ:-}|SRC_SHA=${SRC_SHA:-}|KVER=${KVER:-}|BASE_IMAGE=${BASE_IMAGE:-}|COMMIT_FILE=${COMMIT_FILE:-}|SLOW=${HADOOP_ALLOW_SLOW:-}|leak=$(env | grep -cE '^(ID|COMMIT|SEAL_TEST|WORKERS|MACHINE_TYPE|DRY|CONFIRM|IMG|RUN_ID|MASTER)=')" >> "$C/driver.log"
echo "fake driver: stage $st for $BUILDER in ${ZONE:-}"
if [ "$st" = builder ]; then
  [ -e "$C/nocap-$ZONE" ] && { echo "ERROR: ZONE_RESOURCE_POOL_EXHAUSTED: the zone $ZONE does not have enough resources"; exit 1; }
  [ -e "$C/nocap-all" ] && { echo "ERROR: ZONE_RESOURCE_POOL_EXHAUSTED: no room"; exit 1; }
  [ -e "$C/othererr" ] && { echo "ERROR: permission denied for this project"; exit 1; }
  mkdir -p "$C/builders"; touch "$C/builders/$BUILDER"
  [ -e "$C/startfail" ] && { echo "ERROR: the builder did not start"; exit 1; }
fi
[ "$st" = bake ] && [ -e "$C/slow" ] && sleep 1.5
[ -e "$C/fail-$st-$BUILDER" ] && { echo "the stage $st broke on $BUILDER"; exit 1; }
if [ "$st" = manifest ]; then mkdir -p "$OUT/r4"; if [ -e "$C/badcommit" ]; then echo "commit deadbeefdeadbeef" > "$OUT/r4/source.txt"; else echo "commit $(cat "$COMMIT_FILE")" > "$OUT/r4/source.txt"; fi; printf 'one\t1\ntwo\t2\nthree\t3\n' > "$OUT/r4/events.tsv"; fi
exit 0
EOD

mkstepsdir() {  # KITDIR: a step folder whose step list holds step 1 only, and whose files are links to the kit in KITDIR (the step finds its own library next to it)
  rm -rf "$W/sd"; mkdir -p "$W/sd/steps"
  for f in names.sh lib.sh record.sh tools.sh hadoop-fetch.sh steps-crawl.sh; do ln -s "$1/$f" "$W/sd/$f"; done
  ln -s "$1/steps/01-build-twice.sh" "$W/sd/steps/01-build-twice.sh"
  printf 'RK_STEPS=("1|build-twice|Build the image twice|steps/01-build-twice.sh")\n' > "$W/sd/steps-build.sh"
}
setup() {  # a fresh home with the unpacked tree, the commit file, the two archives and the fake driver, as step 0 leaves them
  rm -rf "$W/home" "$W/ctl"; mkdir -p "$W/home" "$W/ctl/builders"; B="$W/home/build-$C9"; TR="$B/tree"
  mkdir -p "$TR/ops/image/debs" "$TR/ops/image/test"; printf 'base_image: ubuntu-2204-jammy-v20261105\n' > "$TR/ops/image/debs/SOURCE.txt"
  echo k > "$TR/ops/image/debs/linux-image-6.17.0-1022-gcp_6.17.0-1022.25_amd64.deb"; echo k > "$TR/ops/image/debs/linux-modules-6.17.0-1022-gcp_6.17.0-1022.25_amd64.deb"
  echo "$COMMIT_FULL" > "$B/commit.txt"; head -c 4000 /dev/urandom > "$W/home/src-$C9.tgz"; head -c 4100 /dev/urandom > "$W/home/src-$C9-alt.tgz"
  cp "$W/fake-driver.sh" "$TR/ops/image/test/f03-drive.sh"
}

suite() {  # DIR: all the checks against the kit in DIR
  local D="$1" o rc a b
  mkstepsdir "$D"
  rk() { env HOME="$W/home" CTL="$W/ctl" PATH="$W/fakebin:$PATH" RK_STEPS_DIR="$W/sd" RK_HEARTBEAT_SECS=0.2 bash "$D/run-kit.sh" build --commit "$COMMIT_FULL" --until build-twice "$@" 2>&1; }
  calls() { grep "|BUILDER=$1|" "$W/ctl/driver.log" 2>/dev/null | cut -d'|' -f1 | tr '\n' ' '; }       # the stages that the driver was asked for on one builder
  ncall() { grep -c "^$2|BUILDER=$1|" "$W/ctl/driver.log" 2>/dev/null; }
  # a good run
  setup; o="$(rk)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 1 DONE: both builds are finished" && chk "a good run: STEP 1 DONE, both builds finished" ok || chk "a good run: STEP 1 DONE, both builds finished (exit $rc)" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-300)"
  [ "$(calls $BA)" = "$DRV_STAGES " ] && [ "$(calls $BB)" = "$DRV_STAGES " ] && chk "each build asks the driver for the stages in the driver's order, once, on its own builder" ok || chk "each build asks the driver for the stages in the driver's order, once, on its own builder" bad "A: $(calls $BA) | B: $(calls $BB)"
  L="$(grep "^bake|BUILDER=$BA|" "$W/ctl/driver.log")"; SA="$(sha256sum "$W/home/src-$C9.tgz" | cut -c1-64)"; SB="$(sha256sum "$W/home/src-$C9-alt.tgz" | cut -c1-64)"
  [ "$L" = "bake|BUILDER=$BA|ZONE=us-central1-a|OUT=$B/a|SRC_TGZ=$W/home/src-$C9.tgz|SRC_SHA=$SA|KVER=6.17.0-1022-gcp|BASE_IMAGE=ubuntu-2204-jammy-v20261105|COMMIT_FILE=$B/commit.txt|SLOW=1|leak=0" ] && chk "build A gives the driver its builder, zone, evidence folder, archive and SHA-256, kernel (from the packages), base image and commit file, and nothing else of this run" ok || chk "build A gives the driver its builder, zone, evidence folder, archive and SHA-256, kernel (from the packages), base image and commit file, and nothing else of this run" bad "$L"
  L="$(grep "^bake|BUILDER=$BB|" "$W/ctl/driver.log")"
  [ "$L" = "bake|BUILDER=$BB|ZONE=us-central1-a|OUT=$B/b|SRC_TGZ=$W/home/src-$C9-alt.tgz|SRC_SHA=$SB|KVER=6.17.0-1022-gcp|BASE_IMAGE=ubuntu-2204-jammy-v20261105|COMMIT_FILE=$B/commit.txt|SLOW=1|leak=0" ] && chk "build B uses the repacked twin of the archive (and its own SHA-256), its own builder and its own folder" ok || chk "build B uses the repacked twin of the archive (and its own SHA-256), its own builder and its own folder" bad "$L"
  [ -s "$B/evidence-a.tar.gz" ] && [ -s "$B/evidence-b.tar.gz" ] && [ "$(cat "$B/a/zone.txt")" = us-central1-a ] && chk "the evidence of each build is packed, and the zone of each builder is recorded" ok || chk "the evidence of each build is packed, and the zone of each builder is recorded" bad
  # the Hadoop tarball
  [ "$(grep -c "^compute ssh $BA .*HBASE='https://dlcdn.apache.org/hadoop/common/hadoop-3.4.3' PARTS=1 EXPECT_SIZE=514917037 bash -s" "$W/ctl/gcloud.log")" = 1 ] && cmp -s "$W/ctl/ssh-stdin-$BA.sh" "$K/hadoop-fetch.sh" && ! grep -q "tc-r47-b" "$W/ctl/gcloud.log" "$W/ctl/driver.log" && chk "each builder fetches the Hadoop tarball from the mirror with the proven script (sent through ssh), and no seed builder is used" ok || chk "each builder fetches the Hadoop tarball from the mirror with the proven script (sent through ssh), and no seed builder is used" bad "$(grep ssh "$W/ctl/gcloud.log" | head -2 | cut -c1-200)"
  setup; touch "$W/ctl/fetchskip"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$(cat "$W/home/build-$C9/a/build.log")" | grep -q "HADOOP-FETCH-SKIP" && chk "a skipped fetch is no failure: the bake downloads by itself, and the build goes on" ok || chk "a skipped fetch is no failure: the bake downloads by itself, and the build goes on" bad "exit $rc"
  # a failed stage is retried on the same builder
  setup; touch "$W/ctl/fail-bake-$BB"; o="$(rk)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "^STEP 1 FAILED" && printf '%s' "$o" | grep -q "BUILD-TWICE-FAILED: 1 of the 2 builds failed" && printf '%s' "$o" | grep -q "BUILD-TWICE-FAILED at stage bake" && chk "when build B fails (and A succeeds) the step fails, says which build and which stage, and keeps both builders" ok || chk "when build B fails (and A succeeds) the step fails, says which build and which stage, and keeps both builders" bad "exit $rc: $(printf '%s' "$o" | tail -5 | tr '\n' ' ' | cut -c1-300)"
  rm -f "$W/ctl/fail-bake-$BB"; o="$(rk)"; rc=$?
  [ "$rc" = 0 ] && [ "$(calls $BA)" = "$DRV_STAGES " ] && [ "$(ncall $BB bake)" = 2 ] && [ "$(ncall $BB builder)" = 1 ] && [ "$(ncall $BB prep)" = 1 ] && [ "$(ncall $BB manifest)" = 1 ] && chk "the rerun skips every finished stage: A is not touched, B goes on at bake on the same builder (builder and prep not run again)" ok || chk "the rerun skips every finished stage: A is not touched, B goes on at bake on the same builder (builder and prep not run again)" bad "A: $(calls $BA) | B bake=$(ncall $BB bake) builder=$(ncall $BB builder)"
  setup; touch "$W/ctl/fail-ship-source-$BA"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "BUILD-TWICE-FAILED at stage ship-source" && chk "when build A fails (and B succeeds) the step fails too" ok || chk "when build A fails (and B succeeds) the step fails too" bad "exit $rc"
  # the zones
  setup; touch "$W/ctl/nocap-us-central1-a"; o="$(rk)"; rc=$?
  [ "$rc" = 0 ] && [ "$(cat "$W/home/build-$C9/a/zone.txt")" = us-central1-b ] && [ "$(cat "$W/home/build-$C9/b/zone.txt")" = us-central1-b ] && grep -q "no capacity in us-central1-a: trying the next zone" "$W/home/build-$C9/a/build.log" && grep -q "^bake|BUILDER=$BA|ZONE=us-central1-b|" "$W/ctl/driver.log" && chk "a zone without capacity: the next zone is tried, its name is recorded and given to every later stage" ok || chk "a zone without capacity: the next zone is tried, its name is recorded and given to every later stage" bad "exit $rc"
  setup; touch "$W/ctl/othererr"; o="$(rk)"; rc=$?
  [ "$rc" = 1 ] && [ "$(ncall $BA builder)" = 1 ] && [ "$(ncall $BB builder)" = 1 ] && printf '%s' "$(cat "$W/home/build-$C9/a/build.log")" | grep -q "for a reason other than capacity" && chk "any other error than capacity stops at once: no other zone is tried" ok || chk "any other error than capacity stops at once: no other zone is tried" bad "exit $rc, calls A $(ncall $BA builder) B $(ncall $BB builder)"
  setup; touch "$W/ctl/nocap-all"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && [ "$(ncall $BA builder)" = 4 ] && printf '%s' "$(cat "$W/home/build-$C9/a/build.log")" | grep -q "no zone had capacity" && chk "no zone with capacity: all four zones of the region were tried, and the step says so" ok || chk "no zone with capacity: all four zones of the region were tried, and the step says so" bad "exit $rc, tries $(ncall $BA builder)"
  setup; touch "$W/ctl/startfail"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$(cat "$W/home/build-$C9/a/build.log")" | grep -q "the builder $BA was created in us-central1-a but its start failed (it is kept" && [ "$(ncall $BA builder)" = 1 ] && chk "a builder that was created but did not start is kept and named, and no other zone is tried" ok || chk "a builder that was created but did not start is kept and named, and no other zone is tried" bad "exit $rc"
  # what a build records, and the conditions
  setup; touch "$W/ctl/badcommit"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$(cat "$W/home/build-$C9/a/build.log")" | grep -q "records another commit than the archive" && chk "an image that records another commit than the archive is refused" ok || chk "an image that records another commit than the archive is refused" bad "exit $rc"
  setup; rm -rf "$W/home/build-$C9/tree"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "step 0 has not run" && [ ! -s "$W/ctl/driver.log" ] && chk "without the unpacked tree the step says that step 0 has not run, and starts nothing" ok || chk "without the unpacked tree the step says that step 0 has not run, and starts nothing" bad "exit $rc"
  setup; echo k > "$W/home/build-$C9/tree/ops/image/debs/linux-image-6.8.0-1073-gcp_6.8.0-1073.75_amd64.deb"; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "exactly one kernel image package" && [ ! -s "$W/ctl/driver.log" ] && chk "two kernel image packages in the committed packages are refused before anything starts" ok || chk "two kernel image packages in the committed packages are refused before anything starts" bad "exit $rc"
  setup; rm "$W/home/build-$C9/tree/ops/image/debs/linux-image-"*; o="$(rk)"; rc=$?; [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "exactly one kernel image package" && chk "no kernel image package is refused too" ok || chk "no kernel image package is refused too" bad "exit $rc"
  setup; touch "$W/ctl/slow"; o="$(rk)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "\[heartbeat .* build A: " && printf '%s' "$o" | grep -q "build B: " && chk "while the builds run, a heartbeat line shows each build's progress" ok || chk "while the builds run, a heartbeat line shows each build's progress" bad "exit $rc"
}

echo "== the checks of step 1 with a fake image driver and a fake cloud"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== the mutants (each check removed in turn; each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME OLD NEW: replaces the exact text OLD of the step by NEW
  local name="$1"; rm -rf "$W/m"; mkdir -p "$W/m/steps"; cp "$K"/*.sh "$W/m/"; cp "$K"/steps/*.sh "$W/m/steps/"
  python3 - "$W/m/steps/01-build-twice.sh" "$2" "$3" <<'PY' || { echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PY
  PASS=0; FAIL=0; suite "$W/m"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
mutant "build B uses the archive of build A"          'BUILDER="$BUILDER_B"; ARCH="$H/$SOURCE_ALT_TGZ"'                     'BUILDER="$BUILDER_B"; ARCH="$H/$SOURCE_TGZ"'
mutant "build B uses the builder of build A"          'BUILDER="$BUILDER_B"; ARCH='                                          'BUILDER="$BUILDER_A"; ARCH='
mutant "every error counts as no capacity"            'if grep -qE "$RK_CAPACITY_RX" "$OUT/builder-$z.txt"; then'          'if true; then'
mutant "finished stages run again"                    'if grep -qx "$st" "$DONE"; then echo "== $st: done before, skipped"; continue; fi'  'if false; then echo "== $st: done before, skipped"; continue; fi'
mutant "the recorded commit is not checked"           '[ "$(cat "$OUT/r4/source.txt")" = "commit $COMMIT" ] || {'          'true || {'
mutant "a seed builder is used again"                 'echo fetch-hadoop >> "$DONE"; continue'                               'gcloud compute ssh tc-r47-b --zone="$ZZ" --quiet --command=true < /dev/null; echo fetch-hadoop >> "$DONE"; continue'
mutant "the Hadoop fetch is not run"                  'gcloud compute ssh "$BUILDER" --zone="$ZZ" --quiet --command="HVER='  'true # gcloud compute ssh "$BUILDER" --zone="$ZZ" --quiet --command="HVER='
mutant "a builder that did not start is not noticed"  'if [ -n "$(gcloud compute instances list --filter="name=$BUILDER" --format='"'"'value(name)'"'"' 2>/dev/null)" ]; then'  'if false; then'
mutant "the kernel version is fixed in the kit"       'KV="$(ls "$TREE/ops/image/debs" | sed -n '"'"'s/^linux-image-\(.*-gcp\)_.*\.deb$/\1/p'"'"' | sort -u)"'  'KV="6.8.0-1073-gcp"'
mutant "a failed build does not fail the step"        '[ "$BAD" = 0 ] || fail'                                               'true || fail'
mutant "the evidence is not packed"                   'tar czf "$BD/evidence-$idl.tar.gz"'                                   'true "$BD/evidence-$idl.tar.gz"'
mutant "there is no heartbeat"                        'echo "   [heartbeat $(date -u +%H:%M) UTC'                              'echo "   [beat $(date -u +%H:%M) UTC'
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of step 1: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-STEP1-REHEARSAL-OK"; else echo "RUN-KIT-STEP1-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
