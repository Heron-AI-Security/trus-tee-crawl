#!/usr/bin/env bash
# Phase 4 (steps F0.4, F0.5 and F0.6): the last layer of the image, in one of two modes. On the builder, after tc-image-fleet.sh:
#   bash tc-image-lock.sh debug  KITDIR    the DEBUG image: login kept (sshd, guest agent), port 22 open in the firewall, nothing forbidden
#   bash tc-image-lock.sh locked KITDIR    the LOCKED image: no sshd, no guest agent, no OS Login, no login on the serial console; tc-measure refuses to go on if any of them is present
# Both: the host firewall (nftables, default drop, only wg0 and the WireGuard port), the measured list with the firewall (15 events), a generic network configuration (cloud-init is
# switched off: its file names the builder's MAC address), and the self-report unit. Nothing is started and the builder is not rebooted.
# Hooks for the rehearsal only: TC_ROOT, TC_SUDO, TC_NO_APT, TC_NO_NETPLAN, TC_NO_NFT, TC_ANALYZE.
set -uo pipefail
MODE="${1:-}"; KIT="${2:-}"; R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"
fail() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }
case "$MODE" in debug|locked) ;; *) fail "usage: $0 debug|locked KITDIR" ;; esac
[ -d "$KIT" ] || fail "usage: $0 debug|locked KITDIR"
IMGDIR="$KIT/ops/image/rootfs"; U=usr/local/lib/tc/units
say "pre-flight ($MODE image)"
[ -x "$R/usr/local/lib/tc/tc-fleet.sh" ] || fail "the fleet flow is not in place: run tc-image-fleet.sh first"
for f in etc/tc/nftables-$MODE.conf etc/tc/forbidden-paths-$MODE.txt etc/tc/measured-paths-f4.txt etc/tc/netplan-dhcp.yaml usr/local/lib/tc/tc-report.sh usr/local/lib/tc/tc-measure.sh $U/tc-report.service $U/tc-ssh-hostkeys.service; do
  [ -f "$IMGDIR/$f" ] || fail "missing in $KIT: ops/image/rootfs/$f"
