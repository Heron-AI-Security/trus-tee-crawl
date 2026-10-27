#!/usr/bin/env bash
# Rehearsal of the builder-side script of step R3.3 (tc-image-sealbake.sh). The verification (gates 4 and 5) runs for real on a small initramfs that is made by hand from the REAL veritysetup, cryptsetup, mke2fs and blkid with
# their libraries and the REAL scripts; faults (a missing library, a changed script, a wrong order, a missing module) must be caught there. The build itself (mkinitramfs against the kernel's modules) is for the builder:
# in the sandbox only its failure path is rehearsed. Needs root, cryptsetup-bin, e2fsprogs, cpio, initramfs-tools-core.
#   bash r3-bake-rehearse.sh KITDIR
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; SB="$I/build/tc-image-sealbake.sh"; SRC="$I/rootfs/etc/tc"; CONF="$SRC/initramfs-tools"; PASS=0; FAILN=0; KV=6.17.0-1022-gcp
chk() { local t="$1"; shift; if [ "${1:-1}" = 0 ]; then echo "  pass: $t"; PASS=$((PASS+1)); else echo "  FAIL: $t"; FAILN=$((FAILN+1)); fi; }
for t in veritysetup cryptsetup integritysetup blkdiscard mke2fs blkid cpio lsinitramfs unmkinitramfs dash chroot; do command -v $t >/dev/null || { echo "  FAIL: the rehearsal needs $t"; exit 2; }; done; [ "$(id -u)" = 0 ] || { echo "  FAIL: needs root"; exit 2; }
W="$(mktemp -d)"
cpbin() { # SRC DESTINATION-IN-THE-INITRAMFS: the binary and every library that ldd names, at the same paths
  local s="$(readlink -f "$1")"; mkdir -p "$R/$(dirname "$2")"; cp "$s" "$R/$2"; ldd "$s" 2>/dev/null | awk '/=>/ {print $3} /ld-linux/ {print $1}' | grep '^/' | while read -r l; do mkdir -p "$R/$(dirname "$l")"; [ -e "$R$l" ] || cp -L "$l" "$R$l"; done; }
