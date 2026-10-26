#!/usr/bin/env bash
# Rehearsal of step R3.3 (the offline sealing): the REAL tc-image-seal.sh runs on file-backed disk images with the REAL e2fsprogs and veritysetup (a real GPT, a real ext4, a real hash tree).
# Only two things are not real here: the kernel's dm-verity (gate 8, run on the cluster) and the mount of the EFI partition (a folder stands in for it). Every fault that must be caught before the first change is
# also checked to have left the disk and the EFI partition exactly as they were.
#   bash r3-seal-rehearse.sh KITDIR      (as root; needs e2fsprogs, cryptsetup-bin, gdisk, fdisk, cpio, grub-common, initramfs-tools-core)
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; SEAL="$I/build/tc-image-seal.sh"; PASS=0; FAILN=0
chk() { local t="$1"; shift; if [ "${1:-1}" = 0 ]; then echo "  pass: $t"; PASS=$((PASS+1)); else echo "  FAIL: $t"; FAILN=$((FAILN+1)); fi; }
for t in mke2fs e2fsck resize2fs tune2fs debugfs dumpe2fs veritysetup sfdisk sgdisk cpio lsinitramfs grub-script-check; do command -v $t >/dev/null || { echo "  FAIL: the rehearsal needs $t"; exit 2; }; done
[ "$(id -u)" = 0 ] || { echo "  FAIL: the rehearsal needs root"; exit 2; }
W="$(mktemp -d)"; KV=6.17.0-1022-gcp; TPL="$I/rootfs/etc/tc/grub-sealed.cfg.in"
mkfix() { # NAME: a fixture; the options come from the environment: BULK_MB NO_INITRD NO_KERNEL NO_TV BAD_SHA TPL_NO_HASH TPL_BAD NO_ESPCFG NOT_EXT4 NO_P15
  F="$W/$1"; rm -rf "$F"; mkdir -p "$F/tree/boot" "$F/tree/etc/tc" "$F/ird/scripts/local-top" "$F/ird/scripts/init-bottom" "$F/ird/lib/modules/$KV" "$F/esp/EFI/ubuntu" "$F/out"
  head -c 65536 /dev/urandom > "$F/tree/boot/vmlinuz-$KV"; [ -z "${NO_KERNEL:-}" ] || rm "$F/tree/boot/vmlinuz-$KV"
  echo 'NAME="Ubuntu"' > "$F/tree/etc/os-release"; head -c $(( ${BULK_MB:-20} * 1048576 )) /dev/urandom > "$F/tree/bulk.bin"
  for f in scripts/local-top/tc-scratch-dev scripts/init-bottom/tc-scratch-bind scripts/init-bottom/overlayroot lib/modules/$KV/dm-verity.ko lib/modules/$KV/dm-integrity.ko lib/modules/$KV/dm-crypt.ko lib/modules/$KV/dm-bufio.ko; do echo "$f" > "$F/ird/$f"; done
  [ -n "${NO_TV:-}" ] || echo tcverity > "$F/ird/scripts/local-top/tc-verity"; ( cd "$F/ird" && find . | cpio -o -H newc --quiet | gzip -n ) > "$F/initrd"
  if [ -z "${NO_INITRD:-}" ]; then cp "$F/initrd" "$F/tree/boot/initrd.img-tc"; echo "$(sha256sum "$F/initrd" | cut -d' ' -f1)  /boot/initrd.img-tc" > "$F/tree/boot/initrd.img-tc.sha256"; [ -z "${BAD_SHA:-}" ] || echo "$(printf '%064d' 1)  /boot/initrd.img-tc" > "$F/tree/boot/initrd.img-tc.sha256"; fi
  if [ -n "${REAL_BOOT:-}" ]; then cp /boot/initrd.img-tc /boot/initrd.img-tc.sha256 "$F/tree/boot/"; cp /etc/tc/grub-sealed.cfg.in "$F/tree/etc/tc/grub-sealed.cfg.in"; fi
  [ -n "${REAL_BOOT:-}" ] || cp "$TPL" "$F/tree/etc/tc/grub-sealed.cfg.in"; [ -z "${TPL_NO_HASH:-}" ] || sed -i 's/@ROOTHASH@/nohash/' "$F/tree/etc/tc/grub-sealed.cfg.in"; [ -z "${TPL_BAD:-}" ] || echo 'menuentry "x" {' >> "$F/tree/etc/tc/grub-sealed.cfg.in"
  mke2fs -q -t ext4 -F -b 4096 -O has_journal,metadata_csum,64bit -d "$F/tree" "$F/p1.img" 256M >/dev/null 2>&1; [ -z "${NOT_EXT4:-}" ] || head -c 268435456 /dev/zero > "$F/p1.img"
  truncate -s 400M "$F/disk.img"; if [ -n "${NO_P15:-}" ]; then sgdisk -n 14:2048:+4M -t 14:ef02 -n 1:0:0 -t 1:8300 "$F/disk.img" >/dev/null 2>&1; else sgdisk -n 14:2048:+4M -t 14:ef02 -n 15:0:+16M -t 15:ef00 -n 1:0:0 -t 1:8300 "$F/disk.img" >/dev/null 2>&1; fi
  printf 'search.fs_uuid 00000000-0000-0000-0000-000000000000 root\nconfigfile ($root)/boot/grub/grub.cfg\n' > "$F/esp/EFI/ubuntu/grub.cfg"; echo efi > "$F/esp/EFI/ubuntu/grubx64.efi"; [ -z "${NO_ESPCFG:-}" ] || rm "$F/esp/EFI/ubuntu/grub.cfg"; }
