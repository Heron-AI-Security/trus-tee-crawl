#!/usr/bin/env bash
# Steps F0.1 and F0.2, the image build part 1: make kernel 6.17 the DEFAULT kernel (not a one-time boot) and install the boot-time measurement of RTMR3.
# Run on a builder VM, or on a disposable test VM made from the Ubuntu 22.04 image, as a user with sudo. It does NOT reboot.
#   bash tc-image-prep.sh REPO_DIR [--with-placeholder]
# REPO_DIR holds ops/image/ and attest/ (quote.sh, measure/treehash.sh, measure/rtmr3_replay.py). --with-placeholder adds a TEST-ONLY unit that stands in for Hadoop.
# It replaces ops/worker-kernel-prep.sh for the image: the same checks and the same pinned packages, but a permanent default and no Hadoop to stop.
# Hooks for the rehearsal only: TC_ROOT (a fake root), TC_SUDO, TC_UNAME, TC_FREE_KB, BOOT_DIR, GRUB_D, EFI_DIR, TC_TSM, TC_CURL, TC_WORK, TC_BACKUP_DIR, TC_WAIT, TC_POLL, GRUB_FILE, DEB_SHA_IMAGE, DEB_SHA_MODULES.
set -euo pipefail
REPO="${1:?usage: $0 REPO_DIR [--with-placeholder]}"; PLACEHOLDER=no; [ "${2:-}" = "--with-placeholder" ] && PLACEHOLDER=yes
NEW=6.17.0-1022-gcp
RUNK="${TC_UNAME:-$(uname -r)}"
R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"
BOOT="${BOOT_DIR:-/boot}"; CFG="$BOOT/grub/grub.cfg"; GD="${GRUB_D:-/etc/default/grub.d}"
EFI="${EFI_DIR:-/sys/firmware/efi}"; SBVAR="$EFI/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
TSM="${TC_TSM:-/sys/kernel/config/tsm/report}"
URL=http://archive.ubuntu.com/ubuntu/pool/main/l
IMG="linux-image-6.17.0-1022-gcp_6.17.0-1022.25_amd64.deb"
MOD="linux-modules-6.17.0-1022-gcp_6.17.0-1022.25_amd64.deb"
SHA_IMG="${DEB_SHA_IMAGE:-d7d0052d4534fdca991efaf32af81864b577b13e27f4e5449f4d663598ea3b96}"
SHA_MOD="${DEB_SHA_MODULES:-b0ecac54e326ebad0aee134ed55a785c564a4b97a22d3cdebb72bcbea39ec76f}"
ENTRY="Advanced options for Ubuntu>Ubuntu, with Linux $NEW"
fail() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }

say "pre-flight"
for t in python3 sha384sum sha256sum od awk curl; do command -v "$t" >/dev/null || fail "the tool $t is missing"; done
if ! command -v xxd >/dev/null; then $SUDO apt-get install -y xxd >/dev/null 2>&1 || fail "the tool xxd is missing and could not be installed"; fi
case "$RUNK" in 6.8.0-*-gcp|"$NEW") ;; *) fail "unexpected running kernel: $RUNK" ;; esac
[ -d "$EFI" ] || fail "not an EFI boot"
SB="$($SUDO od -An -t u1 "$SBVAR" | awk '{print $NF}')"
[ "$SB" = "0" ] || fail "Secure Boot is not off (value $SB)"
[ -f "$GD/40-force-partuuid.cfg" ] || fail "initrdless setup (40-force-partuuid.cfg) not found"
FREE_KB="${TC_FREE_KB:-$(df --output=avail / | tail -1 | tr -d ' ')}"
[ "$FREE_KB" -gt 1500000 ] || fail "less than 1.5 GB free on /"
[ -d "$TSM" ] || fail "no configfs-tsm at $TSM: this is not a TDX guest"
for f in ops/image/rootfs/usr/local/lib/tc/tc-extend.sh ops/image/rootfs/usr/local/lib/tc/tc-measure.sh ops/image/rootfs/etc/tc/measured-paths.txt ops/image/rootfs/etc/systemd/system/tc-measure.service ops/image/rootfs/etc/systemd/system/tc-placeholder.service attest/quote.sh attest/measure/treehash.sh attest/measure/rtmr3_replay.py; do
  [ -f "$REPO/$f" ] || fail "missing in $REPO: $f"
done
$SUDO grep -q "menuentry 'Ubuntu, with Linux $RUNK' " "$CFG" || fail "no GRUB menu entry for the running kernel"
echo "running kernel $RUNK, ${FREE_KB} KB free, Secure Boot off, TDX guest"

say "freeze automatic package changes (they would change measured files between boots)"
# Only a RUN of a package tool blocks. The permanent daemon of unattended-upgrades (unattended-upgrade-shutdown, which every Ubuntu machine has) is not a package job, so it must not match.
busy() { pgrep -x dpkg >/dev/null || pgrep -x apt-get >/dev/null || pgrep -x apt >/dev/null || pgrep -x apt.systemd.dai >/dev/null || pgrep -f '/usr/bin/unattended-upgrade( |$)' >/dev/null; }
WAIT="${TC_WAIT:-300}"; POLL="${TC_POLL:-5}"; waited=0
while busy; do
  [ "$waited" -lt "$WAIT" ] || fail "a package job is still running after $WAIT seconds; run again later"
  [ "$waited" != 0 ] || echo "a package job is running (updates after the first boot are normal); waiting up to $WAIT seconds"
  sleep "$POLL"; waited=$((waited + POLL))
