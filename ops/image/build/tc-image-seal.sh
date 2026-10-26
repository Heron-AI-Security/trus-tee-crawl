#!/usr/bin/env bash
# Step R3.3, OFFLINE sealing of a COPY of the builder's boot disk. Run as root on a helper VM that has the copy attached as a second disk (or, in the rehearsal, on file images).
#   tc-image-seal.sh --disk DISK --p1 ROOTPART --esp ESPPART|--esp-dir DIR --kver KVER --destructive-ok [--blocks N] [--salt HEX] [--out DIR] [--no-kernel-test]
# What it does to the root partition: removes the journal, shrinks the ext4 file system to N 4096-byte blocks, builds the dm-verity hash tree right after it (the same partition), and prints the root hash. What it writes to the
# EFI partition: the complete grub.cfg (the root hash is on the kernel command line, which the TDX log measures into RTMR2); the old one is kept as grub.cfg.orig.
# FAIL FAST: every check that can fail is made BEFORE the first change (gates 1 to 5, all read-only, seconds); then the changes (gate 6), the hash tree and its full verification (gate 7), the test through the real kernel (gate 8),
# and the GRUB configuration (gate 9). The first line of every failure is SEAL-STOP, and gates 1 to 5 leave the disk exactly as it was.
set -uo pipefail
DISK=""; P1=""; ESP=""; ESPDIR=""; KVER=""; N=2621440; SALT="$(printf 'tc-sealed-root-salt-v1' | sha256sum | cut -c1-64)"; OUT="${HOME:-/root}"; DESTRUCTIVE=0; KERNELTEST=1
while [ $# -gt 0 ]; do case "$1" in
  --disk) DISK="$2"; shift 2 ;; --p1) P1="$2"; shift 2 ;; --esp) ESP="$2"; shift 2 ;; --esp-dir) ESPDIR="$2"; shift 2 ;; --kver) KVER="$2"; shift 2 ;; --blocks) N="$2"; shift 2 ;;
  --salt) SALT="$2"; shift 2 ;; --out) OUT="$2"; shift 2 ;; --destructive-ok) DESTRUCTIVE=1; shift ;; --no-kernel-test) KERNELTEST=0; shift ;; *) echo "SEAL-STOP: unknown argument $1" >&2; exit 2 ;; esac; done
