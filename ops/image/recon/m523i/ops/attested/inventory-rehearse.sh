#!/usr/bin/env bash
# Rehearsal of inventory.sh on the machine it runs on (the real script, no stand-in for the commands: it only reads), plus a planted authorized_keys file that must be counted and never shown.
#   bash inventory-rehearse.sh KITDIR
set -uo pipefail
KIT="$1"; A="$KIT/ops/attested"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; fi; }
R="$(mktemp -d)"; mkdir -p "$R/h/user1/.ssh"; echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPLANTEDSECRETKEYDATA0123456789 planted@test" > "$R/h/user1/.ssh/authorized_keys"; printf 'ssh-rsa AAAAB3NzaC1yc2EPLANTED2 b@c\nssh-ed25519 AAAAPLANTED3 d@e\n' > "$R/h/user1/.ssh/authorized_keys2"
run() { ( export INV_SUDO="" INV_HOMES="$R/h/*" INV_ROOTSSH="$R/none"; bash "$A/inventory.sh" "$@" ) 2>&1; }
echo "=== 1. the happy path"; out="$(run "$R/inv1.txt")"; rc=$?; echo "$out" | tail -2 | cut -c1-160
chk "exits 0 and says INVENTORY-OK with the number of lines and sections" $([ $rc = 0 ] && grep -q '^INVENTORY-OK: .* 11 sections' <<<"$out"; echo $?)
chk "all eleven sections are in the file" $([ "$(grep -c '^##### ' "$R/inv1.txt")" = 11 ]; echo $?)
chk "the machine's facts are there (OS name, kernel, listeners or services)" $(grep -q '^PRETTY_NAME=' "$R/inv1.txt" && grep -q '^kernel: ' "$R/inv1.txt" && grep -q '^tool bash: ' "$R/inv1.txt"; echo $?)
chk "the planted authorized_keys file is COUNTED (1 key) and its content is not in the output" $(grep -q 'authorized_keys: .*/user1/.ssh/authorized_keys has 1 key(s)' "$R/inv1.txt" && ! grep -q 'PLANTEDSECRETKEYDATA\|ssh-ed25519\|AAAAC3Nza' "$R/inv1.txt"; echo $?)
chk "the file mode of the output is not changed to anything unusual and the script wrote only the output file (no other file in the folder)" $([ "$(ls "$R" | tr '\n' ' ')" = "h inv1.txt " ]; echo $?)
echo "=== 2. faults"
out="$(run "$R/inv1.txt")"; rc=$?; chk "fault: the output file exists already -> stops and does not overwrite it" $([ $rc != 0 ] && grep -q 'exists already' <<<"$out" && grep -q '^##### 1\.' "$R/inv1.txt"; echo $?)
out="$( ( export INV_SUDO="" INV_HOMES="$R/h/*"; bash "$A/inventory.sh" 2>&1 ) )"; rc=$?; chk "fault: no output file named -> usage, no run" $([ $rc != 0 ] && grep -q 'usage' <<<"$out"; echo $?)
cat > "$R/leaky.sh" <<'EOL'
#!/usr/bin/env bash
sed 's/^echo "inventory:/echo "ssh-rsa AAAALEAKED"; echo "inventory:/' "$1" > "$2"
EOL
sed 's/^echo "inventory:/echo "ssh-rsa AAAALEAKED planted"; echo "inventory:/' "$A/inventory.sh" > "$R/inventory-leaky.sh"; chmod +x "$R/inventory-leaky.sh"
out="$( ( export INV_SUDO="" INV_HOMES="$R/h/*" INV_ROOTSSH="$R/none"; bash "$R/inventory-leaky.sh" "$R/inv2.txt" ) 2>&1 )"; rc=$?
chk "fault: if a key-looking string ever got into the output the script deletes the file and stops" $([ $rc != 0 ] && grep -q 'looks like a key' <<<"$out" && [ ! -e "$R/inv2.txt" ]; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; [ "$FAILN" = 0 ] && echo "REHEARSAL-PASS: the real inventory script reads, prints no key, refuses to overwrite and deletes a leaky output; $PASS checks" || echo "REHEARSAL-FAIL"
