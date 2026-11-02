#!/usr/bin/env bash
# ops/tree-helper.sh: step P4.2. It runs ON the helper VM, as root, and is copied there by ops/tree-diff.sh. It mounts the root partition of an attached image disk READ-ONLY and writes the manifest of its file tree.
# Usage:   sudo bash tree-helper.sh DEVICE OUTFILE LABEL [PARTUUID]
#   DEVICE    the device name of the attached disk (it appears as /dev/disk/by-id/google-DEVICE)
#   PARTUUID  the PARTUUID of the root data partition (the tc.data= value on the kernel command line); without it the one partition that is ext4 and holds /usr and /etc/os-release is used
# It never writes to the disk: the mount is ro,noload (the journal is not replayed). Ends with the line of ops/tree-manifest.py; exit code 0, 2 (the tree had read errors), or 1 (it could not find or mount the partition).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV="${1:-}"; OUT="${2:-}"; LABEL="${3:-}"; PUID="${4:-}"
fail() { echo "TREE-HELPER-FAILED: $*" >&2; exit 1; }
[ -n "$DEV" ] && [ -n "$OUT" ] || fail "usage: tree-helper.sh DEVICE OUTFILE LABEL [PARTUUID]"
fakevar="TC_FAKE_MOUNT_${DEV}"; FAKE="${!fakevar:-}"     # the tests give a folder instead of a disk
if [ -n "$FAKE" ]; then ROOTDIR="$FAKE"; else
  disk="/dev/disk/by-id/google-$DEV"; [ -e "$disk" ] || fail "the disk $disk is not attached"
  MNT="$(mktemp -d)"; trap 'umount "$MNT" 2>/dev/null; rmdir "$MNT" 2>/dev/null' EXIT
  echo "the partitions of $DEV:"; lsblk -o NAME,SIZE,FSTYPE,PARTUUID "$disk" | sed 's/^/   /'
  if [ -n "$PUID" ]; then
    part="/dev/disk/by-partuuid/$PUID"; [ -e "$part" ] || fail "no partition with the PARTUUID $PUID on the disk"
  else
    cands=()
    while read -r p; do
      [ "$(blkid -o value -s TYPE "$p" 2>/dev/null)" = ext4 ] || continue
      if mount -o ro,noload,nosuid,nodev,noexec "$p" "$MNT" 2>/dev/null; then
        if [ -d "$MNT/usr" ] && [ -e "$MNT/etc/os-release" ]; then cands+=("$p"); fi
        umount "$MNT"
      fi
    done < <(lsblk -ln -o PATH,TYPE "$disk" | awk '$2=="part"{print $1}')
    [ "${#cands[@]}" = 1 ] || fail "${#cands[@]} partitions look like a root partition (${cands[*]:-none}); give the PARTUUID with --partuuid"
    part="${cands[0]}"
  fi
  mount -o ro,noload,nosuid,nodev,noexec "$part" "$MNT" || fail "cannot mount $part read-only"
  echo "mounted $part read-only"; ROOTDIR="$MNT"
fi
python3 "$HERE/tree-manifest.py" "$ROOTDIR" --label "$LABEL" --out "$OUT"