say() { echo; echo "== $*"; }; ok() { echo "   ok:   $*"; }
W="$(mktemp -d /tmp/seal.XXXXXX)"; MNT=""; VNAME=""
cleanup() { [ -z "$VNAME" ] || { umount "$W/vt" 2>/dev/null; veritysetup close "$VNAME" 2>/dev/null; }; [ -z "$MNT" ] || umount "$MNT" 2>/dev/null; rm -rf "$W"; }
trap cleanup EXIT
die() { echo "SEAL-STOP: $*" >&2; exit 1; }
devsize() { if [ -b "$1" ]; then blockdev --getsize64 "$1"; else stat -c %s "$1"; fi; }
dbg() { debugfs -R "$1" "$P1" 2>/dev/null; }          # read-only look into the root partition without mounting it
dbgexists() { dbg "stat $1" | grep -q '^Inode:'; }
say "gate 1 (read-only, seconds): the arguments and the tools"
[ "$(id -u)" = 0 ] || die "run as root"
[ "$DESTRUCTIVE" = 1 ] || die "this script rewrites the root partition: pass --destructive-ok, and only for a COPY of the builder's disk"
[ -n "$DISK" ] && [ -n "$P1" ] && [ -n "$KVER" ] || die "give --disk, --p1 and --kver"
[ -n "$ESP" ] || [ -n "$ESPDIR" ] || die "give --esp (the EFI partition) or --esp-dir (a folder that holds it)"
[[ "$KVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-gcp$ ]] || die "--kver must look like 6.17.0-1022-gcp"
[[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -ge 16384 ] || die "--blocks must be a number of at least 16384"
[[ "$SALT" =~ ^[0-9a-f]{64}$ ]] || die "--salt must be 64 hex digits"
for t in e2fsck resize2fs tune2fs debugfs dumpe2fs veritysetup sfdisk lsinitramfs grub-script-check blkid sha256sum; do command -v "$t" >/dev/null || die "missing tool: $t"; done
[ -e "$DISK" ] && [ -e "$P1" ] || die "the disk or the root partition does not exist"
ok "arguments and tools; the plan: $N blocks of 4096 bytes ($((N * 4096 / 1048576)) MiB), salt ${SALT:0:16}..., kernel $KVER"
say "gate 2: the partition table is the one of a cloud image (partitions 1, 14 and 15), and the root partition is not in use"
SFD="$(sfdisk -d "$DISK" 2>/dev/null)" || die "cannot read the partition table of $DISK"
NUMS="$(grep -E '^[^ ]+ : start=' <<<"$SFD" | awk '{print $1}' | sed -E 's/.*[^0-9]([0-9]+)$/\1/' | sort -n | tr '\n' ' ')"
[ "$NUMS" = "1 14 15 " ] || die "the partitions are '$NUMS' and not '1 14 15 '"
grep -qi '^[^ ]*[^0-9]1 : .*type=0FC63DAF-8483-4772-8E79-3D69D8477DE4' <<<"$SFD" || die "partition 1 is not a Linux file system partition"
grep -qi '^[^ ]*[^0-9]15 : .*type=C12A7328-F81F-11D2-BA4B-00A0C93EC93B' <<<"$SFD" || die "partition 15 is not an EFI system partition"
PARTUUID="$(grep -E '^[^ ]+[^0-9]1 : start=' <<<"$SFD" | sed -E 's/.*uuid=([0-9A-Fa-f-]+).*/\1/' | tr 'A-F' 'a-f')"; [[ "$PARTUUID" =~ ^[0-9a-f-]{36}$ ]] || die "could not read the PARTUUID of partition 1"
if [ -b "$P1" ]; then
  [ -z "$(findmnt -rn -S "$P1" 2>/dev/null)" ] || die "$P1 is mounted"
  [ "$(readlink -f "$P1")" != "$(readlink -f "$(findmnt -no SOURCE / 2>/dev/null)")" ] || die "$P1 is the root of THIS machine"
fi
ok "partitions 1, 14, 15; partition 1 has the PARTUUID $PARTUUID and is not in use"
say "gate 3: the file system of partition 1"
DH="$(dumpe2fs -h "$P1" 2>/dev/null)" || die "$P1 holds no ext2/3/4 file system"
grep -q '^Filesystem features:.*extent' <<<"$DH" || die "this is not an ext4 file system"
BS="$(awk -F: '/^Block size:/ {gsub(/ /,"",$2); print $2}' <<<"$DH")"; BC="$(awk -F: '/^Block count:/ {gsub(/ /,"",$2); print $2}' <<<"$DH")"; FB="$(awk -F: '/^Free blocks:/ {gsub(/ /,"",$2); print $2}' <<<"$DH")"
FSUUID="$(awk -F: '/^Filesystem UUID:/ {gsub(/ /,"",$2); print $2}' <<<"$DH")"
[ "$BS" = 4096 ] || die "the file system block size is $BS, not 4096"
[ "$BC" -gt "$N" ] || [ "$BC" -eq "$N" ] || die "the file system has $BC blocks, fewer than the plan ($N)"
USED=$((BC - FB)); [ $((USED * 100)) -le $((N * 80)) ] || die "the root uses $((USED * 4096 / 1048576)) MiB: more than 80% of the plan ($((N * 4096 / 1048576)) MiB); raise --blocks"
PS="$(devsize "$P1")"; L=$(( (N + 127) / 128 )); HB=$L; while [ "$L" -gt 1 ]; do L=$(( (L + 127) / 128 )); HB=$((HB + L)); done; NEED=$((N * 4096 + HB * 4096 + 1048576))
[ "$PS" -ge "$NEED" ] || die "partition 1 has $((PS / 1048576)) MiB, and the data plus the hash tree need $((NEED / 1048576)) MiB"
ok "ext4, 4096-byte blocks, UUID $FSUUID, uses $((USED * 4096 / 1048576)) MiB of the $((N * 4096 / 1048576)) MiB plan; the hash tree ($((HB * 4096 / 1048576)) MiB) fits behind it"
say "gate 4: what is INSIDE partition 1 (read with debugfs, nothing is mounted)"
for f in "/boot/vmlinuz-$KVER" /boot/initrd.img-tc /boot/initrd.img-tc.sha256 /etc/tc/grub-sealed.cfg.in /etc/os-release; do dbgexists "$f" || die "partition 1 has no $f (was the sealed initramfs built on the builder?)"; done
dbg "dump /boot/initrd.img-tc $W/initrd" >/dev/null; [ -s "$W/initrd" ] || die "could not read the initramfs"
WANT="$(dbg 'cat /boot/initrd.img-tc.sha256' | awk '{print $1}')"; HAVE="$(sha256sum "$W/initrd" | cut -d' ' -f1)"; [ "$WANT" = "$HAVE" ] || die "the initramfs differs from the one that the builder verified (${HAVE:0:16} against ${WANT:0:16})"
lsinitramfs "$W/initrd" > "$W/ls.txt" 2>/dev/null || die "the initramfs cannot be listed"
for p in 'scripts/local-top/tc-verity$' 'scripts/local-top/tc-scratch-dev$' 'scripts/init-bottom/tc-scratch-bind$' 'scripts/init-bottom/overlayroot$' 'dm-verity\.ko' 'dm-integrity\.ko' 'dm-crypt\.ko' 'dm-bufio\.ko'; do grep -qE "$p" "$W/ls.txt" || die "the initramfs lacks $p"; done
dbg "cat /etc/tc/grub-sealed.cfg.in" > "$W/tpl"; render() { sed -e "s#@ROOTFS_UUID@#$FSUUID#g" -e "s#@KVER@#$KVER#g" -e "s#@ROOTHASH@#$1#g" -e "s#@BLOCKS@#$N#g" -e "s#@SALT@#$SALT#g" -e "s#@DATA_PARTUUID@#$PARTUUID#g" "$W/tpl"; }
for p in ROOTFS_UUID KVER ROOTHASH BLOCKS SALT DATA_PARTUUID; do grep -q "@$p@" "$W/tpl" || die "the GRUB template has no @$p@"; done
render "$(printf '%064d' 0)" > "$W/grub.dry"; ! grep -q '@' "$W/grub.dry" || die "the rendered GRUB configuration still has a placeholder"
grub-script-check "$W/grub.dry" || die "the GRUB configuration does not parse (grub-script-check)"
ok "kernel, initramfs (checksum equal to the builder's, with the verity script, the two scratch scripts, the overlay script and the four modules), os-release, and a GRUB template that parses"
say "gate 5: the EFI partition"
if [ -n "$ESPDIR" ]; then ESPM="$ESPDIR"; else MNT="$W/esp"; mkdir -p "$MNT"; mount -t vfat -o rw,umask=0077 "$ESP" "$MNT" || die "cannot mount the EFI partition $ESP"; ESPM="$MNT"; fi
[ -f "$ESPM/EFI/ubuntu/grub.cfg" ] && [ -f "$ESPM/EFI/ubuntu/grubx64.efi" ] || die "the EFI partition has no EFI/ubuntu/grub.cfg and grubx64.efi"
: > "$ESPM/EFI/ubuntu/.tc-write-test" 2>/dev/null && rm -f "$ESPM/EFI/ubuntu/.tc-write-test" || die "the EFI partition is not writable"
ok "EFI/ubuntu/grub.cfg and grubx64.efi are there, and the partition is writable (everything above this line left the disk unchanged)"
say "gate 6: the first change: remove the journal and shrink the file system to $N blocks"
e2fsck -fy "$P1" >"$W/fsck1.log" 2>&1; [ $? -le 1 ] || { tail -5 "$W/fsck1.log"; die "e2fsck found damage that it could not repair"; }
tune2fs -O ^has_journal "$P1" >"$W/tune.log" 2>&1 || { tail -5 "$W/tune.log"; die "tune2fs could not remove the journal"; }
e2fsck -fy "$P1" >"$W/fsck2.log" 2>&1; [ $? -le 1 ] || { tail -5 "$W/fsck2.log"; die "e2fsck after tune2fs failed"; }
if [ "$BC" -gt "$N" ]; then resize2fs "$P1" "$N" >"$W/resize.log" 2>&1 || { tail -5 "$W/resize.log"; die "resize2fs failed"; }; fi
e2fsck -fn "$P1" >"$W/fsck3.log" 2>&1 || { tail -5 "$W/fsck3.log"; die "the file system is not clean after the shrink"; }
DH2="$(dumpe2fs -h "$P1" 2>/dev/null)"; [ "$(awk -F: '/^Block count:/ {gsub(/ /,"",$2); print $2}' <<<"$DH2")" = "$N" ] || die "the file system does not have $N blocks"
! grep -q '^Filesystem features:.*has_journal' <<<"$DH2" || die "the journal is still there"
ok "no journal, $N blocks, clean (a sealed root is read-only, so it needs no journal)"
say "gate 7: the dm-verity hash tree after the data, and its full verification (this reads the whole $((N * 4096 / 1048576)) MiB)"
VARGS=(--no-superblock --hash=sha256 --data-block-size=4096 --hash-block-size=4096 --data-blocks="$N" --hash-offset=$((N * 4096)) --salt="$SALT")
veritysetup format "${VARGS[@]}" "$P1" "$P1" >"$W/verity.log" 2>&1 || { tail -8 "$W/verity.log"; die "veritysetup format failed"; }
ROOTHASH="$(awk '/^Root hash:/ {print $3}' "$W/verity.log")"; [[ "$ROOTHASH" =~ ^[0-9a-f]{64}$ ]] || { tail -8 "$W/verity.log"; die "no root hash in the output of veritysetup"; }
veritysetup verify "${VARGS[@]}" "$P1" "$P1" "$ROOTHASH" >"$W/verify.log" 2>&1 || { tail -5 "$W/verify.log"; die "the hash tree does not verify"; }
ok "root hash $ROOTHASH; the tree verifies against all the data"
if [ "$KERNELTEST" = 1 ]; then
  say "gate 8: the same device through the real kernel: open it as the initramfs will, mount it read-only, read a file"
  VNAME="tcseal-test"; veritysetup open "${VARGS[@]}" "$P1" "$VNAME" "$P1" "$ROOTHASH" >"$W/open.log" 2>&1 || { tail -5 "$W/open.log"; die "the kernel refused to open the verity device"; }
  mkdir -p "$W/vt"; mount -o ro "/dev/mapper/$VNAME" "$W/vt" || die "cannot mount the verity device read-only"
  grep -q '^NAME="Ubuntu"' "$W/vt/etc/os-release" && [ -f "$W/vt/boot/initrd.img-tc" ] && [ -f "$W/vt/boot/vmlinuz-$KVER" ] || die "the verity device does not show the expected files"
  ! touch "$W/vt/.write-test" 2>/dev/null || die "the verity device is writable"
  umount "$W/vt"; veritysetup close "$VNAME"; VNAME=""
  ok "the kernel opens it, mounts it read-only, and shows os-release, the kernel and the initramfs; a write is refused"
else
  say "gate 8: skipped (--no-kernel-test): the kernel's dm-verity is not available here"
fi
say "gate 9: the GRUB configuration on the EFI partition"
render "$ROOTHASH" > "$W/grub.new"; ! grep -q '@' "$W/grub.new" || die "a placeholder is left in the GRUB configuration"
[ "$(grep -c "tc.verity=$ROOTHASH" "$W/grub.new")" = 1 ] || die "the root hash is not exactly once on the kernel command line"
grub-script-check "$W/grub.new" || die "the final GRUB configuration does not parse"
[ -f "$ESPM/EFI/ubuntu/grub.cfg.orig" ] || cp -p "$ESPM/EFI/ubuntu/grub.cfg" "$ESPM/EFI/ubuntu/grub.cfg.orig"
cp "$W/grub.new" "$ESPM/EFI/ubuntu/grub.cfg.tmp" && mv "$ESPM/EFI/ubuntu/grub.cfg.tmp" "$ESPM/EFI/ubuntu/grub.cfg" && sync
cmp -s "$W/grub.new" "$ESPM/EFI/ubuntu/grub.cfg" || die "the written grub.cfg is not what was generated"
ok "grub.cfg written and read back (the old one is kept as grub.cfg.orig); the root hash is on the kernel command line once"
mkdir -p "$OUT"; { echo "roothash=$ROOTHASH"; echo "blocks=$N"; echo "salt=$SALT"; echo "data_partuuid=$PARTUUID"; echo "rootfs_uuid=$FSUUID"; echo "kver=$KVER"; echo "initrd_sha256=$HAVE"; echo "grub_cfg_sha256=$(sha256sum "$W/grub.new" | cut -d' ' -f1)"; } > "$OUT/seal-report.txt"
sync
echo; echo "SEAL-OK roothash=$ROOTHASH blocks=$N rootfs_uuid=$FSUUID data_partuuid=$PARTUUID"
