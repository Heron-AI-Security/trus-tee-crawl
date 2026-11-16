#!/usr/bin/env bash
# Rehearsal of the runner of the one run kit (ops/kits/run-kit/lib.sh, record.sh, steps-*.sh and the commands of run-kit.sh).
#   bash run-kit-runner-rehearse.sh TREE        (TREE holds ops/; no cloud, no network; a throwaway HOME and a fake gcloud; nothing is written outside a temporary folder)
# FAKE STEPS (one that fails, one that ends without a result, one that is slow, one that reports the names it was given) prove that the runner:
#  1. runs the steps in order, marks them done, times them, and skips them on a second run;   2. stops at a failing step, keeps the finished ones and resumes at the failed one;
#  3. does not count a step that ends without a result;   4. stops after the step of --until, and refuses an unknown step;   5. refuses a second run at the same time (a lock);
#  6. refuses a run with other flags in a folder that another command line started, and lets --restart start again;   7. gives every step the names of names.sh;
#  8. runs build and crawl in one command (all);   9. shows the state (status) and what the steps found (report);
# 10. stops the cloud resources by the RUN LABEL (crawl) or the two builders (build), only after a yes;   11. makes a build record that has the same fingerprint every time, checks it, and refuses a damaged one;
# 12. makes ssh-keygen run under a lock without calling itself;   13. the real step lists are numbered 0 to 13 without a gap, and no old step label or old tool name is in the kit apart from tools.sh;
# 14. mutants of lib.sh, record.sh and run-kit.sh (a step without a result is done, a failed step is done, --until ignored, stop by a name pattern, no question before a stop, no input pin,
#     finished steps run again, no lock, a record that is not deterministic, an old label in the kit) are all caught by the same checks.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W="$(mktemp -d)"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
for f in lib.sh record.sh run-kit.sh names.sh steps-build.sh steps-crawl.sh; do [ -f "$K/$f" ] || { echo "RUN-KIT-RUNNER-REHEARSAL-FAIL: $K/$f is missing"; exit 1; }; done
COMMIT=bd339c8d2e88; C9=${COMMIT:0:9}; CRAWL="--build $C9 --size 1k --storage on --comms off --provenance on"; RID=1k-s1c0p1

# ---- the fake cloud and the fake steps
mkdir -p "$W/fakebin" "$W/fake/steps"
cat > "$W/fakebin/gcloud" <<'EOG'
#!/bin/sh
echo "$*" >> "$GCLOG"
case "$*" in
  "compute instances list --filter=labels.tc-run="*"--format=value("*) cat "$VMS" 2>/dev/null ;;
  "compute instances list --filter=name="*"--format=value("*) echo "us-central1-b" ;;
  "compute instances list"*) printf 'NAME STATUS ZONE\nfake RUNNING us-central1-a\n' ;;
esac
exit 0
EOG
chmod +x "$W/fakebin/gcloud"
cat > "$W/fake/steps-build.sh" <<'EOS'
RK_STEPS=("0|one|First step|steps/one.sh" "1|two|Second step|steps/two.sh" "2|three|Third step|steps/three.sh")
EOS
cat > "$W/fake/steps-crawl.sh" <<'EOS'
RK_STEPS=("6|four|Fourth step|steps/four.sh" "7|five|Fifth step|steps/five.sh")
EOS
cat > "$W/fake/steps/one.sh"   <<'EOS'
echo "one runs"; echo "x" >> "$CTL/count-one"; echo "first ok" >> "$RK_RESULT_FILE"
EOS
cat > "$W/fake/steps/two.sh"   <<'EOS'
echo "two runs"; echo "x" >> "$CTL/count-two"; if [ -e "$CTL/fail-two" ]; then echo "two breaks"; exit 1; fi; echo "second ok" >> "$RK_RESULT_FILE"
EOS
cat > "$W/fake/steps/three.sh" <<'EOS'
echo "three runs"; echo "x" >> "$CTL/count-three"; [ ! -e "$CTL/slow-three" ] || sleep 4; [ ! -e "$CTL/noresult-three" ] || exit 0; echo "third ok" >> "$RK_RESULT_FILE"
EOS
cat > "$W/fake/steps/four.sh"  <<'EOS'
echo "four runs"; echo "x" >> "$CTL/count-four"; echo "env RUN_ID=$RUN_ID MASTER=$MASTER IMAGE_1=$IMAGE_1 WORKERS=$WORKERS C9=$C9" >> "$RK_RESULT_FILE"
EOS
cat > "$W/fake/steps/five.sh"  <<'EOS'
echo "five runs"; echo "x" >> "$CTL/count-five"; echo "fifth ok" >> "$RK_RESULT_FILE"
EOS