done
UP="unattended-upgrades.service apt-daily.timer apt-daily-upgrade.timer apt-daily.service apt-daily-upgrade.service"
# shellcheck disable=SC2086
$SUDO systemctl stop $UP >/dev/null 2>&1 || true
# shellcheck disable=SC2086
$SUDO systemctl mask $UP >/dev/null 2>&1 || fail "could not stop the automatic upgrades"
echo "automatic upgrades are stopped and masked"

say "backup GRUB files"
B="${TC_BACKUP_DIR:-/root}/grub-backup-$(date +%Y%m%d%H%M%S)"
$SUDO mkdir -p "$B"; $SUDO cp -a "${GRUB_FILE:-/etc/default/grub}" "$GD" "$CFG" "$B"/
echo "saved in $B"

if [ ! -f "$BOOT/vmlinuz-$NEW" ]; then
  say "download and verify the 6.17 packages"
  D="${TC_WORK:-$HOME/k617}"; mkdir -p "$D"; cd "$D"
  ${TC_CURL:-curl} -fsSO "$URL/linux-signed-gcp-6.17/$IMG"
  ${TC_CURL:-curl} -fsSO "$URL/linux-gcp-6.17/$MOD"
  printf '%s  %s\n' "$SHA_IMG" "$IMG" "$SHA_MOD" "$MOD" | sha256sum --strict -c - || fail "package checksum mismatch"
  say "install"
  $SUDO dpkg -i "$MOD" "$IMG" > "$D/dpkg.log" 2>&1 || { tail -30 "$D/dpkg.log"; fail "dpkg failed"; }
  cd - >/dev/null
else
  say "the 6.17 packages are already installed"
fi
[ -f "$BOOT/vmlinuz-$NEW" ] || fail "kernel file missing after install"
grep -q '^CONFIG_TSM_MEASUREMENTS=y' "$BOOT/config-$NEW" || fail "measurement option not enabled in the kernel $NEW"
$SUDO grep -q "menuentry 'Ubuntu, with Linux $NEW' " "$CFG" || fail "no GRUB menu entry for $NEW"

say "make $NEW the default kernel (permanent, not a one-time boot)"
echo 'GRUB_DEFAULT=saved' | $SUDO tee "$GD/zz-saved-default.cfg" >/dev/null
$SUDO update-grub >/dev/null 2>&1 || fail "update-grub failed"
$SUDO grub-set-default "$ENTRY"
$SUDO grub-editenv - unset next_entry
ENV="$($SUDO grub-editenv list)"
printf '%s\n' "$ENV" | grep -qxF "saved_entry=$ENTRY" || fail "the default was not recorded"
if printf '%s\n' "$ENV" | grep -q '^next_entry='; then fail "a one-time entry is still set"; fi
$SUDO grep -qF 'set default="${saved_entry}"' "$CFG" || fail "grub.cfg does not use the saved entry"
echo "default: $NEW"

say "install the measurement"
if [ ! -e "$R/usr/bin/wg" ]; then $SUDO apt-get install -y wireguard-tools >/dev/null 2>&1 || fail "could not install wireguard-tools (the list measures wg)"; fi
$SUDO install -d -m 0755 "$R/usr/local/lib/tc" "$R/etc/tc" "$R/etc/systemd/system"
for f in tc-extend.sh tc-measure.sh; do $SUDO install -m 0755 "$REPO/ops/image/rootfs/usr/local/lib/tc/$f" "$R/usr/local/lib/tc/$f"; done
$SUDO install -m 0755 "$REPO/attest/measure/treehash.sh" "$R/usr/local/lib/tc/treehash.sh"
$SUDO install -m 0755 "$REPO/attest/measure/rtmr3_replay.py" "$R/usr/local/lib/tc/rtmr3_replay.py"
$SUDO install -m 0755 "$REPO/attest/quote.sh" "$R/usr/local/lib/tc/quote.sh"
$SUDO install -m 0644 "$REPO/ops/image/rootfs/etc/tc/measured-paths.txt" "$R/etc/tc/measured-paths.txt"
$SUDO install -m 0644 "$REPO/ops/image/rootfs/etc/systemd/system/tc-measure.service" "$R/etc/systemd/system/tc-measure.service"
UNITS="tc-measure.service"
if [ "$PLACEHOLDER" = yes ]; then $SUDO install -m 0644 "$REPO/ops/image/rootfs/etc/systemd/system/tc-placeholder.service" "$R/etc/systemd/system/tc-placeholder.service"; UNITS="$UNITS tc-placeholder.service"; fi
$SUDO systemctl daemon-reload
for u in $UNITS; do $SUDO systemctl enable "$u" >/dev/null 2>&1 || fail "could not enable $u"; done
TC_ROOT="$R" TC_LIST="$R/etc/tc/measured-paths.txt" TC_LIB="$R/usr/local/lib/tc" "$R/usr/local/lib/tc/tc-measure.sh" --check-list || fail "the measured list does not match this machine"
echo "installed and enabled: $UNITS"
echo
echo "READY (nothing was rebooted). If everything above looks right, run:  sudo reboot"
