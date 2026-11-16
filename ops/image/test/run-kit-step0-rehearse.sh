#!/usr/bin/env bash
# Rehearsal of build step 0, check-source (ops/kits/run-kit/steps/00-check-source.sh), run through the REAL run-kit.sh.
#   bash run-kit-step0-rehearse.sh TREE        (TREE holds ops/; no cloud: a fake gcloud answers; a throwaway HOME; a small repository made here and its git archive)
# A good source passes (the tree is unpacked, the commit file names the full commit, the second archive differs, the rehearsals run once, nothing is created in the cloud).
# Every check is then made to FAIL on purpose, with the message that tells the person what to do: a package that does not match SHA256SUMS, no base image, no packages,
# a missing tool file, a __pycache__, a second archive with the same bytes, no archive, an archive of another commit, a builder or a sealed image of this commit that
# exists already, too little quota (vCPUs, disks), a rehearsal that fails twice (no marker), and one that fails once and passes the second time (a note, and the marker).
# Mutants of the step (each check removed in turn) must all be caught by the same cases.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W="$(mktemp -d)"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1${3:+ | the step said: $3}"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
[ -f "$K/steps/00-check-source.sh" ] && [ -f "$K/tools.sh" ] || { echo "RUN-KIT-STEP0-REHEARSAL-FAIL: the step or tools.sh is missing in $K"; exit 1; }
. "$K/tools.sh"

mkdir -p "$W/fakebin"
cat > "$W/fakebin/gcloud" <<'EOG'
#!/bin/sh
echo "$*" >> "$GCLOG"
case "$*" in
  "compute regions describe "*) cat "$QJSON" ;;
  "compute instances list --filter=name~'^tc-b-"*) cat "$VMS_EXIST" ;;
  "compute images list --filter=name~'^tc-img-"*) cat "$IMGS_EXIST" ;;
esac
exit 0
EOG
printf '#!/bin/sh\nexit 0\n' > "$W/fakebin/xxd"; chmod +x "$W/fakebin/gcloud" "$W/fakebin/xxd"

mkrepo() {  # NAME [DEFECT]: a small repository with everything step 0 checks, and its git archive: $W/NAME.tgz, the commit in $W/NAME.commit
  local n="$1" d="${2:-}" r="$W/$1" f
  rm -rf "$r"; mkdir -p "$r/ops/image/debs" "$r/ops/image/test" "$r/ops/image/build" "$r/ops/image/rootfs/usr/local/lib/tc"
  seq 1 5000 > "$r/ops/image/debs/a.deb"; seq 6000 9000 > "$r/ops/image/debs/b.deb"; ( cd "$r/ops/image/debs" && sha256sum a.deb b.deb > SHA256SUMS )
  printf 'base_image: ubuntu-2204-jammy-v20261105\n' > "$r/ops/image/debs/SOURCE.txt"
  for f in $RK_REQUIRED_FILES; do mkdir -p "$(dirname "$r/$f")"; echo "placeholder $f" > "$r/$f"; done
  cp "$T/ops/image/test/r4-archive.py" "$r/$RK_T_ARCHIVE_CHECK"
  printf '#!/bin/sh\necho "FAKE-REHEARSAL-PASS"\necho x >> "$(dirname "$HOME")/ctl/count-pass"\n' > "$r/$RK_REHEARSAL_DIR/fake-pass.sh"
  printf '#!/bin/sh\necho "   FAIL: a check that fails"\necho "FAKE-REHEARSAL-FAIL"\n' > "$r/$RK_REHEARSAL_DIR/fake-fail.sh"
  printf '#!/bin/sh\necho "Traceback (most recent call last):"\necho "boom: a tool is missing"\nexit 1\n' > "$r/$RK_REHEARSAL_DIR/fake-crash.sh"
  printf '#!/bin/sh\nfor v in SEAL_TEST ZONE WORKERS ID IMG OUT DRY MACHINE_TYPE RK_C9 RK_ID POLLUTION_TEST; do if [ -n "$(printenv $v)" ]; then echo "   FAIL: $v is set in the environment of a rehearsal"; echo FAKE-ENV-FAIL; exit 1; fi; done\necho FAKE-ENV-PASS\n' > "$r/$RK_REHEARSAL_DIR/fake-env.sh"
  printf '#!/bin/sh\nC="$(dirname "$HOME")/ctl"; if [ -e "$C/flaky-seen" ]; then echo FAKE-REHEARSAL-PASS; else touch "$C/flaky-seen"; echo "  FAIL: first time"; echo FAKE-REHEARSAL-FAIL; fi\n' > "$r/$RK_REHEARSAL_DIR/fake-flaky.sh"
  case "$d" in
    badsum) echo "changed" >> "$r/ops/image/debs/a.deb";;
    nobase) printf 'note: no base image here\n' > "$r/ops/image/debs/SOURCE.txt";;
    nosums) rm "$r/ops/image/debs/SHA256SUMS";;
    notool) rm "$r/ops/verify-export.py";;
    pycache) mkdir -p "$r/ops/image/test/__pycache__"; echo x > "$r/ops/image/test/__pycache__/x.pyc";;
  esac
  ( cd "$r" && git init -q && git config user.email t@t && git config user.name t && git add -A && git commit -qm "test commit" && git rev-parse HEAD > "$W/$n.commit" )
  if [ "$d" = twin ]; then ( cd "$r" && git archive --format=tar HEAD | gzip -1 -n > "$W/$n.tgz" ); else ( cd "$r" && git archive --format=tar.gz -9 -o "$W/$n.tgz" HEAD ); fi
}
quota() {  # C3-USAGE SSD-USAGE: the quota that the fake cloud reports
  printf '{"quotas":[{"metric":"C3_CPUS","limit":100,"usage":%s},{"metric":"SSD_TOTAL_GB","limit":2000,"usage":%s},{"metric":"DISKS_TOTAL_GB","limit":4000,"usage":100}]}\n' "$1" "$2" > "$W/quota.json"
}
mkrepo good; mkrepo badsum badsum; mkrepo nobase nobase; mkrepo nosums nosums; mkrepo notool notool; mkrepo pycache pycache; mkrepo twin twin