seal() { # [extra args]: the real script, on the fixture $F
  out="$(bash "$SEAL" --disk "$F/disk.img" --p1 "$F/p1.img" --esp-dir "$F/esp" --kver "${KVER:-$KV}" --destructive-ok --blocks "${BLOCKS:-32768}" --out "$F/out" --no-kernel-test "$@" 2>&1)"; rc=$?; }
snap() { sha256sum "$F/p1.img" "$F/disk.img" "$F/esp/EFI/ubuntu/grub.cfg" 2>/dev/null | awk '{print $1}' | tr '\n' ' '; }
echo "=== A. a successful sealing, on real images"
unset BULK_MB NO_INITRD NO_KERNEL NO_TV BAD_SHA TPL_NO_HASH TPL_BAD NO_ESPCFG NOT_EXT4 NO_P15; mkfix a; ORIG="$(cat "$F/esp/EFI/ubuntu/grub.cfg")"; seal; echo "$out" | tail -3 | cut -c1-170
RH="$(awk -F= '/^roothash=/ {print $2}' "$F/out/seal-report.txt")"; PU="$(sfdisk -d "$F/disk.img" | grep -E 'img1 :' | sed -E 's/.*uuid=([0-9A-Fa-f-]+).*/\1/' | tr A-F a-f)"
VA=(--no-superblock --hash=sha256 --data-block-size=4096 --hash-block-size=4096 --data-blocks=32768 --hash-offset=$((32768 * 4096)) --salt="$(printf 'tc-sealed-root-salt-v1' | sha256sum | cut -c1-64)")
chk "the script ends with SEAL-OK and a root hash of 64 hex digits, which is in the report" $([ $rc = 0 ] && grep -q '^SEAL-OK roothash=' <<<"$out" && [[ "$RH" =~ ^[0-9a-f]{64}$ ]] && grep -q "SEAL-OK roothash=$RH " <<<"$out"; echo $?)
chk "the file system has exactly 32768 blocks, no journal, and is clean (checked independently)" $([ "$(dumpe2fs -h "$F/p1.img" 2>/dev/null | awk -F: '/^Block count:/ {gsub(/ /,"",$2); print $2}')" = 32768 ] && ! dumpe2fs -h "$F/p1.img" 2>/dev/null | grep -q '^Filesystem features:.*has_journal' && e2fsck -fn "$F/p1.img" >/dev/null 2>&1; echo $?)
chk "an independent veritysetup verify accepts the data with the printed root hash" $(veritysetup verify "${VA[@]}" "$F/p1.img" "$F/p1.img" "$RH" >/dev/null 2>&1; echo $?)
chk "control: the same verification REFUSES a root hash with one digit changed" $(! veritysetup verify "${VA[@]}" "$F/p1.img" "$F/p1.img" "${RH:0:63}$([ "${RH:63:1}" = 0 ] && echo 1 || echo 0)" >/dev/null 2>&1; echo $?)
cp "$F/p1.img" "$W/p1.flip"; printf '\xff\xfe' | dd of="$W/p1.flip" bs=1 seek=$((50 * 1048576)) conv=notrunc 2>/dev/null
chk "control: one flipped byte anywhere in the data is caught by the verification" $(! veritysetup verify "${VA[@]}" "$W/p1.flip" "$W/p1.flip" "$RH" >/dev/null 2>&1; echo $?)
cp "$F/p1.img" "$W/p1.flip2"; printf '\xff' | dd of="$W/p1.flip2" bs=1 seek=$((32768 * 4096 + 100)) conv=notrunc 2>/dev/null
chk "control: one flipped byte in the hash tree is caught too" $(! veritysetup verify "${VA[@]}" "$W/p1.flip2" "$W/p1.flip2" "$RH" >/dev/null 2>&1; echo $?)
G="$F/esp/EFI/ubuntu/grub.cfg"; SA="$(printf 'tc-sealed-root-salt-v1' | sha256sum | cut -c1-64)"; FU="$(dumpe2fs -h "$F/p1.img" 2>/dev/null | awk -F: '/^Filesystem UUID:/ {gsub(/ /,"",$2); print $2}')"
chk "grub.cfg has the root hash once, the block count, the salt, the root partition's PARTUUID (lower case) and the file system's UUID, and no placeholder" $([ "$(grep -c "tc.verity=$RH" "$G")" = 1 ] && grep -q 'tc.blocks=32768' "$G" && grep -q "tc.salt=$SA" "$G" && grep -q "tc.data=$PU" "$G" && grep -q "search --no-floppy --fs-uuid --set=root $FU" "$G" && ! grep -q '@' "$G"; echo $?)
chk "the kernel command line has root=/dev/mapper/vroot, ro, fsck.mode=skip (the read-only verity root cannot be fscked), overlayroot=tmpfs and the initramfs is /boot/initrd.img-tc (and there is NO panic= setting: a failed boot hangs and can be read)" $(grep -q 'root=/dev/mapper/vroot ro fsck.mode=skip ' "$G" && grep -q 'overlayroot=tmpfs' "$G" && grep -q 'initrd /boot/initrd.img-tc' "$G" && ! grep -q 'panic=' "$G"; echo $?)
chk "grub-script-check accepts the written grub.cfg, and the old one is kept as grub.cfg.orig, unchanged" $(grub-script-check "$G" && [ "$(cat "$F/esp/EFI/ubuntu/grub.cfg.orig")" = "$ORIG" ]; echo $?)
chk "the report has the root hash, the block count, the salt, the PARTUUID, the file system UUID, the kernel and the checksums of the initramfs and of grub.cfg" $(ok=0; for k in roothash blocks salt data_partuuid rootfs_uuid kver initrd_sha256 grub_cfg_sha256; do grep -q "^$k=" "$F/out/seal-report.txt" || ok=1; done; echo $ok)
echo "=== B. every fault that can be seen BEFORE the first change is caught there, and the disk and the EFI partition are left exactly as they were"
fault() { # NAME DESCRIPTION WORDS [extra args]: a fresh fixture (options from the environment), the script must stop with SEAL-STOP and these words, and change nothing
  local n="$1" d="$2" w="$3"; shift 3; mkfix "$n"; B="$(snap)"; seal "$@"; chk "fault: $d: SEAL-STOP, says '$w', and changes nothing" $([ $rc != 0 ] && grep -q '^SEAL-STOP: ' <<<"$out" && grep -q -- "$w" <<<"$out" && [ "$B" = "$(snap)" ]; echo $?); unset BULK_MB NO_INITRD NO_KERNEL NO_TV BAD_SHA TPL_NO_HASH TPL_BAD NO_ESPCFG NOT_EXT4 NO_P15; KVER=""; BLOCKS=""; }
