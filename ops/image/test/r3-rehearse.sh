#!/usr/bin/env bash
# Rehearsal of step R3 (the verity root and the encrypted scratch disk), piece by piece as the pieces are built. Now: R3.1, the read-only probe and the driver's spare disk.
#   bash r3-rehearse.sh KITDIR
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; T="$I/test"; PASS=0; FAILN=0
chk() { local t="$1"; shift; if [ "${1:-1}" = 0 ]; then echo "  pass: $t"; PASS=$((PASS+1)); else echo "  FAIL: $t"; FAILN=$((FAILN+1)); fi; }
W="$(mktemp -d)"; TREE0="$(cd "$KIT" && find ops -type f -not -path '*/__pycache__/*' | sort | xargs -d '\n' sha256sum | sha256sum)"   # the rehearsal must leave the tested tree as it found it
echo "=== R3.1 the probe"
bash "$T/r3-disks.sh" > "$W/probe.txt" 2>&1; rc=$?
chk "the probe finishes in an environment where most of its tools and disks are missing (it must never stop half way)" $([ $rc = 0 ] && tail -1 "$W/probe.txt" | grep -q 'R3-DISKS-DONE'; echo $?)
chk "it prints all eight sections (the machine, the disks, the root disk, GRUB's files, the initramfs tooling, mkinitramfs, the kernel's modules and settings, what the boot writes)" $([ "$(grep -c '^== ' "$W/probe.txt")" = 8 ]; echo $?)
lint_ro() { # FILE: 0 when the script cannot write: no destructive tool is RUN (a tool that is only looked up with command -v does not count), no redirection into a file, apt only in simulation
  local S; S="$(grep -v '^[[:space:]]*#' "$1" | grep -v '^for t in ' | sed -e 's/2>&1//g' -e 's#>/dev/null##g' -e 's#2>/dev/null##g' -e 's#/usr/sbin/mkinitramfs##g' -e 's/"[^"]*"//g')"
  ! grep -E '\b(rm|mkfs[a-z.0-9]*|dd|mount|umount|losetup|tee|truncate|wipefs|resize2fs|e2fsck|mkinitramfs|update-initramfs|update-grub|systemctl (start|stop|enable|disable))\b' <<<"$S" >/dev/null \
    && ! grep -E '(cryptsetup|veritysetup|integritysetup) +(open|create|format|luks[A-Za-z]*|close|remove|resize|reencrypt|erase|repair)' <<<"$S" >/dev/null \
    && ! grep '>' <<<"$S" >/dev/null && ! grep -E 'tune2fs +-[^l]|sfdisk +-[^d]|sfdisk +[^-]|udevadm +(trigger|control|settle)' <<<"$S" >/dev/null \
    && [ "$(grep -v '^[[:space:]]*#' "$1" | grep -o 'apt-get[^|;]*' | grep -vc 'apt-get -s ')" = 0 ] && ! grep -v '^[[:space:]]*#' "$1" | grep -qE 'apt(-get)? +(install|update|upgrade|remove)|apt +-s'; }
chk "it is read-only: no destructive tool is run, no redirection into a file, apt only as a simulation, and tune2fs, sfdisk and udevadm only list" $(lint_ro "$T/r3-disks.sh"; echo $?)
for m in 'rm -rf /tmp/x' 'echo x | tee /etc/x' 'echo x > /etc/y' 'apt-get install -y cryptsetup-bin' 'mkfs.ext4 /dev/nvme0n2' 'tune2fs -O ^has_journal /dev/nvme0n1p1' 'cryptsetup luksFormat /dev/nvme0n2' 'mount /dev/nvme0n2 /mnt'; do
  { cat "$T/r3-disks.sh"; echo "$m"; } > "$W/bad.sh"; chk "the lint catches a probe that does: $m" $(lint_ro "$W/bad.sh" && echo 1 || echo 0); done
echo "=== R3.1 the driver's spare disk"
export DRY=1 IMG=tc-img-x OUT="$W/out"; mkdir -p "$OUT"
out="$(BUILDER=tc-probe3 BUILDER_FROM=tc-img-dbg-5 EXTRA_DISK_GB=10 timeout 60 bash "$T/f03-drive.sh" builder 2>&1)"; L="$(grep 'DRY: gcloud compute instances create' <<<"$out" | sed 's/\\//g')"   # a dry run shows commas as \\,
chk "with EXTRA_DISK_GB=10 the probe VM is created from the image with a spare disk of that size, named after the VM, with the device name tcscratch, deleted with the VM" $(grep -q -- '--create-disk=name=tc-probe3-scratch,size=10GB,type=pd-balanced,device-name=tcscratch,auto-delete=yes' <<<"$L" && grep -q -- '--image=tc-img-dbg-5' <<<"$L" && grep -q 'create tc-probe3 ' <<<"$L"; echo $?)
chk "the real builder is not mentioned in the creation of the probe VM (it cannot be touched by it)" $(! grep -q 'tc-builder' <<<"$L"; echo $?)
out="$(timeout 60 bash "$T/f03-drive.sh" builder 2>&1)"; chk "without EXTRA_DISK_GB there is no spare disk (the old behavior is unchanged)" $(! grep -q -- '--create-disk' <<<"$out"; echo $?)
chk "the stage r3-disks is in the stage list at the top of the driver and in its case" $(grep -q '^# Stages: builder | r3-disks |' "$T/f03-drive.sh" && grep -q '^    r3-disks)' "$T/f03-drive.sh"; echo $?)
chk "the probe VM is deleted by its exact name only: the stage delete needs CONFIRM=yes and names the VMs of this driver (no pattern)" $(grep -A1 '^    delete)' "$T/f03-drive.sh" | grep -q 'CONFIRM:-}" = yes' && ! grep -E 'instances delete .*(\*|--filter)' "$T/f03-drive.sh" >/dev/null; echo $?)
echo "=== R3.2 the initramfs scripts (the real scripts under dash, with a fake sysfs, fake block devices and stand-in tools; the real device-mapper is for the cluster)"
IT="$I/rootfs/etc/tc/initramfs-tools"; SB="$W/sb"; mkdir -p "$SB"
if ! mknod "$W/probe-node" b 259 9 2>/dev/null; then echo "  FAIL: this rehearsal needs root (it makes fake block devices with mknod)"; exit 2; fi; rm -f "$W/probe-node"
for t in modprobe udevadm; do printf '#!/bin/sh\necho "%s $*" >> "${LOG:-/dev/null}"\nexit 0\n' "$t" > "$SB/$t"; done
cat > "$SB/sleep" <<'EOS'
#!/bin/sh
# the stand-in for sleep: no wait, except where a test needs time to pass (SLEEPT); in a "late disk" test the first sleep makes the spare disk appear
if [ -e "$E/late" ] && [ ! -e "$E/late.done" ]; then touch "$E/late.done"; mkdir -p "$E/sys/devices/pci0/nvme0n2/queue"; echo 20971520 > "$E/sys/devices/pci0/nvme0n2/size"; echo 2199023255040 > "$E/sys/devices/pci0/nvme0n2/queue/discard_max_bytes"; ln -s ../devices/pci0/nvme0n2 "$E/sys/block/nvme0n2"; mknod "$E/dev/nvme0n2" b 259 4; fi
exec /bin/sleep "${SLEEPT:-0}"
EOS
printf '#!/bin/sh\necho "poweroff $*" >> "$LOG"; touch "$E/poweroff"\nexit 0\n' > "$SB/poweroff"
printf '#!/bin/sh\necho "veritysetup $*" >> "$LOG"\n[ -z "${HANG_VERITY:-}" ] || exec /bin/sleep 1000\n[ -z "${FAIL_VERITY:-}" ]\n' > "$SB/veritysetup"
printf '#!/bin/sh\necho "mke2fs $*" >> "$LOG"\n[ -z "${HANG_MKE2FS:-}" ] || exec /bin/sleep 1000\n[ -z "${FAIL_MKE2FS:-}" ]\n' > "$SB/mke2fs"
printf '#!/bin/sh\necho "mount $*" >> "$LOG"\n[ -z "${HANG_MOUNT:-}" ] || exec /bin/sleep 1000\n[ -z "${HANG_MOUNT_ON:-}" ] || case "$*" in *"$HANG_MOUNT_ON"*) exec /bin/sleep 1000;; esac\n[ -z "${FAIL_MOUNT_ON:-}" ] || case "$*" in *"$FAIL_MOUNT_ON"*) exit 1;; esac\n[ -z "${FAIL_MOUNT:-}" ]\n' > "$SB/mount"
cat > "$SB/blkid" <<'EOS'
#!/bin/sh
case " $* " in *" TYPE "*) printf '%s' "${FAKE_SIG:-}" ;; *" PTTYPE "*) printf '%s' "${FAKE_PT:-}" ;; esac; exit 0
EOS
cat > "$SB/cryptsetup" <<'EOS'
#!/bin/sh
echo "cryptsetup $*" >> "$LOG"
case "$1" in
  open) [ -z "${HANG_OPEN:-}" ] || exec /bin/sleep 1000; [ -z "${FAIL_OPEN:-}" ] || exit 1; prev=""; for a in "$@"; do [ "$prev" = --key-file ] && [ -f "$a" ] && cp "$a" "$E/kccopy"; prev="$a"; done; mknod "$E/dev/mapper/tc-scratch" b 259 8 ;;