mkird() { # NAME: a hand-made initramfs in $R and $W/NAME.cpio.gz; fault options from the environment: NO_LIB NO_SCRIPT BAD_ORDER NO_VERITY_ORDER NO_DEV_ORDER BAD_LOCAL_ORDER CHANGED_SCRIPT NO_MODULE NO_DEP TINY
  R="$W/$1"; rm -rf "$R"; mkdir -p "$R/scripts/local-top" "$R/scripts/init-bottom" "$R/bin" "$R/usr/lib/modules/$KV/kernel/drivers/md" "$R/etc"
  cpbin /usr/sbin/veritysetup sbin/veritysetup; cpbin /usr/sbin/cryptsetup sbin/cryptsetup; cpbin /usr/sbin/integritysetup sbin/integritysetup; cpbin "$(command -v blkdiscard)" sbin/blkdiscard; cpbin /usr/sbin/mke2fs sbin/mke2fs; cpbin /usr/sbin/blkid sbin/blkid; echo busybox > "$R/bin/busybox"
  [ -n "${NO_SCRIPT:-}" ] || cp "$CONF/scripts/local-top/tc-verity" "$R/scripts/local-top/tc-verity"; cp "$CONF/scripts/local-top/tc-scratch-dev" "$R/scripts/local-top/tc-scratch-dev"; cp "$CONF/scripts/init-bottom/tc-scratch-bind" "$R/scripts/init-bottom/tc-scratch-bind"; echo overlayroot > "$R/scripts/init-bottom/overlayroot"
  [ -z "${CHANGED_SCRIPT:-}" ] || echo "# changed" >> "$R/scripts/init-bottom/tc-scratch-bind"
  if [ -n "${NO_VERITY_ORDER:-}" ]; then printf '/scripts/local-top/udev "$@"\n/scripts/local-top/tc-scratch-dev "$@"\n' > "$R/scripts/local-top/ORDER"
  elif [ -n "${NO_DEV_ORDER:-}" ]; then printf '/scripts/local-top/tc-verity "$@"\n' > "$R/scripts/local-top/ORDER"
  elif [ -n "${BAD_LOCAL_ORDER:-}" ]; then printf '/scripts/local-top/tc-scratch-dev "$@"\n/scripts/local-top/tc-verity "$@"\n' > "$R/scripts/local-top/ORDER"
  else printf '/scripts/local-top/tc-verity "$@"\n/scripts/local-top/tc-scratch-dev "$@"\n' > "$R/scripts/local-top/ORDER"; fi
  if [ -n "${BAD_ORDER:-}" ]; then printf '/scripts/init-bottom/tc-scratch-bind "$@"\n/scripts/init-bottom/overlayroot "$@"\n' > "$R/scripts/init-bottom/ORDER"; else printf '/scripts/init-bottom/overlayroot "$@"\n/scripts/init-bottom/tc-scratch-bind "$@"\n' > "$R/scripts/init-bottom/ORDER"; fi
  : > "$R/usr/lib/modules/$KV/modules.dep"; for m in dm-verity dm-integrity dm-crypt dm-bufio authenc overlay; do [ "$m" = "${NO_MODULE:-}" ] || echo x > "$R/usr/lib/modules/$KV/kernel/drivers/md/$m.ko"; dep=""; case "$m" in dm-verity|dm-integrity) dep=" kernel/drivers/md/dm-bufio.ko" ;; esac; [ "$m" = "${NO_DEP:-}" ] || echo "kernel/drivers/md/$m.ko:$dep" >> "$R/usr/lib/modules/$KV/modules.dep"; done
  [ -z "${NO_LIB:-}" ] || rm -f "$R"/lib/x86_64-linux-gnu/libcryptsetup.so.12 "$R"/usr/lib/x86_64-linux-gnu/libcryptsetup.so.12
  if [ -n "${TINY:-}" ]; then rm -rf "$R"/*; echo x > "$R/x"; fi
  ( cd "$R" && find . | cpio -o -H newc --quiet | gzip -n ) > "$W/$1.cpio.gz"; }
vfy() { out="$(bash "$SB" --verify-only "$W/$1.cpio.gz" --kver "$KV" --conf "$CONF" 2>&1)"; rc=$?; }
echo "=== A. the verification of an initramfs (gates 4 and 5), for real"
unset NO_LIB NO_SCRIPT BAD_ORDER NO_VERITY_ORDER NO_DEV_ORDER BAD_LOCAL_ORDER CHANGED_SCRIPT NO_MODULE NO_DEP TINY; mkird good; vfy good; echo "$out" | tail -3 | cut -c1-160
chk "a good initramfs: SEALBAKE-VERIFY-OK, and its six tools were run inside the unpacked tree" $([ $rc = 0 ] && grep -q 'SEALBAKE-VERIFY-OK' <<<"$out" && grep -q 'veritysetup, cryptsetup, integritysetup, blkdiscard, mke2fs and blkid run inside' <<<"$out"; echo $?)
vfault() { # NAME DESCRIPTION WORDS (the options from the environment)
  mkird "$1"; vfy "$1"; chk "fault: $2: SEALBAKE-STOP, says '$3'" $([ $rc != 0 ] && grep -q '^SEALBAKE-STOP: ' <<<"$out" && grep -q -- "$3" <<<"$out" && ! grep -q 'SEALBAKE-VERIFY-OK' <<<"$out"; echo $?); unset NO_LIB NO_SCRIPT BAD_ORDER NO_VERITY_ORDER NO_DEV_ORDER BAD_LOCAL_ORDER CHANGED_SCRIPT NO_MODULE NO_DEP TINY; }
NO_LIB=1 vfault v1 "a shared library of cryptsetup is missing (this would fail at BOOT)" "cannot be run inside the initramfs"
NO_SCRIPT=1 vfault v2 "the verity script is not in it" "lacks scripts/local-top/tc-verity"
BAD_ORDER=1 vfault v3 "the scratch script would run before the overlay" "the overlay must run BEFORE the scratch script"
CHANGED_SCRIPT=1 vfault v4 "a script that is not the source" "is not the same as the source"
NO_MODULE=dm-verity vfault v5 "the dm-verity module is missing" "lacks dm-verity"
NO_DEP=dm-integrity vfault v6 "a module that is not in the module index" "not in the module index"
TINY=1 vfault v7 "an almost empty initramfs" "odd size"
NO_DEV_ORDER=1 vfault v9 "the order file does not run the scratch disk script" "does not run tc-scratch-dev"
BAD_LOCAL_ORDER=1 vfault v10 "the scratch disk script would run BEFORE the verity script" "the verity script must run BEFORE the scratch disk script"
NO_VERITY_ORDER=1 vfault v8 "the verity script is in the initramfs but the order file does not run it (the machine would boot an UNVERIFIED root)" "does not run tc-verity"
echo "=== B. the gates before the build, and the failure path of the build"
unset NO_LIB; mkdir -p /boot /lib/modules/6.17.0-8888-gcp; touch /boot/vmlinuz-6.17.0-8888-gcp /lib/modules/6.17.0-8888-gcp/modules.dep; mkdir -p "$W/fakebin"; printf '#!/bin/sh\necho "Status: install ok installed"\n' > "$W/fakebin/dpkg"; chmod +x "$W/fakebin/dpkg"
run() { out="$(PATH="$W/fakebin:$PATH" bash "$SB" --kit "$1" --kver "${2:-6.17.0-8888-gcp}" 2>&1)"; rc=$?; }
run "$KIT" 6.17.0-9999-gcp; chk "fault: a kernel that is not installed stops at gate 1" $([ $rc != 0 ] && grep -q 'kernel 6.17.0-9999-gcp or its modules are not installed' <<<"$out"; echo $?)
run /nonexistent; chk "fault: a kit without the sources stops at gate 1" $([ $rc != 0 ] && grep -q 'the kit lacks initramfs-tools/initramfs.conf' <<<"$out"; echo $?)
cpkit() { rm -rf "$W/kit"; mkdir -p "$W/kit/ops/image/rootfs/etc"; cp -r "$SRC" "$W/kit/ops/image/rootfs/etc/tc"; }
cpkit; echo 'if [' >> "$W/kit/ops/image/rootfs/etc/tc/initramfs-tools/scripts/local-top/tc-verity"; run "$W/kit"; chk "fault: a script with a syntax error stops at gate 2, before any build" $([ $rc != 0 ] && grep -q 'tc-verity does not parse under dash' <<<"$out" && ! grep -q 'gate 3' <<<"$out"; echo $?)
cpkit; sed -i 's/^MODULES=list/MODULES=most/' "$W/kit/ops/image/rootfs/etc/tc/initramfs-tools/initramfs.conf"; run "$W/kit"; chk "fault: a configuration that is not MODULES=list stops at gate 2" $([ $rc != 0 ] && grep -q 'does not say MODULES=list' <<<"$out"; echo $?)
cpkit; sed -i 's/@SALT@/nosalt/' "$W/kit/ops/image/rootfs/etc/tc/grub-sealed.cfg.in"; run "$W/kit"; chk "fault: a GRUB template without a placeholder stops at gate 2" $([ $rc != 0 ] && grep -q 'has no @SALT@' <<<"$out"; echo $?)
BKV="$(ls -d /lib/modules/*-gcp 2>/dev/null | xargs -n1 basename 2>/dev/null | grep -E '^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-gcp$' | sort -V | tail -1)"
cpkit; sed -i 's/^exit 0$/exit 3/' "$W/kit/ops/image/rootfs/etc/tc/initramfs-tools/hooks/tc-seal"; touch "/boot/vmlinuz-6.17.0-8888-gcp"
if [ -n "$BKV" ]; then
  rm -f /boot/initrd.img-tc /boot/initrd.img-tc.sha256; touch "/boot/vmlinuz-$BKV"; D0="$(find /etc/initramfs-tools -type f 2>/dev/null | sort | xargs -r sha256sum | sha256sum)"
  out="$(PATH="$PATH" bash "$SB" --kit "$W/kit" --kver "$BKV" 2>&1)"; rc=$?
  chk "fault: a hook that fails makes the build fail with a clear message, and NOTHING is installed (no /boot/initrd.img-tc, no checksum file)" $([ $rc != 0 ] && grep -q 'SEALBAKE-STOP: mkinitramfs failed' <<<"$out" && [ ! -e /boot/initrd.img-tc ] && [ ! -e /boot/initrd.img-tc.sha256 ]; echo $?)
  echo "--- the REAL build, with the real hook and the real kernel modules of $BKV (the image's own 6.17 kernel is for the builder)"
  out="$(bash "$SB" --kit "$KIT" --kver "$BKV" 2>&1)"; rc=$?; echo "$out" | tail -4 | cut -c1-170
  chk "the real build ends with SEALBAKE-OK: gates 1 to 5 pass on a REAL initramfs (the hook, the six modules, the tools that run, the scripts equal to the sources, the right order), and it is installed" $([ $rc = 0 ] && grep -q '^SEALBAKE-OK initrd_sha256=' <<<"$out" && [ -s /boot/initrd.img-tc ] && [ "$(cut -d' ' -f1 /boot/initrd.img-tc.sha256)" = "$(sha256sum /boot/initrd.img-tc | cut -d' ' -f1)" ]; echo $?)
  chk "the stock initramfs configuration (/etc/initramfs-tools) is untouched by the build" $([ "$D0" = "$(find /etc/initramfs-tools -type f 2>/dev/null | sort | xargs -r sha256sum | sha256sum)" ]; echo $?)
  chk "the sealed initramfs carries only what it needs: it is far smaller than a stock one (under 30 MB) and has no stock root-device hook such as cryptroot's prompt" $([ "$(stat -c %s /boot/initrd.img-tc)" -lt 31457280 ] && ! lsinitramfs /boot/initrd.img-tc | grep -q 'cryptroot-unlock'; echo $?)
  echo "--- step R4.4: two REAL builds of the same sources with a hook that writes what the real overlayroot and mdadm hooks write (a random seed, the clock time)"
  cpkit; HK="$W/kit/ops/image/rootfs/etc/tc/initramfs-tools/hooks/zz-test-volatile"
  printf '%s\n' '#!/bin/sh' 'PREREQ=""' 'prereqs() { echo "$PREREQ"; }' 'case "$1" in prereqs) prereqs; exit 0;; esac' '. /usr/share/initramfs-tools/hook-functions' 'dd if=/dev/urandom of="${DESTDIR}/.random-seed" bs=4096 count=1 2>/dev/null' 'mkdir -p "${DESTDIR}/etc/mdadm"' 'printf "# mdadm.conf\n# This configuration was auto-generated on %s by mkconf\n" "$(date -R)" > "${DESTDIR}/etc/mdadm/mdadm.conf"' 'exit 0' > "$HK"; chmod 755 "$HK"
  rm -f /boot/initrd.img-tc /boot/initrd.img-tc.sha256; out1="$(bash "$SB" --kit "$W/kit" --kver "$BKV" 2>&1)"; rc1=$?; H1="$(sha256sum /boot/initrd.img-tc 2>/dev/null | cut -d' ' -f1)"; cp /boot/initrd.img-tc "$W/ird1.img" 2>/dev/null
  sleep 2; rm -f /boot/initrd.img-tc /boot/initrd.img-tc.sha256; out2="$(bash "$SB" --kit "$W/kit" --kver "$BKV" 2>&1)"; rc2=$?; H2="$(sha256sum /boot/initrd.img-tc 2>/dev/null | cut -d' ' -f1)"
  chk "step R4.4: two real builds of the same sources, two seconds apart, with a hook that writes a random seed and the clock time, install the SAME initramfs (byte for byte)" $([ $rc1 = 0 ] && [ $rc2 = 0 ] && [ -n "$H1" ] && [ "$H1" = "$H2" ]; echo $?)
  printf '%s\n' 'import gzip, sys' 'raw = open(sys.argv[1], "rb").read(); off = 0 if raw[:2] == b"\x1f\x8b" else raw.find(b"\x1f\x8b\x08"); dec = gzip.decompress(raw[off:]); p = 0; found = {}' 'while True:' '    f = [int(dec[p + 6 + 8 * i:p + 14 + 8 * i], 16) for i in range(13)]; size, nsize = f[6], f[11]; name = dec[p + 110:p + 110 + nsize - 1].decode(); q = (p + 110 + nsize + 3) & ~3; found[name] = dec[q:q + size]; p = (q + size + 3) & ~3' '    if name == "TRAILER!!!": break' 'ok = found.get(".random-seed") == bytes(4096) and b"auto-generated on Thu, 01 Jan 2026 00:00:00 +0000 by mkconf" in found.get("etc/mdadm/mdadm.conf", b"")' 'sys.exit(0 if ok else 1)' > "$W/chkinit.py"
  chk "step R4.4: the installed initramfs carries a seed of zeros (not the build machine's random bytes) and the fixed time of SOURCE_DATE_EPOCH in mdadm.conf" $(python3 -B "$W/chkinit.py" /boot/initrd.img-tc >/dev/null 2>&1; echo $?)
  chk "step R4.4: the checksum file that the build writes is the SHA-256 of the installed (normalized) initramfs" $([ "$(cut -d' ' -f1 /boot/initrd.img-tc.sha256)" = "$H2" ]; echo $?)
  rm -f "/boot/vmlinuz-$BKV" /boot/initrd.img-tc /boot/initrd.img-tc.sha256
else echo "  note: no gcp kernel modules are installed here, so the REAL build test is skipped (the builder runs it)"; fi
rm -rf /boot/vmlinuz-6.17.0-8888-gcp /lib/modules/6.17.0-8888-gcp /etc/tc/initramfs-tools /etc/tc/grub-sealed.cfg.in; rmdir /etc/tc 2>/dev/null
echo "=== C. the order in the script itself"
L() { grep -n "$1" "$SB" | head -1 | cut -d: -f1; }
chk "the initramfs is verified BEFORE it is installed, the checksum file is written after the install, and mkinitramfs uses its own configuration folder (-d) and writes into the temporary folder" $(a=$(L 'verify_initrd "\$W/initrd.tc"'); b=$(L 'install -m 0644 -o root -g root "\$W/initrd.tc" /boot/initrd.img-tc'); c=$(L 'sha256sum initrd.img-tc'); [ "$a" -lt "$b" ] && [ "$b" -lt "$c" ] && grep -q 'mkinitramfs -d "\$CONF" -o "\$W/initrd.tc"' "$SB"; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "R3-BAKE-REHEARSAL-PASS"; else echo "R3-BAKE-REHEARSAL-FAIL"; fi
rm -rf "$W"; [ "$FAILN" = 0 ]
