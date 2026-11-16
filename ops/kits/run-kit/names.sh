#!/usr/bin/env bash
# names.sh: the ONE place where the run kit makes its names. No other file of the kit spells a VM, an image, a label or a folder.
# It is sourced (never run) by run-kit.sh and by ops/image/test/run-kit-names-rehearse.sh. It makes no cloud call and writes nothing.
#
# Two ids, because a build is made once per commit and many runs use it:
#   the BUILD id is the commit (its first 9 characters, C9): it names the builders, the images and the build record;
#   the RUN id is made from the inputs of a crawl (size, the three switches, an optional tag): it names the fleet and the evidence.
#       RUN_ID = <size>-s<0|1>c<0|1>p<0|1>[-<tag>]      example: 1k-s1c0p1 = size 1k, storage on, comms off, provenance on
#
#   rk_inputs_check    checks SIZE STORAGE COMMS PROVENANCE WORKERS MACHINE_TYPE ZONE TAG and fills in the defaults
#   rk_run_names       makes the names of a crawl run
#   rk_build_names ID  makes the names of a build (ID = a commit id)
#   rk_worker N        prints the name of worker N (1, 2, 3, ...)
#   rk_gce_names       prints every VM, image and disk name that was made, one per line
#   rk_check_names     refuses a name that Google would refuse, and a name that appears twice
# A VM or image name follows the rule of Google: lower case letters, digits and hyphens, a letter first, no hyphen last, at most 63 characters.

RK_NAME_RX='^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$'
RK_SIZES="1k 10k 100k 1m"
RK_DEFAULT_WORKERS=10; RK_DEFAULT_MACHINE=c3-standard-4; RK_DEFAULT_ZONE=us-central1-a; RK_MAX_WORKERS=20

rk_die() { echo "RUN-KIT-INPUT-ERROR: $*" >&2; return 1; }
rk_digit() { case "$1" in on) echo 1;; off) echo 0;; *) return 1;; esac; }

rk_check_zone() {
  ZONE="${ZONE:-$RK_DEFAULT_ZONE}"
  [[ "$ZONE" =~ ^[a-z]+-[a-z]+[0-9]+-[a-z]$ ]] || { rk_die "--zone must look like us-central1-a (got '$ZONE')"; return 1; }
}

rk_inputs_check() {
  local s v f
  WORKERS="${WORKERS:-$RK_DEFAULT_WORKERS}"; MACHINE_TYPE="${MACHINE_TYPE:-$RK_DEFAULT_MACHINE}"; TAG="${TAG:-}"
  [ -n "${SIZE:-}" ] || { rk_die "--size is missing (one of: $RK_SIZES)"; return 1; }
  case " $RK_SIZES " in *" $SIZE "*) ;; *) rk_die "--size must be one of: $RK_SIZES (got '$SIZE')"; return 1;; esac
  for s in STORAGE COMMS PROVENANCE; do
    v="${!s:-}"; f="--$(printf '%s' "$s" | tr 'A-Z' 'a-z')"
    [ -n "$v" ] || { rk_die "$f is missing (on or off)"; return 1; }
    rk_digit "$v" >/dev/null || { rk_die "$f must be on or off (got '$v')"; return 1; }
  done
  [[ "$WORKERS" =~ ^[0-9]+$ ]] && [ "$((10#$WORKERS))" -ge 1 ] && [ "$((10#$WORKERS))" -le "$RK_MAX_WORKERS" ] || { rk_die "--workers must be a number from 1 to $RK_MAX_WORKERS (got '$WORKERS')"; return 1; }
  WORKERS="$((10#$WORKERS))"
  [ -z "$TAG" ] || [[ "$TAG" =~ ^[a-z0-9]{1,8}$ ]] || { rk_die "--tag must be 1 to 8 characters of a-z and 0-9 (got '$TAG')"; return 1; }
  [[ "$MACHINE_TYPE" =~ ^[a-z][a-z0-9]*-[a-z0-9-]+$ ]] || { rk_die "--machine-type must look like c3-standard-4 (got '$MACHINE_TYPE')"; return 1; }
  rk_check_zone
}

