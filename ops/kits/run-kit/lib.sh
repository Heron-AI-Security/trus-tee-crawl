#!/usr/bin/env bash
# lib.sh: the runner of the run kit. It is sourced (never run) by run-kit.sh and by ops/image/test/run-kit-runner-rehearse.sh.
# It starts no VM. Only rk_status and rk_stop talk to the cloud, and rk_stop touches only VMs that carry the run label (crawl) or the two builders of the commit (build).
#
# A STEP is one line of a step list (steps-build.sh, steps-crawl.sh):   NUMBER|ID|TITLE|SCRIPT
#   SCRIPT is a file of the kit (relative to the step folder), or - while the step is not written yet.
# A step is DONE only when its script exits 0 AND the script reported its result with rk_result: a script that ends without a result did not do its job.
# The state of a phase lives in one folder: stages.done (the ids of the finished steps), timings.txt, logs/ (one log per step), results/ (the result line
# of each finished step), inputs.txt (the flags that started the phase) and lock. A second run of the same command skips the finished steps.

rk_mins() { echo $(( ($(date +%s) - $1 + 30) / 60 )); }

rk_state_init() {  # DIR
  RK_DIR="$1"; RK_DONE="$RK_DIR/stages.done"; RK_TIM="$RK_DIR/timings.txt"; RK_LOGS="$RK_DIR/logs"; RK_RESULTS="$RK_DIR/results"
  mkdir -p "$RK_LOGS" "$RK_RESULTS" && touch "$RK_DONE" "$RK_TIM"
}

rk_result() { printf '%s\n' "$*" >> "${RK_RESULT_FILE:?rk_result is for the scripts of the steps}"; }   # a step calls this when it has done its job

rk_lock() {  # two runs of the same phase would delete each other's work
  command -v flock >/dev/null 2>&1 || { echo "RUN-KIT-NO-FLOCK: the command flock is missing in this shell, and the lock against a second run needs it. The kit runs in Cloud Shell (Linux). Nothing was started."; return 1; }
  exec 8>"$RK_DIR/lock"
  flock -n 8 || { echo "RUN-KIT-BUSY: another run of this kit is already active for $RK_DIR (look at its tab, or run: run-kit.sh status ...). Do not start a second one"; return 1; }
}

rk_inputs_pin() {  # TEXT: the first run writes its flags, a later run must have the same flags
  if [ -s "$RK_DIR/inputs.txt" ]; then
    [ "$(cat "$RK_DIR/inputs.txt")" = "$1" ] || { echo "RUN-KIT-INPUTS-DIFFER: the folder $RK_DIR was started with other flags."; echo "   started with: $(cat "$RK_DIR/inputs.txt")"; echo "   now:          $1"; echo "   Use the same flags, another --tag, or --restart (it forgets the finished steps; nothing in the cloud is touched)."; return 1; }
  else
    printf '%s\n' "$1" > "$RK_DIR/inputs.txt"
  fi
}

rk_step() {  # NUMBER ID TITLE SCRIPT
  local n="$1" id="$2" title="$3" script="$4" t0 rc log
  if grep -qx "$id" "$RK_DONE"; then echo "STEP $n skipped, done before: $title"; return 0; fi
  if [ "$script" = - ]; then echo "STEP $n NOT WRITTEN: $title. This version of the kit does not have this step yet; nothing was started."; return 3; fi
  [ -f "${RK_STEPS_DIR:?}/$script" ] || { echo "STEP $n FAILED: the script $script of this step is missing"; return 1; }
  log="$RK_LOGS/$(printf '%02d' "$n")-$id.log"; export RK_RESULT_FILE="$RK_RESULTS/$id.txt"; rm -f "$RK_RESULT_FILE"
  echo; echo "STEP $n START: $title ($(date -u +%H:%M:%S) UTC)"; t0=$(date +%s)
  echo "===== attempt at $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$log"; : > "$RK_DIR/last-attempt.txt"   # the log keeps every attempt; last-attempt.txt holds this one only
  bash "$RK_STEPS_DIR/$script" 2>&1 | tee -a "$log" "$RK_DIR/last-attempt.txt"; rc=${PIPESTATUS[0]}
  if [ "$rc" = 0 ] && [ -s "$RK_RESULT_FILE" ]; then
    echo "$id" >> "$RK_DONE"; echo "$n $id: $(rk_mins "$t0") min" >> "$RK_TIM"
    echo "STEP $n DONE: $(head -1 "$RK_RESULT_FILE")  [$(rk_mins "$t0") min]"; return 0
  fi
  if [ "$rc" = 0 ]; then echo "STEP $n FAILED: $title. The script ended with exit 0 but without reporting a result, so it did not do its job."; else echo "STEP $n FAILED: $title (exit $rc)."; fi
  echo "   The last lines of this attempt (the log of all attempts is $log):"; tail -n 20 "$RK_DIR/last-attempt.txt" | cut -c1-200 | sed 's/^/   | /'
  echo "   The finished steps are kept: the same command runs again from this step."
  return 1
}

