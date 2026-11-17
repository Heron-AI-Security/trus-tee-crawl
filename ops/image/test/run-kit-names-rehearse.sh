#!/usr/bin/env bash
# Rehearsal of the names and the command line of the one run kit (ops/kits/run-kit/names.sh and run-kit.sh).
#   bash run-kit-names-rehearse.sh TREE        (TREE holds ops/; no cloud, no network, nothing is written outside a temporary folder)
# 1. every combination of the inputs makes valid names that never collide, and two commits never share a name;
# 2. a bad command line is refused (exit 2) with a clear message, before anything is created;
# 3. the plan makes no cloud call at all (a fake gcloud, ssh, scp, curl, wget and git fail the test if the kit calls one);
# 4. the names are the convention of the kit (master, worker 1 to N, images, folders);
# 5. no name of an earlier run is left in the kit folder;
# 6. the real fleet driver (f1-drive.sh, in a dry run) creates and deletes exactly the VMs that the plan names, with the run label and the machine type,
#    and nothing changes for a caller that sets none of the new settings (VMWBASE, EXTRA_LABELS, MACHINE_TYPE);
# 7. mutants of names.sh, run-kit.sh and f1-drive.sh (a name that drops the tag, a worker off by one, a switch digit swapped, upper case, a limit removed,
#    a cloud call in the plan, a commit missing from a name, an old name left behind, a driver that ignores the base name, the labels or the machine type)
#    are all caught by the same checks.
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
  o="$(cd "$D" && bash -c '. ./names.sh; rk_build_names aaaaaaaaa; a="$BUILDER_A $BUILDER_B $IMAGE_1 $IMAGE_2 $SEAL_DISK_A $SEALER_A $SEAL_TEST_A $SEAL_TEST_B $SEAL_OUT_A $BUILD_DIR $SOURCE_TGZ $SOURCE_ALT_TGZ $BUILD_TREE $BUILD_COMMIT_FILE"; rk_build_names bbbbbbbbb; b="$BUILDER_A $BUILDER_B $IMAGE_1 $IMAGE_2 $SEAL_DISK_A $SEALER_A $SEAL_TEST_A $SEAL_TEST_B $SEAL_OUT_A $BUILD_DIR $SOURCE_TGZ $SOURCE_ALT_TGZ $BUILD_TREE $BUILD_COMMIT_FILE"; for x in $a; do for y in $b; do [ "$x" = "$y" ] && echo SAME; done; done; echo END' 2>/dev/null)"
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
  refuse "$D" "does not belong to 'plan build'" plan build --commit bd339c8d2 --size 1k && chk "a crawl flag on the build command is refused" ok || chk "a crawl flag on the build command is refused" bad
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
  mkdir -p "$W/home" "$W/toysteps"; for f in names.sh lib.sh record.sh tools.sh steps-build.sh; do ln -sf "$D/$f" "$W/toysteps/$f"; done; printf 'RK_STEPS=("6|check-build|Check the image before using it|-")\n' > "$W/toysteps/steps-crawl.sh"; HOME="$W/home" PATH="$W/fake:$PATH" RK_STEPS_DIR="$W/toysteps" bash "$D/run-kit.sh" crawl $OKARGS > "$W/crawl.out" 2>&1; [ "$?" = 3 ] && grep -q "NOT WRITTEN" "$W/crawl.out" || chk "crawl stops with exit 3 and says that the step is not written yet" bad
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


