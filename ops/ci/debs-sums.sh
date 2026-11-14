#!/usr/bin/env bash
# ops/ci/debs-sums.sh: proves that the Ubuntu packages committed in ops/image/debs are exactly the bytes that SHA256SUMS names (the acceptance of the issue: sha256sum -c passes in CI).
#   bash ops/ci/debs-sums.sh [TREE]        TREE = the repository root (default: the root of the repository that holds this script). No network, no secret, nothing is written.
# It checks: every listed file matches (sha256sum -c), every package in the folder is listed and nothing else is in the folder, no file is over 95 MB (GitHub refuses 100 MB), and SOURCE.txt records the date, the base image and that the kernel files are chained to the signed index.
# It ends with  DEBS-SUMS-OK files=N  or  DEBS-SUMS-FAILED (n).
set -uo pipefail
T="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"; D="$T/ops/image/debs"; bad=0
ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; bad=$((bad + 1)); }
[ -d "$D" ] || { echo "DEBS-SUMS-FAILED: $D does not exist (the packages that the build installs are committed there)"; exit 1; }
[ -s "$D/SHA256SUMS" ] || { echo "DEBS-SUMS-FAILED: $D/SHA256SUMS is missing or empty"; exit 1; }
cd "$D" || exit 1; shopt -s nullglob
echo "== 1. sha256sum -c SHA256SUMS"
RES="$(sha256sum -c SHA256SUMS 2>&1)"; if [ $? = 0 ]; then ok "$(grep -c ': OK$' <<<"$RES") files match"; else no "sha256sum -c failed: $(grep -v ': OK$' <<<"$RES" | head -3 | tr '\n' ' ' | cut -c1-200)"; fi
echo "== 2. the folder holds the packages that SHA256SUMS lists, and nothing else"
STRAY="$(ls -A | grep -vE '^[A-Za-z0-9][A-Za-z0-9._+~-]*\.deb$|^SHA256SUMS$|^SOURCE\.txt$' | tr '\n' ' ')"; [ -z "$STRAY" ] && ok "no other file in the folder" || no "files that do not belong in the folder: $STRAY"
DIFF="$(diff <(printf '%s\n' *.deb | sed '/^$/d' | LC_ALL=C sort) <(awk '{print $2}' SHA256SUMS | LC_ALL=C sort) | grep '^[<>]' | head -3 | tr '\n' ' ')"; [ -z "$DIFF" ] && ok "every package is listed and every listed package is there" || no "the packages and SHA256SUMS differ: $DIFF"
echo "== 3. the size (GitHub refuses a file over 100 MB)"
BIG="$(find . -maxdepth 1 -type f -size +95M -printf '%f ' 2>/dev/null)"; [ -z "$BIG" ] && ok "no file is over 95 MB" || no "over 95 MB: $BIG (such packages go to a bucket, not to git)"
echo "== 4. SOURCE.txt: where the packages come from"
if [ -s SOURCE.txt ]; then
  grep -Eq '^snapshot_date: [0-9]{8}T[0-9]{6}Z\r?$' SOURCE.txt && ok "snapshot_date is recorded" || no "SOURCE.txt has no snapshot_date"
  grep -Eq '^base_image: ubuntu-2204-jammy-v[0-9]{8}\r?$' SOURCE.txt && ok "the base image is a dated image" || no "SOURCE.txt names no dated base image"
  grep -Eq '^kernel_signature: signed: ' SOURCE.txt && ok "the kernel files are chained to the signed index" || no "SOURCE.txt does not say that the kernel files are chained to the signed index (kernel_signature: signed)"
else no "SOURCE.txt is missing or empty"; fi
if [ $bad = 0 ]; then echo "DEBS-SUMS-OK files=$(grep -c . SHA256SUMS)"; else echo "DEBS-SUMS-FAILED ($bad)"; fi; [ $bad = 0 ]
