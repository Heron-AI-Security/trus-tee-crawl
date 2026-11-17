#!/usr/bin/env bash
# Step 3, seal-images: each build becomes a SEALED image. Both builders are stopped (a stopped VM costs only its disk); then, for A and B at the same time, the builder is LOCKED, cleaned
# and powered off in one ssh session (the lock removes sshd, so a second session is impossible), its disk is copied and normalized and sealed offline on a helper VM; then the image is made
# from the sealed disk and the helper VM and the copied disk are deleted. The step decides by itself what an earlier attempt left behind: a sealed disk is never sealed twice, a builder that
# was locked is never started again, and leftovers of a killed attempt stop the step with the exact command that removes them. Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names
H="$HOME"; TREE="$H/$BUILD_TREE"; CF="$H/$BUILD_COMMIT_FILE"; BD="$H/$BUILD_DIR"
fail() { echo "SEAL-IMAGES-FAILED: $*"; exit 1; }
for i in a b; do [ -s "$BD/$i/zone.txt" ] && grep -qx manifest "$BD/$i/done.txt" 2>/dev/null || fail "build ${i^^} is not finished (step 1): run the same command without --until"; done
[ -s "$CF" ] && [ -d "$TREE" ] || fail "there is no unpacked commit (step 0 has not run)"
KV="$(rk_kernel_version "$TREE")" || fail "no kernel version"
ZA="$(cat "$BD/a/zone.txt")"; ZB="$(cat "$BD/b/zone.txt")"; cd "$TREE" || exit 1
t0=$(date +%s)

echo "== 1. stop both builders (the images are made from their disks; the evidence of both is saved; a stopped VM costs only its disk)"
gcloud compute instances stop "$BUILDER_A" --zone="$ZA" --quiet 2>&1 | tail -1
gcloud compute instances stop "$BUILDER_B" --zone="$ZB" --quiet 2>&1 | tail -1
echo "== 2. the preflight of the sealing session (read-only, seconds)"
mkdir -p "$H/$SEAL_OUT_A" "$H/$SEAL_OUT_B"
env BUILDER="$BUILDER_A" ZONE="$ZA" IMG="$IMAGE_1" OUT="$H/$SEAL_OUT_A" BASE_IMAGE="$RK_SEAL_BASE_IMAGE" bash "$TREE/$RK_T_SEAL_PREFLIGHT" "$TREE" || fail "the preflight of the sealing session failed (the first FAIL line is above); nothing was sealed"

seal_env() {  # ID: the settings that the driver reads for the sealing of one build, in an array named DENV (set here, used by the callers)
  local ID="$1"
  if [ "$ID" = A ]; then S_BUILDER="$BUILDER_A"; S_ZONE="$ZA"; S_IMG="$IMAGE_1"; S_OUT="$H/$SEAL_OUT_A"; S_DISK="$SEAL_DISK_A"; S_SEALER="$SEALER_A"; S_TEST="$SEAL_TEST_A"
  else S_BUILDER="$BUILDER_B"; S_ZONE="$ZB"; S_IMG="$IMAGE_2"; S_OUT="$H/$SEAL_OUT_B"; S_DISK="$SEAL_DISK_B"; S_SEALER="$SEALER_B"; S_TEST="$SEAL_TEST_B"; fi
  DENV=(env BUILDER="$S_BUILDER" ZONE="$S_ZONE" IMG="$S_IMG" OUT="$S_OUT" KVER="$KV" COMMIT_FILE="$CF" SEAL_DISK="$S_DISK" SEALER="$S_SEALER" SEAL_TEST="$S_TEST")
}
leftovers() {  # the helper VMs and the copied disk of the current build (seal_env was called)
  { gcloud compute instances list --filter="name=$S_SEALER OR name=$S_TEST" --format='value(name)' 2>/dev/null; gcloud compute disks list --filter="name=$S_DISK" --format='value(name)' 2>/dev/null; } | tr '\n' ' '
}

