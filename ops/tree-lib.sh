#!/usr/bin/env bash
# ops/tree-lib.sh: step P4.2. Functions shared by ops/tree-helper.sh and ops/tree-tamper-helper.sh (they run on the helper VM and source this file; it is copied there with them). Not to be run by itself.
# tc_find_part DISK PARTUUID: prints the path of the partition OF THIS DISK that has the PARTUUID. Two disks that were made from the same image carry the same PARTUUIDs, and /dev/disk/by-partuuid/ then points to only one
# of them: so the partition is looked for among the partitions of the one disk (lsblk DISK), never in the global list. Exit code 1 if there is none.
tc_find_part() {
  local disk="$1" want="${2,,}" path pu
  while read -r path pu; do
    [ -n "$pu" ] && [ "${pu,,}" = "$want" ] && { echo "$path"; return 0; }
  done < <("${TC_LSBLK:-lsblk}" -ln -o PATH,PARTUUID "$disk" 2>/dev/null)
  return 1
}
# tc_verity_args BLOCKS SALT: sets VARGS, the parameters with which the node opens its root (the sealing wrote the hash tree with the same ones): no superblock, sha256, 4096-byte blocks, the hash tree right after the data.
# shellcheck disable=SC2034   # VARGS is read by the scripts that source this file
tc_verity_args() { VARGS=(--no-superblock --hash=sha256 --data-block-size=4096 --hash-block-size=4096 --data-blocks="$1" --hash-offset="$(($1 * 4096))" --salt="$2"); }
