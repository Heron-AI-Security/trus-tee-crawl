#!/usr/bin/env bash
# ops/tree-helper.sh: step P4.2. It runs ON the helper VM, as root, and is copied there by ops/tree-diff.sh. It opens the root partition of an attached image disk READ-ONLY and writes the manifest of its file tree.
# Usage:   sudo bash tree-helper.sh DEVICE OUTFILE LABEL [PARTUUID [ROOTHASH BLOCKS SALT]]
#   DEVICE    the device name of the attached disk (it appears as /dev/disk/by-id/google-DEVICE)
#   PARTUUID  the PARTUUID of the root data partition (the tc.data= value on the kernel command line of the image)
#   ROOTHASH BLOCKS SALT   the dm-verity parameters of the image (the tc.verity=, tc.blocks= and tc.salt= values on its kernel command line). With them the disk is opened EXACTLY as the node opens it:
#             every block of the partition is first checked against the root hash (veritysetup verify), then the partition is opened through dm-verity (veritysetup open) and the device mapper is mounted
#             read-only, so that every byte that is read is checked again. A disk that does not match the root hash is refused with exit code 3 and the line VERITY CHECK FAILED.
#   Without ROOTHASH the partition (the one by PARTUUID, or the one ext4 partition that holds /usr and /etc/os-release) is only mounted read-only, with NO check against a root hash.
# It never writes to the disk: the mount is ro,noload (the journal is not replayed), and a verity device is read-only. Ends with the line of ops/tree-manifest.py; exit code 0, 2 (the tree had read errors), 3 (verity check failed), or 1 (anything else).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEV="${1:-}"; OUT="${2:-}"; LABEL="${3:-}"; PUID="${4:-}"; ROOTH="${5:-}"; BLOCKS="${6:-}"; SALT="${7:-}"
fail() { echo "TREE-HELPER-FAILED: $*" >&2; exit 1; }
[ -n "$DEV" ] && [ -n "$OUT" ] || fail "usage: tree-helper.sh DEVICE OUTFILE LABEL [PARTUUID [ROOTHASH BLOCKS SALT]]"
if [ -n "$ROOTH" ]; then
  [[ "$ROOTH" =~ ^[0-9a-f]{64}$ ]] || fail "the root hash must be 64 lowercase hexadecimal digits"
  { [[ "$BLOCKS" =~ ^[0-9]{1,12}$ ]] && [ "$BLOCKS" -gt 0 ]; } || fail "BLOCKS must be a positive number"
  [[ "$SALT" =~ ^[0-9a-f]{2,128}$ ]] || fail "the salt must be hexadecimal"
  [[ "$PUID" =~ ^[0-9A-Fa-f-]{8,40}$ ]] || fail "with a root hash the PARTUUID of the root data partition is needed"
fi
VS="${TC_VERITYSETUP:-veritysetup}"
fakepart="TC_FAKE_PART_${DEV}"; FPART="${!fakepart:-}"; fakevar="TC_FAKE_MOUNT_${DEV}"; FAKE="${!fakevar:-}"   # the tests give a file or a folder instead of a disk
MNT=""; OPENED=""
cleanup() { [ -z "$MNT" ] || umount "$MNT" 2>/dev/null; [ -z "$OPENED" ] || "$VS" close "$OPENED" 2>/dev/null; [ -z "$MNT" ] || rmdir "$MNT" 2>/dev/null; }
trap cleanup EXIT
MOUNTOPTS="ro,noload,nosuid,nodev,noexec"
if [ -n "$FAKE" ] && [ -z "$ROOTH" ]; then ROOTDIR="$FAKE"; else
  if [ -n "$FPART" ]; then part="$FPART"; else
    disk="/dev/disk/by-id/google-$DEV"; [ -e "$disk" ] || fail "the disk $disk is not attached"
    echo "the partitions of $DEV:"; lsblk -o NAME,SIZE,FSTYPE,PARTUUID "$disk" | sed 's/^/   /'
    if [ -n "$PUID" ]; then
      part="/dev/disk/by-partuuid/$PUID"; [ -e "$part" ] || fail "no partition with the PARTUUID $PUID on the disk"
    else
      MNT="$(mktemp -d)"; cands=()
      while read -r p; do
        [ "$(blkid -o value -s TYPE "$p" 2>/dev/null)" = ext4 ] || continue
        if mount -o "$MOUNTOPTS" "$p" "$MNT" 2>/dev/null; then
          if [ -d "$MNT/usr" ] && [ -e "$MNT/etc/os-release" ]; then cands+=("$p"); fi
          umount "$MNT"
        fi
      done < <(lsblk -ln -o PATH,TYPE "$disk" | awk '$2=="part"{print $1}')
      [ "${#cands[@]}" = 1 ] || fail "${#cands[@]} partitions look like a root partition (${cands[*]:-none}); give the PARTUUID"
      part="${cands[0]}"
    fi
  fi
  if [ -n "$ROOTH" ]; then
    if ! command -v "$VS" >/dev/null 2>&1; then
      [ -z "$FPART" ] || fail "$VS is not installed"
      echo "installing cryptsetup-bin (for veritysetup)"; DEBIAN_FRONTEND=noninteractive apt-get update -qq >&2 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cryptsetup-bin >&2; command -v "$VS" >/dev/null 2>&1 || fail "veritysetup could not be installed"
    fi
    VARGS=(--no-superblock --hash=sha256 --data-block-size=4096 --hash-block-size=4096 --data-blocks="$BLOCKS" --hash-offset="$((BLOCKS * 4096))" --salt="$SALT")
    echo "checking every block of $part against the root hash ${ROOTH:0:16}... (the node's own parameters: $BLOCKS blocks, hash tree at $((BLOCKS * 4096)))"
    vout="$("$VS" verify "${VARGS[@]}" "$part" "$part" "$ROOTH" 2>&1)" || { echo "VERITY CHECK FAILED: the partition does not match the root hash $ROOTH (veritysetup says: $(echo "$vout" | tr '\n' ' ' | cut -c1-200))" >&2; exit 3; }
    echo "verity check passed: every block matches the root hash"
    if [ -n "$FAKE" ]; then ROOTDIR="$FAKE"; else
      MAPNAME="tcv-$DEV"; "$VS" open "${VARGS[@]}" "$part" "$MAPNAME" "$part" "$ROOTH" || fail "veritysetup open failed"; OPENED="$MAPNAME"
      [ -n "$MNT" ] || MNT="$(mktemp -d)"
      mount -o "$MOUNTOPTS" "/dev/mapper/$MAPNAME" "$MNT" || fail "cannot mount the verity device read-only"
      echo "opened through dm-verity and mounted read-only"; ROOTDIR="$MNT"
    fi
  else
    [ -n "$MNT" ] || MNT="$(mktemp -d)"
    mount -o "$MOUNTOPTS" "$part" "$MNT" || fail "cannot mount $part read-only"
    echo "mounted $part read-only (NOT checked against a root hash)"; ROOTDIR="$MNT"
  fi
fi
MARGS=("$ROOTDIR" --label "$LABEL" --out "$OUT"); [ -z "$ROOTH" ] || MARGS+=(--verity "$ROOTH")
python3 "$HERE/tree-manifest.py" "${MARGS[@]}"
