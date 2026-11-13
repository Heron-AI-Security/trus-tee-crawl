#!/usr/bin/env bash
# Step R4.7 (28 October 2026): the source line of /etc/tc/job-versions.txt (on the verified root) names the COMMIT, proven from the archive's own header, and not the file name and the SHA-256 of the archive:
# the name is chosen by the operator and the hash depends on the bytes of the gzip stream, so a second party who made her own archive of the same commit could not reproduce the image.
#   bash tc-source-id.sh ARCHIVE COMMIT     prints "source: commit COMMIT" when the archive is a git archive of exactly that commit, and stops otherwise
set -euo pipefail
A="${1:?usage: $0 ARCHIVE COMMIT}"; C="${2:?usage: $0 ARCHIVE COMMIT}"
[[ "$C" =~ ^[0-9a-f]{40}$ ]] || { echo "ABORT: give the full 40-digit commit id" >&2; exit 1; }
[ -f "$A" ] || { echo "ABORT: the source archive is missing: $A" >&2; exit 1; }
H="$(gzip -dc "$A" 2>/dev/null | head -c 4096 | grep -a -o 'comment=[0-9a-f]\{40\}' | head -1 | cut -d= -f2 || true)"
[ -n "$H" ] || { echo "ABORT: the archive has no commit header (it must be made by git archive of a commit)" >&2; exit 1; }
[ "$H" = "$C" ] || { echo "ABORT: the archive is of commit ${H:0:12}..., not of ${C:0:12}..." >&2; exit 1; }
echo "source: commit $C"