rk_run_names() {
  CODE="s$(rk_digit "$STORAGE")c$(rk_digit "$COMMS")p$(rk_digit "$PROVENANCE")"
  RUN_ID="${SIZE}-${CODE}${TAG:+-$TAG}"
  MASTER="tc-${RUN_ID}-m"; WORKER_BASE="tc-${RUN_ID}-w"
  RUN_LABEL="$RUN_ID"; EVIDENCE="evidence-${RUN_ID}"; RUN_DIR="run-${RUN_ID}"
}

rk_worker() { echo "${WORKER_BASE}${1}"; }

rk_build_names() {
  local id="${1:-}"
  [[ "$id" =~ ^[0-9a-f]{9,40}$ ]] || { rk_die "the commit id must be 9 to 40 characters of 0-9 and a-f, in lower case (got '$id')"; return 1; }
  C9="${id:0:9}"
  BUILDER_A="tc-b-${C9}-a"; BUILDER_B="tc-b-${C9}-b"
  IMAGE_1="tc-img-${C9}-1"; IMAGE_2="tc-img-${C9}-2"
  SEAL_DISK_A="tc-seal-disk-${C9}-a"; SEAL_DISK_B="tc-seal-disk-${C9}-b"
  SEALER_A="tc-sealer-${C9}-a"; SEALER_B="tc-sealer-${C9}-b"; SEAL_TEST="tc-seal-test-${C9}"
  BUILD_DIR="build-${C9}"; BUILD_RECORD="builds/${C9}"
  SOURCE_TGZ="src-${C9}.tgz"; SOURCE_ALT_TGZ="src-${C9}-alt.tgz"   # the archive of the commit (made on the laptop) and its repacked twin for build B, both in the home folder
  BUILD_TREE="${BUILD_DIR}/tree"; BUILD_COMMIT_FILE="${BUILD_DIR}/commit.txt"; REHEARSED_MARK="${BUILD_DIR}/rehearsals-ok"; BUILD_REHEARSALS="${BUILD_DIR}/rehearsals"
}

rk_gce_names() {
  local i
  if [ -n "${RUN_ID:-}" ]; then echo "$MASTER"; for i in $(seq 1 "$WORKERS"); do rk_worker "$i"; done; fi
  if [ -n "${C9:-}" ]; then printf '%s\n' "$BUILDER_A" "$BUILDER_B" "$IMAGE_1" "$IMAGE_2" "$SEAL_DISK_A" "$SEAL_DISK_B" "$SEALER_A" "$SEALER_B" "$SEAL_TEST"; fi
}

rk_check_names() {
  local n bad=0 seen=" "
  while IFS= read -r n; do
    [[ "$n" =~ $RK_NAME_RX ]] || { echo "RUN-KIT-NAME-ERROR: '$n' is not a valid VM or image name" >&2; bad=1; }
    case "$seen" in *" $n "*) echo "RUN-KIT-NAME-ERROR: '$n' appears twice" >&2; bad=1;; esac
    seen="$seen$n "
  done < <(rk_gce_names)
  return $bad
}

# every variable that the functions above set. The runner hands them to a step as RK_<NAME> and NEVER under the plain name: the older tools read plain names such as
# SEAL_TEST, ZONE, WORKERS, ID or COMMIT from the environment, and a leaked name changes what they do (a rehearsal failed in Cloud Shell because of SEAL_TEST).
RK_NAME_VARS="SIZE STORAGE COMMS PROVENANCE WORKERS MACHINE_TYPE ZONE TAG ID CODE RUN_ID MASTER WORKER_BASE RUN_LABEL EVIDENCE RUN_DIR C9 BUILDER_A BUILDER_B IMAGE_1 IMAGE_2 SEAL_DISK_A SEAL_DISK_B SEALER_A SEALER_B SEAL_TEST BUILD_DIR BUILD_RECORD SOURCE_TGZ SOURCE_ALT_TGZ BUILD_TREE BUILD_COMMIT_FILE REHEARSED_MARK BUILD_REHEARSALS"
