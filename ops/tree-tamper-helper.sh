#!/usr/bin/env bash
# ops/tree-tamper-helper.sh: step P4, the tamper cases. It runs ON the helper VM, as root, and is copied there by ops/image/test/tamper-test.sh. It is a TEST tool: it WRITES to the disks that it is given (never to the original).
# Usage:   sudo bash tree-tamper-helper.sh ROOTHASH BLOCKS SALT PARTUUID OUTDIR KIND:DEVICE [KIND:DEVICE ...]
#   treeo        the ORIGINAL image's disk, attached read-only: its manifest is made through dm-verity, as ops/tree-helper.sh always does (OUTDIR/orig.manifest)
#   KIND:DEVICE  a COPY of the original (disk device name DEVICE, attached read-write). KIND says what is done to it:
#                  control   nothing is changed: the copy is only resealed. Its new root hash must equal ROOTHASH (that proves that the sealing parameters are exactly the ones of the real sealing)
#                  changed   one line is appended to /etc/issue                          (one changed file)
#                  added     the file /usr/local/bin/tc-added-file is created           (one added file)
#                  mode      the mode of /etc/issue.net is changed (600 or 644)         (one changed mode)
#                  xattr     a file capability (CAP_NET_RAW) is set on /usr/bin/cat      (one added extended attribute)
#   For each copy: mount it read-write, make the one change, unmount, RESEAL it (veritysetup format with the node's parameters: a new hash tree after the data, a new root hash), and make its manifest through
#   dm-verity against that NEW root hash. All the copies and the original are processed at the same time. OUTDIR gets KIND.manifest, KIND.root (the new root hash), KIND.rc and KIND.log for each, and orig.manifest.
#   The copies are not bootable (the boot configuration still names the old root hash): only the file trees are compared.
# Exit code 0 if every job worked, 1 otherwise.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ops/tree-lib.sh
. "$HERE/tree-lib.sh"
ROOTH="${1:-}"; BLOCKS="${2:-}"; SALT="${3:-}"; PUID="${4:-}"; OUTD="${5:-}"; shift 5 2>/dev/null || true
fail() { echo "TREE-TAMPER-FAILED: $*" >&2; exit 1; }
[[ "$ROOTH" =~ ^[0-9a-f]{64}$ ]] || fail "usage: tree-tamper-helper.sh ROOTHASH BLOCKS SALT PARTUUID OUTDIR KIND:DEVICE ... (the root hash must be 64 lowercase hexadecimal digits)"
{ [[ "$BLOCKS" =~ ^[0-9]{1,12}$ ]] && [ "$BLOCKS" -gt 0 ]; } || fail "BLOCKS must be a positive number"
[[ "$SALT" =~ ^[0-9a-f]{2,128}$ ]] || fail "the salt must be hexadecimal"
[[ "$PUID" =~ ^[0-9A-Fa-f-]{8,40}$ ]] || fail "the PARTUUID is needed"
[ -n "$OUTD" ] && [ $# -ge 1 ] || fail "usage: tree-tamper-helper.sh ROOTHASH BLOCKS SALT PARTUUID OUTDIR KIND:DEVICE ..."
for j in "$@"; do [[ "$j" =~ ^(control|changed|added|mode|xattr):[a-z0-9]+$ ]] || fail "'$j' is not KIND:DEVICE with KIND one of control, changed, added, mode, xattr"; done
mkdir -p "$OUTD" || fail "cannot make $OUTD"
VS="${TC_VERITYSETUP:-veritysetup}"; command -v "$VS" >/dev/null 2>&1 || { DEBIAN_FRONTEND=noninteractive apt-get update -qq >&2 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cryptsetup-bin >&2; command -v "$VS" >/dev/null 2>&1 || fail "veritysetup is not installed and could not be installed"; }
edit() {   # edit KIND MOUNTPOINT: the ONE change
  local f m
  case "$1" in
    changed) f="$2/etc/issue"; [ -f "$f" ] || { echo "there is no /etc/issue"; return 1; }; printf 'tampered by the tamper test\n' >> "$f";;
    added) mkdir -p "$2/usr/local/bin" && printf '#!/bin/sh\necho added\n' > "$2/usr/local/bin/tc-added-file" && chmod 755 "$2/usr/local/bin/tc-added-file";;
    mode) f="$2/etc/issue.net"; [ -f "$f" ] || { echo "there is no /etc/issue.net"; return 1; }; m="$(stat -c %a "$f")"; if [ "$m" = 600 ]; then chmod 644 "$f"; else chmod 600 "$f"; fi;;
    xattr) f="$2/usr/bin/cat"; [ -f "$f" ] || { echo "there is no /usr/bin/cat"; return 1; }; python3 -c "import os, sys; os.setxattr(sys.argv[1], 'security.capability', bytes.fromhex('0100000200200000' + '00' * 12))" "$f";;
    *) echo "unknown kind $1"; return 1;;
  esac
}
tamper_inner() {   # tamper_inner KIND DEVICE
  local kind="$1" dev="$2" part disk mnt out newroot fakevar
  fakevar="TC_FAKE_PART_${dev}"; part="${!fakevar:-}"   # the tests give a file instead of a disk
  if [ -z "$part" ]; then
    disk="${TC_DISK_DIR:-/dev/disk/by-id}/google-$dev"; for ((w = 0; w < ${TREE_DISK_WAIT:-60}; w += 2)); do [ -e "$disk" ] && break; sleep 2; done   # a disk attached after the boot shows up a few seconds later
    [ -e "$disk" ] || { echo "the disk $disk is not attached"; return 1; }
    part="$(tc_find_part "$disk" "$PUID")" || { echo "no partition with the PARTUUID $PUID on the disk $dev"; return 1; }
  fi
  echo "copy $dev ($kind): partition $part"
  if [ "$kind" != control ]; then
    mnt="$(mktemp -d)"; mount -o rw,nosuid,nodev "$part" "$mnt" || { echo "cannot mount $part read-write"; return 1; }
    edit "$kind" "$mnt" || { umount "$mnt"; rmdir "$mnt"; return 1; }
    sync; umount "$mnt" || { echo "cannot unmount $mnt"; return 1; }; rmdir "$mnt"
    echo "the change was made"
  fi
  tc_verity_args "$BLOCKS" "$SALT"
  out="$("$VS" format "${VARGS[@]}" "$part" "$part" 2>&1)" || { echo "veritysetup format failed: $out"; return 1; }
  newroot="$(awk '/Root hash:/ {print $3}' <<<"$out")"; [[ "$newroot" =~ ^[0-9a-f]{64}$ ]] || { echo "no root hash in the output of veritysetup format: $out"; return 1; }
  echo "resealed: the new root hash is $newroot"; echo "$newroot" > "$OUTD/$kind.root"
  bash "$HERE/tree-helper.sh" "$dev" "$OUTD/$kind.manifest" "tamper-$kind" "$PUID" "$newroot" "$BLOCKS" "$SALT"
}
job() { tamper_inner "$1" "$2" > "$OUTD/$1.log" 2>&1; echo $? > "$OUTD/$1.rc"; }
echo "the original (treeo) and ${#} copies are processed at the same time"
( bash "$HERE/tree-helper.sh" treeo "$OUTD/orig.manifest" tamper-original "$PUID" "$ROOTH" "$BLOCKS" "$SALT" > "$OUTD/orig.log" 2>&1; echo $? > "$OUTD/orig.rc" ) &
for j in "$@"; do job "${j%%:*}" "${j##*:}" & done
wait
bad=0
for k in orig "${@%%:*}"; do rc="$(cat "$OUTD/$k.rc" 2>/dev/null || echo missing)"; echo "JOB $k rc=$rc root=$(cat "$OUTD/$k.root" 2>/dev/null | cut -c1-16)"; [ "$rc" = 0 ] || { bad=1; echo "--- the output of $k:"; tail -8 "$OUTD/$k.log" 2>/dev/null | sed 's/^/   /'; }; done
[ "$bad" = 0 ] && echo "TREE-TAMPER-JOBS-OK" || echo "TREE-TAMPER-JOBS-FAILED"
exit "$bad"