suite() {  # DIR: all the checks against the kit in DIR
  local D="$1" o rc n bg
  rk() { HOME="$W/home" CTL="$W/ctl" GCLOG="$W/gcloud.log" VMS="$W/vms.txt" PATH="$W/fakebin:$PATH" RK_STEPS_DIR="$W/fake" bash "$D/run-kit.sh" "$@"; }
  reset() { rm -rf "$W/home" "$W/ctl" "$W/gcloud.log"; mkdir -p "$W/home" "$W/ctl"; : > "$W/gcloud.log"; }
  cnt() { cat "$W/ctl/count-$1" 2>/dev/null | wc -l | tr -d ' '; }
  SD="$W/home/build-$C9/state"
  # 1. in order, done, timed; and skipped on a second run
  reset; o="$(rk build --commit $COMMIT 2>&1)"; rc=$?
  [ "$rc" = 0 ] && for n in 0 1 2; do printf '%s' "$o" | grep -q "^STEP $n DONE: " || rc=9; done; [ "$rc" = 0 ] && chk "build runs its three steps and says STEP 0, 1 and 2 DONE" ok || chk "build runs its three steps and says STEP 0, 1 and 2 DONE (exit $rc)" bad
  [ "$(tr '\n' ' ' < "$SD/stages.done" 2>/dev/null)" = "one two three " ] && [ "$(wc -l < "$SD/timings.txt" 2>/dev/null | tr -d ' ')" = 3 ] && chk "the finished steps are listed in order and each has a time" ok || chk "the finished steps are listed in order and each has a time" bad
  o="$(rk build --commit $COMMIT 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ "$(printf '%s' "$o" | grep -c 'skipped, done before')" = 3 ] && [ "$(cnt one)$(cnt two)$(cnt three)" = 111 ] && chk "a second run skips the three finished steps and runs none of them again" ok || chk "a second run skips the three finished steps and runs none of them again" bad
  # 2. a failing step: finished steps kept, resume at the failed one
  reset; touch "$W/ctl/fail-two"; o="$(rk build --commit $COMMIT 2>&1)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "^STEP 1 FAILED" && [ "$(cat "$SD/stages.done" | tr '\n' ' ')" = "one " ] && chk "a failing step stops the run with exit 1 and says STEP 1 FAILED; the first step stays done" ok || chk "a failing step stops the run with exit 1 and says STEP 1 FAILED; the first step stays done (exit $rc)" bad
  rm -f "$W/ctl/fail-two"; o="$(rk build --commit $COMMIT 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ "$(cnt one)" = 1 ] && [ "$(cnt two)" = 2 ] && [ "$(cnt three)" = 1 ] && chk "after the fix the run goes on at the failed step: step 0 is not run again, step 1 is run again, step 2 runs" ok || chk "after the fix the run goes on at the failed step (counts: $(cnt one) $(cnt two) $(cnt three), exit $rc)" bad
  # 3. a step that ends without a result
  reset; touch "$W/ctl/noresult-three"; o="$(rk build --commit $COMMIT 2>&1)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "without reporting a result" && ! grep -qx three "$SD/stages.done" && chk "a step that ends with exit 0 but no result is a failure, and it is not marked done" ok || chk "a step that ends with exit 0 but no result is a failure, and it is not marked done (exit $rc)" bad
  # 4. --until
  reset; o="$(rk build --commit $COMMIT --until two 2>&1)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "Stopped after step 1 (two)" && [ "$(cat "$SD/stages.done" | tr '\n' ' ')" = "one two " ] && chk "--until two stops after step 1 with exit 0 and leaves step 2 undone" ok || chk "--until two stops after step 1 with exit 0 and leaves step 2 undone (exit $rc)" bad
  o="$(rk build --commit $COMMIT 2>&1)"; rc=$?; [ "$rc" = 0 ] && [ "$(cnt three)" = 1 ] && [ "$(cnt two)" = 1 ] && chk "the next run without --until runs only the step that was left" ok || chk "the next run without --until runs only the step that was left" bad
  o="$(rk build --commit $COMMIT --until nonsense 2>&1)"; rc=$?; [ "$rc" = 2 ] && printf '%s' "$o" | grep -q "RUN-KIT-INPUT-ERROR: --until must name a step" && printf '%s' "$o" | grep -q "one two three" && chk "--until with an unknown step is refused (exit 2) and the steps are listed" ok || chk "--until with an unknown step is refused (exit 2) and the steps are listed" bad
  # 5. the lock
  if command -v flock >/dev/null 2>&1; then
    reset; touch "$W/ctl/slow-three"; rk build --commit $COMMIT > "$W/bg.out" 2>&1 & bg=$!; sleep 1.5
    o="$(rk build --commit $COMMIT 2>&1)"; rc=$?; wait $bg
    [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "RUN-KIT-BUSY" && chk "a second run at the same time is refused (exit 1, RUN-KIT-BUSY) while the first one goes on" ok || chk "a second run at the same time is refused (exit 1, RUN-KIT-BUSY) while the first one goes on (exit $rc)" bad
  else chk "a second run at the same time is refused (skipped: no flock in this shell)" ok; fi
  o="$( . "$D/lib.sh"; rk_state_init "$W/home/lk"; command() { if [ "${1:-}" = -v ] && [ "${2:-}" = flock ]; then return 1; fi; builtin command "$@"; }; rk_lock 2>&1 )"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "RUN-KIT-NO-FLOCK" && chk "a shell without flock refuses to start (RUN-KIT-NO-FLOCK) and does not say that another run is active" ok || chk "a shell without flock refuses to start (RUN-KIT-NO-FLOCK) and does not say that another run is active (exit $rc: $o)" bad
  # 6. the inputs of a phase are pinned
  reset; rk crawl $CRAWL > /dev/null 2>&1
  o="$(rk crawl $CRAWL --workers 5 2>&1)"; rc=$?
  [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "RUN-KIT-INPUTS-DIFFER" && printf '%s' "$o" | grep -q "workers=10" && printf '%s' "$o" | grep -q "workers=5" && chk "other flags in the folder of another command line are refused, and the message shows both" ok || chk "other flags in the folder of another command line are refused, and the message shows both (exit $rc)" bad
  o="$(rk crawl $CRAWL --workers 5 --restart 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ "$(cnt four)" = 2 ] && chk "--restart forgets the finished steps and accepts the new flags: the steps run again" ok || chk "--restart forgets the finished steps and accepts the new flags: the steps run again (exit $rc, count $(cnt four))" bad
  # 7. the names that a step is given
  reset; rk crawl $CRAWL > /dev/null 2>&1
  [ "$(head -1 "$W/home/run-$RID/results/four.txt" 2>/dev/null)" = "env RUN_ID=$RID MASTER=tc-$RID-m IMAGE_1=tc-img-$C9-1 WORKERS=10 C9=$C9" ] && chk "a step is given the names of names.sh (run id, master, image, workers, commit)" ok || chk "a step is given the names of names.sh (got: $(head -1 "$W/home/run-$RID/results/four.txt" 2>/dev/null))" bad
  [ -d "$W/home/run-$RID" ] && [ ! -d "$W/home/build-$C9" ] && chk "the state of a crawl is the run folder (~/run-<run id>) and the crawl does not touch the build folder" ok || chk "the state of a crawl is the run folder (~/run-<run id>) and the crawl does not touch the build folder" bad
  # 8. all
  reset; o="$(rk all --commit $COMMIT --size 1k --storage on --comms off --provenance on 2>&1)"; rc=$?
  [ "$rc" = 0 ] && [ "$(printf '%s' "$o" | grep -o '^STEP [0-9]* DONE' | tr '\n' ' ')" = "STEP 0 DONE STEP 1 DONE STEP 2 DONE STEP 6 DONE STEP 7 DONE " ] && [ -d "$SD" ] && [ -d "$W/home/run-$RID" ] && chk "all runs the build steps and then the crawl steps, each phase in its own folder" ok || chk "all runs the build steps and then the crawl steps, each phase in its own folder (exit $rc)" bad
  # 9. status and report
  reset; touch "$W/ctl/fail-two"; rk build --commit $COMMIT > /dev/null 2>&1
  o="$(rk status build --commit $COMMIT 2>&1)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "done  step  0  one" && ! printf '%s' "$o" | grep -q "done  step  1  two" && printf '%s' "$o" | grep -q "step  1  two" && chk "status shows step 0 as done and step 1 as not done" ok || chk "status shows step 0 as done and step 1 as not done" bad
  grep -q -- "--filter=name~'^tc-(b|sealer|seal-disk|seal-test)-$C9'" "$W/gcloud.log" && chk "status asks the cloud for the VMs of the build by the commit in their names" ok || chk "status asks the cloud for the VMs of the build by the commit in their names" bad
  o="$(rk report build --commit $COMMIT 2>&1)"; printf '%s' "$o" | grep -q "First step: first ok" && ! printf '%s' "$o" | grep -q "Second step" && chk "report shows what the finished step found and nothing for the unfinished one" ok || chk "report shows what the finished step found and nothing for the unfinished one" bad
  reset; o="$(rk status crawl $CRAWL 2>&1)"; [ "$(ls "$W/home" | wc -l | tr -d ' ')" = 0 ] && printf '%s' "$o" | grep -q "no folder yet" && chk "status of a run that never started says so and creates nothing" ok || chk "status of a run that never started says so and creates nothing" bad
  # 10. stop
  reset; printf 'tc-%s-m\tus-central1-a\ntc-%s-w1\tus-central1-a\ntc-%s-w2\tus-central1-a\n' $RID $RID $RID > "$W/vms.txt"
  o="$(printf 'no\n' | rk stop crawl $CRAWL 2>&1)"; rc=$?
  [ "$rc" = 1 ] && ! grep -q "instances delete" "$W/gcloud.log" && chk "stop shows the VMs and deletes nothing when the answer is not yes" ok || chk "stop shows the VMs and deletes nothing when the answer is not yes (exit $rc)" bad
  o="$(rk stop crawl $CRAWL --yes 2>&1)"; rc=$?
  [ "$rc" = 0 ] && grep -q -- "--filter=labels.tc-run=$RID --format" "$W/gcloud.log" && grep -q "instances delete tc-$RID-m tc-$RID-w1 tc-$RID-w2 --zone=us-central1-a --quiet" "$W/gcloud.log" && chk "stop --yes finds the VMs by the label tc-run=$RID and deletes exactly them in one call" ok || chk "stop --yes finds the VMs by the label tc-run=$RID and deletes exactly them in one call (exit $rc: $(grep delete "$W/gcloud.log" | head -2))" bad
  ! grep -q "name~" "$W/gcloud.log" && chk "stop of a crawl never looks for VMs by a name pattern" ok || chk "stop of a crawl never looks for VMs by a name pattern" bad
  : > "$W/gcloud.log"; o="$(rk stop build --commit $COMMIT --yes 2>&1)"; rc=$?
  [ "$rc" = 0 ] && grep -q "instances stop tc-b-$C9-a --zone=us-central1-b --quiet" "$W/gcloud.log" && grep -q "instances stop tc-b-$C9-b --zone=us-central1-b --quiet" "$W/gcloud.log" && ! grep -q "instances delete" "$W/gcloud.log" && chk "stop of a build stops the two builders and deletes nothing" ok || chk "stop of a build stops the two builders and deletes nothing" bad
  # 11. the build record
  reset; mkdir -p "$W/rec/a/measurements" "$W/rec/b/measurements" "$W/rec/reference"
  ( . "$D/record.sh"
    ok=1; rk_record_check "$W/rec" > "$W/rc.out" 2>&1 && ok=0
    [ "$ok" = 1 ] && grep -q "RUN-KIT-RECORD-INCOMPLETE" "$W/rc.out" && grep -q "commit.txt" "$W/rc.out" && echo CHECK-REFUSES-EMPTY )  > "$W/r1.out"
  grep -q CHECK-REFUSES-EMPTY "$W/r1.out" && chk "an incomplete build record is refused and the missing files are named" ok || chk "an incomplete build record is refused and the missing files are named" bad
  ( . "$D/record.sh"; for f in $RK_RECORD_REQUIRED; do mkdir -p "$W/rec/$(dirname "$f")"; echo "content of $f" > "$W/rec/$f"; done
    rk_record_check "$W/rec" && echo CHECK-ACCEPTS-FULL
    find "$W/rec" -type f -exec touch -d '2020-01-01 00:00:00' {} +; rk_record_pack "$W/rec" "$W/r1.tgz"; find "$W/rec" -type f -exec touch -d '2026-06-06 06:06:06' {} +; rk_record_pack "$W/rec" "$W/r2.tgz"
    [ "$(rk_record_fingerprint "$W/r1.tgz")" = "$(rk_record_fingerprint "$W/r2.tgz")" ] && echo SAME-FINGERPRINT
    FP="$(rk_record_fingerprint "$W/r1.tgz")"; rk_record_verify "$W/r1.tgz" "${FP:0:32}" && echo VERIFY-OK
    echo changed > "$W/rec/compare.txt"; rk_record_pack "$W/rec" "$W/r3.tgz"; rk_record_verify "$W/r3.tgz" "${FP:0:32}" > "$W/v.out" 2>&1 || grep -q RUN-KIT-RECORD-MISMATCH "$W/v.out" && echo DAMAGE-REFUSED ) > "$W/r2.out" 2>&1
  for x in "CHECK-ACCEPTS-FULL:a complete build record is accepted" "SAME-FINGERPRINT:the same files give the same archive and fingerprint, whatever their times" "VERIFY-OK:the fingerprint of the image label (first 32 characters) verifies the record" "DAMAGE-REFUSED:a record with one changed file is refused"; do grep -q "${x%%:*}" "$W/r2.out" && chk "${x#*:}" ok || chk "${x#*:}" bad; done
  # 12. ssh-keygen under a lock
  reset; mkdir -p "$W/kbin"; printf '#!/bin/sh\necho called >> "%s/keygen.log"\n' "$W" > "$W/kbin/ssh-keygen"; chmod +x "$W/kbin/ssh-keygen"; rm -f "$W/keygen.log"
  o="$( HOME="$W/home" PATH="$W/kbin:$PATH" bash -c ". '$D/lib.sh'; rk_state_init '$W/home/st'; rk_ssh_keygen_lock; rk_ssh_keygen_lock; command -v ssh-keygen; ssh-keygen -q; ssh-keygen -q" 2>&1 )"
  printf '%s' "$o" | head -1 | grep -q "$W/home/st/bin/ssh-keygen" && [ "$(cat "$W/keygen.log" 2>/dev/null | wc -l | tr -d ' ')" = 2 ] && chk "ssh-keygen runs under the lock, calls the real one once per call and does not call itself (the lock is set twice)" ok || chk "ssh-keygen runs under the lock, calls the real one once per call and does not call itself (got: $o)" bad
  # 13. the real step lists, and no old label in the kit
  o="$(cd "$D" && bash -c 'RK_STEPS=(); . ./steps-build.sh; A=("${RK_STEPS[@]}"); RK_STEPS=(); . ./steps-crawl.sh; for e in "${A[@]}" "${RK_STEPS[@]}"; do echo "$e"; done' 2>/dev/null)"
  [ "$(echo "$o" | cut -d'|' -f1 | tr '\n' ' ')" = "0 1 2 3 4 5 6 7 8 9 10 11 12 13 " ] && chk "the real steps are numbered 0 to 13 in order, without a gap, build first and then crawl" ok || chk "the real steps are numbered 0 to 13 in order, without a gap (got: $(echo "$o" | cut -d'|' -f1 | tr '\n' ' '))" bad
  [ "$(echo "$o" | cut -d'|' -f2 | sort | uniq -d | wc -l | tr -d ' ')" = 0 ] && ! echo "$o" | cut -d'|' -f2 | grep -qvE '^[a-z]+(-[a-z]+)*$' && ! echo "$o" | cut -d'|' -f3 | grep -q '^$' && chk "every step has its own id of lower case words with hyphens, and a title" ok || chk "every step has its own id of lower case words with hyphens, and a title" bad
  n="$(grep -rEn '(^|[^A-Za-z0-9_])(P[1-6]|R[0-7]|F[0-5])([.0-9a-z]*)([^A-Za-z0-9_]|$)|r[0-9][a-z]?-(accept|diff|derive|recompute|archive|rehearse)|r[35]-[a-z]|f03-|f1-drive|f1-fleet|publish-ref|verify-reference|tree-diff' --exclude=tools.sh "$D" 2>/dev/null | head -2)"
  [ -z "$n" ] && chk "no old step label (P, R, F with a number) and no old tool name is in the kit apart from tools.sh" ok || chk "no old step label and no old tool name is in the kit apart from tools.sh (found: $n)" bad
}

echo "== 1 to 13. the runner, with fake steps and a fake cloud"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== 14. the mutants (each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME FILE SED-EXPRESSION
  local name="$1" file="$2" expr="$3"; rm -rf "$W/m"; mkdir -p "$W/m"; cp "$K"/* "$W/m/"
  sed -i "$expr" "$W/m/$file"
  if cmp -s "$K/$file" "$W/m/$file"; then echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; fi
  PASS=0; FAIL=0; suite "$W/m"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
mutant "a step without a result counts as done"      lib.sh    's/if \[ "$rc" = 0 \] \&\& \[ -s "$RK_RESULT_FILE" \]; then/if [ "$rc" = 0 ]; then/'
mutant "a failed step is marked done"                lib.sh    's/if \[ "$rc" = 0 \] \&\& \[ -s "$RK_RESULT_FILE" \]; then/if true; then/'
mutant "--until is ignored"                          lib.sh    's/if \[ "${UNTIL:-}" = "$id" \]; then/if false; then/'
mutant "finished steps run again"                    lib.sh    's/if grep -qx "$id" "$RK_DONE"; then echo "STEP $n skipped/if false; then echo "STEP $n skipped/'
mutant "stop finds the VMs by a name pattern"        lib.sh    "s/--filter=\"labels.tc-run=\$1\"/--filter=\"name~'^tc-'\"/"
mutant "stop asks no question"                       lib.sh    's/rk_confirm() { \[ "${YES:-0}" = 1 \] \&\& return 0;/rk_confirm() { return 0;/'
mutant "the inputs are not pinned"                   lib.sh    's/\[ "$(cat "$RK_DIR\/inputs.txt")" = "$1" \] ||/true ||/'
mutant "there is no lock"                            lib.sh    's/flock -n 8 ||/true ||/'
mutant "a missing flock lets the run go on unlocked" lib.sh    's/command -v flock >\/dev\/null 2>\&1 || { echo "RUN-KIT-NO-FLOCK/true || { echo "RUN-KIT-NO-FLOCK/'
mutant "the record archive depends on file times"    record.sh "s/--mtime='UTC 2000-01-01' //"
mutant "an old step label is left in the kit"        lib.sh    '2a # the step P4 of the old plan'
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of the runner: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-RUNNER-REHEARSAL-OK"; else echo "RUN-KIT-RUNNER-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
