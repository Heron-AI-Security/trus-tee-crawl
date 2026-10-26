#!/usr/bin/env bash
# Step R3.4, READ-ONLY, on a booted SEALED VM: is the root really a verified read-only disk under a RAM overlay, and is the scratch disk really encrypted with integrity? (It only creates and removes two files of its own.)
#   sudo bash r3-seal-check.sh [ROOTHASH]      ROOTHASH: the root hash of the seal report; it must equal the one on the kernel command line
set -uo pipefail
RH="${1:-}"; BAD=0
ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; BAD=$((BAD+1)); }
say() { echo; echo "== $*"; }
say "the kernel command line (RTMR2 measures it on a TDX machine)"
CL="$(cat /proc/cmdline)"; echo "$CL" | cut -c1-300
for k in 'root=/dev/mapper/vroot' ' ro ' 'overlayroot=tmpfs' 'tc.verity=' 'tc.data=' 'tc.blocks=' 'tc.salt='; do grep -q -- "$k" <<<"$CL" && ok "the command line has $k" || no "the command line lacks $k"; done
CH="$(grep -o 'tc.verity=[0-9a-f]*' <<<"$CL" | cut -d= -f2)"; [ -z "$RH" ] || { [ "$CH" = "$RH" ] && ok "the root hash on the command line is the one of the seal report" || no "the root hash on the command line ($CH) is not the one of the seal report ($RH)"; }
say "the root: a verified read-only disk under a RAM overlay"
grep -q '^root_verity=ok' /run/tc-seal.state 2>/dev/null && ok "the initramfs says that the root matched its hash: $(grep '^root_verity' /run/tc-seal.state | cut -c1-120)" || no "no root_verity=ok in /run/tc-seal.state"
[ "$(findmnt -no FSTYPE /)" = overlay ] && ok "/ is an overlay" || no "/ is not an overlay: $(findmnt -no FSTYPE,SOURCE /)"
S="$(findmnt -no SOURCE,OPTIONS /media/root-ro 2>/dev/null)"; grep -q '/dev/mapper/vroot' <<<"$S" && grep -qE '(^|[ ,])ro(,| |$)' <<<"$S" && ok "the lower layer /media/root-ro is /dev/mapper/vroot, mounted read-only" || no "the lower layer is not vroot read-only: $S"
ST="$(dmsetup status vroot 2>&1)"; grep -q ' verity V' <<<"$ST" && ok "dm-verity says the device is valid: $ST" || no "dm-verity status is not 'V' (valid): $ST"
TB="$(dmsetup table vroot 2>&1)"; [ -n "$CH" ] && grep -q "$CH" <<<"$TB" && ok "the active verity table holds the root hash of the command line" || no "the verity table does not hold the root hash of the command line"
touch /etc/tc-seal-check-file 2>/dev/null && [ ! -e /media/root-ro/etc/tc-seal-check-file ] && ok "a write to / works (it goes to RAM) and the verified disk does not see it" || no "a write to / failed or reached the verified disk"
! touch /media/root-ro/etc/tc-seal-check-lower 2>/dev/null && ok "a write straight to the verified lower layer is refused" || { no "the verified lower layer is writable"; rm -f /media/root-ro/etc/tc-seal-check-lower; }
rm -f /etc/tc-seal-check-file
say "the scratch disk: dm-integrity (HMAC-SHA256) under dm-crypt (AES-XTS), keys that are gone"
grep -q '^scratch=' /run/tc-seal.state 2>/dev/null && ok "the initramfs says: $(grep '^scratch=' /run/tc-seal.state)" || no "no scratch= line in /run/tc-seal.state"
CS="$(cryptsetup status tc-scratch 2>&1)"; echo "$CS" | sed 's/^/        /'
grep -q 'type: *PLAIN' <<<"$CS" && grep -q 'cipher: *aes-xts-plain64' <<<"$CS" && grep -q 'device: */dev/mapper/tc-int' <<<"$CS" && ok "the encryption layer is dm-crypt, aes-xts-plain64, on /dev/mapper/tc-int" || no "the encryption layer is not plain aes-xts-plain64 on /dev/mapper/tc-int"
IT="$(dmsetup table tc-int 2>&1 | sed -E 's/hmac\(sha256\):[0-9a-f]+/hmac(sha256):<key hidden>/')"; echo "$IT" | cut -c1-220 | sed 's/^/        /'
grep -q 'internal_hash:hmac(sha256)' <<<"$IT" && grep -q 'allow_discards' <<<"$IT" && ok "the integrity layer is dm-integrity with an HMAC-SHA256 internal hash" || no "the integrity layer is not dm-integrity with an HMAC-SHA256 internal hash"
for p in /var/lib/hadoop /var/log /tmp; do findmnt -no SOURCE "$p" | grep -q '/dev/mapper/tc-scratch' && ok "$p comes from the scratch disk" || no "$p does not come from the scratch disk: $(findmnt -no SOURCE "$p")"; done
[ ! -e /run/tc-scratch.ki ] && [ ! -e /run/tc-scratch.kc ] && ok "no key file is left (the two keys exist only inside the kernel)" || no "a key file is still in /run"
V="$(dd if=/dev/zero of=/var/lib/hadoop/tc-seal-write-test bs=1M count=64 conv=fsync 2>&1 | tail -1)"; rm -f /var/lib/hadoop/tc-seal-write-test; ok "64 MiB written to the scratch disk with fsync: $V"
say "the machine"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>&1 | head -14; free -m | head -2; df -h /run /dev/shm /var/lib/hadoop 2>&1 | head -5; systemctl --failed --no-legend 2>/dev/null | head -8
echo; if [ "$BAD" = 0 ]; then echo "SEAL-CHECK-OK"; else echo "SEAL-CHECK-FAILED ($BAD)"; fi