rk_run_phase() {  # runs the steps of RK_STEPS in order; 0 = all done, 1 = a step failed, 3 = a step is not written, 100 = stopped by --until
  local e n id title script rc
  for e in "${RK_STEPS[@]}"; do
    IFS='|' read -r n id title script <<< "$e"
    rk_step "$n" "$id" "$title" "$script"; rc=$?
    [ "$rc" = 0 ] || return "$rc"
    if [ "${UNTIL:-}" = "$id" ]; then echo "Stopped after step $n ($id), as asked with --until. Run the same command without --until to go on."; return 100; fi
  done
  echo; echo "== all $(grep -c . "$RK_DONE") steps of this phase are done ($(awk -F': ' '{s+=$2} END {print s+0}' "$RK_TIM") min of step time; the times are in $RK_TIM)"
  return 0
}

rk_status() {  # the steps of RK_STEPS with their state, the last log lines, and VMS_FILTER (a gcloud filter for the VMs of this phase)
  local e n id title script mark tm last
  for e in "${RK_STEPS[@]}"; do
    IFS='|' read -r n id title script <<< "$e"
    if grep -qx "$id" "$RK_DONE"; then mark="done "; tm="$(sed -n "s/^$n $id: //p" "$RK_TIM" | tail -1)"; else mark="     "; tm=""; fi
    printf '   %s step %2s  %-15s %s%s\n' "$mark" "$n" "$id" "$title" "${tm:+  ($tm)}"
  done
  last="$(ls -t "$RK_LOGS"/*.log 2>/dev/null | head -1)"
  [ -z "$last" ] || { echo "   the last lines of the newest log ($(basename "$last")):"; tail -n 3 "$last" | cut -c1-160 | sed 's/^/   | /'; }
  [ -z "${VMS_FILTER:-}" ] || { echo "   VMs of this phase:"; gcloud compute instances list --filter="$VMS_FILTER" --format="table(name,status,zone.basename())" 2>&1 | sed 's/^/   /'; }
}

rk_report() {  # one plain line for each finished step
  local e n id title script any=0
  for e in "${RK_STEPS[@]}"; do
    IFS='|' read -r n id title script <<< "$e"
    if grep -qx "$id" "$RK_DONE" && [ -s "$RK_RESULTS/$id.txt" ]; then echo "   step $n  $title: $(head -1 "$RK_RESULTS/$id.txt")  [$(sed -n "s/^$n $id: //p" "$RK_TIM" | tail -1)]"; any=1; fi
  done
  [ "$any" = 1 ] || echo "   no step is finished yet"
}

rk_confirm() { [ "${YES:-0}" = 1 ] && return 0; printf 'Type yes to continue: '; local a=""; read -r a; [ "$a" = yes ]; }

rk_stop_crawl() {  # LABEL: delete the VMs that carry the run label (never a name pattern); the images and the evidence stay
  local rows z names
  rows="$(gcloud compute instances list --filter="labels.tc-run=$1" --format='value(name,zone.basename())' 2>/dev/null)"
  [ -n "$rows" ] || { echo "no VM carries the label tc-run=$1: nothing to delete"; return 0; }
  echo "these VMs carry the label tc-run=$1 and will be DELETED (the images and the evidence stay):"; echo "$rows" | sed 's/^/   /'
  rk_confirm || { echo "nothing was deleted"; return 1; }
  for z in $(echo "$rows" | awk '{print $2}' | sort -u); do
    names="$(echo "$rows" | awk -v z="$z" '$2 == z {print $1}' | tr '\n' ' ')"
    gcloud compute instances delete $names --zone="$z" --quiet
  done
}

rk_stop_build() {  # BUILDER_A BUILDER_B: stop (not delete) the builders, after ONE question; their disks hold the build
  local v zz rows=""
  for v in "$1" "$2"; do
    zz="$(gcloud compute instances list --filter="name=$v" --format='value(zone.basename())' 2>/dev/null | head -1)"
    [ -n "$zz" ] && rows="$rows$v $zz"$'\n' || echo "no builder named $v: nothing to stop"
  done
  [ -n "$rows" ] || return 0
  echo "these builders will be STOPPED (not deleted: their disks hold the build):"; printf '%s' "$rows" | sed 's/^/   /'
  rk_confirm || { echo "nothing was stopped"; return 1; }
  while read -r v zz; do [ -n "$v" ] && gcloud compute instances stop "$v" --zone="$zz" --quiet; done <<< "$rows"
  return 0   # the here-string ends with an empty line, whose iteration would make the status 1
}