mkfix f0; B="$(snap)"; out="$(bash "$SEAL" --disk "$F/disk.img" --p1 "$F/p1.img" --esp-dir "$F/esp" --kver $KV --blocks 32768 --no-kernel-test 2>&1)"; rc=$?; chk "fault: without --destructive-ok it refuses at once, and changes nothing" $([ $rc != 0 ] && grep -q 'pass --destructive-ok' <<<"$out" && [ "$B" = "$(snap)" ]; echo $?)
NO_P15=1 fault f1 "a partition table without partition 15" "the partitions are"
NO_INITRD=1 fault f2 "no sealed initramfs in the root partition" "has no /boot/initrd.img-tc"
NO_KERNEL=1 fault f3 "no kernel file" "has no /boot/vmlinuz"
NO_TV=1 fault f4 "an initramfs without the verity script (its checksum is right)" "lacks scripts/local-top/tc-verity"
BAD_SHA=1 fault f5 "an initramfs that is not the one the builder verified" "differs from the one that the builder verified"
BULK_MB=60 BLOCKS=16384 fault f6 "a root that uses more than 80% of the plan" "more than 80% of the plan"
BLOCKS=65536 fault f7 "a plan whose hash tree does not fit in the partition" "need"
TPL_NO_HASH=1 fault f8 "a GRUB template without the root hash placeholder" "has no @ROOTHASH@"
TPL_BAD=1 fault f9 "a GRUB template that does not parse" "does not parse"
NO_ESPCFG=1 fault f10 "an EFI partition without grub.cfg" "no EFI/ubuntu/grub.cfg"
NOT_EXT4=1 fault f11 "a root partition that holds no file system" "no ext2/3/4"
KVER=6.17.0-9999-gcp fault f12 "a kernel that is not installed" "has no /boot/vmlinuz-6.17.0-9999-gcp"
fault f13 "a malformed salt" "salt must be 64 hex" --salt xyz
fault f14 "a block count below 16384" "at least 16384" --blocks 100
mkfix f15; B="$(snap)"; out="$(bash "$SEAL" --disk "$F/disk.img" --p1 "$F/p1.img" --kver $KV --destructive-ok --no-kernel-test 2>&1)"; rc=$?; chk "fault: neither --esp nor --esp-dir: refuses, and changes nothing" $([ $rc != 0 ] && grep -q 'give --esp' <<<"$out" && [ "$B" = "$(snap)" ]; echo $?)
echo "=== D. the contract between the two scripts: the output of the REAL builder script is accepted by the REAL sealing script"
BKV="$(ls -d /lib/modules/*-gcp 2>/dev/null | xargs -n1 basename 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-gcp$' | sort -V | tail -1)"
if [ -n "$BKV" ] && dpkg -s overlayroot cryptsetup-initramfs busybox-initramfs dmsetup initramfs-tools >/dev/null 2>&1; then
  rm -f /boot/initrd.img-tc /boot/initrd.img-tc.sha256; mkdir -p /boot; touch "/boot/vmlinuz-$BKV"
  bo="$(bash "$I/build/tc-image-sealbake.sh" --kit "$KIT" --kver "$BKV" 2>&1)"; brc=$?
  chk "the real builder script builds a real initramfs and ends with SEALBAKE-OK" $([ $brc = 0 ] && grep -q '^SEALBAKE-OK' <<<"$bo"; echo $?)
  KV_SAVE="$KV"; KV="$BKV"; REAL_BOOT=1 mkfix real; KV="$KV_SAVE"; KVER="$BKV" BLOCKS=32768 seal; unset REAL_BOOT KVER BLOCKS
  chk "the real sealing script accepts that output (its checksum file, its file names, the template that the builder installed) and ends with SEAL-OK" $([ $rc = 0 ] && grep -q '^SEAL-OK roothash=' <<<"$out"; echo $?)
  chk "and the root hash and the real initramfs's checksum are in grub.cfg's report" $(grep -q "^initrd_sha256=$(sha256sum /boot/initrd.img-tc | cut -d' ' -f1)" "$F/out/seal-report.txt" && grep -q 'initrd /boot/initrd.img-tc' "$F/esp/EFI/ubuntu/grub.cfg"; echo $?)
  rm -f "/boot/vmlinuz-$BKV" /boot/initrd.img-tc /boot/initrd.img-tc.sha256; rm -rf /etc/tc/initramfs-tools /etc/tc/grub-sealed.cfg.in; rmdir /etc/tc 2>/dev/null
else echo "  note: no gcp kernel modules or no initramfs packages here, so the contract test is skipped (it needs the builder's tools)"; fi
echo "=== C. the order of the gates, in the script itself"
L() { grep -n "$1" "$SEAL" | head -1 | cut -d: -f1; }
chk "every read-only check comes before the first change: tune2fs and resize2fs and veritysetup format come after the last of gates 1 to 5, and the full verification comes after the hash tree" $(a=$(L 'say "gate 5'); b=$(L 'tune2fs -O'); c=$(L 'resize2fs "\$P1"'); d=$(L 'veritysetup format'); e=$(L 'veritysetup verify'); [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ] && [ "$d" -lt "$e" ]; echo $?)
chk "the real kernel test (gate 8) exists, comes after the verification and before GRUB is written, and the driver never passes --no-kernel-test" $(a=$(L 'say "gate 7'); b=$(L 'veritysetup open'); c=$(L 'say "gate 9'); [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && ! grep -q -- '--no-kernel-test' "$I/test/f03-drive.sh"; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "R3-SEAL-REHEARSAL-PASS"; else echo "R3-SEAL-REHEARSAL-FAIL"; fi
rm -rf "$W"; [ "$FAILN" = 0 ]
