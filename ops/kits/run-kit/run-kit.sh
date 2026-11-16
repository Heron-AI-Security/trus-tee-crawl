#!/usr/bin/env bash
# run-kit.sh: the one run kit (issue "one run kit per fleet configuration").
# THIS VERSION HAS THE NAMES, THE PLAN AND THE RUNNER. The steps are added one by one: a step that is not written yet stops the run (exit 3) before anything is started.
# Only flags count: a variable that happens to be set in your shell is ignored. A bad flag is refused (exit 2) before anything is created.
rk_usage() {
  cat <<'EOU'
run-kit.sh: the one run kit.
  bash run-kit.sh plan|status|report|stop  build|crawl|all  FLAGS      show the names and the steps | the state | what each finished step found | stop the cloud resources
  bash run-kit.sh build|crawl|all  FLAGS  [--until STEP]  [--restart]  run the steps in order; a second run skips the finished steps
Flags of build:  --commit COMMIT [--zone us-central1-a]
Flags of crawl:  --build COMMIT --size 1k|10k|100k|1m --storage on|off --comms on|off --provenance on|off [--workers 10] [--machine-type c3-standard-4] [--zone us-central1-a] [--tag r2]
Flags of all:    --commit COMMIT and the flags of crawl except --build
stop deletes the VMs that carry the run label (crawl) or stops the two builders (build) and asks first; --yes skips the question.
--restart forgets the finished steps of the phase (nothing in the cloud is touched). --until STEP stops after the step with that id (see plan).
EOU
}
set -uo pipefail
KD="$(cd "$(dirname "$0")" && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/record.sh"; . "$KD/tools.sh"
RK_STEPS_DIR="${RK_STEPS_DIR:-$KD}"

rk_once() { case "$seen" in *" $1 "*) rk_die "$2 was given twice"; return 1;; esac; seen="$seen$1 "; }   # a flag may be given once only (seen belongs to rk_parse)

rk_parse() {  # sets the variables of the flags; refuses an unknown flag, a missing value, a flag given twice and a flag that does not belong to the command
  local f k seen=" "
  while [ $# -gt 0 ]; do
    f="$1"
    case "$f" in
      --size) k=SIZE;; --storage) k=STORAGE;; --comms) k=COMMS;; --provenance) k=PROVENANCE;; --workers) k=WORKERS;;
      --machine-type) k=MACHINE_TYPE;; --zone) k=ZONE;; --tag) k=TAG;; --build) k=BUILD;; --commit) k=COMMIT;;
      --until) k=UNTIL;; --restart) k=RESTART;; --yes) k=YES;;
      *) rk_die "unknown option '$f' (run: run-kit.sh help)"; return 1;;
    esac
    case " $ALLOWED " in *" $k "*) ;; *) rk_die "$f does not belong to '$CMD $MODE' (run: run-kit.sh help)"; return 1;; esac
    if [ "$k" = RESTART ] || [ "$k" = YES ]; then rk_once "$k" "$f" || return 1; printf -v "$k" '%s' 1; shift; continue; fi
    { [ $# -ge 2 ] && [[ "$2" != --* ]]; } || { rk_die "$f needs a value"; return 1; }
    rk_once "$k" "$f" || return 1; printf -v "$k" '%s' "$2"; shift 2
  done
}

rk_load_steps() { RK_STEPS=(); . "$RK_STEPS_DIR/steps-$1.sh"; }   # PHASE: sets RK_STEPS

rk_phase_dir() { case "$1" in build) echo "$HOME/$BUILD_DIR/state";; crawl) echo "$HOME/$RUN_DIR";; esac; }   # the state of the build lives with its work folder, the state of a run is its run folder

rk_inputs_text() {  # PHASE: the flags that make this phase what it is
  case "$1" in
    build) echo "commit=$ID zone=$ZONE";;
    crawl) echo "build=$ID size=$SIZE storage=$STORAGE comms=$COMMS provenance=$PROVENANCE workers=$WORKERS machine-type=$MACHINE_TYPE zone=$ZONE tag=$TAG";;
  esac
}

rk_vms_filter() { case "$1" in build) echo "name~'^tc-(b|sealer|seal-disk|seal-test)-$C9'";; crawl) echo "labels.tc-run=$RUN_LABEL";; esac; }

rk_plan() {
  local ws ph e n id title script
  echo "== the plan (command: $MODE). No cloud call was made; nothing was created."
  echo "   zone: $ZONE"
  if [ "$MODE" = crawl ]; then echo "== the build that this crawl uses (already made; the crawl only reads it)"; else echo "== the build (once per commit; the commit id names everything of it)"; fi
  echo "   commit: $ID    (names use its first 9 characters: $C9)"
  echo "   builders: $BUILDER_A, $BUILDER_B"
  echo "   sealed images: $IMAGE_1 (build A, the fleet uses it), $IMAGE_2 (build B, the check of reproducibility)"
  echo "   seal helpers: $SEAL_DISK_A, $SEAL_DISK_B, $SEALER_A, $SEALER_B, $SEAL_TEST"
  echo "   work folder: ~/$BUILD_DIR    build record in the bucket: $BUILD_RECORD/"
  echo "   source archive: ~/$SOURCE_TGZ (made on the laptop with git archive and uploaded; build B uses its repacked twin ~/$SOURCE_ALT_TGZ)"
  if [ "$MODE" != build ]; then
    echo "== the crawl (one per configuration)"
    echo "   run id: $RUN_ID    (size $SIZE; storage $STORAGE, comms $COMMS, provenance $PROVENANCE${TAG:+; tag $TAG})"
    if [ "$WORKERS" = 1 ]; then ws="$(rk_worker 1)"; else ws="$(rk_worker 1) ... $(rk_worker "$WORKERS")"; fi
    echo "   fleet: master $MASTER and $WORKERS worker(s) $ws, machine type $MACHINE_TYPE"
    echo "   label on every VM: tc-run=$RUN_LABEL"
    echo "   evidence: ~/$EVIDENCE    run folder (lock, finished stages, timings): ~/$RUN_DIR"
    echo "   image used: $IMAGE_1 (from the build of $C9)"
  fi
  echo "== the steps, in order"
  for ph in $PHASES; do
    rk_load_steps "$ph"; if [ "$ph" = build ]; then echo "   build (once per commit):"; else echo "   crawl (one per configuration):"; fi
    for e in "${RK_STEPS[@]}"; do IFS='|' read -r n id title script <<< "$e"; printf '     %2s  %-15s %s\n' "$n" "$id" "$title"; done
  done
}