suite() {  # DIR: all the checks against the kit in DIR
  local D="$1" o rc C C9 H
  home_with() {  # NAME: a fresh home folder that holds the archive of NAME as ~/src-<C9>.tgz
    unset CM REH PARTIAL; rm -rf "$W/home" "$W/ctl"; mkdir -p "$W/home" "$W/ctl"; : > "$W/exist-vms.txt"; : > "$W/exist-imgs.txt"; : > "$W/gcloud.log"; quota 0 100
    C="$(cat "$W/$1.commit")"; C9="${C:0:9}"; H="$W/home/build-$C9"; cp "$W/$1.tgz" "$W/home/src-$C9.tgz"
  }
  run0() { env HOME="$W/home" CTL="$W/ctl" GCLOG="$W/gcloud.log" VMS_EXIST="$W/exist-vms.txt" IMGS_EXIST="$W/exist-imgs.txt" QJSON="$W/quota.json" PATH="$W/fakebin:$PATH" RK_REHEARSALS_DEFAULT="${REH:-fake-pass fake-env}" ${PARTIAL:+RK_REHEARSALS=$PARTIAL} bash "$D/run-kit.sh" build --commit "${CM:-$C}" --until check-source "$@" 2>&1; }
  cnt() { cat "$W/ctl/count-pass" 2>/dev/null | wc -l | tr -d ' '; }
  refused() {  # TEXT: the last run failed with exit 1 and its output says STEP 0 FAILED and TEXT
    [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "^STEP 0 FAILED" && printf '%s' "$o" | grep -qF -- "$1"
  }
  # a good source
  home_with good; o="$(run0)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 0 DONE: source of commit $C9 is ready: 2 packages match" && chk "a good source passes: STEP 0 DONE, with the number of packages in the result" ok || chk "a good source passes (exit $rc: $(printf '%s' "$o" | tail -3 | tr '\n' ' '))" bad
  [ -f "$H/tree/ops/image/debs/a.deb" ] && [ "$(cat "$H/commit.txt" 2>/dev/null)" = "$C" ] && chk "the tree is unpacked, and commit.txt holds the FULL commit id that the archive names" ok || chk "the tree is unpacked, and commit.txt holds the FULL commit id that the archive names" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  [ -s "$W/home/src-$C9-alt.tgz" ] && ! cmp -s "$W/home/src-$C9.tgz" "$W/home/src-$C9-alt.tgz" && [ "$(gzip -dc "$W/home/src-$C9.tgz" | sha256sum)" = "$(gzip -dc "$W/home/src-$C9-alt.tgz" | sha256sum)" ] && chk "the second archive has other bytes and the same content" ok || chk "the second archive has other bytes and the same content" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  [ -e "$H/rehearsals-ok" ] && [ "$(cnt)" = 1 ] && [ -s "$H/rehearsals/fake-env.out" ] && grep -q FAKE-ENV-PASS "$H/rehearsals/fake-env.out" && chk "the rehearsals ran once and left the marker; a rehearsal sees nothing of this run in its environment" ok || chk "the rehearsals ran once and left the marker (count $(cnt))" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  ! grep -qE "instances (create|delete|stop|start)|images (create|delete|add-labels)|add-labels|disks (create|delete)" "$W/gcloud.log" && grep -q "regions describe" "$W/gcloud.log" && chk "step 0 only reads the cloud (quota, builders, images) and creates nothing" ok || chk "step 0 only reads the cloud (quota, builders, images) and creates nothing" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  o="$(run0)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "STEP 0 skipped, done before" && chk "a second run skips the finished step" ok || chk "a second run skips the finished step" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  echo "sentinel" > "$H/tree/sentinel"; o="$(run0 --restart)"; rc=$?
  [ "$rc" = 0 ] && [ ! -e "$H/tree/sentinel" ] && [ "$(cnt)" = 1 ] && printf '%s' "$o" | grep -q "all of them passed on this commit before" && chk "--restart unpacks the tree again but does not run the rehearsals again (the marker)" ok || chk "--restart unpacks the tree again but does not run the rehearsals again (exit $rc, count $(cnt))" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with good; o="$(RK_NEED_FREE_MB=999999999 run0)"; rc=$?; refused "MB are free in the home folder" && printf '%s' "$o" | grep -q "the biggest items in the home folder" && printf '%s' "$o" | grep -q "src-$C9.tgz" && [ ! -d "$H/tree" ] && chk "too little free disk is refused before anything is unpacked, and the biggest items of the home folder are listed" ok || chk "too little free disk is refused before anything is unpacked, and the biggest items of the home folder are listed" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-300)"
  home_with good; o="$(POLLUTION_TEST=1 SEAL_TEST=polluted ZONE=polluted DRY=1 run0)"; rc=$?; [ "$rc" = 0 ] && chk "variables of the caller do not reach a rehearsal either: the rehearsals still pass" ok || chk "variables of the caller do not reach a rehearsal either: the rehearsals still pass (exit $rc)" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-300)"
  # defects of the source
  home_with badsum; o="$(run0)"; rc=$?; refused "a committed package does not match SHA256SUMS" && chk "a package that does not match SHA256SUMS is refused" ok || chk "a package that does not match SHA256SUMS is refused" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with nobase; o="$(run0)"; rc=$?; refused "does not name a base image" && chk "a SOURCE.txt without a base image is refused" ok || chk "a SOURCE.txt without a base image is refused" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with nosums; o="$(run0)"; rc=$?; refused "ops/image/debs is not in this commit" && chk "a commit without the checksum list of the packages is refused" ok || chk "a commit without the checksum list of the packages is refused" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with notool; o="$(run0)"; rc=$?; refused "ops/verify-export.py is not in the commit that is to be built" && chk "a commit that lacks a tool of the later steps is refused, and the file is named" ok || chk "a commit that lacks a tool of the later steps is refused, and the file is named" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with pycache; o="$(run0)"; rc=$?; refused "__pycache__" && chk "a __pycache__ folder is refused" ok || chk "a __pycache__ folder is refused" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with twin; o="$(run0)"; rc=$?; refused "the repacked archive equals the original" && chk "a second archive with the same bytes as the first is refused" ok || chk "a second archive with the same bytes as the first is refused" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with good; rm -f "$W/home/src-$C9.tgz"; o="$(run0)"; rc=$?; refused "there is no ~/src-$C9.tgz" && printf '%s' "$o" | grep -q "git archive --format=tar.gz -o src-$C9.tgz $C9" && chk "no archive: refused, with the command that makes it" ok || chk "no archive: refused, with the command that makes it" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with good; cp "$W/home/src-$C9.tgz" "$W/home/src-aaaaaaaaa.tgz"; o="$(CM=aaaaaaaaa1234 run0)"; rc=$?; refused "is not an archive of commit aaaaaaaaa1234" && chk "an archive of another commit than the one asked for is refused" ok || chk "an archive of another commit than the one asked for is refused (exit $rc: $(printf '%s' "$o" | tail -2 | tr '\n' ' '))" bad
  # what exists in the cloud, and the quota
  home_with good; printf 'tc-b-%s-a\tus-central1-a\n' "$C9" > "$W/exist-vms.txt"; o="$(run0)"; rc=$?; refused "builders of this commit exist from an earlier attempt: tc-b-$C9-a" && chk "a builder of this commit that exists already is refused, and named" ok || chk "a builder of this commit that exists already is refused, and named" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with good; printf 'tc-img-%s-1\n' "$C9" > "$W/exist-imgs.txt"; o="$(run0)"; rc=$?; refused "sealed images of this commit exist already: tc-img-$C9-1" && chk "a sealed image of this commit that exists already is refused, and named" ok || chk "a sealed image of this commit that exists already is refused, and named" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with good; quota 90 100; o="$(run0)"; rc=$?; refused "the quota has too little room" && printf '%s' "$o" | grep -q "C3_CPUS: 90 of 100 in use, 10 free" && chk "too few free vCPUs are refused, with the numbers" ok || chk "too few free vCPUs are refused, with the numbers" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with good; quota 0 1900; o="$(run0)"; rc=$?; refused "the quota has too little room" && printf '%s' "$o" | grep -q "SSD_TOTAL_GB: 1900 of 2000 GB in use, 100 GB free" && chk "too little free disk is refused, with the numbers" ok || chk "too little free disk is refused, with the numbers" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  # the rehearsals
  home_with good; o="$(REH=fake-fail run0)"; rc=$?; refused "the rehearsal fake-fail does not pass here" && printf '%s' "$o" | grep -q "FAIL: a check that fails" && [ ! -e "$H/rehearsals-ok" ] && chk "a rehearsal that fails twice is refused, named, shows its FAIL line, and leaves no marker" ok || chk "a rehearsal that fails twice is refused, named, and leaves no marker" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
  home_with good; o="$(REH=fake-crash run0)"; rc=$?; refused "the rehearsal fake-crash does not pass here" && printf '%s' "$o" | grep -q "boom: a tool is missing" && chk "a rehearsal that crashes without a FAIL line is refused, and its last lines are shown" ok || chk "a rehearsal that crashes without a FAIL line is refused, and its last lines are shown" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-300)"
  home_with good; o="$(REH="fake-pass fake-flaky" PARTIAL=fake-pass run0)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "SHORTER list" && o="$(REH="fake-pass fake-flaky" run0 --restart)"; rc=$?
  [ "$rc" = 0 ] && [ "$(cnt)" = 2 ] && [ -s "$H/rehearsals/fake-flaky.out" ] && [ "$(cat "$H/rehearsals-ok")" = "fake-pass fake-flaky" ] && chk "a shorter list of rehearsals (a quick try) does not count as the full list: the next full run runs them all" ok || chk "a shorter list of rehearsals (a quick try) does not count as the full list: the next full run runs them all (exit $rc, count $(cnt))" bad "$(printf '%s' "$o" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  home_with good; o="$(REH=fake-flaky run0)"; rc=$?; [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "NOTE: fake-flaky passed on the second run" && [ -e "$H/rehearsals-ok" ] && chk "a rehearsal that fails once and passes the second time passes with a note, and the marker is left" ok || chk "a rehearsal that fails once and passes the second time passes with a note, and the marker is left (exit $rc)" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-320)"
}

