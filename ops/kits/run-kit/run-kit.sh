#!/usr/bin/env bash
# run-kit.sh: the one run kit (issue "one run kit per fleet configuration").
# THIS VERSION HAS THE NAMES AND THE PLAN ONLY: the stages are added in the next steps, and until then build, crawl and all stop after printing the plan.
#   bash run-kit.sh plan build --commit COMMIT
#   bash run-kit.sh plan crawl --build COMMIT --size 1k --storage on --comms off --provenance on [--workers 10] [--machine-type c3-standard-4] [--zone us-central1-a] [--tag r2]
#   bash run-kit.sh plan all   --commit COMMIT --size 1k --storage on --comms off --provenance on
#   bash run-kit.sh build|crawl|all ...        the same flags; checks them, prints the plan, then stops (exit 3) in this version
#   bash run-kit.sh help
# Only flags count: a variable that happens to be set in your shell is ignored. A bad flag is refused (exit 2) before anything is created.
set -uo pipefail
KD="$(cd "$(dirname "$0")" && pwd)"; . "$KD/names.sh"

rk_usage() { sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'; }

rk_parse() {  # sets the variables of the flags; refuses an unknown flag, a missing value, a flag given twice and a flag that does not belong to the command
  local f k seen=" "
  while [ $# -gt 0 ]; do
    f="$1"
    case "$f" in
      --size) k=SIZE;; --storage) k=STORAGE;; --comms) k=COMMS;; --provenance) k=PROVENANCE;; --workers) k=WORKERS;;
      --machine-type) k=MACHINE_TYPE;; --zone) k=ZONE;; --tag) k=TAG;; --build) k=BUILD;; --commit) k=COMMIT;;
      *) rk_die "unknown option '$f' (run: run-kit.sh help)"; return 1;;
    esac
    case " $ALLOWED " in *" $k "*) ;; *) rk_die "$f does not belong to '$MODE' (run: run-kit.sh help)"; return 1;; esac
    { [ $# -ge 2 ] && [[ "$2" != --* ]]; } || { rk_die "$f needs a value"; return 1; }
    case "$seen" in *" $k "*) rk_die "$f was given twice"; return 1;; esac
    seen="$seen$k "; printf -v "$k" '%s' "$2"; shift 2
  done
}

rk_plan() {
  local ws
  echo "== the plan (command: $MODE). No cloud call was made; nothing was created."
  echo "   zone: $ZONE"
  if [ "$MODE" = crawl ]; then echo "== the build that this crawl uses (already made; the crawl only reads it)"; else echo "== the build (once per commit; the commit id names everything of it)"; fi
  echo "   commit: $ID    (names use its first 9 characters: $C9)"
  echo "   builders: $BUILDER_A, $BUILDER_B"
  echo "   sealed images: $IMAGE_1 (build A, the fleet uses it), $IMAGE_2 (build B, the check of reproducibility)"
  echo "   seal helpers: $SEAL_DISK_A, $SEAL_DISK_B, $SEALER_A, $SEALER_B, $SEAL_TEST"
  echo "   work folder: ~/$BUILD_DIR    build record in the bucket: $BUILD_RECORD/"
  [ "$MODE" = build ] && return 0
  echo "== the crawl (one per configuration)"
  echo "   run id: $RUN_ID    (size $SIZE; storage $STORAGE, comms $COMMS, provenance $PROVENANCE${TAG:+; tag $TAG})"
  if [ "$WORKERS" = 1 ]; then ws="$(rk_worker 1)"; else ws="$(rk_worker 1) ... $(rk_worker "$WORKERS")"; fi
  echo "   fleet: master $MASTER and $WORKERS worker(s) $ws, machine type $MACHINE_TYPE"
  echo "   label on every VM: tc-run=$RUN_LABEL"
  echo "   evidence: ~/$EVIDENCE    run folder (lock, finished stages, timings): ~/$RUN_DIR"
  echo "   image used: $IMAGE_1 (from the build of $C9)"
}

CMD="${1:-help}"; [ $# -gt 0 ] && shift
case "$CMD" in help|-h|--help) rk_usage; exit 0;; esac
if [ "$CMD" = plan ]; then
  MODE="${1:-}"; [ $# -gt 0 ] && shift
  case "$MODE" in build|crawl|all) ;; *) rk_die "plan needs build, crawl or all (run: run-kit.sh help)"; exit 2;; esac
else
  case "$CMD" in build|crawl|all) MODE="$CMD";; *) rk_die "unknown command '$CMD' (run: run-kit.sh help)"; exit 2;; esac
fi
case "$MODE" in
  build) ALLOWED="COMMIT ZONE";;
  crawl) ALLOWED="BUILD SIZE STORAGE COMMS PROVENANCE WORKERS MACHINE_TYPE ZONE TAG";;
  all)   ALLOWED="COMMIT SIZE STORAGE COMMS PROVENANCE WORKERS MACHINE_TYPE ZONE TAG";;
esac
unset SIZE STORAGE COMMS PROVENANCE WORKERS MACHINE_TYPE ZONE TAG BUILD COMMIT   # only the flags count, never a variable that is in the environment
rk_parse "$@" || exit 2
if [ "$MODE" = crawl ]; then ID="${BUILD:-}"; [ -n "$ID" ] || { rk_die "--build is missing (the commit of the sealed image)"; exit 2; }
else ID="${COMMIT:-}"; [ -n "$ID" ] || { rk_die "--commit is missing"; exit 2; }; fi
if [ "$MODE" = build ]; then rk_check_zone || exit 2; else rk_inputs_check || exit 2; rk_run_names; fi
rk_build_names "$ID" || exit 2
rk_check_names || exit 2
rk_plan
[ "$CMD" = plan ] && exit 0
echo "RUN-KIT-STAGES-MISSING: this version of the kit has the names and the plan only. The stages are added in the next steps; nothing was started."
exit 3