dry_creates() {  # DRIVER VAR=value ...: the VMs that the driver would create in a dry run, one per line: name|machine type|labels
  local DRV="$1"; shift
  env DRY=1 IMG=tc-img-x OUT="$W/dryout" "$@" bash "$DRV" fleet-vms 2>&1 | awk '/^DRY: gcloud compute instances create /{ m=""; l=""; for(i=1;i<=NF;i++){ if($i ~ /^--machine-type=/) m=substr($i,16); if($i ~ /^--labels=/) l=substr($i,10) } gsub(/\\/, "", l); gsub(/\\/, "", m); print $6 "|" m "|" l }'   # a dry run prints each argument with %q, which shows a comma as \, ; the real command gets a plain comma
}
dry_deletes() {  # DRIVER VAR=value ...: the names that the stage fleet-delete would delete, on one line
  local DRV="$1"; shift
  env DRY=1 IMG=tc-img-x OUT="$W/dryout" "$@" bash "$DRV" fleet-delete 2>&1 | awk '/^DRY: gcloud compute instances delete /{ s=""; for(i=6;i<=NF;i++){ if($i ~ /^--/) break; s=s $i " " } print s }'
}
driver_suite() {  # DRIVER: the real driver in a dry run, with the names and settings that names.sh makes
  local DRV="$1" got c envs exp names labels mt dels
  got="$(dry_creates "$DRV" WORKERS=3 | cut -d'|' -f1 | tr '\n' ' ')"
  [ "$got" = "tc-f1-m tc-f1-w tc-f1-w2 tc-f1-w3 " ] && chk "no new setting: the driver still creates tc-f1-m, tc-f1-w, tc-f1-w2 and tc-f1-w3" ok || chk "no new setting: the driver still creates tc-f1-m, tc-f1-w, tc-f1-w2 and tc-f1-w3 (got: $got)" bad
  c="$(dry_creates "$DRV" WORKERS=2 | cut -d'|' -f2-3 | sort -u | tr '\n' ' ')"
  [ "$c" = "c3-standard-4|purpose=tc-f1 " ] && chk "no new setting: machine type c3-standard-4 and the label purpose=tc-f1, nothing else" ok || chk "no new setting: machine type c3-standard-4 and the label purpose=tc-f1, nothing else (got: $c)" bad
  for c in "1k on off on 10 c3-standard-8" "100k off on off 1 c3-standard-4 r2" "10k on on on 4 c3-standard-4 a1b2"; do
    set -- $c; local tg="${7:-}"
    envs="$(cd "$K" && SIZE=$1 STORAGE=$2 COMMS=$3 PROVENANCE=$4 TAG=$tg WORKERS=$5 bash -c '. ./names.sh; rk_run_names; echo "VMM=$MASTER VMW=$(rk_worker 1) VMWBASE=$WORKER_BASE EXTRA_LABELS=tc-run=$RUN_LABEL"')"
    exp="$(cd "$K" && SIZE=$1 STORAGE=$2 COMMS=$3 PROVENANCE=$4 TAG=$tg WORKERS=$5 bash -c '. ./names.sh; rk_run_names; rk_gce_names' | tr '\n' ' ')"
    got="$(dry_creates "$DRV" $envs WORKERS=$5 MACHINE_TYPE=$6)"
    names="$(echo "$got" | cut -d'|' -f1 | tr '\n' ' ')"; mt="$(echo "$got" | cut -d'|' -f2 | sort -u | tr '\n' ' ')"; labels="$(echo "$got" | cut -d'|' -f3 | sort -u | tr '\n' ' ')"
    [ "$names" = "$exp" ] && chk "the driver creates exactly the VMs that the plan names for $1/$2/$3/$4 with $5 worker(s): $(echo "$exp" | cut -d' ' -f1,2) ..." ok || chk "the driver creates exactly the VMs that the plan names for $1/$2/$3/$4 with $5 worker(s) (plan: $exp | driver: $names)" bad
    [ "$mt" = "$6 " ] && chk "every VM of the fleet $1/$2/$3/$4 has the machine type $6" ok || chk "every VM of the fleet $1/$2/$3/$4 has the machine type $6 (got: $mt)" bad
    [ "$labels" = "purpose=tc-f1,tc-run=$(echo "$envs" | sed 's/.*EXTRA_LABELS=tc-run=//') " ] && chk "every VM of the fleet $1/$2/$3/$4 has the labels purpose=tc-f1 and tc-run=<run id>" ok || chk "every VM of the fleet $1/$2/$3/$4 has the labels purpose=tc-f1 and tc-run=<run id> (got: $labels)" bad
    dels="$(dry_deletes "$DRV" $envs WORKERS=$5)"
    [ "$dels" = "$exp" ] && chk "the stage fleet-delete deletes the same VMs, no more and no fewer (fleet $1/$2/$3/$4)" ok || chk "the stage fleet-delete deletes the same VMs (plan: $exp | delete: $dels)" bad
  done
}
echo "== 1 to 5. the kit itself"; suite "$K"
echo "== 6. the real fleet driver creates and deletes exactly the VMs that the plan names (a dry run of f1-drive.sh)"; mkdir -p "$W/dryout"; driver_suite "$T/ops/image/test/f1-drive.sh"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== 7. the mutants (each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME FILE SED-EXPRESSION
  local name="$1" file="$2" expr="$3"; rm -rf "$W/m"; mkdir -p "$W/m"; cp -r "$K"/. "$W/m/"
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
mutant "a flag given twice is accepted"           run-kit.sh 's/rk_die "$2 was given twice"; return 1;;/:;;/'
dmutant() {  # NAME SED-EXPRESSION: a mutant of the driver
  local name="$1" expr="$2"; rm -rf "$W/dt"; mkdir -p "$W/dt"; cp "$T/ops/image/test/f1-drive.sh" "$W/dt/f1-drive.sh"
  sed -i "$expr" "$W/dt/f1-drive.sh"
  if cmp -s "$T/ops/image/test/f1-drive.sh" "$W/dt/f1-drive.sh"; then echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; fi
  PASS=0; FAIL=0; driver_suite "$W/dt/f1-drive.sh"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
dmutant "the driver names the other workers from VMW again"  's/ALL+=("${VMWBASE}$i")/ALL+=("${VMW}$i")/'
dmutant "the driver drops the extra labels"                  's/${EXTRA_LABELS:+,$EXTRA_LABELS}//'
dmutant "the driver ignores the machine type"                's/\[ -z "${MACHINE_TYPE:-}" \] || A=("${A\[@\]\/--machine-type=\*\/--machine-type=$MACHINE_TYPE}"); //'
dmutant "the driver's default base is not VMW"               's/VMWBASE="${VMWBASE:-$VMW}"/VMWBASE="${VMWBASE:-tc-zz-w}"/'
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of the kit: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-NAMES-REHEARSAL-OK"; else echo "RUN-KIT-NAMES-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