echo "== the checks of step 0 on a good source and on every defect"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== the mutants (each check removed in turn; each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME OLD NEW: replaces the exact text OLD of the step by NEW
  local name="$1"; rm -rf "$W/m"; mkdir -p "$W/m"; cp -r "$K"/. "$W/m/"
  python3 - "$W/m/steps/00-check-source.sh" "$2" "$3" <<'PY' || { echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PY
  PASS=0; FAIL=0; suite "$W/m"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
mutant "the packages are not checked against SHA256SUMS"  '( cd ops/image/debs && sha256sum --quiet -c SHA256SUMS ) || fail'  'true || fail'
mutant "a second archive with the same bytes is accepted" '[ "$(sha256sum < "$A")" != "$(sha256sum < "$ALT")" ] || fail'          'true || fail'
mutant "the archive may name another commit"              '--expect "$ID" '                                                      ''
mutant "the rehearsals run every time"                    'if [ -e "$MARK" ] && [ "$(cat "$MARK")" = "$RK_REHEARSALS_DEFAULT" ]; then'  'if false; then'
mutant "a sealed image that exists is accepted"           '[ -z "$OLDI" ] || fail'                                               'true || fail'
mutant "a builder that exists is accepted"                '[ -z "$OLDV" ] || fail'                                               'true || fail'
mutant "the disk space is not checked"                    'if [ "${FREE:-0}" -lt "$NEED_FREE_MB" ]; then'                       'if false; then'
mutant "the quota is not checked"                         'NEED_C3_CPUS=24; NEED_DISK_GB=590'                                    'NEED_C3_CPUS=0; NEED_DISK_GB=0'
mutant "a missing tool file is accepted"                  '[ -f "$f" ] || fail "$f is not in the commit'                        'true || fail "$f is not in the commit'
mutant "a rehearsal that fails twice is accepted"         $'grep -q \'PASS\' || { F="$(grep -E'                                        $'true || { F="$(grep -E'
mutant "a shorter list counts as the full list"          'echo "$LIST" > "$MARK"; REH_NOTE'                                    'echo "$RK_REHEARSALS_DEFAULT" > "$MARK"; REH_NOTE'
mutant "the rehearsals run with the caller's environment"  '$SU "${RENV[@]}" bash'                                                  '$SU bash'
mutant "a crash without a FAIL line shows nothing"        '[ -n "$F" ] || F="$(tail -12 "$RD/$s.out")"; '                       ''
mutant "a __pycache__ folder is accepted"                 '[ -z "$(find "$H/$BUILD_DIR" -name __pycache__ 2>/dev/null | head -1)" ] || fail'  'true || fail'
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of step 0: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-STEP0-REHEARSAL-OK"; else echo "RUN-KIT-STEP0-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
