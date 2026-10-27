#!/usr/bin/env bash
# Step R4.2, on the BUILDER: record the commit that this image is built from, in /etc/tc/source.txt (one line: "commit <40 or 64 hex characters>"). The file is in the measured folder /etc/tc and is the first
# event (source) of the measured list, so every quote names the commit. The commit comes from the file KIT/COMMIT, which the driver writes from the HEADER of the git archive (r4-archive.py), not from a person.
# It fails closed: with no valid COMMIT the build stops. For a development build only, ALLOW_NO_COMMIT=1 records "commit none" (a verifier that pins a commit refuses it).
#   bash tc-image-source.sh KITDIR          Hooks for the rehearsal only: TC_ROOT, TC_SUDO.
set -uo pipefail
KIT="${1:?usage: $0 KITDIR}"; R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"; CF="$KIT/COMMIT"
fail() { echo "SOURCE-STOP: $*" >&2; exit 1; }
if [ -s "$CF" ] && [ "$(wc -l < "$CF")" -le 1 ] && grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$' "$CF"; then LINE="commit $(tr -d '\n' < "$CF")"
elif [ -e "$CF" ] && [ -s "$CF" ]; then fail "$CF is not a commit id (40 or 64 lower-case hex characters, one line)"
elif [ "${ALLOW_NO_COMMIT:-}" = 1 ]; then LINE="commit none"; echo "WARNING: no COMMIT file: this image does not name its commit (a development build; a verifier that pins a commit will refuse it)"
else fail "no COMMIT file in the kit: the image must be built from a git archive of a named commit (step R4.2); ALLOW_NO_COMMIT=1 records 'commit none' for a development build"; fi
T="$(mktemp)"; trap 'rm -f "$T"' EXIT; printf '%s\n' "$LINE" > "$T"
$SUDO install -d -m 0755 "$R/etc/tc" && $SUDO install -m 0644 "$T" "$R/etc/tc/source.txt" || fail "could not install /etc/tc/source.txt"
echo "SOURCE-OK: /etc/tc/source.txt holds: $LINE"