rk_ssh_keygen_lock() {  # parallel ssh sessions edit the same known-hosts file: ssh-keygen runs under a lock (a failure of a long run found this)
  local real
  [ "${RK_KEYGEN_LOCKED:-0}" = 1 ] && return 0
  real="$(PATH="${PATH//$RK_DIR\/bin:/}" command -v ssh-keygen 2>/dev/null)"
  { [ -n "$real" ] && command -v flock >/dev/null 2>&1; } || return 0
  mkdir -p "$RK_DIR/bin" "$HOME/.ssh"
  printf '#!/usr/bin/env bash\nexec flock "$HOME/.ssh/known-hosts.lock" %s "$@"\n' "$real" > "$RK_DIR/bin/ssh-keygen"; chmod +x "$RK_DIR/bin/ssh-keygen"
  export PATH="$RK_DIR/bin:$PATH" RK_KEYGEN_LOCKED=1
}

rk_load_names() {  # in a step: sets the plain names (SEAL_TEST, ZONE, C9 ...) as ordinary shell variables from the RK_ ones. They are NOT exported, so no tool can read them.
  local v n
  for v in $RK_NAME_VARS; do n="RK_$v"; unset "$v"; printf -v "$v" '%s' "${!n:-}"; done
}

rk_kernel_version() {  # TREE: the kernel of the image, taken from the committed packages (exactly one linux-image-...-gcp package); prints it, or says why not and fails
  local kv; kv="$(ls "$1/ops/image/debs" 2>/dev/null | sed -n 's/^linux-image-\(.*-gcp\)_.*\.deb$/\1/p' | sort -u)"
  [ "$(echo "$kv" | grep -c .)" = 1 ] || { echo "ops/image/debs must carry exactly one kernel image package (linux-image-...-gcp); found: $(echo $kv)" >&2; return 1; }
  echo "$kv"
}

rk_wait_watch() {  # PRINT_FUNCTION PID...: waits for the processes; every RK_HEARTBEAT_SECS it calls PRINT_FUNCTION (which prints the progress lines); it notices the end within a second
  local fn="$1" hb="${RK_HEARTBEAT_SECS:-300}" tick last now alive p; shift
  tick="$(awk -v h="$hb" 'BEGIN { print (h < 1) ? h : 1 }')"; last="$(date +%s.%N)"
  while :; do
    alive=0; for p in "$@"; do kill -0 "$p" 2>/dev/null && alive=1; done; [ "$alive" = 1 ] || break
    sleep "$tick"; now="$(date +%s.%N)"
    if awk -v n="$now" -v l="$last" -v h="$hb" 'BEGIN { exit !(n - l >= h) }'; then last="$now"; "$fn"; fi
  done
}

rk_run_watched() {  # LOG LABEL COMMAND...: runs the command in the background with its output in LOG, prints a heartbeat with the last line of LOG while it runs, returns the status of the command
  local log="$1" label="$2" pid t0; shift 2; t0=$(date +%s)
  "$@" > "$log" 2>&1 & pid=$!
  rk_hb() { echo "   [heartbeat $(date -u +%H:%M) UTC, $(rk_mins "$t0") min] $label: $(grep -av -E "${RK_HIDE_FROM_HEARTBEAT:-^\$}" "$log" | grep -av '^\s*$' | tail -n 1 | cut -c1-120)"; }
  rk_wait_watch rk_hb "$pid"; wait "$pid"
}

rk_run_watched_retry() {  # LOG LABEL MAXATT TRANSIENT_RX OK_RX COMMAND...: like rk_run_watched, but when the command fails with a line that matches TRANSIENT_RX (a call to the cloud failed: that is not a verdict)
  # it is run again, up to MAXATT times (a function named in RK_BEFORE_RETRY is called first, to clean up); it returns 0 only when the command exited 0 and OK_RX is in the log
  local log="$1" label="$2" max="$3" trx="$4" okrx="$5" att=1 rc; shift 5
  while :; do
    rk_run_watched "$log" "$label" "$@"; rc=$?
    if [ "$rc" = 0 ] && grep -aqE "$okrx" "$log"; then return 0; fi
    if [ "$att" -lt "$max" ] && grep -aqE "$trx" "$log"; then
      echo "   a call to the cloud failed, which is not a verdict on the images ($(grep -aE "$trx" "$log" | head -1 | cut -c1-140)): trying again, attempt $((att + 1)) of $max"
      cp "$log" "$log.attempt$att"; att=$((att + 1)); [ -z "${RK_BEFORE_RETRY:-}" ] || "$RK_BEFORE_RETRY"; continue
    fi
    [ "$rc" != 0 ] && return "$rc"; return 1
  done
}
