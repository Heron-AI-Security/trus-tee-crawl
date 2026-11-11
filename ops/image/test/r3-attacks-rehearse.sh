#!/usr/bin/env bash
# Rehearsal of steps R3.7 (the strip of the TC_ hooks) and R3.6 (the attack scripts and stages): the REAL verifier code with hand-made quotes, the REAL strip tool, the REAL flip script on a real ext4 image,
# and the dry runs of the drivers. Needs root, e2fsprogs, python3.   bash r7-rehearse.sh KITDIR
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; T="$I/test"; L="$I/rootfs/usr/local/lib/tc"; PASS=0; FAILN=0; W="$(mktemp -d)"
chk() { local t="$1"; shift; if [ "${1:-1}" = 0 ]; then echo "  pass: $t"; PASS=$((PASS+1)); else echo "  FAIL: $t"; FAILN=$((FAILN+1)); fi; }
[ "$(id -u)" = 0 ] || { echo "  FAIL: needs root"; exit 2; }
echo "=== R3.7: the strip of the TC_ hooks"
rm -rf "$W/k" "$W/d"; mkdir -p "$W/k/ops/image/build" "$W/d"; cp -r "$I/rootfs" "$W/k/ops/image/"; cp "$I/build/tc-strip-hooks.py" "$W/k/ops/image/build/"; out="$(bash "$I/build/tc-image-refresh.sh" --kit "$W/k" --dest "$W/d" 2>&1)"; rc=$?
chk "the strip ends with REFRESH-OK, installs the six scripts and the peer checker (mode 0755), and no TC_ name except TC_LOG is left in them" $([ $rc = 0 ] && grep -q '^REFRESH-OK' <<<"$out" && [ "$(ls "$W/d" | wc -l)" = 7 ] && [ "$(stat -c %a "$W/d/tc-peer-verify.py")" = 755 ] && ! grep -q 'TC_' "$W/d/tc-peer-verify.py" && [ "$(grep -ohE 'TC_[A-Z0-9_]+' "$W/d"/*.sh | sort -u | tr '\n' ' ')" = "TC_LOG " ] && [ "$(stat -c %a "$W/d/tc-fleet.sh")" = 755 ]; echo $?)
chk "every stripped script parses, and the command hook of tc-extend.sh is gone with its branch" $(ok=0; for f in "$W/d"/*.sh; do bash -n "$f" || ok=1; done; ! grep -q 'TC_WRITE' "$W/d/tc-extend.sh" && grep -q '^RT="/sys/devices/virtual/misc/tdx_guest/measurements/rtmr3:sha384"' "$W/d/tc-extend.sh" || ok=1; echo $ok)
chk "the stripped scripts do what the sources do with their defaults: every default of a hook is the text that replaced it (checked for 20 samples)" $(python3 - "$L" "$W/d" <<'PY'
import re, sys, glob, os
L, D = sys.argv[1:3]; n = 0; bad = 0
for f in sorted(glob.glob(L + "/tc-*.sh")):
    src = open(f).read(); dst = open(D + "/" + os.path.basename(f)).read()
    for m in re.finditer(r'\$\{TC_([A-Z0-9_]+)(?::-|-)([^}]*)\}', src):
        if m.group(1) == "LOG": continue
        n += 1
        if m.group(2) not in dst: bad += 1
print(0 if bad == 0 and n >= 20 else 1)
PY
)
rm -rf "$W/k2" "$W/d2"; mkdir -p "$W/k2/ops/image/build" "$W/d2"; cp -r "$I/rootfs" "$W/k2/ops/image/"; cp "$I/build/tc-strip-hooks.py" "$W/k2/ops/image/build/"; echo 'echo "$TC_SNEAKY"' >> "$W/k2/ops/image/rootfs/usr/local/lib/tc/tc-report.sh"; out="$(bash "$I/build/tc-image-refresh.sh" --kit "$W/k2" --dest "$W/d2" 2>&1)"; rc=$?
chk "fault: a hook that the strip cannot remove (a bare \$TC_SNEAKY) makes the gate refuse, names it, and installs NOTHING" $([ $rc != 0 ] && grep -q 'REFRESH-STOP: these TC_ names are left after the strip: TC_LOG TC_SNEAKY' <<<"$out" && [ -z "$(ls "$W/d2")" ]; echo $?)
echo "=== R3.6: the attack scripts"
mkdir -p "$W/root/usr/lib/systemd"; head -c 100000 /dev/urandom > "$W/root/usr/lib/systemd/systemd"; mke2fs -q -t ext4 -F -b 4096 -d "$W/root" "$W/p1.img" 64M >/dev/null 2>&1; cp "$W/p1.img" "$W/p1.orig"
out="$(bash "$T/r3-flip.sh" --p1 "$W/p1.img" 2>&1)"; rc=$?; N="$(cmp -l "$W/p1.orig" "$W/p1.img" | wc -l)"; BLK="$(debugfs -R "bmap /usr/lib/systemd/systemd 0" "$W/p1.img" 2>/dev/null | tail -1)"; FIRST="$(cmp -l "$W/p1.orig" "$W/p1.img" | awk '{print $1-1}')"
chk "the flip changes exactly ONE byte (one bit), inside the first block of /usr/lib/systemd/systemd, and says so" $([ $rc = 0 ] && grep -q '^FLIP-OK' <<<"$out" && [ "$N" = 1 ] && [ "$FIRST" -ge $((BLK * 4096)) ] && [ "$FIRST" -lt $((BLK * 4096 + 4096)) ]; echo $?)
out="$(bash "$T/r3-flip.sh" --p1 "$W/p1.img" --path /no/such/file 2>&1)"; rc=$?; chk "fault: a file that is not in the file system is refused (nothing flipped)" $([ $rc != 0 ] && grep -q 'FLIP-STOP: no block' <<<"$out"; echo $?)
export DRY=1 IMG=tc-img-seal-4 OUT="$W/evd"; mkdir -p "$OUT"; dryo() { timeout 60 bash "$T/f03-drive.sh" "$@" 2>&1 | sed 's/\\//g'; }
a="$(dryo attack-root)"; chk "attack-root: a disk from the image, a helper that holds it, the flip script on the real root partition, then a VM that boots FROM that disk with its own scratch disk; the helper and nothing else is deleted" $(grep -q 'disks create tc-atk-disk --image=tc-img-seal-4' <<<"$a" && grep -q -- '--disk=name=tc-atk-disk,device-name=target,mode=rw,boot=no,auto-delete=no' <<<"$a" && grep -q 'r3-flip.sh --p1 /dev/disk/by-id/google-target-part1' <<<"$a" && grep -q 'instances create tc-atk-test .*--disk=name=tc-atk-disk,boot=yes' <<<"$a" && grep -q 'instances delete tc-sealer ' <<<"$a"; echo $?)
rm -rf "$W/ev3"; mkdir -p "$W/ev3"; ALLC="$(for s in seal-disk seal-image seal-boot attack-root; do dryo $s; done; DRY=1 IMG=tc-img-x OUT="$W/ev3" SCRATCH_GB=10 bash "$T/f1-drive.sh" fleet-vms 2>&1 | sed 's/\\//g')"
chk "GCE RULE (c3 machines boot only from pd-balanced, pd-ssd or Hyperdisk): every 'disks create' of every driver names --type=pd-balanced (or clones a disk, which keeps the type), and no command names pd-standard" $(! grep 'disks create' <<<"$ALLC" | grep -v -e '--type=pd-balanced' -e '--source-disk' | grep -q . && ! grep -q 'pd-standard' <<<"$ALLC" && [ "$(grep -c 'disks create' <<<"$ALLC")" -ge 2 ]; echo $?)
chk "GCE RULE: every VM that is created from a disk or an image for a c3 machine says pd-balanced for its own new disks (create-disk and boot-disk-type), and the attack disk's type is verified right after its creation" $(! grep 'create-disk' <<<"$ALLC" | grep -v 'type=pd-balanced' | grep -q . && grep -q "value(type.basename())" "$T/f03-drive.sh"; echo $?)
b="$(dryo attack-scratch)"; chk "attack-scratch: the first part runs, then the VM is reset (the disks stay) and the second part runs with the old file system UUID" $(grep -q 'r3-attack-scratch.sh before' <<<"$b" && grep -q 'instances reset tc-seal-test' <<<"$b"; echo $?)
c="$(CONFIRM=yes dryo seal-delete)"; chk "seal-delete also removes the attack VM and the attack disk, by their exact names, and nothing of the teammate's" $(grep -q 'instances delete tc-atk-test ' <<<"$c" && grep -q 'disks delete tc-atk-disk ' <<<"$c" && ! grep -qiE 'subhi|tdx-lab' <<<"$a$b$c"; echo $?)
d="$(dryo bake-seal)"; chk "bake-seal runs the strip BEFORE the initramfs build, and both markers are required" $(a1=$(grep -n 'tc-image-refresh.sh' <<<"$d" | head -1 | cut -d: -f1); [ -n "$a1" ] && grep -q 'tc-image-refresh.sh --kit ~/f03 && sudo bash ~/f03/ops/image/build/tc-image-sealbake.sh' <<<"$d"; echo $?)
eval "$(sed -n '/^attack_evidence()/,/^}/p' "$T/f03-drive.sh")"
chk "REAL CONSOLE of the attack on a root with one flipped bit (from the real-kernel run): the evidence check accepts it (a verity corruption error, an init that cannot run, a panic, no login)" $(attack_evidence "$T/fixtures/attack-root-console.txt"; echo $?)
printf '%s\n' 'tc-verity: the root disk matches the root hash abc' 'Kernel panic - not syncing: some other reason' > "$W/other.txt"; chk "a panic for ANOTHER reason (our own success line says 'verity' too) is NOT accepted as the refusal" $(! attack_evidence "$W/other.txt"; echo $?)
{ cat "$T/fixtures/attack-root-console.txt"; echo 'tc-seal-test login: '; } > "$W/login.txt"; chk "a console that reaches the login is NOT a refusal, whatever else it shows" $(! attack_evidence "$W/login.txt"; echo $?)
unset DRY; chk "the in-VM attack script parses, makes a marker, tampers a 400 MiB range of the RAW disk whatever the layout (no offset is read from the kernel's table), and checks both the exit code and the kernel log" $(bash -n "$T/r3-attack-scratch.sh" && grep -q 'dd of=/dev/nvme0n2' "$T/r3-attack-scratch.sh" && grep -q "Checksum failed" "$T/r3-attack-scratch.sh" && grep -q 'tc-attack-marker' "$T/r3-attack-scratch.sh" && grep -q 'seek=1 conv=notrunc' "$T/r3-attack-scratch.sh" && grep -q '419430400' "$T/r3-attack-scratch.sh" && ! grep -v '^[[:space:]]*#' "$T/r3-attack-scratch.sh" | grep -qE 'journal_sectors|OFF='; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "R7-REHEARSAL-PASS"; else echo "R7-REHEARSAL-FAIL"; fi
rm -rf "$W"; [ "$FAILN" = 0 ]