done
bash -n "$IMGDIR/usr/local/lib/tc/tc-report.sh" || fail "tc-report.sh has a syntax error"
echo "the fleet flow is in place; the firewall, the lists, the report and the units are in the kit"
say "the packages (nftables)"
if [ -z "${TC_NO_APT:-}" ] && ! command -v nft >/dev/null 2>&1; then $SUDO env DEBIAN_FRONTEND=noninteractive apt-get install -y nftables >/dev/null 2>&1 || fail "could not install nftables"; fi
say "install the firewall, the lists, the generic network configuration, the report and the units (owned by root)"
$SUDO install -m 0644 "$IMGDIR/etc/tc/nftables-$MODE.conf" "$R/etc/nftables.conf"
$SUDO install -m 0644 "$IMGDIR/etc/tc/forbidden-paths-$MODE.txt" "$R/etc/tc/forbidden-paths.txt"
printf '%s\n' "$MODE" | $SUDO tee "$R/etc/tc/image-mode" > /dev/null
$SUDO install -m 0755 "$IMGDIR/usr/local/lib/tc/tc-report.sh" "$R/usr/local/lib/tc/tc-report.sh"
$SUDO install -m 0755 "$IMGDIR/usr/local/lib/tc/tc-measure.sh" "$R/usr/local/lib/tc/tc-measure.sh"
for u in tc-report tc-ssh-hostkeys; do $SUDO install -m 0644 "$IMGDIR/$U/$u.service" "$R/$U/$u.service"; done
$SUDO rm -f "$R/etc/netplan/50-cloud-init.yaml"; $SUDO install -d -m 0755 "$R/etc/netplan" "$R/etc/cloud/cloud.cfg.d"
$SUDO install -m 0600 "$IMGDIR/etc/tc/netplan-dhcp.yaml" "$R/etc/netplan/60-tc-dhcp.yaml"
$SUDO touch "$R/etc/cloud/cloud-init.disabled"; printf 'network: {config: disabled}\n' | $SUDO tee "$R/etc/cloud/cloud.cfg.d/99-tc-no-network.cfg" > /dev/null
if [ -z "${TC_NO_NETPLAN:-}" ]; then $SUDO netplan generate 2>&1 | grep -v "^$" | head -3; [ "${PIPESTATUS[0]}" = 0 ] || fail "netplan does not accept the generic network configuration"; fi
$SUDO install -m 0644 "$IMGDIR/etc/tc/measured-paths-f4.txt" "$R/etc/tc/measured-paths.txt"
say "enable the units"
$SUDO systemctl daemon-reload
$SUDO systemctl enable nftables.service >/dev/null 2>&1 || fail "could not enable nftables"
$SUDO systemctl enable "$R/$U/tc-report.service" >/dev/null 2>&1 || fail "could not enable tc-report"
[ "$MODE" = debug ] && { $SUDO systemctl enable "$R/$U/tc-ssh-hostkeys.service" >/dev/null 2>&1 || fail "could not enable tc-ssh-hostkeys"; }
if [ "$MODE" = locked ]; then
  say "the lock: no sshd, no guest agent, no OS Login, no login on the serial console"
  PK="openssh-server openssh-sftp-server google-guest-agent google-osconfig-agent google-compute-engine-oslogin google-compute-engine"
  HAVE=""; for p in $PK; do dpkg -s "$p" >/dev/null 2>&1 && HAVE="$HAVE $p"; done
  [ -z "$HAVE" ] || { echo "removing:$HAVE"; $SUDO env DEBIAN_FRONTEND=noninteractive apt-get purge -y $HAVE >/dev/null 2>&1 || fail "could not remove$HAVE"; }
  for p in $PK; do ! dpkg -s "$p" >/dev/null 2>&1 || fail "the package $p is still installed"; done
  $SUDO systemctl mask serial-getty@ttyS0.service serial-getty@ttyS1.service getty@tty1.service >/dev/null 2>&1 || fail "could not mask the login prompts"
  echo "none of the login packages is installed; the login prompts of the serial console and the screen are masked"
  # Units that keep GRUB's own bookkeeping in /boot/grub/grubenv. On a sealed image the boot configuration is a sealed file on the EFI partition (it carries the root hash), there is no boot menu and no fallback initrd, and /boot is a read-only bind (tc-scratch-bind), so these units cannot write and have no function: they are masked. A failed unit is never tolerated (the report and locked-check refuse it), so another unit that fails for the same reason is one more name in this list.
  MASK_LOCKED="grub-common.service grub-initrd-fallback.service"
  $SUDO systemctl mask $MASK_LOCKED >/dev/null 2>&1 || fail "could not mask $MASK_LOCKED"
  echo "masked, because they only keep the GRUB flags of a writable /boot: $MASK_LOCKED"
fi
say "the checks: the firewall's syntax, the 15-event list with the forbidden paths, and the units"
if [ -z "${TC_NO_NFT:-}" ]; then $SUDO nft -c -f "$R/etc/nftables.conf" || fail "nft does not accept the firewall file"; echo "nft accepts the firewall file"; fi
TC_ROOT="$R" TC_LIST="$R/etc/tc/measured-paths.txt" TC_FORBID="$R/etc/tc/forbidden-paths.txt" TC_LIB="$R/usr/local/lib/tc" "$R/usr/local/lib/tc/tc-measure.sh" --check-list || fail "the measured list or the forbidden paths do not match this machine"
AOUT="$($SUDO ${TC_ANALYZE:-systemd-analyze} verify "$R/$U/tc-report.service" "$R/$U/tc-ssh-hostkeys.service" 2>&1 || true)"
if printf '%s\n' "$AOUT" | grep -i 'unknown' | grep -q 'tc-[a-z-]*\.service'; then printf '%s\n' "$AOUT" | grep -i 'unknown' | sed 's/^/   /'; fail "systemd does not understand part of a unit file"; fi
echo "systemd reads the new units without an unknown key or section"
echo
echo "READY (the $MODE image; nothing was started, nothing was rebooted). Next: tc-image-clean.sh, then stop the builder and make the image."
