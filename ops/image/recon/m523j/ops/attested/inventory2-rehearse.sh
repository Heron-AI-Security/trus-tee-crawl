#!/usr/bin/env bash
# Rehearsal of inventory2.sh on the machine it runs on (the real script, which only reads), with a planted authorized_keys file that must be counted and never shown, a planted fstab, and an unreachable metadata server.
#   bash inventory2-rehearse.sh KITDIR
set -uo pipefail
KIT="$1"; A="$KIT/ops/attested"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; fi; }
R="$(mktemp -d)"; mkdir -p "$R/h/user1/.ssh"; printf 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPLANTEDSECRETKEYDATA0123456789 planted@test\nssh-rsa AAAAB3NzaPLANTED2 b@c\n' > "$R/h/user1/.ssh/authorized_keys"
printf '# a comment\nLABEL=cloudimg-rootfs / ext4 discard,errors=remount-ro 0 1\nLABEL=UEFI /boot/efi vfat umask=0077 0 1\n' > "$R/fstab"
run() { ( export INV_SUDO="" INV_METADATA="http://127.0.0.1:9/none" INV_FSTAB="$R/fstab" INV_HOMEGLOB="$R/h/*/.ssh/authorized_keys"; bash "$A/inventory2.sh" "$@" ) 2>&1; }
echo "=== 1. the happy path"; out="$(run "$R/i2.txt")"; rc=$?; echo "$out" | tail -2 | cut -c1-150
chk "exits 0 and says INVENTORY2-OK with 8 sections" $([ $rc = 0 ] && grep -q '^INVENTORY2-OK: .* 8 sections' <<<"$out"; echo $?)
chk "the planted authorized_keys file is COUNTED (2 keys) and no key text is in the output" $(grep -q "keys: $R/h/user1/.ssh/authorized_keys has 2 key(s)" "$R/i2.txt" && ! grep -q 'PLANTEDSECRET\|ssh-ed25519\|AAAAB3Nza' "$R/i2.txt"; echo $?)
chk "the planted fstab is read without its comment (2 lines)" $([ "$(grep -c '^fstab: ' "$R/i2.txt")" = 2 ]; echo $?)
chk "an unreachable metadata server does not stop the script (the names are simply empty)" $(grep -q '^instance/attributes: ' "$R/i2.txt" && grep -q '^project/attributes: ' "$R/i2.txt"; echo $?)
chk "the machine's facts are there (at least one of: addresses, enabled units, packages; a bare container has few)" $(grep -q '^addr: \|^enabled: \|^package: \|^route: ' "$R/i2.txt"; echo $?)
echo "=== 2. faults"
out="$(run "$R/i2.txt")"; rc=$?; chk "fault: the output file exists already -> stops and does not overwrite it" $([ $rc != 0 ] && grep -q 'exists already' <<<"$out" && grep -q '^##### 1\.' "$R/i2.txt"; echo $?)
out="$( ( export INV_SUDO=""; bash "$A/inventory2.sh" 2>&1 ) )"; rc=$?; chk "fault: no output file named -> usage, no run" $([ $rc != 0 ] && grep -q 'usage' <<<"$out"; echo $?)
sed 's/^echo "inventory2:/echo "ssh-rsa AAAALEAKED planted"; echo "inventory2:/' "$A/inventory2.sh" > "$R/leaky.sh"
out="$( ( export INV_SUDO="" INV_METADATA="http://127.0.0.1:9/none" INV_FSTAB="$R/fstab"; bash "$R/leaky.sh" "$R/i3.txt" ) 2>&1 )"; rc=$?
chk "fault: a key-looking string in the output makes the script delete the file and stop" $([ $rc != 0 ] && grep -q 'looks like a key' <<<"$out" && [ ! -e "$R/i3.txt" ]; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; [ "$FAILN" = 0 ] && echo "REHEARSAL-PASS: the real inventory2 script reads, counts keys without showing them, refuses to overwrite and deletes a leaky output; $PASS checks" || echo "REHEARSAL-FAIL"