esac; exit 0
EOS
cat > "$SB/integritysetup" <<'EOS'
#!/bin/sh
echo "integritysetup $*" >> "$LOG"
case "$1" in
  format) [ -z "${HANG_INTFORMAT:-}" ] || exec /bin/sleep 1000; [ -z "${FAIL_INTFORMAT:-}" ] || exit 1; prev=""; for a in "$@"; do [ "$prev" = --integrity-key-file ] && [ -f "$a" ] && cp "$a" "$E/kicopy"; prev="$a"; done ;;
  open) [ -z "${HANG_INTOPEN:-}" ] || exec /bin/sleep 1000; [ -z "${FAIL_INTOPEN:-}" ] || exit 1; mknod "$E/dev/mapper/tc-int" b 259 9 ;;
esac; exit 0
EOS
printf '#!/bin/sh\necho "blkdiscard $*" >> "$LOG"\n[ -z "${HANG_DISCARD:-}" ] || exec /bin/sleep 1000\n[ -z "${FAIL_DISCARD:-}" ]\n' > "$SB/blkdiscard"
chmod +x "$SB"/*
PU="67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8"; RH="$(printf '%064d' 0 | tr 0 a)"; SL="$(printf '%064d' 0 | tr 0 b)"
mkenv() { E="$W/e$1"; rm -rf "$E"; mkdir -p "$E/proc" "$E/dev/disk/by-partuuid" "$E/dev/mapper" "$E/run" "$E/scratch" "$E/root/var/lib/hadoop/datanode" "$E/root/var/lib/hadoop/namenode" "$E/root/var/log" "$E/root/tmp" "$E/sys/class/block" "$E/sys/block" "$E/sys/devices/pci0/nvme0n1/nvme0n1p1" "$E/sys/devices/pci0/nvme0n1/nvme0n1p14" "$E/sys/devices/pci0/nvme0n1/nvme0n1p15" "$E/sys/devices/pci0/nvme0n2"
  ln -s ../../devices/pci0/nvme0n1/nvme0n1p1 "$E/sys/class/block/nvme0n1p1"; ln -s ../devices/pci0/nvme0n1 "$E/sys/block/nvme0n1"; ln -s ../devices/pci0/nvme0n2 "$E/sys/block/nvme0n2"
  echo 62914560 > "$E/sys/devices/pci0/nvme0n1/size"; echo 20971520 > "$E/sys/devices/pci0/nvme0n2/size"; mkdir -p "$E/sys/devices/pci0/nvme0n2/queue"; echo "${DISCARD_MAX:-2199023255040}" > "$E/sys/devices/pci0/nvme0n2/queue/discard_max_bytes"
  mknod "$E/dev/nvme0n1p1" b 259 1; mknod "$E/dev/nvme0n2" b 259 4; ln -s ../../nvme0n1p1 "$E/dev/disk/by-partuuid/$PU"
  echo "console=ttyS0,115200 root=/dev/mapper/vroot ro overlayroot=tmpfs tc.verity=$RH tc.data=$PU tc.blocks=2621440 tc.salt=$SL" > "$E/proc/cmdline"
  echo keep > "$E/root/var/lib/hadoop/datanode/keep"; echo line > "$E/root/var/log/syslog"; chmod 750 "$E/root/var/lib/hadoop" "$E/root/var/lib/hadoop/datanode"; chmod 1777 "$E/root/tmp"; : > "$E/log"; }
tx() { # SCRIPT NAME: a copy of the script whose ONE line of path assignments points into the fake tree $E (and the time limit is 3 seconds); nothing else changes
  sed -e "s#^\(CMDLINE\|DEVDIR\)=.*#CMDLINE=$E/proc/cmdline; SYSFS=$E/sys; DEVDIR=$E/dev; PARTUUIDDIR=$E/dev/disk/by-partuuid; RUNDIR=$E/run; SCRATCH=$E/scratch; CONSOLE=$E/console; SYSRQ=$E/sysrq; MINSECTORS=2097152; TMO=3; WAITDISK=3; WIPETMO=4#" "$1" > "$W/$2.t"; }
run() { # SCRIPT NAME [VAR=VALUE ...]: run the transformed copy under dash, with the stand-in tools first in the path
  local s="$1" n="$2"; shift 2; tx "$s" "$n"; t0=$(date +%s); out="$(env "$@" PATH="$SB:$PATH" LOG="$E/log" E="$E" rootmnt="$E/root" timeout 60 dash "$W/$n.t" 2>&1)"; rc=$?; el=$(( $(date +%s) - t0 )); }
V="$IT/scripts/local-top/tc-verity"; SD="$IT/scripts/local-top/tc-scratch-dev"; BD="$IT/scripts/init-bottom/tc-scratch-bind"
echo "--- the files"
chk "the files of the sealed boot parse under dash (the shell of the initramfs)" $(ok=0; for f in "$IT/hooks/tc-seal" "$V" "$SD" "$BD"; do dash -n "$f" || ok=1; done; echo $ok)
chk "the hook adds the modules dm_verity and dm_integrity (not in the stock initramfs), dm_crypt, dm_bufio, authenc and overlay, and the tools veritysetup, cryptsetup, mke2fs and blkid; MODULES=list" $(h="$IT/hooks/tc-seal"; ok=0; for m in dm_bufio dm_verity dm_crypt dm_integrity authenc overlay; do grep -q "manual_add_modules.* $m" "$h" || ok=1; grep -qx "$m" "$IT/modules" || ok=1; done; for b in veritysetup cryptsetup mke2fs blkid; do grep -q "copy_exec /usr/sbin/$b" "$h" || ok=1; done; grep -qx 'MODULES=list' "$IT/initramfs.conf" || ok=1; echo $ok)
mkenv 0; for pair in "$V:v0" "$SD:d0" "$BD:b0"; do tx "${pair%%:*}" "${pair##*:}"; n="$(diff "${pair%%:*}" "$W/${pair##*:}.t" | grep -c '^[<>]')"; chk "the test copy of $(basename "${pair%%:*}") differs from the real script in ONE line only (the path assignments): $n lines changed" $([ "$n" = 2 ]; echo $?); done
echo "--- tc-verity (local-top)"
mkenv 1; run "$V" v1; chk "the happy path: exit 0, dm_verity is loaded, and veritysetup opens the root partition once with the root hash, the salt, the size and the hash tree after the data" $([ $rc = 0 ] && [ "$(grep -c '^veritysetup open' "$E/log")" = 1 ] && grep -q "^veritysetup open --no-superblock --hash=sha256 --data-block-size=4096 --hash-block-size=4096 --data-blocks=2621440 --hash-offset=10737418240 --salt=$SL $E/dev/nvme0n1p1 vroot $E/dev/nvme0n1p1 $RH\$" "$E/log" && grep -q '^modprobe dm_verity' "$E/log" && [ ! -e "$E/poweroff" ]; echo $?)
chk "it prints a progress line before the slow step, and its only tc-verity: line is the success line (the watcher must not see a failure in a progress line)" $(grep -q '^tc-seal: verity: opening the root partition' <<<"$out" && [ "$(grep -c '^tc-verity: ' <<<"$out")" = 1 ] && grep -q '^tc-verity: the root disk matches the root hash' <<<"$out"; echo $?)
chk "it records what it did for the report (root_verity=ok and the root hash)" $(grep -q "^root_verity=ok roothash=$RH" "$E/run/tc-seal.state"; echo $?)
chk "an upper-case PARTUUID on the command line finds the same partition" $(mkenv 1b; sed -i "s/$PU/$(echo $PU | tr a-f A-F)/" "$E/proc/cmdline"; run "$V" v1b; [ $rc = 0 ] && grep -q '^veritysetup open' "$E/log"; echo $?)
vfault() { mkenv "$1"; [ -z "${4:-}" ] || sed -i "$4" "$E/proc/cmdline"; run "$V" "v$1" ${5:-X=1}; chk "fault: $2: powers off with the reason, and opens nothing" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q "$3" <<<"$out" && ! grep -q '^veritysetup' "$E/log"; echo $?); }
vfault f1 "no root hash on the command line" "no valid tc.verity" 's/tc.verity=[^ ]*//'
vfault f2 "a root hash that is not 64 hex digits" "tc.verity is not 64 hex digits" "s/tc.verity=$RH/tc.verity=abc/"
vfault f3 "a root hash with a character that is not hex" "no valid tc.verity" "s/tc.verity=a/tc.verity=g/"
vfault f4 "a block count that is not a number" "no valid tc.blocks" 's/tc.blocks=2621440/tc.blocks=26x/'
vfault f5 "no salt" "no valid tc.salt" 's/tc.salt=[^ ]*//'
mkenv f6; rm "$E/dev/disk/by-partuuid/$PU"; run "$V" vf6; chk "fault: the root partition never appears: powers off after the wait, and opens nothing" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q 'did not appear' <<<"$out" && ! grep -q '^veritysetup' "$E/log"; echo $?)
mkenv f7; run "$V" vf7 FAIL_VERITY=1; chk "fault: a root disk that does not match the root hash (veritysetup fails): powers off, says so, and writes no state" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q 'does not match the root hash' <<<"$out" && [ ! -e "$E/run/tc-seal.state" ]; echo $?)
mkenv f8; run "$V" vf8 HANG_VERITY=1 SLEEPT=0.3; chk "fault: a veritysetup that HANGS: the time limit turns it into a clear failure and a power-off, in seconds, and no state is written" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q 'veritysetup hung for 3 seconds' <<<"$out" && [ "$el" -le 8 ] && [ ! -e "$E/run/tc-seal.state" ]; echo $?)
chk "tc-verity never formats or writes: it calls veritysetup open and nothing that creates or changes a disk" $(! grep -v '^#' "$V" | grep -E 'veritysetup +(format|create|resize)|cryptsetup|mke2fs|mkfs|\bdd\b|wipefs' >/dev/null; echo $?)
echo "--- tc-scratch-dev (local-top, the disk: dm-integrity HMAC under dm-crypt, initialised by discard)"
mkenv 2; run "$SD" d2; L="$E/log"
chk "the happy path: exit 0, and the one spare NVMe disk (nvme0n2) gets dm-integrity with HMAC-SHA256 (key size 32, sector size 4096, no wipe)" $([ $rc = 0 ] && grep -q "^integritysetup format --batch-mode --integrity hmac-sha256 --integrity-key-file $E/run/tc-scratch.ki --integrity-key-size 32 --sector-size 4096 --no-wipe $E/dev/nvme0n2\$" $L && [ ! -e "$E/poweroff" ]; echo $?)
chk "the integrity layer is opened with no journal and with discards allowed, and the whole device is then marked as valid zeros (blkdiscard --force), BEFORE anything reads it" $(grep -q "^integritysetup open --integrity hmac-sha256 --integrity-key-file $E/run/tc-scratch.ki --integrity-key-size 32 --integrity-no-journal --allow-discards $E/dev/nvme0n2 tc-int\$" $L && grep -q "^blkdiscard --force $E/dev/mapper/tc-int\$" $L; echo $?)
chk "the encryption layer is plain dm-crypt, aes-xts-plain64, a 512-bit key, 4096-byte sectors, on top of the integrity device" $(grep -q "^cryptsetup open --type plain --cipher aes-xts-plain64 --key-file $E/run/tc-scratch.kc --key-size 512 --sector-size 4096 $E/dev/mapper/tc-int tc-scratch\$" $L; echo $?)
chk "then an ext4 file system without a journal, with the inode tables written (lazy_itable_init=0: reading a discarded sector gives garbage after decryption, not zeros)" $(grep -q "^mke2fs -q -t ext4 -F -m 0 -O ^has_journal -E lazy_itable_init=0,lazy_journal_init=0,nodiscard -L tc-scratch $E/dev/mapper/tc-scratch\$" $L; echo $?)
chk "the order is: integrity format, integrity open, discard, encryption open, mke2fs (and no mount here: the root is not mounted yet)" $(a=$(grep -n '^integritysetup format' $L | cut -d: -f1); b=$(grep -n '^integritysetup open' $L | cut -d: -f1); c=$(grep -n '^blkdiscard' $L | cut -d: -f1); d=$(grep -n '^cryptsetup open' $L | cut -d: -f1); e=$(grep -n '^mke2fs' $L | cut -d: -f1); [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && [ "$c" -lt "$d" ] && [ "$d" -lt "$e" ] && ! grep -q '^mount' $L; echo $?)
chk "it prints a progress line for every step, and prints NO line that starts with tc-scratch: (so a progress line cannot look like a failure to the watcher)" $([ "$(grep -c '^tc-seal: scratch: ' <<<"$out")" -ge 7 ] && ! grep -q '^tc-scratch: ' <<<"$out"; echo $?)
chk "there are two different keys (32 and 64 bytes), and both are gone after the use" $([ "$(wc -c < "$E/kicopy")" = 32 ] && [ "$(wc -c < "$E/kccopy")" = 64 ] && [ ! -e "$E/run/tc-scratch.ki" ] && [ ! -e "$E/run/tc-scratch.kc" ]; echo $?)
cp "$E/kicopy" "$W/ki1"; cp "$E/kccopy" "$W/kc1"; mkenv 2b; run "$SD" d2b; chk "the keys are random: a second boot makes other keys" $(! cmp -s "$W/ki1" "$E/kicopy" && ! cmp -s "$W/kc1" "$E/kccopy"; echo $?)
chk "it records the scratch disk, the layers and that the keys are ephemeral" $(grep -q 'scratch=nvme0n2 layout=dm-integrity(hmac-sha256,no-journal)+dm-crypt(aes-xts-plain64,plain) key=ephemeral' "$E/run/tc-seal.state"; echo $?)
mkenv 3; run "$SD" d3 FAKE_SIG=DM_integrity; chk "the integrity superblock of the last boot (the scratch disk of an earlier run) is accepted: it is formatted again" $([ $rc = 0 ] && grep -q 'integritysetup format' "$E/log"; echo $?)
dfault() { local n="$1" d="$2" w="$3"; shift 3; run "$SD" "d$n" "$@"; chk "fault: $d: powers off with the reason, and never formats" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q "$w" <<<"$out" && ! grep -q 'integritysetup\|cryptsetup\|mke2fs' "$E/log"; echo $?); }
mkenv f1; dfault f1 "a spare disk that holds an ext4 file system (a wrong disk must not be wiped)" "it is not wiped" FAKE_SIG=ext4
mkenv f1b; dfault f1b "a spare disk with a LUKS header (the old design is gone; nothing of ours writes it any more)" "it is not wiped" FAKE_SIG=crypto_LUKS
mkenv f2; dfault f2 "a spare disk that holds a partition table" "it is not wiped" FAKE_PT=gpt
mkenv f3; rm -rf "$E/sys/devices/pci0/nvme0n2" "$E/sys/block/nvme0n2"; dfault f3 "no spare disk at all, even after the wait" "and I found 0"
mkenv f4; mkdir -p "$E/sys/devices/pci0/nvme0n3"; echo 20971520 > "$E/sys/devices/pci0/nvme0n3/size"; ln -s ../devices/pci0/nvme0n3 "$E/sys/block/nvme0n3"; mknod "$E/dev/nvme0n3" b 259 7; dfault f4 "two spare disks (it must not guess)" "and I found 2"
mkenv f5; echo 2048 > "$E/sys/devices/pci0/nvme0n2/size"; dfault f5 "a spare disk smaller than 1 GiB" "smaller than 1 GiB"
mkenv f6b; mkdir -p "$E/sys/devices/pci0/nvme0n2/nvme0n2p1"; dfault f6 "a spare disk that already has a partition (so it is not a candidate)" "and I found 0"
mkenv f7b; sed -i 's/ tc.data=[^ ]*//' "$E/proc/cmdline"; dfault f7 "no tc.data on the command line (the root's disk is unknown)" "no tc.data"
mkenv late1; rm -rf "$E/sys/devices/pci0/nvme0n2" "$E/sys/block/nvme0n2" "$E/dev/nvme0n2"; touch "$E/late"; run "$SD" dlate; chk "the second NVMe namespace appears a moment AFTER the script starts (a race on the real machine): the script waits for it, says so, and then works" $([ $rc = 0 ] && grep -q 'the spare disk appeared after 1 seconds' <<<"$out" && grep -q 'integritysetup format' "$E/log" && [ ! -e "$E/poweroff" ]; echo $?)
sfault() { local n="$1" what="$2" w="$3" nxt="$4"; shift 4; mkenv "$n"; run "$SD" "d$n" "$@"; chk "fault: $what fails: powers off with '$w', both key files are removed, and $nxt never runs" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q "$w" <<<"$out" && [ ! -e "$E/run/tc-scratch.ki" ] && [ ! -e "$E/run/tc-scratch.kc" ] && ! grep -q "$nxt" "$E/log"; echo $?); }
sfault s1 "integritysetup format" "integritysetup format failed or hung" "integritysetup open" FAIL_INTFORMAT=1
sfault s2 "integritysetup open" "integritysetup open failed or hung" "blkdiscard" FAIL_INTOPEN=1
sfault s3 "the discard" "blkdiscard failed or hung" "cryptsetup open" FAIL_DISCARD=1
sfault s4 "cryptsetup open" "cryptsetup open failed or hung" "mke2fs" FAIL_OPEN=1
sfault s5 "mke2fs" "mke2fs failed or hung" "zzz-nothing-follows" FAIL_MKE2FS=1
hfault() { local n="$1" step="$2" w="$3"; shift 3; mkenv "$n"; run "$SD" "d$n" "$@" SLEEPT=0.3; chk "fault: $step HANGS: the time limit makes it a clear failure ('$w'), in seconds, with a power-off, and no key left behind" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q "^tc-scratch: .*$w" <<<"$out" && [ "$el" -le 10 ] && [ ! -e "$E/run/tc-scratch.ki" ] && [ ! -e "$E/run/tc-scratch.kc" ]; echo $?); }
hfault h1 "integritysetup format" "integritysetup format failed or hung" HANG_INTFORMAT=1
hfault h2 "integritysetup open" "integritysetup open failed or hung" HANG_INTOPEN=1
hfault h3 "the discard" "blkdiscard failed or hung" HANG_DISCARD=1
hfault h4 "cryptsetup open" "cryptsetup open failed or hung" HANG_OPEN=1
hfault h5 "mke2fs" "mke2fs failed or hung" HANG_MKE2FS=1
chk "the guard comes before the first write (the signature check is above integritysetup format), the script never mounts or calls veritysetup, and it never uses LUKS or the recalculate option (the kernel refuses recalculate with HMAC, and LUKS integrity needs a full wipe before the first read)" $(a=$(grep -n 'blkid' "$SD" | head -1 | cut -d: -f1); b=$(grep -n 'integritysetup format' "$SD" | grep -v '^[0-9]*:#' | head -1 | cut -d: -f1); [ "$a" -lt "$b" ] && ! grep -v '^[[:space:]]*#' "$SD" | grep -qE '(^|[ ;])mount |veritysetup|luksFormat|--type luks|integrity-recalculate|integrity-no-wipe'; echo $?)
mkenv nd; echo 0 > "$E/sys/devices/pci0/nvme0n2/queue/discard_max_bytes"; run "$SD" dnd; L="$E/log"
chk "a spare disk WITHOUT discard support: it says so (a warning line, naming the slow way), formats WITHOUT --no-wipe, opens WITHOUT --allow-discards, never calls blkdiscard, and still ends with the encryption layer and the file system" $([ $rc = 0 ] && grep -q 'does not support discard: the integrity tags are initialised by writing the whole disk' <<<"$out" && grep -q "^integritysetup format --batch-mode --integrity hmac-sha256 --integrity-key-file $E/run/tc-scratch.ki --integrity-key-size 32 --sector-size 4096 $E/dev/nvme0n2\$" $L && grep -q "^integritysetup open --integrity hmac-sha256 --integrity-key-file $E/run/tc-scratch.ki --integrity-key-size 32 --integrity-no-journal $E/dev/nvme0n2 tc-int\$" $L && ! grep -q '^blkdiscard' $L && grep -q '^cryptsetup open' $L && grep -q '^mke2fs' $L; echo $?)
mkenv nd2; echo 0 > "$E/sys/devices/pci0/nvme0n2/queue/discard_max_bytes"; run "$SD" dnd2 HANG_INTFORMAT=1 SLEEPT=0.3; chk "the slow way HANGS: it has its own, longer time limit (here 4 seconds), and still ends in a clear failure and a power-off" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q 'within 4 seconds (integritysetup format failed or hung)' <<<"$out"; echo $?)
echo "--- tc-scratch-bind (init-bottom, the mounts)"
mkbind() { mkenv "$1"; mknod "$E/dev/mapper/tc-scratch" b 259 8; echo "root_verity=ok roothash=$RH" > "$E/run/tc-seal.state"; echo "scratch=nvme0n2 cipher=aes-xts-plain64 integrity=hmac-sha256 key=ephemeral" >> "$E/run/tc-seal.state"; }
mkbind b1; run "$BD" b1; chk "the happy path: it mounts the scratch disk and binds /var/lib/hadoop, /var/log and /tmp from it, and says so with the success line that the watcher looks for" $([ $rc = 0 ] && grep -q "^mount -o noatime,nodev,nosuid $E/dev/mapper/tc-scratch $E/scratch\$" "$E/log" && for p in var/lib/hadoop var/log tmp; do grep -q "^mount --bind $E/scratch/$(basename $p) $E/root/$p\$" "$E/log" || exit 1; done && grep -q '^tc-scratch: nvme0n2 is the scratch disk (dm-integrity HMAC-SHA256 under dm-crypt AES-XTS' <<<"$out"; echo $?)
chk "the skeleton of the image is copied with its modes (the datanode folder, the log file, /tmp 1777)" $([ -f "$E/scratch/hadoop/datanode/keep" ] && [ "$(stat -c %a "$E/scratch/hadoop")" = 750 ] && [ "$(stat -c %a "$E/scratch/tmp")" = 1777 ] && [ -f "$E/scratch/log/syslog" ]; echo $?)
bfault() { local n="$1" d="$2" w="$3"; shift 3; run "$BD" "b$n" "$@"; chk "fault: $d: powers off with '$w'" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q "$w" <<<"$out"; echo $?); }
mkbind bf1; rm "$E/dev/mapper/tc-scratch"; bfault bf1 "the scratch device was not set up" "there is no"
mkbind bf2; echo "root_verity=ok" > "$E/run/tc-seal.state"; bfault bf2 "the state file has no scratch line" "no scratch= line"
mkbind bf3; rm -rf "$E/root/var/log"; bfault bf3 "the root has no /var/log" "the root has no /var/log"
mkbind bf4; bfault bf4 "the mount fails" "could not mount the scratch disk" FAIL_MOUNT=1
mkbind bf5; run "$BD" bbf5 HANG_MOUNT=1 SLEEPT=0.3; chk "fault: a mount that HANGS: a clear failure at the time limit, with a power-off, in seconds" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q 'could not mount the scratch disk within 3 seconds' <<<"$out" && [ "$el" -le 10 ]; echo $?)
echo "--- tc-scratch-bind (init-bottom, the lock of the code trees: work item, change 1)"
mklock() { mkbind "$1"; for d in usr etc opt boot root; do mkdir -p "$E/root/media/root-ro/$d" "$E/root/$d"; done; mkdir -p "$E/root/media/root-ro/etc/tc"; echo "${2:-locked}" > "$E/root/media/root-ro/etc/tc/image-mode"; }   # the file that tc-image-lock.sh writes into the image: the mode
mklock l1; run "$BD" l1
exp="$(for d in usr etc opt boot root; do echo "mount --bind $E/root/media/root-ro/$d $E/root/$d"; echo "mount -o remount,bind,ro $E/root/$d"; done)"; got="$(grep '^mount' "$E/log" | head -10)"
chk "a locked image: for each of usr, etc, opt, boot and root, the verified lower tree is bound over the tree and then remounted read-only, in this order, and nothing else is mounted before" $([ $rc = 0 ] && [ "$got" = "$exp" ]; echo $?)
chk "the lock comes BEFORE the scratch disk is mounted and the three folders are bound (the 11th mount is the scratch disk), and the scratch part still ends with its success line" $([ "$(grep '^mount' "$E/log" | sed -n 11p | cut -c1-29)" = "mount -o noatime,nodev,nosuid" ] && grep -q '^tc-scratch: .* is the scratch disk' <<<"$out"; echo $?)
chk "the lock says so with a progress line (tc-seal: lock: ...), and not with a line that the watcher would read as success or failure (tc-scratch: or tc-verity:)" $(grep -q '^tc-seal: lock: the five code trees' <<<"$out" && ! grep -q '^tc-scratch: lock' <<<"$out"; echo $?)
mklock l2 debug; run "$BD" l2
chk "a debug image (its image-mode says debug): the lock is skipped and says so, nothing of the lower root is mounted, and the scratch disk is still set up" $([ $rc = 0 ] && ! grep -q 'root-ro' "$E/log" && grep -q '^tc-seal: lock: skipped' <<<"$out" && grep -q '^mount -o noatime' "$E/log"; echo $?)
lfault() { local n="$1" d="$2" w="$3"; shift 3; chk "fault: $d: powers off with '$w' and the scratch disk is not touched" $([ $rc != 0 ] && [ -e "$E/poweroff" ] && grep -q "$w" <<<"$out" && ! grep -q 'noatime' "$E/log"; echo $?); }
mklock l3; rm -rf "$E/root/media/root-ro/opt"; run "$BD" l3; lfault l3 "the lower root has no opt tree (overlayroot left it somewhere else)" "could not lock /opt: there is no"
mklock l4; run "$BD" l4 FAIL_MOUNT_ON=--bind; lfault l4 "the bind mount fails" "could not lock /usr: the bind mount failed"
mklock l5; run "$BD" l5 FAIL_MOUNT_ON=remount; lfault l5 "the read-only remount fails" "could not lock /usr: the read-only remount failed"
mklock l6; run "$BD" l6 HANG_MOUNT_ON=--bind SLEEPT=0.3; lfault l6 "a bind mount that HANGS (stopped at the time limit, not a frozen boot)" "took more than 3 seconds"
chk "the lock never undoes itself: the script has no umount" $([ "$(grep -v '^[[:space:]]*#' "$BD" | grep -c umount)" = 0 ]; echo $?)
MP="$(sed -n 's#.*"\$LOWER/\(etc/tc/[A-Za-z-]*\)".*#\1#p' "$BD" | head -1)"   # the file that the lock reads in the lower root
chk "the marker that the lock reads in the lower root ($MP) is a file that tc-image-lock.sh WRITES INTO THE IMAGE with the mode as its content (the destination side: a file that exists only in the source tree is not in the image), and the VM report reads the same file" $([ -n "$MP" ] && grep "\"\$R/$MP\"" "$I/build/tc-image-lock.sh" | grep -q '\$MODE' && grep -q "${MP#etc/tc/}" "$I/rootfs/usr/local/lib/tc/tc-report.sh" && grep -q 'debug|locked' "$I/build/tc-image-lock.sh"; echo $?)
mklock nm; rm -f "$E/root/media/root-ro/etc/tc/image-mode"; run "$BD" nm
chk "a lower root with no image-mode file at all (an old image) is treated as not locked: the lock is skipped and says so, and nothing of the lower root is mounted" $([ $rc = 0 ] && grep -q '^tc-seal: lock: skipped' <<<"$out" && ! grep -q 'root-ro' "$E/log"; echo $?)
mkkeep() { mklock "$1"; mkdir -p "$E/root/media/root-rw/overlay/etc"; echo overlayfstab > "$E/root/media/root-rw/overlay/etc/fstab"; [ "${2:-target}" != target ] || echo lowerfstab > "$E/root/etc/fstab"; }
mkkeep k1; run "$BD" k1
exp="$(for d in usr etc opt boot root; do echo "mount --bind $E/root/media/root-ro/$d $E/root/$d"; echo "mount -o remount,bind,ro $E/root/$d"; done; echo "mount --bind $E/root/media/root-rw/overlay/etc/fstab $E/root/etc/fstab"; echo "mount -o remount,bind,ro $E/root/etc/fstab")"; got="$(grep '^mount' "$E/log" | head -12)"
chk "the overlay own fstab is kept: after the five trees it is bound back from the RAM layer over etc/fstab, read-only, in this order" $([ $rc = 0 ] && [ "$got" = "$exp" ]; echo $?)
chk "... before the scratch disk (the 13th mount), and the lock line names what was kept (etc/fstab)" $([ "$(grep '^mount' "$E/log" | sed -n 13p | cut -c1-29)" = "mount -o noatime,nodev,nosuid" ] && grep -q '^tc-seal: lock: .*kept from the overlay own layer, read-only: etc/fstab' <<<"$out"; echo $?)
mkkeep k2; run "$BD" k2 FAIL_MOUNT_ON="--bind $E/root/media/root-rw"; lfault k2 "the bind of the kept fstab fails" "could not keep etc/fstab of the overlay: the bind mount failed"
mkkeep k3; run "$BD" k3 FAIL_MOUNT_ON="remount,bind,ro $E/root/etc/fstab"; lfault k3 "the read-only remount of the kept fstab fails" "could not keep etc/fstab of the overlay: the read-only remount failed"
mkkeep k4; cp "$BD" "$W/tc-scratch-bind.nokeep"; sed -i 's#^KEEP_UPPER=.*#KEEP_UPPER=""#' "$W/tc-scratch-bind.nokeep"; run "$W/tc-scratch-bind.nokeep" k4
chk "the switch: with KEEP_UPPER empty nothing of the overlay is kept (10 lock mounts, then the scratch disk) and the lock line says nothing" $([ $rc = 0 ] && [ "$(grep '^mount' "$E/log" | sed -n 11p | cut -c1-16)" = "mount -o noatime" ] && grep -q 'kept from the overlay own layer, read-only: nothing' <<<"$out"; echo $?)
mkkeep k5 notarget; run "$BD" k5
chk "an fstab in the RAM layer but none in the locked tree to bind it over: it is skipped, the lock still succeeds and says nothing was kept" $([ $rc = 0 ] && ! grep -q 'overlay/etc/fstab' "$E/log" && grep -q 'read-only: nothing' <<<"$out"; echo $?)
chk "the bind script never calls cryptsetup, veritysetup or mke2fs (udev is not needed here)" $(! grep -v '^#' "$BD" | grep -E 'cryptsetup|veritysetup|mke2fs|mkfs' >/dev/null; echo $?)
chk "the scripts use no absolute path outside their assignment line except /dev/null and /dev/urandom (so the rehearsal cannot touch the real system, and nothing is hard-coded)" $(ok=0; for f in "$V" "$SD" "$BD"; do grep -v '^[[:space:]]*#' "$f" | grep -v -E '^(CMDLINE|DEVDIR)=' | sed -e 's#/dev/null##g' -e 's#/dev/urandom##g' -e 's#"\$[A-Za-z]*"/#V/#g' | grep -E '(^|[ "=:(])/[a-z]' >/dev/null && ok=1; done; echo $ok)
chk "no progress line of any script starts with tc-verity: or tc-scratch: (those prefixes mean success or FAILURE to the watcher)" $(! grep -h 'say "' "$V" "$SD" "$BD" | grep -E 'say "(tc-verity|tc-scratch):' >/dev/null; echo $?)
echo "=== R3.3 and R3.4: the driver's sealing stages (the commands they would issue, and the serial-console watcher against a fake console)"
D="$T/f03-drive.sh"; export DRY=1 IMG=tc-img-seal-1 OUT="$W/outd"; mkdir -p "$OUT"
dry() { out="$(timeout 60 bash "$D" "$@" 2>&1 | sed 's/\\//g')"; }
dry seal-disk; chk "seal-disk: the disk is copied from the builder, the helper is a plain n2 VM that holds the copy as a second disk (device name target), and the sealing runs with --destructive-ok on the copy and on the real kernel test" $(grep -q 'DRY: gcloud compute disks create tc-seal-work --source-disk=tc-builder' <<<"$out" && grep -q 'instances create tc-sealer .*--machine-type=n2-standard-2' <<<"$out" && grep -q -- '--disk=name=tc-seal-work,device-name=target,mode=rw,boot=no,auto-delete=no' <<<"$out" && grep -q -- '--no-service-account' <<<"$out" && grep -q -- 'tc-image-seal.sh --disk /dev/disk/by-id/google-target --p1 /dev/disk/by-id/google-target-part1 --esp /dev/disk/by-id/google-target-part15 --kver 6.17.0-1022-gcp --destructive-ok --blocks 2621440' <<<"$out" && ! grep -q -- '--no-kernel-test' <<<"$out"; echo $?)
chk "seal-disk: the helper is made from an image whose disk identifiers differ from the builder's (tc-img-dbg-1, not tc-img-dbg-5), so it cannot boot from the copy by mistake" $(grep -q 'instances create tc-sealer .*--image=tc-img-dbg-1 ' <<<"$out" && ! grep -q 'instances create tc-sealer .*--image=tc-img-dbg-5' <<<"$out"; echo $?)
dry seal-image; chk "seal-image: the image is made from the sealed copy" $(grep -q 'DRY: gcloud compute images create tc-img-seal-1 --source-disk=tc-seal-work' <<<"$out"; echo $?)
dry seal-boot; chk "seal-boot: a plain c3 VM (NO --confidential-compute-type) from the sealed image with a spare disk of 10 GB, device name tcscratch, deleted with the VM" $(L="$(grep 'DRY: gcloud compute instances create' <<<"$out")"; grep -q 'create tc-seal-test ' <<<"$L" && grep -q -- '--machine-type=c3-standard-4' <<<"$L" && grep -q -- '--image=tc-img-seal-1' <<<"$L" && ! grep -q 'confidential-compute-type' <<<"$L" && grep -q -- '--create-disk=name=tc-seal-test-scratch,size=10GB,type=pd-balanced,device-name=tcscratch,auto-delete=yes' <<<"$L"; echo $?)
dry seal-delete; chk "seal-delete without CONFIRM=yes refuses, and names the exact VMs and disk" $(grep -q 'STOP: set CONFIRM=yes to delete tc-seal-test, tc-sealer and the disk tc-seal-work' <<<"$out"; echo $?)
CONFIRM=yes dry seal-delete; chk "seal-delete deletes only tc-seal-test, tc-sealer, tc-atk-test and the disks tc-seal-work and tc-atk-disk, each by its exact name (5 deletes, nothing else)" $([ "$(grep -c 'DRY: gcloud compute instances delete\|DRY: gcloud compute disks delete' <<<"$out")" = 5 ] && grep -q 'instances delete tc-seal-test --zone' <<<"$out" && grep -q 'instances delete tc-sealer --zone' <<<"$out" && grep -q 'instances delete tc-atk-test --zone' <<<"$out" && grep -q 'disks delete tc-seal-work --zone' <<<"$out" && grep -q 'disks delete tc-atk-disk --zone' <<<"$out"; echo $?)
ALLD=""; for st in bake-seal seal-stop seal-disk seal-image seal-boot seal-check; do dry $st; ALLD="$ALLD$out"$'\n'; done; CONFIRM=yes dry seal-delete; ALLD="$ALLD$out"
chk "no sealing stage names a VM that is not ours: nothing about the teammate's VMs or the old lab nodes, and no wildcard or filter in a delete" $(! grep -qiE 'subhi|tdx-lab' <<<"$ALLD" && ! grep -E 'delete .*(\*|--filter)' <<<"$ALLD" >/dev/null; echo $?)
FG="$W/fgs"; mkdir -p "$FG"; cat > "$FG/gcloud" <<'EOS'
#!/usr/bin/env bash
a="$*"
case "$a" in
  *get-serial-port-output*) n=$(cat "$FAKE_SERIAL.n" 2>/dev/null || echo 0); echo $((n + 1)) > "$FAKE_SERIAL.n"; [ "$n" -lt "${FAKE_EMPTY_CALLS:-0}" ] && exit 0; [ "$n" -ge "${FAKE_EMPTY_AFTER:-999}" ] && exit 0; cat "$FAKE_SERIAL" ;;
  *"instances describe"*--format*) echo "${FAKE_STATUS:-RUNNING}" ;;
  *"instances describe"*) exit 1 ;;
  *"images describe"*) exit 0 ;;
  *) exit 0 ;;
