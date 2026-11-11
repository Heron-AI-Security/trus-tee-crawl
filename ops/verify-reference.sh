#!/usr/bin/env bash
# ops/verify-reference.sh: step P4 of the mentor's plan. Verify the published reference of a commit.
# Usage:   bash ops/verify-reference.sh COMMIT (--published DIR | --release TAG) [--published-image IMAGE] [--own-image IMAGE] [--ignore FILE] [--no-trees] [--work DIR]
#   COMMIT           the commit (9 to 40 hexadecimal digits) that the published image was built from
#   --published      a folder that holds the files of the release (reference.json, release.json, ..., SHA256SUMS)
#   --release        the tag of the GitHub release (for example publish-ref-16bafb3b1): the files are downloaded with the gh CLI (the repository must be readable by you; GITHUB_REPO sets it)
#   --published-image  the PUBLISHED image, an image of your project or PROJECT/IMAGE for an image that another project shares with you. Your own dummy run of it must reproduce the published reference
#                    EXACTLY: that proves that it is the image of the release.
#   --own-image      YOUR OWN build of the commit (an image in your project, built from a git archive of the commit, see docs/cluster-rebuild.md). Your own dummy run is compared with the reference:
#                    equal, or different only in the root hash and UUIDs (two builds seal two different disks).
#   With both images the files of the two root disks are compared too (ops/tree-diff.sh: a helper VM opens both disks through dm-verity, each against its own root hash that was read from its authenticated
#                    boot log, and compares every file, extended attributes and capabilities included), and the verdict needs them identical. --no-trees leaves that out.
#   --ignore         a file of patterns for the file-tree diff (see ops/tree-diff.py); every ignored difference is still reported
#   --work           where to put the files (default: verify-work)
#   Without any image only part A runs, which needs no cloud. Each dummy run makes one TDX VM (about 4 minutes, a few cents), reads it, and deletes it.
# Settings: VERIFY_WAIT (seconds to wait after a stockout, default 300), VERIFY_HB (heartbeat seconds, default 60). It ends with VERIFY-REFERENCE-OK or VERIFY-REFERENCE-FAILED (n).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}" >&2; exit 2; }
fail() { echo "VERIFY-REFERENCE-FAILED: $*" >&2; exit 1; }
[ $# -ge 1 ] || usage
COMMIT="$1"; shift; PUBLISHED=""; TAG=""; OWN=""; PIMG=""; IGN=""; TREES=1; WORK="verify-work"
while [ $# -gt 0 ]; do
  case "$1" in
    --published) [ $# -ge 2 ] || usage; PUBLISHED="$2"; shift 2;;
    --release) [ $# -ge 2 ] || usage; TAG="$2"; shift 2;;
    --own-image) [ $# -ge 2 ] || usage; OWN="$2"; shift 2;;
    --published-image) [ $# -ge 2 ] || usage; PIMG="$2"; shift 2;;
    --ignore) [ $# -ge 2 ] || usage; IGN="$2"; shift 2;;
    --no-trees) TREES=0; shift;;
    --work) [ $# -ge 2 ] || usage; WORK="$2"; shift 2;;
    *) echo "unknown option: $1" >&2; usage;;
  esac
done
[[ "$COMMIT" =~ ^[0-9a-f]{9,40}$ ]] || { echo "COMMIT must be 9 to 40 lowercase hexadecimal digits, got '$COMMIT'" >&2; exit 2; }
{ [ -n "$PUBLISHED" ] && [ -z "$TAG" ]; } || { [ -z "$PUBLISHED" ] && [ -n "$TAG" ]; } || { echo "give exactly one of --published and --release" >&2; usage; }
[ -z "$IGN" ] || [ -f "$IGN" ] || fail "the ignore file $IGN does not exist"
mkdir -p "$WORK" || fail "cannot make the folder $WORK"
if [ -n "$TAG" ]; then
  GH="${TC_GH:-gh}"; command -v "$GH" >/dev/null 2>&1 || fail "the gh CLI is needed for --release; install it, or download the files of the release yourself and use --published"
  PUBLISHED="$WORK/published"; rm -rf "$PUBLISHED"
  echo "== downloading the release $TAG of ${GITHUB_REPO:-Heron-AI-Security/nutch-private}"
  "$GH" release download "$TAG" --repo "${GITHUB_REPO:-Heron-AI-Security/nutch-private}" --dir "$PUBLISHED" || fail "the release $TAG could not be downloaded (does it exist, and can you read the repository?)"