CMD="${1:-help}"; [ $# -gt 0 ] && shift
case "$CMD" in help|-h|--help) rk_usage; exit 0;; esac
case "$CMD" in
  plan|status|report|stop) MODE="${1:-}"; [ $# -gt 0 ] && shift
    case "$MODE" in build|crawl|all) ;; *) rk_die "$CMD needs build, crawl or all (run: run-kit.sh help)"; exit 2;; esac;;
  build|crawl|all) MODE="$CMD";;
  *) rk_die "unknown command '$CMD' (run: run-kit.sh help)"; exit 2;;
esac
case "$MODE" in
  build) ALLOWED="COMMIT ZONE"; PHASES="build";;
  crawl) ALLOWED="BUILD SIZE STORAGE COMMS PROVENANCE WORKERS MACHINE_TYPE ZONE TAG"; PHASES="crawl";;
  all)   ALLOWED="COMMIT SIZE STORAGE COMMS PROVENANCE WORKERS MACHINE_TYPE ZONE TAG"; PHASES="build crawl";;
esac
case "$CMD" in build|crawl|all) ALLOWED="$ALLOWED UNTIL RESTART";; stop) ALLOWED="$ALLOWED YES";; esac
unset $RK_NAME_VARS $RK_LEGACY_ENV BUILD COMMIT UNTIL RESTART YES   # only the flags count, never a variable that is in the environment (nor a variable of an older tool)
rk_parse "$@" || exit 2
if [ "$MODE" = crawl ]; then ID="${BUILD:-}"; [ -n "$ID" ] || { rk_die "--build is missing (the commit of the sealed image)"; exit 2; }
else ID="${COMMIT:-}"; [ -n "$ID" ] || { rk_die "--commit is missing"; exit 2; }; fi
if [ "$MODE" = build ]; then rk_check_zone || exit 2; else rk_inputs_check || exit 2; rk_run_names; fi
rk_build_names "$ID" || exit 2
rk_check_names || exit 2
if [ -n "${UNTIL:-}" ]; then
  IDS=""; for ph in $PHASES; do rk_load_steps "$ph"; for e in "${RK_STEPS[@]}"; do IFS='|' read -r n id title script <<< "$e"; IDS="$IDS $id"; done; done
  case "$IDS " in *" $UNTIL "*) ;; *) rk_die "--until must name a step of '$MODE' (one of:$IDS)"; exit 2;; esac
fi
for v in $RK_NAME_VARS; do export "RK_$v=${!v:-}"; done   # a step gets the names as RK_* only (rk_load_names makes the plain ones inside the step, not exported)

rk_for_phases() {  # FUNCTION: calls it for every phase of the mode, with the state of that phase loaded and read only
  local ph d
  for ph in $PHASES; do
    d="$(rk_phase_dir "$ph")"; echo "== the $ph phase ($d)"
    [ -d "$d" ] || { echo "   no folder yet: nothing was started"; continue; }
    rk_load_steps "$ph"; rk_state_init "$d"; VMS_FILTER="$(rk_vms_filter "$ph")"; "$1"
  done
}

case "$CMD" in
  plan) rk_plan; exit 0;;
  status) rk_for_phases rk_status; exit 0;;
  report) rk_for_phases rk_report; exit 0;;
  stop) rc=0
    case "$MODE" in crawl|all) rk_stop_crawl "$RUN_LABEL" || rc=1;; esac
    case "$MODE" in build|all) rk_stop_build "$BUILDER_A" "$BUILDER_B" || rc=1;; esac
    exit $rc;;
esac

# build, crawl or all: run the steps of each phase in order
for ph in $PHASES; do
  rk_load_steps "$ph"; rk_state_init "$(rk_phase_dir "$ph")"
  if [ "${RESTART:-0}" = 1 ]; then : > "$RK_DONE"; : > "$RK_TIM"; rm -rf "$RK_RESULTS" "$RK_DIR/inputs.txt"; mkdir -p "$RK_RESULTS"; echo "The finished steps of the $ph phase are forgotten (nothing in the cloud is touched)."; fi
  rk_lock || exit 1
  rk_inputs_pin "$(rk_inputs_text "$ph")" || exit 1
  rk_ssh_keygen_lock
  echo "== the $ph phase: $(rk_inputs_text "$ph")"
  rk_run_phase; rc=$?
  case $rc in 0) ;; 100) exit 0;; *) exit $rc;; esac
done
exit 0