esac
EOS
chmod +x "$FG/gcloud"
watch() { # NAME SERIAL-TEXT [STATUS]: the stage seal-boot with a fake console
  printf '%s\n' "$2" > "$W/serial.$1"; rm -f "$W/serial.$1.n"; unset DRY; t0=$(date +%s); out="$(PATH="$FG:$PATH" FAKE_SERIAL="$W/serial.$1" FAKE_STATUS="${3:-RUNNING}" SEAL_REFETCH=0 SEAL_POLL=1 SEAL_WATCH_SECONDS=4 IMG=tc-img-seal-1 OUT="$OUT" timeout 60 bash "$D" seal-boot 2>&1)"; rc=$?; el=$(( $(date +%s) - t0 )); export DRY=1; }
OKV='tc-verity: the root disk matches the root hash 0123'; OKS='tc-scratch: nvme0n2 is the scratch disk (dm-integrity HMAC-SHA256 under dm-crypt AES-XTS, keys that exist only in this boot)'
watch w1 "$(printf 'boot\n%s\nmore\n%s\ntc-seal-test login: ' "$OKV" "$OKS")"; chk "the watcher: both success lines and a login prompt end it with success, at the first look" $([ $rc = 0 ] && grep -q 'the sealed boot worked' <<<"$out" && [ "$el" -le 3 ]; echo $?)
chk "the watcher saves the whole serial console as evidence" $(grep -q 'tc-seal-test login' "$OUT/serial-tc-seal-test.txt"; echo $?)
watch w2 "$(printf 'boot\ntc-verity: the root disk does not match the root hash on the kernel command line\npoweroff')" ; chk "the watcher: a failing verity check stops it at the FIRST look, with the failing line and the last lines of the console" $([ $rc != 0 ] && grep -q 'THE BOOT FAILED' <<<"$out" && grep -q 'does not match the root hash' <<<"$out" && grep -q 'the last 30 lines' <<<"$out" && [ "$el" -le 3 ]; echo $?)
watch w3 "$(printf '%s\ntc-scratch: the scratch disk must be the only spare NVMe disk without partitions, and I found 0:' "$OKV")"; chk "the watcher: a failing scratch check stops it at once" $([ $rc != 0 ] && grep -q 'THE BOOT FAILED' <<<"$out" && grep -q 'and I found 0' <<<"$out" && [ "$el" -le 3 ]; echo $?)
watch w4 "$(printf 'boot\nKernel panic - not syncing: VFS: Unable to mount root fs')"; chk "the watcher: a kernel panic stops it at once" $([ $rc != 0 ] && grep -q 'THE BOOT FAILED' <<<"$out" && grep -q 'Kernel panic' <<<"$out" && [ "$el" -le 3 ]; echo $?)
watch w5 "$(printf 'boot\n(initramfs) ')"; chk "the watcher: a drop to the initramfs shell stops it at once" $([ $rc != 0 ] && grep -q 'THE BOOT FAILED' <<<"$out" && [ "$el" -le 3 ]; echo $?)
watch w6 "$(printf 'boot\n%s' "$OKV")" TERMINATED; chk "the watcher: a VM that is no longer RUNNING before the boot is complete stops it (our scripts power the machine off on a failure)" $([ $rc != 0 ] && grep -q 'THE VM IS TERMINATED' <<<"$out" && [ "$el" -le 3 ]; echo $?)
watch w7 "$(printf 'boot\nsome text')"; chk "the watcher: a console that never shows a result ends at the timeout with 'NO RESULT' and the last lines (and does not wait for ever)" $([ $rc != 0 ] && grep -q 'NO RESULT after 4s' <<<"$out" && [ "$el" -le 8 ]; echo $?)
watch2() { printf '%s\n' "$2" > "$W/serial.$1"; unset DRY; t0=$(date +%s); out="$(PATH="$FG:$PATH" FAKE_SERIAL="$W/serial.$1" FAKE_STATUS=RUNNING SEAL_POLL=1 SEAL_WATCH_SECONDS=30 SEAL_STALL=3 IMG=tc-img-seal-1 OUT="$OUT" timeout 60 bash "$D" seal-boot 2>&1)"; rc=$?; el=$(( $(date +%s) - t0 )); export DRY=1; }
watch2 w9 "$(printf 'boot\ntc-seal: scratch: formatting nvme0n2 (LUKS2, AES-XTS, HMAC-SHA256 integrity, a random key)')"; chk "the watcher: a console that stops changing for 3 s (here instead of 90 s) is reported as STALLED, naming the step that was running, long before the timeout" $([ $rc != 0 ] && grep -q 'STALLED: the serial console has not changed for 3s' <<<"$out" && grep -q 'formatting nvme0n2' <<<"$out" && [ "$el" -le 12 ]; echo $?)
watch w10 "$(printf 'boot\ntc-seal: verity: opening the root partition')"; chk "the watcher shows the last progress step in every poll line" $(grep -q 'last step: tc-seal: verity: opening the root partition' <<<"$out"; echo $?)
export FAKE_EMPTY_CALLS=3; watch w11 "$(printf 'boot\n%s\ntc-scratch: could not make the file system of the scratch disk within 120 seconds (mke2fs failed or hung)' "$OKV")" TERMINATED; unset FAKE_EMPTY_CALLS
chk "the watcher (the loss of the evidence in boot 2): the console comes back empty while the VM stops, and is then read again: the failing line of ours is shown as THE REASON, and the saved console file holds the text" $([ $rc != 0 ] && grep -q 'THE VM IS TERMINATED' <<<"$out" && grep -q 'THE REASON, from the console' <<<"$out" && grep -q 'could not make the file system' <<<"$out" && grep -q 'could not make the file system' "$OUT/serial-tc-seal-test.txt"; echo $?)
export FAKE_EMPTY_AFTER=1; watch w12 "$(printf 'boot\n%s' "$OKV")"; unset FAKE_EMPTY_AFTER
chk "the watcher: an empty answer after a good one never replaces the saved console (the file keeps the text that was read)" $(grep -q 'the root disk matches the root hash' "$OUT/serial-tc-seal-test.txt"; echo $?)
watch w13 "$(printf 'boot\nerror: file '"'"'/EFI/ubuntu/initrd.img-tc'"'"' not found.')"; chk "the watcher: a GRUB error line stops it at once" $([ $rc != 0 ] && grep -q 'THE BOOT FAILED' <<<"$out" && grep -q "^error: file" <<<"$out" && [ "$el" -le 3 ]; echo $?)
GE="error: can't find command \`serial'."; K1='[    0.530871] ACPI: bus type USB registered'; K2='[    0.543561] clocksource: Switched to clocksource kvm-clock'; K3='[    0.555454] NET: Registered PF_INET protocol family'
watch w14 "$(printf '%s\n%s\n%s\n%s\n' "$GE" "$K1" "$K2" "$K3")"; chk "REAL CONSOLE (the failed Block 3 of 23 October): the harmless GRUB line about the serial command, followed by the real early kernel lines, is NOT a failure: the watcher goes on until its timeout and never says THE BOOT FAILED" $([ $rc != 0 ] && ! grep -q 'THE BOOT FAILED' <<<"$out" && grep -q 'NO RESULT' <<<"$out"; echo $?)
watch w15 "$(printf '%s\n%s\n%s\n%s\n%s\n%s\n%s\n' "$GE" "$K1" 'tc-verity: the root disk matches the root hash 482962f0c4b2041a56a67ed477d5370e9d2ea86a7f1690824b7a5690059615fc' 'tc-seal: scratch: mounting it and binding the three folders' "$OKS" 'tc-builder login: Oct 23 14:26:55 tc-builder systemd[1]: systemd-timedated.service: Deactivated successfully.' 'more')"; chk "REAL CONSOLE (the good boot of 23 October): the same GRUB line, then the real success lines and the login prompt, ends with SUCCESS" $([ $rc = 0 ] && grep -q 'the sealed boot worked' <<<"$out"; echo $?)
watch w16 "$(printf '%s\n%s\n%s\n' "$GE" "$K1" 'tc-scratch: could not make the file system of the scratch disk within 120 seconds (mke2fs failed or hung)')"; chk "the harmless GRUB line followed by a REAL failure of ours: the real failure is what is reported (not the GRUB line)" $([ $rc != 0 ] && grep -q 'THE BOOT FAILED' <<<"$out" && grep -q 'could not make the file system' <<<"$out" && ! grep -A2 'THE BOOT FAILED' <<<"$out" | grep -q "can't find command"; echo $?)
watch w17 "$(printf '%s\n%s\n' "$GE" 'grub> ')"; chk "a GRUB that drops to its prompt IS a failure" $([ $rc != 0 ] && grep -q 'THE BOOT FAILED' <<<"$out"; echo $?)
watch w8 "$(printf '%s\n%s\n' "$OKV" "$OKS")"; chk "the watcher: both success lines but no login prompt yet is NOT success" $([ $rc != 0 ] && ! grep -q 'the sealed boot worked' <<<"$out"; echo $?)
unset DRY; chk "the post-boot check is syntactically sound and creates only two files of its own (a test file in /etc and one on the scratch disk), both removed" $(bash -n "$T/r3-seal-check.sh" && grep -q 'touch /etc/tc-seal-check-file' "$T/r3-seal-check.sh" && grep -q 'rm -f /etc/tc-seal-check-file' "$T/r3-seal-check.sh" && grep -q 'of=/var/lib/hadoop/tc-seal-write-test' "$T/r3-seal-check.sh" && grep -q 'rm -f /var/lib/hadoop/tc-seal-write-test' "$T/r3-seal-check.sh" && ! grep -v '^[[:space:]]*#' "$T/r3-seal-check.sh" | grep -E '\b(mkfs|mke2fs|cryptsetup (format|luks|open|close)|veritysetup (format|open|close)|dmsetup (create|remove)|umount|mount )' >/dev/null; echo $?)
echo "=== E. the preflight of the session, against a fake gcloud in several situations"
PG="$W/pg"; mkdir -p "$PG"; cat > "$PG/gcloud" <<'EOS'
#!/usr/bin/env bash
a="$*"
case "$a" in
  *"images describe tc-img-dbg-1"*) [ "${PF_NO_HELPER:-}" = 1 ] && exit 1; echo READY ;;
  *"images describe tc-img-dbg-5"*) echo READY ;;
  *"images describe tc-img-seal-1"*) [ "${PF_IMG_EXISTS:-}" = 1 ] && { echo READY; exit 0; }; exit 1 ;;
  *"instances describe tc-builder"*) echo "${PF_BUILDER:-TERMINATED}" ;;
  *"instances describe tc-sealer"*|*"instances describe tc-seal-test"*) [ "${PF_VM_EXISTS:-}" = 1 ] && { echo RUNNING; exit 0; }; exit 1 ;;
  *"disks describe tc-seal-work"*) [ "${PF_DISK_EXISTS:-}" = 1 ] && { echo x; exit 0; }; exit 1 ;;
  *"regions describe"*) echo "{\"quotas\":[{\"metric\":\"C3_CPUS\",\"usage\":${PF_USAGE:-16},\"limit\":24}]}" ;;
  *) exit 0 ;;
