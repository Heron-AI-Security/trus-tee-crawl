#!/usr/bin/env bash
# ops/verify-reference.sh: step P4 of the mentor's plan. Verify the published reference of a commit.
# Usage:   bash ops/verify-reference.sh COMMIT (--published DIR | --release TAG) [--own-image IMAGE] [--work DIR]
#   COMMIT         the commit (9 to 40 hexadecimal digits) that the published image was built from
#   --published    a folder that holds the files of the release (reference.json, release.json, ..., SHA256SUMS)
#   --release      the tag of the GitHub release (for example publish-ref-16bafb3b1): the files are downloaded with the gh CLI (the repository must be readable by you; GITHUB_REPO sets it)
#   --own-image    YOUR OWN build of the commit (an image in your Google Cloud project, built from a git archive of the commit, see docs/cluster-rebuild.md). Without it only part A runs, which needs no cloud.
#                  With it, one TDX VM is made from your image (about 4 minutes, a few cents), read, and deleted, and your dummy run is compared with the published reference.
#   --work         where to put the files (default: verify-work)
# Settings: VERIFY_WAIT (seconds to wait after a stockout, default 300), VERIFY_HB (heartbeat seconds, default 60). It ends with VERIFY-REFERENCE-OK or VERIFY-REFERENCE-FAILED (n).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 2; }
fail() { echo "VERIFY-REFERENCE-FAILED: $*" >&2; exit 1; }
[ $# -ge 1 ] || usage
COMMIT="$1"; shift; PUBLISHED=""; TAG=""; OWN=""; WORK="verify-work"
while [ $# -gt 0 ]; do
  case "$1" in
    --published) [ $# -ge 2 ] || usage; PUBLISHED="$2"; shift 2;;
    --release) [ $# -ge 2 ] || usage; TAG="$2"; shift 2;;
    --own-image) [ $# -ge 2 ] || usage; OWN="$2"; shift 2;;
    --work) [ $# -ge 2 ] || usage; WORK="$2"; shift 2;;
    *) echo "unknown option: $1" >&2; usage;;
  esac
done
[[ "$COMMIT" =~ ^[0-9a-f]{9,40}$ ]] || { echo "COMMIT must be 9 to 40 lowercase hexadecimal digits, got '$COMMIT'" >&2; exit 2; }
{ [ -n "$PUBLISHED" ] && [ -z "$TAG" ]; } || { [ -z "$PUBLISHED" ] && [ -n "$TAG" ]; } || { echo "give exactly one of --published and --release" >&2; usage; }
mkdir -p "$WORK" || fail "cannot make the folder $WORK"
if [ -n "$TAG" ]; then
  GH="${TC_GH:-gh}"; command -v "$GH" >/dev/null 2>&1 || fail "the gh CLI is needed for --release; install it, or download the files of the release yourself and use --published"
  PUBLISHED="$WORK/published"; rm -rf "$PUBLISHED"
  echo "== downloading the release $TAG of ${GITHUB_REPO:-Heron-AI-Security/nutch-private}"
  "$GH" release download "$TAG" --repo "${GITHUB_REPO:-Heron-AI-Security/nutch-private}" --dir "$PUBLISHED" || fail "the release $TAG could not be downloaded (does it exist, and can you read the repository?)"
fi
[ -d "$PUBLISHED" ] || fail "the folder $PUBLISHED does not exist"
ARGS=(--published "$PUBLISHED" --commit "$COMMIT")
if [ -n "$OWN" ]; then
  command -v "${TC_GCLOUD:-gcloud}" >/dev/null 2>&1 || command -v gcloud >/dev/null 2>&1 || fail "gcloud is needed for --own-image"
  RUNNER="${TC_REFERENCE_RUN:-$HERE/reference-run.sh}"; [ -f "$RUNNER" ] || fail "the tool is missing: $RUNNER"
  echo "== your own dummy run of $OWN (one TDX VM is made, read, and deleted)"
  ok=0
  for t in 1 2 3 4 5 6; do
    rm -rf "${WORK:?}/own"
    bash "$RUNNER" "$OWN" "$WORK/own" > "$WORK/own.log" 2>&1 &
    pid=$!; while kill -0 "$pid" 2>/dev/null; do sleep "${VERIFY_HB:-60}"; echo "   ... your dummy run is running ($(date -u +%H:%M) UTC)"; done; wait "$pid"
    if grep -q "REFERENCE-RUN-OK" "$WORK/own.log"; then ok=1; break; fi
    if grep -q -i -E "stockout|ZONE_RESOURCE_POOL_EXHAUSTED" "$WORK/own.log"; then echo "   no capacity right now (attempt $t of 6); waiting ${VERIFY_WAIT:-300} seconds"; sleep "${VERIFY_WAIT:-300}"; else break; fi
  done
  [ "$ok" = 1 ] || fail "your own dummy run did not finish; the end of its output: $(tail -6 "$WORK/own.log" | tr '\n' ' ' | cut -c1-600)"
  ARGS+=(--own-run "$WORK/own")
fi
python3 "$HERE/verify-reference.py" "${ARGS[@]}"
