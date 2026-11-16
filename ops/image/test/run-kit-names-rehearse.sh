#!/usr/bin/env bash
# Rehearsal of the names and the command line of the one run kit (ops/kits/run-kit/names.sh and run-kit.sh).
#   bash run-kit-names-rehearse.sh TREE        (TREE holds ops/; no cloud, no network, nothing is written outside a temporary folder)
# 1. every combination of the inputs makes valid names that never collide, and two commits never share a name;
# 2. a bad command line is refused (exit 2) with a clear message, before anything is created;
# 3. the plan makes no cloud call at all (a fake gcloud, ssh, scp, curl, wget and git fail the test if the kit calls one);
# 4. the names are the convention of the kit (master, worker 1 to N, images, folders);
# 5. no name of an earlier run is left in the kit folder;
# 6. mutants of names.sh and run-kit.sh (a name that drops the tag, a worker off by one, a switch digit swapped, upper case, a limit removed,
#    a cloud call in the plan, a commit missing from a name, an old name left behind) are all caught by the same checks.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W="$(mktemp -d)"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad", where a status 1 would count a pass as a failure too
[ -f "$K/names.sh" ] && [ -f "$K/run-kit.sh" ] || { echo "RUN-KIT-NAMES-REHEARSAL-FAIL: $K has no names.sh or run-kit.sh"; exit 1; }
OKARGS="--build bd339c8d2 --size 1k --storage on --comms off --provenance on"

refuse() {  # DIR TEXT args...: exit 2, the error line, and TEXT in the message
  local D="$1" want="$2"; shift 2; local o rc
  o="$(bash "$D/run-kit.sh" "$@" 2>&1)"; rc=$?
  [ "$rc" = 2 ] && printf '%s' "$o" | grep -q "RUN-KIT-INPUT-ERROR" && printf '%s' "$o" | grep -qF -- "$want"
}

