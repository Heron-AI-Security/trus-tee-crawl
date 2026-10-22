#!/usr/bin/env bash
# Step R3.0 (decision 2 of the mentor's review): READ-ONLY facts about a booted node of the debug image, before anything is built. Does the kernel boot with an initrd? Are
# dm-verity, dm-crypt and dm-integrity (and dm-init, which dm-mod.create= needs) built into the kernel, or modules that could not load before the root is mounted? Which register
# covers the kernel command line, and what does the TDX boot log say? Where does the user hadoop live, and is it writable? Run as root:  sudo bash r3-probe.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
sec() { echo; echo "== $*"; }
sec "the kernel and its command line"; uname -r; cat /proc/cmdline
sec "an initrd?"; ls -l /boot/initrd* /boot/vmlinuz* 2>&1 | head -6; dmesg 2>/dev/null | grep -i -E "initrd|initramfs|unpack(ing)? initramfs|rootfs" | head -5 || true
echo "initrd= in the command line: $(grep -c 'initrd=' /proc/cmdline)"
echo "kernel messages about the initrd: $(journalctl -k -b --no-pager 2>/dev/null | grep -i -E 'initrd|initramfs' | head -4 | tr '\n' '|')"; ls -d /run/initramfs 2>&1 | head -1
echo "does the stock initramfs hold the device-mapper modules?"; lsinitramfs /boot/initrd.img-"$(uname -r)" 2>/dev/null | grep -E 'dm-(verity|crypt|integrity|mod)|dm_(verity|crypt|integrity)' | head -6 || true
sec "the root file system and the disks"; findmnt -no SOURCE,FSTYPE,OPTIONS / ; lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT 2>&1 | head -12; df -h / /var/lib/hadoop /tmp 2>&1 | head -5
sec "device-mapper in this kernel (y = built in, m = module: a module cannot be loaded before the root is mounted when there is no initrd)"
for k in CONFIG_BLK_DEV_DM CONFIG_DM_INIT CONFIG_DM_VERITY CONFIG_DM_CRYPT CONFIG_DM_INTEGRITY CONFIG_CRYPTO_AEAD CONFIG_CRYPTO_AES CONFIG_CRYPTO_SHA256; do echo "$(grep -E "^$k[= ]" /boot/config-"$(uname -r)" 2>/dev/null | head -1 || true)" | grep . || echo "$k: not set"; done
echo "loaded dm modules: $(lsmod | awk '$1 ~ /^dm_/ {print $1}' | tr '\n' ' ')"
sec "the TDX boot log (which register covers what)"
if [ -r /sys/firmware/acpi/tables/data/CCEL ]; then python3 "$HERE/r3-ccel.py" /sys/firmware/acpi/tables/data/CCEL; else echo "(no /sys/firmware/acpi/tables/data/CCEL)"; fi
sec "the raw boot log (base64, so that it can be analysed again without a VM)"; if [ -r /sys/firmware/acpi/tables/data/CCEL ]; then echo "CCEL-BASE64-BEGIN"; base64 -w0 /sys/firmware/acpi/tables/data/CCEL; echo; echo "CCEL-BASE64-END"; fi
sec "the user hadoop: home, what the scripts source, and who can write it"
H="$(getent passwd hadoop | cut -d: -f6)"; echo "home of hadoop: $H"; ls -la "$H" 2>&1 | head -8; ls -la "$H/.hadooprc" 2>&1 | head -1; findmnt -no TARGET,SOURCE -T "$H"
sec "mounts that persist between boots"; grep -v '^#' /etc/fstab | grep . || echo "(fstab has no entries)"
echo; echo "R3-PROBE-DONE"
