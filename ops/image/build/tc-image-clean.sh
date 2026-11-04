#!/usr/bin/env bash
# Make the builder's disk fit to become an image: remove what belongs to THIS machine (its identity, its ssh host keys, its first-boot state, its logs and the builder's working folders),
# so that every VM made from the image gets its own. It is destructive on purpose and is run LAST, on the builder only.
#   bash tc-image-clean.sh --this-machine-becomes-an-image
# Step P4 (the build cleanup): it also purges snapd (unless TC_KEEP_SNAPD is set: a confidential node does not need it, and its device key, serial assertion and state.json are different in every build), and it removes
# /root/grub-backup-* with find AS ROOT (a shell glob is expanded by the normal user, who cannot read /root, which is mode 0700: the pattern matched nothing and the backups stayed in the image). What the live cleaning cannot do
# (the session that runs it writes logs; the sealing adds files afterwards) is done offline by tc-image-normalize.sh at gate 6b of tc-image-seal.sh.
# Hooks for the rehearsal only: TC_ROOT (a fake root), TC_SUDO, TC_APT, TC_KEEP_SNAPD.
set -uo pipefail
[ "${1:-}" = "--this-machine-becomes-an-image" ] || { echo "usage: $0 --this-machine-becomes-an-image   (it removes this machine's identity and first-boot state)" >&2; exit 2; }
R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"
say() { echo "== $*"; }
say "first-boot state: cloud-init runs again on the first boot of every new VM"
if command -v cloud-init >/dev/null 2>&1; then $SUDO cloud-init clean --logs >/dev/null 2>&1 || true; fi
say "identity: no machine id and no ssh host keys are left (each VM makes its own)"
$SUDO truncate -s 0 "$R/etc/machine-id"; $SUDO rm -f "$R/var/lib/dbus/machine-id"; $SUDO mkdir -p "$R/var/lib/dbus"; $SUDO ln -sf /etc/machine-id "$R/var/lib/dbus/machine-id"
$SUDO rm -f "$R"/etc/ssh/ssh_host_*
say "the measurement's own state and the builder's working folders"
$SUDO rm -rf "$R/var/lib/tc" "$R/var/lib/tc-crawl" "$R/run/tc"; $SUDO find "$R/root" -maxdepth 1 -mindepth 1 -name 'grub-backup-*' -exec rm -rf {} + 2>/dev/null; $SUDO rm -rf "$R/root/.bash_history" "$R/root/.m2" "$R/root/.ant" "$R/root/.ivy2"
for h in "$R"/home/*; do [ -d "$h" ] || continue; $SUDO rm -rf "$h/.ssh" "$h/.bash_history" "$h/k617" "$h/bake" "$h/build" "$h/.m2" "$h/.ant" "$h/.ivy2" "$h"/f0[0-9]* "$h/downloads"; done
say "Hadoop's data and logs (a builder that ever ran the daemons must not hand its HDFS to every new VM)"
for u in tc-crawl tc-nodemanager tc-resourcemanager tc-datanode tc-namenode tc-fleet; do $SUDO systemctl stop "$u.service" >/dev/null 2>&1 || true; done   # running daemons must not recreate state while it is removed
FIND="${TC_FIND:-find}"
# with $SUDO and WITHOUT an unprivileged test: /var/lib/hadoop is mode 0750 (hadoop), so a plain `[ -d ... ]` of the normal user says "no such directory" and silently skips the deletion (the first fleet run's root cause)
for d in tmp namenode datanode; do $SUDO $FIND "$R/var/lib/hadoop/$d" -mindepth 1 -delete 2>/dev/null; done
$SUDO $FIND "$R/var/log/hadoop" -mindepth 1 -delete 2>/dev/null
LEFT="$($SUDO find "$R/var/lib/hadoop" "$R/var/lib/tc-crawl" -mindepth 2 2>/dev/null | head -3)"; [ -z "$LEFT" ] || { echo "ABORT: Hadoop's data is still on disk after the cleaning: $LEFT" >&2; exit 1; }
echo "verified: no HDFS data is left under /var/lib/hadoop"
if [ -z "${TC_KEEP_SNAPD:-}" ]; then
  say "snapd: purged (a confidential node does not need it; its device key and state are different in every build)"
  for u in snapd.socket snapd.service snapd.seeded.service; do $SUDO systemctl stop "$u" >/dev/null 2>&1 || true; done
  if [ -n "$R" ]; then [ -e "$R/usr/lib/snapd/snapd" ] && HAVESNAP=1 || HAVESNAP=0; else dpkg -s snapd >/dev/null 2>&1 && HAVESNAP=1 || HAVESNAP=0; fi
  if [ "$HAVESNAP" = 1 ]; then
    SIM="$($SUDO ${TC_APT:-apt-get} -s purge snapd 2>/dev/null | grep -E '^(Remv|Purg)')"
    echo "the packages that the purge removes with it (apt-get -s purge snapd):"; echo "$SIM" | sed 's/^/   /' | head -20
    BADP="$(echo "$SIM" | awk '{print $2}' | grep -E '^(cloud-init|openssh|google-|netplan|systemd|linux-|grub|initramfs-tools|cryptsetup|python3|apt|dpkg|sudo|libc6|bash)' | tr '\n' ' ')"
    [ -z "$BADP" ] || { echo "ABORT: purging snapd would also remove packages that the image needs ($BADP): nothing was removed; look at the list above" >&2; exit 1; }
    $SUDO ${TC_APT:-apt-get} purge -y snapd >/dev/null 2>&1 || { echo "ABORT: snapd could not be purged" >&2; exit 1; }
  fi
  $SUDO rm -rf "$R/snap" "$R/var/snap" "$R/var/lib/snapd" "$R/var/cache/snapd" "$R/root/snap"; for h in "$R"/home/*; do [ -d "$h" ] && $SUDO rm -rf "$h/snap"; done
  [ ! -e "$R/usr/lib/snapd/snapd" ] && [ ! -e "$R/var/lib/snapd/device" ] || { echo "ABORT: snapd is still on disk after the purge" >&2; exit 1; }
  echo "verified: snapd and its device key are gone"
else
  say "snapd: KEPT (TC_KEEP_SNAPD is set): two builds will differ in its state; tc-image-seal.sh must then get --allow-snapd"
fi
say "package caches and logs"
$SUDO ${TC_APT:-apt-get} clean >/dev/null 2>&1 || true; $SUDO rm -rf "$R"/var/lib/apt/lists/*
if [ -d "$R/var/log" ]; then $SUDO find "$R/var/log" -type f -exec truncate -s 0 {} + 2>/dev/null || true; fi
if command -v journalctl >/dev/null 2>&1; then $SUDO journalctl --rotate >/dev/null 2>&1 || true; $SUDO journalctl --vacuum-time=1s >/dev/null 2>&1 || true; fi
sync
echo "CLEAN-OK (this machine is ready to be stopped and made into an image; do not start anything else on it)"
