#!/usr/bin/env bash
# Step R3.6 attacks 2 and 3, inside a booted sealed VM (root).   r3-attack-scratch.sh before | after OLD_FS_UUID
#   before: a control read, a marker file, then GARBAGE ON THE RAW SCRATCH DISK; reading it through the stack must fail with a checksum error (attack 2). Prints the file system UUID.
#   after (after a reset of the VM): the marker is gone, the file system UUID is a new one, and no key file exists: the keys of the last boot are lost with it (attack 3).
set -uo pipefail
BAD=0; ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; BAD=$((BAD+1)); }
case "${1:-}" in
before)
  dd if=/dev/mapper/tc-scratch of=/dev/null bs=4096 count=512 2>/dev/null && ok "control: the first 2 MiB read fine before the tamper" || no "the control read failed"
  head -c 16777216 /dev/urandom > /var/lib/hadoop/tc-attack-marker; sync   # 16 MiB: it lies right after the metadata of the file system, inside the range that is tampered below
  UUID="$(blkid -s UUID -o value /dev/mapper/tc-scratch)"
  # The layout of the raw disk is NOT read from the kernel's table (the 6.8 kernel prints journal_sectors, the 6.17 kernel does not, and the journal area of an unused journal is large: garbage there hits nothing).
  # So a range is tampered that surely holds written data whatever the layout is: 400 MiB from 1 MiB on (the superblock at the start stays). It covers the journal area (at most 64 MiB), the tags, the inode tables and the marker.
  C0="$(dmesg | grep -c 'Checksum failed')"
  head -c 419430400 /dev/urandom | dd of=/dev/nvme0n2 bs=1048576 seek=1 conv=notrunc 2>/dev/null; sync; echo 3 > /proc/sys/vm/drop_caches
  dd if=/dev/mapper/tc-scratch of=/dev/null bs=1048576 count=128 iflag=direct >/tmp/dd.out 2>&1; RC=$?; C1="$(dmesg | grep -c 'Checksum failed')"
  if [ "$RC" != 0 ] || [ "$C1" -gt "$C0" ]; then ok "ATTACK 2: garbage written on the raw scratch disk (400 MiB from 1 MiB on) is REFUSED when read through the stack (dd exit $RC, $((C1 - C0)) new 'Checksum failed' lines in the kernel log)"; else no "the tampered area was read without any error"; fi
  dmesg | grep 'Checksum failed' | tail -2 | cut -c1-120
  echo "UUID=$UUID"; [ "$BAD" = 0 ] && echo "ATTACK-SCRATCH-1-OK" || echo "ATTACK-SCRATCH-1-FAILED" ;;
after)
  OLD="${2:?give the old UUID}"; NEW="$(blkid -s UUID -o value /dev/mapper/tc-scratch)"
  [ ! -e /var/lib/hadoop/tc-attack-marker ] && ok "ATTACK 3: the marker of the last boot is gone: the scratch disk was formatted again with new keys" || no "the marker survived the reset"
  [ -n "$NEW" ] && [ "$NEW" != "$OLD" ] && ok "the file system UUID is a new one ($NEW, before $OLD)" || no "the file system UUID is the old one"
  ls /run/tc-scratch.k* >/dev/null 2>&1 && no "a key file exists" || ok "no key file exists (the keys of this boot are only inside the kernel)"
  [ "$BAD" = 0 ] && echo "ATTACK-SCRATCH-2-OK" || echo "ATTACK-SCRATCH-2-FAILED" ;;
*) echo "usage: $0 before | after OLD_FS_UUID" >&2; exit 2 ;;
esac
