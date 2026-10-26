#!/usr/bin/env bash
# Step R3.6 attack 1, on a helper VM: flip ONE bit of the file that the machine runs first (systemd: /usr/lib/systemd/systemd, or /lib/systemd/systemd on a root that is not usr-merged) inside the root partition of a disk copy. The root hash does not change, so the hash tree and the root hash still
# match each other, and the corruption is found only when that block is READ through dm-verity.   r3-flip.sh --p1 DEV [--path FILE]
set -uo pipefail
P1=""; F=""
while [ $# -gt 0 ]; do case "$1" in --p1) P1="$2"; shift 2 ;; --path) F="$2"; shift 2 ;; *) echo "FLIP-STOP: unknown argument $1" >&2; exit 2 ;; esac; done
[ -n "$P1" ] && [ -e "$P1" ] || { echo "FLIP-STOP: give --p1" >&2; exit 1; }
BLK=""; for c in ${F:-/usr/lib/systemd/systemd /lib/systemd/systemd}; do BLK="$(debugfs -R "bmap $c 0" "$P1" 2>/dev/null | tail -1)"; if [[ "$BLK" =~ ^[0-9]+$ ]] && [ "$BLK" -gt 0 ]; then F="$c"; break; fi; BLK=""; done
[ -n "$BLK" ] || { echo "FLIP-STOP: no block for ${F:-/usr/lib/systemd/systemd or /lib/systemd/systemd}" >&2; exit 1; }
OFF=$((BLK * 4096 + 100))
python3 - "$P1" "$OFF" <<'PY' || exit 1
import os, sys
p, off = sys.argv[1], int(sys.argv[2]); fd = os.open(p, os.O_RDWR); b = os.pread(fd, 1, off)[0]; os.pwrite(fd, bytes([b ^ 0x01]), off); os.fsync(fd)
a = os.pread(fd, 1, off)[0]; print("FLIP-OK: byte at offset %d of %s changed from 0x%02x to 0x%02x (one bit, in the first block of the file)" % (off, p, b, a))
PY
