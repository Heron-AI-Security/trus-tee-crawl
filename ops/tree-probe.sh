#!/usr/bin/env bash
# ops/tree-probe.sh DEVICE...: step P4. Runs on the helper VM (shipped by ops/tree-diff.sh probe). Waits until each disk, which was attached AFTER the boot, is visible as /dev/disk/by-id/google-DEVICE,
# lists its partitions, and says how the boot of the VM ended. Exit code 1 if a disk does not appear within TREE_DISK_WAIT seconds (60).
set -uo pipefail
D="${TC_DISK_DIR:-/dev/disk/by-id}"
for dev in "$@"; do
  disk="$D/google-$dev"; for ((w = 0; w < ${TREE_DISK_WAIT:-60}; w += 2)); do [ -e "$disk" ] && break; sleep 2; done
  [ -e "$disk" ] || { echo "PROBE-FAIL: the disk $disk did not appear"; exit 1; }
  echo "$dev: $(lsblk -ln -o NAME,SIZE,FSTYPE,LABEL "$disk" 2>/dev/null | tr -s ' ' | tr '\n' ';')"
done
echo "boot: $(systemctl is-system-running 2>/dev/null || echo unknown)"