suite() {  # DIR: all the checks against the kit in DIR
  local D="$1" sz s c p tg bad r m out n runs=0 allr=" " allm=" " o rc L
  # 1. every combination: valid names, no collision between runs
  for sz in 1k 10k 100k 1m; do for s in on off; do for c in on off; do for p in on off; do for tg in "" r2; do
    out="$(cd "$D" && SIZE=$sz STORAGE=$s COMMS=$c PROVENANCE=$p TAG=$tg WORKERS=20 bash -c '. ./names.sh; rk_inputs_check || exit 9; rk_run_names; rk_build_names bd339c8d2e88 || exit 9; rk_check_names || exit 8; echo "$RUN_ID $MASTER"' 2>/dev/null)"; rc=$?
    runs=$((runs + 1)); bad=0
    [ "$rc" = 0 ] || bad=1
    set -- $out; r="${1:-}"; m="${2:-}"
    case "$allr" in *" $r "*) bad=1;; esac; case "$allm" in *" $m "*) bad=1;; esac; allr="$allr$r "; allm="$allm$m "
    [ "$bad" = 0 ] || chk "the inputs $sz/$s/$c/$p/tag '$tg' make valid, unique names" bad
  done; done; done; done; done
  chk "all $runs combinations of size, switches and tag make valid names, none twice, and no two runs share a run id or a master" "$([ "$FAIL" = "${FAIL0:-0}" ] && echo ok || echo bad)"
  # 1b. the workers: w1 to w20, in order, all different; two commits never share a name
  o="$(cd "$D" && SIZE=1k STORAGE=on COMMS=off PROVENANCE=on bash -c '. ./names.sh; WORKERS=20; rk_run_names; echo "$(rk_worker 1) $(rk_worker 2) $(rk_worker 20)"; rk_gce_names | sort | uniq -d | wc -l' 2>/dev/null)"
  [ "$o" = "$(printf 'tc-1k-s1c0p1-w1 tc-1k-s1c0p1-w2 tc-1k-s1c0p1-w20\n0')" ] && chk "worker 1, 2 and 20 are -w1, -w2 and -w20, and no name is twice" ok || chk "worker 1, 2 and 20 are -w1, -w2 and -w20, and no name is twice (got: $o)" bad
  o="$(cd "$D" && bash -c '. ./names.sh; rk_build_names aaaaaaaaa; a="$BUILDER_A $BUILDER_B $IMAGE_1 $IMAGE_2 $SEAL_DISK_A $SEALER_A $SEAL_TEST $BUILD_DIR"; rk_build_names bbbbbbbbb; b="$BUILDER_A $BUILDER_B $IMAGE_1 $IMAGE_2 $SEAL_DISK_A $SEALER_A $SEAL_TEST $BUILD_DIR"; for x in $a; do for y in $b; do [ "$x" = "$y" ] && echo SAME; done; done; echo END' 2>/dev/null)"
  [ "$o" = END ] && chk "two different commits share no builder, image, seal helper or folder name" ok || chk "two different commits share no builder, image, seal helper or folder name" bad
  # 2. refusals
  refuse "$D" "--size must be one of" plan crawl --build bd339c8d2 --size 5k --storage on --comms on --provenance on && chk "a size that is not 1k, 10k, 100k or 1m is refused" ok || chk "a size that is not 1k, 10k, 100k or 1m is refused" bad
  refuse "$D" "--storage must be on or off" plan crawl --build bd339c8d2 --size 1k --storage yes --comms on --provenance on && chk "a switch that is not on or off is refused" ok || chk "a switch that is not on or off is refused" bad
  refuse "$D" "--comms is missing" plan crawl --build bd339c8d2 --size 1k --storage on --provenance on && chk "a missing switch is refused" ok || chk "a missing switch is refused" bad
  for n in 0 21 abc; do refuse "$D" "--workers must be a number from 1 to 20" plan crawl $OKARGS --workers $n && chk "--workers $n is refused" ok || chk "--workers $n is refused" bad; done
  refuse "$D" "--tag must be" plan crawl $OKARGS --tag R2 && chk "a tag with upper case is refused" ok || chk "a tag with upper case is refused" bad
  refuse "$D" "--tag must be" plan crawl $OKARGS --tag abcdefghi && chk "a tag of 9 characters is refused" ok || chk "a tag of 9 characters is refused" bad
  refuse "$D" "commit id must be" plan crawl --build abc --size 1k --storage on --comms on --provenance on && chk "a commit id of 3 characters is refused" ok || chk "a commit id of 3 characters is refused" bad
  refuse "$D" "commit id must be" plan crawl --build BD339C8D2 --size 1k --storage on --comms on --provenance on && chk "a commit id in upper case is refused" ok || chk "a commit id in upper case is refused" bad
  refuse "$D" "--zone must look like" plan crawl $OKARGS --zone mars && chk "a zone that is not a zone is refused" ok || chk "a zone that is not a zone is refused" bad
  refuse "$D" "--machine-type must look like" plan crawl $OKARGS --machine-type C3_Standard && chk "a machine type with upper case is refused" ok || chk "a machine type with upper case is refused" bad
  refuse "$D" "unknown option '--sise'" plan crawl $OKARGS --sise 1k && chk "a misspelled flag is refused" ok || chk "a misspelled flag is refused" bad
  refuse "$D" "--tag needs a value" plan crawl $OKARGS --tag && chk "a flag without a value is refused" ok || chk "a flag without a value is refused" bad
  refuse "$D" "--tag needs a value" plan crawl $OKARGS --tag --workers 3 && chk "a flag whose value is the next flag is refused" ok || chk "a flag whose value is the next flag is refused" bad
  refuse "$D" "given twice" plan crawl $OKARGS --size 10k && chk "a flag given twice is refused" ok || chk "a flag given twice is refused" bad
  refuse "$D" "does not belong to 'build'" plan build --commit bd339c8d2 --size 1k && chk "a crawl flag on the build command is refused" ok || chk "a crawl flag on the build command is refused" bad
  refuse "$D" "--build is missing" plan crawl --size 1k --storage on --comms on --provenance on && chk "a crawl without --build is refused" ok || chk "a crawl without --build is refused" bad
  refuse "$D" "unknown command" frobnicate && chk "an unknown command is refused" ok || chk "an unknown command is refused" bad
  refuse "$D" "plan needs build, crawl or all" plan && chk "plan without build, crawl or all is refused" ok || chk "plan without build, crawl or all is refused" bad
  o="$(SIZE=5k STORAGE=on bash "$D/run-kit.sh" plan crawl --build bd339c8d2 --comms on --provenance on 2>&1)"; rc=$?
  [ "$rc" = 2 ] && printf '%s' "$o" | grep -qF -- "--size is missing" && chk "a variable in the shell (SIZE=5k) is ignored: only the flags count" ok || chk "a variable in the shell (SIZE=5k) is ignored: only the flags count" bad
  # 3. the plan makes no cloud call
  rm -rf "$W/fake" "$W/calls.log"; mkdir -p "$W/fake"
  for x in gcloud gsutil ssh scp curl wget git; do printf '#!/bin/sh\necho "$0 $*" >> "%s/calls.log"\nexit 99\n' "$W" > "$W/fake/$x"; chmod +x "$W/fake/$x"; done
  for m in "plan build --commit bd339c8d2e88" "plan crawl $OKARGS" "plan all --commit bd339c8d2 --size 100k --storage off --comms on --provenance off --workers 3 --tag r2"; do
    PATH="$W/fake:$PATH" bash "$D/run-kit.sh" $m > "$W/plan.out" 2>&1; rc=$?; [ "$rc" = 0 ] || chk "the plan '$m' ends with exit 0" bad
  done
  PATH="$W/fake:$PATH" bash "$D/run-kit.sh" crawl $OKARGS > "$W/crawl.out" 2>&1; [ "$?" = 3 ] && grep -q "RUN-KIT-STAGES-MISSING" "$W/crawl.out" || chk "crawl stops with exit 3 and says that the stages are missing" bad
  [ ! -s "$W/calls.log" ] && chk "plan, build, crawl and all call no gcloud, gsutil, ssh, scp, curl, wget or git" ok || chk "plan, build, crawl and all call no gcloud, gsutil, ssh, scp, curl, wget or git (calls: $(head -c 120 "$W/calls.log" 2>/dev/null))" bad
  # 4. the convention
  o="$(bash "$D/run-kit.sh" plan crawl $OKARGS 2>&1)"; L=0
  for x in "run id: 1k-s1c0p1" "master tc-1k-s1c0p1-m" "tc-1k-s1c0p1-w1 ... tc-1k-s1c0p1-w10" "label on every VM: tc-run=1k-s1c0p1" "~/evidence-1k-s1c0p1" "~/run-1k-s1c0p1" "tc-img-bd339c8d2-1" "tc-b-bd339c8d2-a" "builds/bd339c8d2/"; do printf '%s' "$o" | grep -qF -- "$x" || { L=1; echo "     missing in the plan: $x"; }; done
  [ "$L" = 0 ] && chk "the plan of 1k with storage on, comms off, provenance on shows the names of the convention" ok || chk "the plan of 1k with storage on, comms off, provenance on shows the names of the convention" bad
  o="$(bash "$D/run-kit.sh" plan all --commit bd339c8d2 --size 100k --storage off --comms on --provenance off --tag r2 --workers 1 2>&1)"
  printf '%s' "$o" | grep -qF "run id: 100k-s0c1p0-r2" && printf '%s' "$o" | grep -qF "master tc-100k-s0c1p0-r2-m and 1 worker(s) tc-100k-s0c1p0-r2-w1," && chk "the tag and a single worker appear in the names (100k-s0c1p0-r2, -w1)" ok || chk "the tag and a single worker appear in the names (100k-s0c1p0-r2, -w1)" bad
  # 5. no name of an earlier run is left in the kit folder
  L="$(grep -rEn '(^|[^a-z0-9])(fin2?|r47|psl|cl2|e15r2?|k1a|k1e)([^a-z0-9]|$)|rel-fix|tc-f1-|tc-r4-' "$D" 2>/dev/null | head -3)"
  [ -z "$L" ] && chk "no name of an earlier run (fin, r47, psl, cl2, e15, k1a, k1e, tc-f1-, tc-r4-) is left in the kit folder" ok || chk "no name of an earlier run is left in the kit folder (found: $L)" bad
}

