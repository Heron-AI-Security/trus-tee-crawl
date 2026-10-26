#!/bin/bash
# reseal.sh [SEALSCRIPT]: rebuild the sealed disk image of the reproduction from the jammy root with the (real) sealing script
W=/tmp/rep; cd $W; S="${1:-$W/tc-image-seal.sh}"; rm -rf esp out p1.img disk.img && mkdir -p esp/EFI/ubuntu out
truncate -s 1330M disk.img && sgdisk -n 14:2048:+4M -t 14:ef02 -n 15:0:+16M -t 15:ef00 -n 1:0:+1280M -t 1:8300 disk.img >/dev/null 2>&1
mke2fs -q -t ext4 -F -b 4096 -O metadata_csum,64bit,has_journal -d /tmp/jam p1.img 1280M
printf 'search.fs_uuid 00000000-0000-0000-0000-000000000000 root\n' > esp/EFI/ubuntu/grub.cfg; echo efi > esp/EFI/ubuntu/grubx64.efi
bash "$S" --disk disk.img --p1 p1.img --esp-dir esp --kver 6.8.0-1070-gcp --destructive-ok --blocks 262144 --out out --no-kernel-test 2>&1 | grep -E "SEAL-(OK|STOP)" | cut -c1-110
START=$(sfdisk -d disk.img | awk '/^disk.img1 /{gsub(",","",$4); print $4}'); dd if=p1.img of=disk.img bs=512 seek=$START conv=notrunc,sparse 2>/dev/null; rm -f p1.img