fi
[ -d "$PUBLISHED" ] || fail "the folder $PUBLISHED does not exist"
ARGS=(--published "$PUBLISHED" --commit "$COMMIT")
drun() {   # drun IMAGE-SPEC OUTDIR LOGFILE WHAT: the dummy run of an image (SPEC is IMAGE or PROJECT/IMAGE), waiting out a stockout
  local spec="$1" outd="$2" logf="$3" what="$4" ok=0 t pid proj img
  case "$spec" in */*) proj="${spec%%/*}"; img="${spec#*/}";; *) proj=""; img="$spec";; esac
  echo "== $what of $spec (one TDX VM is made, read, and deleted)"
  for t in 1 2 3 4 5 6; do
    rm -rf "${outd:?}"
    IMAGE_PROJECT="$proj" bash "$RUNNER" "$img" "$outd" > "$logf" 2>&1 &
    pid=$!; while kill -0 "$pid" 2>/dev/null; do sleep "${VERIFY_HB:-60}"; echo "   ... your dummy run is running ($(date -u +%H:%M) UTC)"; done; wait "$pid"
    if grep -q "REFERENCE-RUN-OK" "$logf"; then ok=1; break; fi
    if grep -q -i -E "stockout|ZONE_RESOURCE_POOL_EXHAUSTED" "$logf"; then echo "   no capacity right now (attempt $t of 6); waiting ${VERIFY_WAIT:-300} seconds"; sleep "${VERIFY_WAIT:-300}"; else break; fi
  done
  [ "$ok" = 1 ] || fail "$what did not finish; the end of its output: $(tail -6 "$logf" | tr '\n' ' ' | cut -c1-600)"
}
if [ -n "$OWN" ] || [ -n "$PIMG" ]; then
  command -v "${TC_GCLOUD:-gcloud}" >/dev/null 2>&1 || command -v gcloud >/dev/null 2>&1 || fail "gcloud is needed for --own-image and --published-image"
  RUNNER="${TC_REFERENCE_RUN:-$HERE/reference-run.sh}"; [ -f "$RUNNER" ] || fail "the tool is missing: $RUNNER"
fi
PV=""
if [ -n "$PIMG" ] && [ -n "$OWN" ] && [ "$TREES" = 1 ]; then   # the dm-verity parameters of the published image first: no VM is worth making if they cannot be read
  PV="$(python3 "$HERE/verify-reference.py" --verity-of "$PUBLISHED" 2>"$WORK/verity-a.err")" || fail "the dm-verity parameters of the published image cannot be read from its authenticated boot log: $(tr '\n' ' ' < "$WORK/verity-a.err" | cut -c1-300)"
fi
if [ -n "$PIMG" ]; then
  drun "$PIMG" "$WORK/image-run" "$WORK/image-run.log" "your dummy run of the published image"; ARGS+=(--image-run "$WORK/image-run")
  if ! python3 "$HERE/verify-reference.py" "${ARGS[@]}" > "$WORK/image-check.txt" 2>&1; then   # stop early: nothing else is worth its time and money if the image is not the image of the release
    cat "$WORK/image-check.txt"; echo "stopped before the other steps: the published image does not reproduce the published reference, or the published evidence is not consistent"; exit 1
  fi
fi
if [ -n "$OWN" ]; then drun "$OWN" "$WORK/own" "$WORK/own.log" "your own dummy run"; ARGS+=(--own-run "$WORK/own"); fi
if [ -n "$PIMG" ] && [ -n "$OWN" ] && [ "$TREES" = 1 ]; then
  echo "== the files of the two root disks: $PIMG against $OWN (a helper VM opens each disk through dm-verity, read-only, against its own root hash)"
  OV="$(python3 "$HERE/verify-reference.py" --verity-of "$WORK/own" 2>"$WORK/verity-b.err")" || fail "the dm-verity parameters of your own image cannot be read from the authenticated boot log of your dummy run (does your image publish a boot event log? build it with the current kit): $(tr '\n' ' ' < "$WORK/verity-b.err" | cut -c1-300)"
  TARGS=(diff "$PIMG" "$OWN" --verity-a "$PV" --verity-b "$OV" --work "$WORK/trees"); [ -z "$IGN" ] || TARGS+=(--ignore "$IGN")
  bash "${TC_TREE_DIFF:-$HERE/tree-diff.sh}" "${TARGS[@]}" 2>&1 | tee "$WORK/trees.log"
  grep '^TREE-DIFF-' "$WORK/trees.log" | tail -1 > "$WORK/tree-verdict.txt"; [ -s "$WORK/tree-verdict.txt" ] || echo "TREE-DIFF-FAILED: no verdict (see $WORK/trees.log)" > "$WORK/tree-verdict.txt"
  ARGS+=(--tree-result "$WORK/tree-verdict.txt")
fi
python3 "$HERE/verify-reference.py" "${ARGS[@]}"