lock_one() {  # ID: lock, clean and seal one build (runs in the background; its output goes to its own log)
  local ID="$1" S_BUILDER S_ZONE S_IMG S_OUT S_DISK S_SEALER S_TEST STAGES LOG STATUS LEFT RC; local -a DENV
  seal_env "$ID"; LOG="$S_OUT/seal-run.log"; touch "$LOG"; STAGES="$RK_SEAL_STAGES"
  STATUS="$(gcloud compute instances describe "$S_BUILDER" --zone="$S_ZONE" --format='value(status)' 2>/dev/null)"
  if grep -aq "$RK_M_SEAL_OK" "$LOG" 2>/dev/null; then echo "build $ID: the disk is already sealed ($RK_M_SEAL_OK in $LOG): not sealed again"; echo "SEAL-RUN-DONE (build $ID)"; return 0; fi
  if grep -aq "$RK_M_SEAL_DONE" "$S_OUT/$RK_SEAL_CONSOLE" 2>/dev/null; then
    [ "$STATUS" = TERMINATED ] || { echo "SEAL-IMAGES-FAILED: the builder $S_BUILDER was locked and cleaned by an earlier attempt but is not stopped (it is $STATUS), so its disk must not be copied. Stop it (run-kit.sh stop build ...) and run the same command again"; return 1; }
    LEFT="$(leftovers)"
    if [ -n "$LEFT" ]; then
      echo "SEAL-IMAGES-FAILED: the builder $S_BUILDER was locked and cleaned by an earlier attempt, and a killed attempt left this behind: $LEFT"
      echo "   Starting the builder again would change the image and could not log in, and the half-made copy must not be reused. Delete the leftovers by their exact names, then run the same command again; only the sealing of the disk will run:"
      echo "   cd $TREE && env CONFIRM=yes ZONE=$S_ZONE SEAL_DISK=$S_DISK SEALER=$S_SEALER SEAL_TEST=$S_TEST IMG=$S_IMG OUT=$S_OUT bash $RK_T_IMAGE_DRIVER $RK_SEAL_CLEAN_STAGE"
      return 1
    fi
    STAGES="seal-disk"; echo "== RESUME: the builder $S_BUILDER was locked and cleaned (SEAL-DONE) and is stopped, with no leftovers: only the sealing of its disk runs again"
  fi
  echo "== sealing build $ID: on the builder $S_BUILDER the lock, the cleaning and the power-off run in ONE ssh session; then its disk is copied, normalized and sealed offline on a helper VM"
  "${DENV[@]}" bash "$TREE/$RK_T_IMAGE_DRIVER" $STAGES 2>&1 | tee -a "$LOG" | cut -c1-200; RC=${PIPESTATUS[0]}
  [ "$RC" = 0 ] || { echo "SEAL-IMAGES-FAILED: the sealing of build $ID ended with exit $RC (the output is above and in $LOG)"; return 1; }
  grep -aq "$RK_M_SEAL_OK" "$LOG" || { echo "SEAL-IMAGES-FAILED: the sealing of build $ID printed no $RK_M_SEAL_OK line (read $LOG)"; return 1; }
  echo "normalization of build $ID: $(grep -a -m1 "$RK_M_NORMALIZE_OK" "$LOG" | cut -c1-120)"
  [ -s "$S_OUT/$RK_SEAL_REPORT_FILE" ] && echo "   what it removed (group, entries): $(awk -F'\t' '{n[$1]+=($3+0)} END {for (g in n) printf "%s=%d ", g, n[g]}' "$S_OUT/$RK_SEAL_REPORT_FILE")"
  echo "SEAL-RUN-DONE (build $ID)"
}

echo "== 3. lock and seal both builds at the same time (the old kit needed about 55 minutes; the logs are $H/$SEAL_OUT_A/seal-run.log and $H/$SEAL_OUT_B/seal-run.log)"
PIDS=()
for ID in A B; do ( lock_one "$ID" ) > "$H/$BUILD_DIR/seal-$(echo "$ID" | tr A-Z a-z)-step.log" 2>&1 & PIDS+=($!); done
hb_print() {  # the state of each sealing from the cloud (the driver prints its output in blocks, so the last line alone says little)
  local ID st LEFT
  for ID in A B; do seal_env "$ID"; st="$(gcloud compute instances describe "$S_BUILDER" --zone="$S_ZONE" --format='value(status)' 2>/dev/null)"; LEFT="$(leftovers)"
    echo "   [heartbeat $(date -u +%H:%M) UTC, $(rk_mins "$t0") min] sealing $ID: builder ${st:-unknown}, helper VM and disk copy: ${LEFT:-none yet} | last line: $(tail -n 1 "$BD/seal-$(echo "$ID" | tr A-Z a-z)-step.log" 2>/dev/null | cut -c1-80)"; done
}
rk_wait_watch hb_print "${PIDS[@]}"   # a heartbeat every few minutes, and the end is noticed within a second
BAD=0; for i in 0 1; do c="$(echo ab | cut -c$((i + 1)))"; wait "${PIDS[$i]}" || { BAD=$((BAD + 1)); echo "sealing of build ${c^^} FAILED. The end of its output:"; tail -n 12 "$BD/seal-$c-step.log" | cut -c1-600 | sed 's/^/   | /'; }   # long lines stay whole: the command that removes leftovers must be copyable
  grep -E "^normalization of build|^   what it removed" "$BD/seal-$c-step.log" | sed 's/^/   /'; done
[ "$BAD" = 0 ] || fail "$BAD of the 2 sealings failed (see above). Finished work is kept: run the same command again"

for ID in A B; do
  seal_env "$ID"; LOGI="$S_OUT/image-run.log"; touch "$LOGI"
  echo "== 4. the sealed LOCKED image $S_IMG of build $ID (a rerun must not make it twice)"
  if [ "$(gcloud compute images describe "$S_IMG" --format='value(status)' 2>/dev/null)" = READY ]; then echo "   $S_IMG exists and is READY: not made again"
  else "${DENV[@]}" SCRATCH_GB=10 bash "$TREE/$RK_T_IMAGE_DRIVER" "$RK_SEAL_IMAGE_STAGE" 2>&1 | tee -a "$LOGI" | tail -4; [ "${PIPESTATUS[0]}" = 0 ] || fail "the image $S_IMG could not be made (the lines above say why)"; fi
  [ "$(gcloud compute images describe "$S_IMG" --format='value(status)' 2>/dev/null)" = READY ] || fail "the image $S_IMG is not READY after the stage"
  echo "   $S_IMG is READY; now the helper VM and the copied disk are deleted (the image stays)"
  "${DENV[@]}" CONFIRM=yes bash "$TREE/$RK_T_IMAGE_DRIVER" "$RK_SEAL_CLEAN_STAGE" 2>&1 | tee -a "$LOGI" | tail -3
done
rk_result "both images are sealed and READY after $(rk_mins "$t0") min: $IMAGE_1 (build A) and $IMAGE_2 (build B), made from the locked, cleaned and normalized disks of the two builders; the helper VMs and the copied disks are deleted"