echo "== 1 to 5. the kit itself"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== 6. the mutants (each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME FILE SED-EXPRESSION
  local name="$1" file="$2" expr="$3"; rm -rf "$W/m"; mkdir -p "$W/m"; cp "$K"/* "$W/m/"
  sed -i "$expr" "$W/m/$file"
  if cmp -s "$K/$file" "$W/m/$file"; then echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; fi
  PASS=0; FAIL=0; suite "$W/m"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
mutant "the run id drops the tag"                 names.sh   's/RUN_ID="${SIZE}-${CODE}${TAG:+-$TAG}"/RUN_ID="${SIZE}-${CODE}"/'
mutant "worker numbers are off by one"            names.sh   's/echo "${WORKER_BASE}${1}"/echo "${WORKER_BASE}$(( ${1} + 1 ))"/'
mutant "the provenance digit is the storage one"  names.sh   's/p$(rk_digit "$PROVENANCE")/p$(rk_digit "$STORAGE")/'
mutant "the run id is in upper case"              names.sh   's/RUN_ID="${SIZE}-/RUN_ID="${SIZE^^}-/'
mutant "the worker limit is removed"              names.sh   's/RK_MAX_WORKERS=20/RK_MAX_WORKERS=999/'
mutant "the plan calls gcloud"                    run-kit.sh 's/^rk_plan() {/rk_plan() { gcloud compute instances list >\/dev\/null 2>\&1/'
mutant "a builder name has no commit"             names.sh   's/BUILDER_A="tc-b-${C9}-a"/BUILDER_A="tc-b-a"/'
mutant "an old name is left behind"               names.sh   '2a # old name tc-f1-m'
mutant "two images get the same name"             names.sh   's/IMAGE_2="tc-img-${C9}-2"/IMAGE_2="tc-img-${C9}-1"/'
mutant "a flag given twice is accepted"           run-kit.sh 's/case "$seen" in \*" $k "\*) rk_die "$f was given twice"; return 1;; esac/:/'
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of the kit: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-NAMES-REHEARSAL-OK"; else echo "RUN-KIT-NAMES-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
