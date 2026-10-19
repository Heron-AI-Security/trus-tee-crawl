#!/usr/bin/env bash
# Extend RTMR3 with the SHA-384 of a file, or of a folder (via treehash.sh), and append one line to our own event log.
# Runs as root (no sudo): it is part of the image's boot. Same log format as attest/measure/rtmr3-extend.sh, so rtmr3_replay.py reads it.
#   tc-extend.sh NAME PATH [SKIP-PATH-INSIDE-FOLDER ...]
# Log line: NAME <TAB> digest <TAB> rtmr3-before <TAB> rtmr3-after
# Hooks for the rehearsal only: TC_RTMR3 (the register file), TC_LOG (the event log), TC_TREEHASH, TC_WRITE (a command that reads the 48 bytes on its standard input and extends the register).
set -euo pipefail
NAME="${1:?usage: $0 NAME PATH [SKIP...]}"; TARGET="${2:?usage: $0 NAME PATH [SKIP...]}"; shift 2
RT="${TC_RTMR3:-/sys/devices/virtual/misc/tdx_guest/measurements/rtmr3:sha384}"
LOG="${TC_LOG:?TC_LOG (the event log) must be set}"
TREEHASH="${TC_TREEHASH:-$(dirname "$0")/treehash.sh}"
read_rt() { xxd -p "$RT" | tr -d '\n'; }
if [ -d "$TARGET" ]; then
  DIGEST="$("$TREEHASH" "$TARGET" "$@" | awk '{print $2}')"
else
  DIGEST="$(sha384sum "$TARGET" | cut -d' ' -f1)"
fi
[ "${#DIGEST}" -eq 96 ] || { echo "digest is not 96 hex characters: $DIGEST" >&2; exit 1; }
BEFORE="$(read_rt)"
if [ -n "${TC_WRITE:-}" ]; then printf '%s' "$DIGEST" | xxd -r -p | $TC_WRITE
else printf '%s' "$DIGEST" | xxd -r -p | dd of="$RT" bs=48 count=1 iflag=fullblock conv=notrunc status=none; fi
AFTER="$(read_rt)"
WANT="$(python3 -c "import hashlib,sys; print(hashlib.sha384(bytes.fromhex(sys.argv[1])+bytes.fromhex(sys.argv[2])).hexdigest())" "$BEFORE" "$DIGEST")"
printf '%s\t%s\t%s\t%s\n' "$NAME" "$DIGEST" "$BEFORE" "$AFTER" >> "$LOG"
if [ "$AFTER" = "$WANT" ]; then echo "EXTENDED $NAME: register equals SHA-384(before + digest)"; else echo "MISMATCH after extending $NAME" >&2; exit 1; fi