esac
EOS
chmod +x "$PG/gcloud"
pf() { out="$(PATH="$PG:$PATH" env "$@" bash "$T/r3-preflight.sh" "$KIT" 2>&1)"; rc=$?; }
pf X=1; chk "preflight: everything in order gives PRECHECK-OK in a moment" $([ $rc = 0 ] && grep -q '^PRECHECK-OK' <<<"$out" && grep -q 'C3_CPUS 16 of 24' <<<"$out"; echo $?)
pf PF_NO_HELPER=1; chk "preflight fault: the helper's image does not exist" $([ $rc != 0 ] && grep -q 'image tc-img-dbg-1 does not exist' <<<"$out"; echo $?)
pf PF_BUILDER=RUNNING; chk "preflight fault: the builder is still running (the copy of its disk would be inconsistent)" $([ $rc != 0 ] && grep -q 'must exist and be stopped (it is: RUNNING)' <<<"$out"; echo $?)
pf PF_DISK_EXISTS=1; chk "preflight fault: the sealed copy of an earlier attempt exists" $([ $rc != 0 ] && grep -q 'the disk tc-seal-work exists already' <<<"$out"; echo $?)
pf PF_VM_EXISTS=1; chk "preflight fault: a helper or test VM of an earlier attempt exists" $([ $rc != 0 ] && grep -q 'the VM tc-sealer exists already' <<<"$out" && grep -q 'the VM tc-seal-test exists already' <<<"$out"; echo $?)
pf PF_IMG_EXISTS=1; chk "preflight fault: the target image exists already" $([ $rc != 0 ] && grep -q 'the image tc-img-seal-1 exists already' <<<"$out"; echo $?)
pf PF_USAGE=20; chk "preflight fault: not enough free C3 quota (and it says never to touch the teammate's VMs)" $([ $rc != 0 ] && grep -q 'less than 8 vCPUs free' <<<"$out" && grep -q "never the teammate's VMs" <<<"$out"; echo $?)
rm -rf "$W/badkit"; mkdir -p "$W/badkit"; cp -r "$KIT/ops" "$W/badkit/"; echo 'if [' >> "$W/badkit/ops/image/build/tc-image-seal.sh"; out="$(PATH="$PG:$PATH" bash "$T/r3-preflight.sh" "$W/badkit" 2>&1)"; rc=$?; chk "preflight fault: a script that does not parse is found at once" $([ $rc != 0 ] && grep -q 'tc-image-seal.sh does not parse' <<<"$out"; echo $?)
chk "the preflight changes nothing: it only describes and lists (no create, delete, start, stop, ssh or scp)" $(! grep -v '^[[:space:]]*#' "$T/r3-preflight.sh" | grep -E 'gcloud compute (instances|disks|images) (create|delete|start|stop|add|attach|detach)|ssh|scp' >/dev/null; echo $?)
chk "the rehearsal leaves the tested tree exactly as it found it (no copy or test file is left inside it)" $([ "$(cd "$KIT" && find ops -type f -not -path '*/__pycache__/*' | sort | xargs -d '\n' sha256sum | sha256sum)" = "$TREE0" ]; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "R3-REHEARSAL-PASS (R3.1 to R3.4)"; else echo "R3-REHEARSAL-FAIL"; fi
[ "$FAILN" = 0 ]
