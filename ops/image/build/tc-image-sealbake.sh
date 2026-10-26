#!/usr/bin/env bash
# Step R3.3, on the BUILDER: install the sealed boot's initramfs sources, build the sealed initramfs INTO /tmp, VERIFY it in many small checks (what is inside it, that its tools RUN with their libraries, that its scripts are
# byte for byte the sources), and only then install it as /boot/initrd.img-tc with its checksum. The stock initramfs and the stock initramfs configuration are not touched (mkinitramfs -d uses a separate folder).
#   tc-image-sealbake.sh --kit DIR --kver KVER [--sde N]            build, verify, install
#   tc-image-sealbake.sh --verify-only FILE --kver KVER --conf DIR   only the verification (gates 4 and 5) of an existing initramfs
# FAIL FAST: gates 1 and 2 (seconds) look at the machine and the sources, gate 3 builds (about a minute), gates 4 and 5 verify (seconds); nothing is installed before all of them passed.
set -uo pipefail
KIT="${HOME:-/root}/f03"; KVER=""; SDE=1767225600; VONLY=""; CONF=/etc/tc/initramfs-tools
while [ $# -gt 0 ]; do case "$1" in --kit) KIT="$2"; shift 2 ;; --kver) KVER="$2"; shift 2 ;; --sde) SDE="$2"; shift 2 ;; --verify-only) VONLY="$2"; shift 2 ;; --conf) CONF="$2"; shift 2 ;; *) echo "SEALBAKE-STOP: unknown argument $1" >&2; exit 2 ;; esac; done
say() { echo; echo "== $*"; }; ok() { echo "   ok:   $*"; }; die() { echo "SEALBAKE-STOP: $*" >&2; exit 1; }
W="$(mktemp -d /tmp/sealbake.XXXXXX)"; trap 'rm -rf "$W"' EXIT
[ "$(id -u)" = 0 ] || die "run as root (sudo)"
[[ "$KVER" =~ ^[0-9]+\.[0-9]+\.[0-9]+-[0-9]+-gcp$ ]] || die "give --kver like 6.17.0-1022-gcp"
verify_initrd() { # FILE: gates 4 and 5
  local F="$1" R
  say "gate 4 (seconds): what is INSIDE the initramfs"
  [ -s "$F" ] || die "the initramfs is empty"; local SZ; SZ="$(stat -c %s "$F")"; [ "$SZ" -gt 100000 ] && [ "$SZ" -lt 31457280 ] || die "the initramfs has an odd size ($SZ bytes: expected 100 KB to 30 MB)"
  lsinitramfs "$F" > "$W/ls.txt" 2>/dev/null || die "the initramfs cannot be listed"
  for p in 'scripts/local-top/tc-verity$' 'scripts/local-top/tc-scratch-dev$' 'scripts/init-bottom/tc-scratch-bind$' 'scripts/init-bottom/overlayroot$' 'dm-verity\.ko' 'dm-integrity\.ko' 'dm-crypt\.ko' 'dm-bufio\.ko' 'authenc\.ko' 'overlay\.ko' 'sbin/veritysetup$' 'sbin/cryptsetup$' 'sbin/integritysetup$' 'sbin/blkdiscard$' 'sbin/mke2fs$' 'sbin/blkid$' '(^|/)busybox$'; do
    grep -qE "$p" "$W/ls.txt" || die "the initramfs lacks $p"; done
  ok "the verity script, the two scratch scripts, the overlay script, the six modules, the six tools and busybox are in it ($SZ bytes)"
  say "gate 5 (seconds): unpack it, run its tools with their libraries, and compare its scripts with the sources"
  rm -rf "$W/ird"; mkdir -p "$W/ird"; unmkinitramfs "$F" "$W/ird" >/dev/null 2>&1 || die "the initramfs cannot be unpacked"
  if [ -d "$W/ird/main" ]; then R="$W/ird/main"; else R="$W/ird"; fi
  for c in "/sbin/veritysetup --version" "/sbin/cryptsetup --version" "/sbin/integritysetup --version" "/sbin/blkdiscard --version" "/sbin/mke2fs -V" "/sbin/blkid -V"; do
    chroot "$R" $c >"$W/run.log" 2>&1 || { tail -3 "$W/run.log"; die "${c%% *} cannot be run inside the initramfs (a missing library or file; the boot would fail here)"; }; done
  ok "veritysetup, cryptsetup, integritysetup, blkdiscard, mke2fs and blkid run inside the unpacked initramfs"
  for s in scripts/local-top/tc-verity scripts/local-top/tc-scratch-dev scripts/init-bottom/tc-scratch-bind; do
    cmp -s "$R/$s" "$CONF/$s" || die "$s in the initramfs is not the same as the source in $CONF"; dash -n "$R/$s" || die "$s does not parse"; done
  ok "the verity script and the two scratch scripts are byte for byte the sources, and parse under dash"
  grep -q 'local-top/tc-verity' "$R/scripts/local-top/ORDER" || die "the order file of local-top does not run tc-verity"
  grep -q 'local-top/tc-scratch-dev' "$R/scripts/local-top/ORDER" || die "the order file of local-top does not run tc-scratch-dev"
  v="$(grep -n 'local-top/tc-verity' "$R/scripts/local-top/ORDER" | head -1 | cut -d: -f1)"; d="$(grep -n 'local-top/tc-scratch-dev' "$R/scripts/local-top/ORDER" | head -1 | cut -d: -f1)"
  [ "$v" -lt "$d" ] || die "in local-top the verity script must run BEFORE the scratch disk script (order lines: tc-verity=$v, tc-scratch-dev=$d)"
  a="$(grep -n 'init-bottom/overlayroot' "$R/scripts/init-bottom/ORDER" | head -1 | cut -d: -f1)"; b="$(grep -n 'init-bottom/tc-scratch-bind' "$R/scripts/init-bottom/ORDER" | head -1 | cut -d: -f1)"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ] || die "in init-bottom the overlay must run BEFORE the scratch script (order lines: overlayroot=${a:-none}, tc-scratch-bind=${b:-none})"
  ok "the order is right: in local-top tc-verity, then tc-scratch-dev (udev still runs); in init-bottom the overlay, then the scratch mounts"
  # an initramfs may have several segments (early/ and main/): the modules and their index are searched in the WHOLE unpacked tree
  DEP="$(find "$W/ird" -name modules.dep | head -1)"; [ -n "$DEP" ] || die "the initramfs has no module index (modules.dep)"
  for m in dm-verity dm-integrity dm-crypt dm-bufio authenc overlay; do
    [ -n "$(find "$W/ird" -name "$m.ko*" | head -1)" ] || die "the module $m is not in the initramfs"; grep -qE "(^|/)$m\.ko[^:]*:" "$DEP" || die "the module $m is not in the module index (modules.dep)"; done
  for m in dm-verity:dm-bufio dm-integrity:dm-bufio; do d="${m%%:*}"; e="${m##*:}"; grep -E "(^|/)$d\.ko[^:]*:" "$DEP" | grep -q "$e\.ko" || die "the module index does not list $e as a dependency of $d (it would not load)"; done
  ok "the six modules are there and indexed, and dm-verity and dm-integrity list dm-bufio as their dependency"
}
if [ -n "$VONLY" ]; then verify_initrd "$VONLY"; echo; echo "SEALBAKE-VERIFY-OK"; exit 0; fi
SRC="$KIT/ops/image/rootfs/etc/tc"
say "gate 1 (seconds): the machine and the kit"
[ -f "/boot/vmlinuz-$KVER" ] && [ -f "/lib/modules/$KVER/modules.dep" ] || die "the kernel $KVER or its modules are not installed on this machine"
for t in mkinitramfs lsinitramfs unmkinitramfs veritysetup cryptsetup mke2fs blkid cpio gzip dash chroot sha256sum; do command -v "$t" >/dev/null || die "missing tool: $t"; done
for pkg in cryptsetup-bin cryptsetup-initramfs dmsetup overlayroot initramfs-tools busybox-initramfs; do dpkg -s "$pkg" 2>/dev/null | grep -q '^Status: install ok installed' || die "the package $pkg is not installed"; done
for f in initramfs-tools/initramfs.conf initramfs-tools/modules initramfs-tools/hooks/tc-seal initramfs-tools/scripts/local-top/tc-verity initramfs-tools/scripts/local-top/tc-scratch-dev initramfs-tools/scripts/init-bottom/tc-scratch-bind grub-sealed.cfg.in; do [ -f "$SRC/$f" ] || die "the kit lacks $f"; done
[ "$(df -m /tmp | awk 'NR==2 {print $4}')" -ge 300 ] || die "less than 300 MB free in /tmp"
ok "kernel $KVER and its modules, the tools, the six packages, and the kit's files"
say "gate 2 (seconds): the sources parse, and the GRUB template is complete"
for f in hooks/tc-seal scripts/local-top/tc-verity scripts/local-top/tc-scratch-dev scripts/init-bottom/tc-scratch-bind; do dash -n "$SRC/initramfs-tools/$f" || die "$f does not parse under dash"; done
grep -qx 'MODULES=list' "$SRC/initramfs-tools/initramfs.conf" || die "initramfs.conf does not say MODULES=list"
for p in ROOTFS_UUID KVER ROOTHASH BLOCKS SALT DATA_PARTUUID; do grep -q "@$p@" "$SRC/grub-sealed.cfg.in" || die "the GRUB template has no @$p@"; done
ok "the four scripts parse, MODULES=list, and the template has its six placeholders"
say "gate 3 (about a minute): install the sources (root-owned) and build the initramfs INTO $W"
rm -rf "$CONF"; mkdir -p /etc/tc; cp -a "$SRC/initramfs-tools" "$CONF"; chown -R root:root "$CONF"; chmod 755 "$CONF/hooks/tc-seal" "$CONF/scripts/local-top/tc-verity" "$CONF/scripts/local-top/tc-scratch-dev" "$CONF/scripts/init-bottom/tc-scratch-bind"; chmod 644 "$CONF/initramfs.conf" "$CONF/modules"
install -m 0644 -o root -g root "$SRC/grub-sealed.cfg.in" /etc/tc/grub-sealed.cfg.in
( SOURCE_DATE_EPOCH="$SDE" mkinitramfs -d "$CONF" -o "$W/initrd.tc" "$KVER" ) >"$W/mk.log" 2>&1 || { tail -15 "$W/mk.log"; die "mkinitramfs failed"; }
grep -E '^E:' "$W/mk.log" && die "mkinitramfs reported errors"; [ -s "$W/initrd.tc" ] || die "mkinitramfs wrote nothing"
ok "built: $(stat -c %s "$W/initrd.tc") bytes$(grep -c '^W:' "$W/mk.log" | awk '$1>0 {print "; "$1" warning(s) in the log"}')"
verify_initrd "$W/initrd.tc"
say "gate 6: install (only now)"
install -m 0644 -o root -g root "$W/initrd.tc" /boot/initrd.img-tc
( cd /boot && sha256sum initrd.img-tc | sed 's#  initrd.img-tc#  /boot/initrd.img-tc#' > initrd.img-tc.sha256 )
cmp -s "$W/initrd.tc" /boot/initrd.img-tc || die "the installed initramfs differs from the verified one"
ok "/boot/initrd.img-tc installed ($(cut -d' ' -f1 /boot/initrd.img-tc.sha256 | cut -c1-16)...), with its checksum file"
echo; echo "SEALBAKE-OK initrd_sha256=$(cut -d' ' -f1 /boot/initrd.img-tc.sha256)"
