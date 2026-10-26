#!/usr/bin/env bash
# R3.1, READ-ONLY. On a booted node of the debug image that has a SECOND disk (made at creation with the device name tcscratch): how the disks show up, what GRUB's files and the
# initramfs tooling look like, which modules and packages a verity root and an encrypted scratch disk need. Nothing is written, installed, mounted or formatted.
set -uo pipefail
sec() { echo; echo "== $*"; }
sec "the machine"; uname -r; echo "cpus: $(nproc); $(free -m | awk 'NR==2 {print "memory: "$2" MB total, "$7" MB available"}')"; cat /sys/class/dmi/id/product_name 2>/dev/null
sec "the disks as the kernel sees them (the second disk has the device name tcscratch)"
lsblk -o NAME,SIZE,TYPE,FSTYPE,SERIAL,MODEL,TRAN,MOUNTPOINT -e7 2>&1 | head -20
for d in /sys/block/nvme*n*; do [ -e "$d" ] || continue; b="$(basename "$d")"; echo "$b: $(cat "$d/size") sectors; serial=[$(cat "$d/device/serial" 2>/dev/null | tr -d ' ')] model=[$(cat "$d/device/model" 2>/dev/null | sed 's/ *$//')] partitions=$(ls "$d" | grep -c "^${b}p")"; done
echo "--- /proc/partitions:"; cat /proc/partitions
echo "--- /dev/disk/by-id:"; ls -l /dev/disk/by-id/ 2>&1 | awk '{print $9, $10, $11}' | head -20
echo "--- udev properties of the second disk:"; for n in /dev/nvme0n2 /dev/nvme1n1 /dev/sdb; do [ -b "$n" ] && { echo "$n:"; udevadm info -q property -n "$n" 2>&1 | grep -E "^(ID_SERIAL|ID_SERIAL_SHORT|ID_MODEL|DEVLINKS|ID_PATH)=" ; }; done
echo "--- the rules that name Google disks (a minimal initramfs does not have them):"; ls /usr/lib/udev/rules.d /lib/udev/rules.d /etc/udev/rules.d 2>/dev/null | grep -i -E "gce|google" | sort -u
sec "the root disk's partition table and file system"
R="$(findmnt -no SOURCE /)"; echo "root device: $R"; findmnt -no SOURCE,FSTYPE,OPTIONS / ; PD="/dev/$(lsblk -no PKNAME "$R" 2>/dev/null | head -1)"; echo "its disk: $PD"
sfdisk -d "$PD" 2>&1 | head -12; blkid 2>&1 | head -8
tune2fs -l "$R" 2>&1 | grep -E "Filesystem UUID|Filesystem created|Last mount time|Filesystem features|Block count|Free blocks|Block size|Inode size|Journal" | head -10
echo "root used: $(df -h --output=used,size,pcent / | tail -1)"
sec "the EFI partition and GRUB's files (the real grub.cfg of a sealed image lives on the EFI partition, which the root hash does not cover)"
findmnt -no SOURCE,FSTYPE,SIZE /boot/efi; ls -l /boot/efi/EFI/ubuntu /boot/efi/EFI/BOOT 2>&1 | head -14; df -h --output=used,size /boot/efi | tail -1
echo "--- the grub.cfg on the EFI partition:"; cat /boot/efi/EFI/ubuntu/grub.cfg 2>&1 | head -12
echo "--- /etc/default/grub (without comments):"; grep -v '^#' /etc/default/grub | grep -v '^$'; for f in /etc/default/grub.d/*.cfg; do [ -e "$f" ] || continue; echo "--- $f"; grep -v '^#' "$f" | grep -v '^$'; done
echo "--- /boot:"; ls -l /boot | head -16
sec "the initramfs tooling and the packages that the sealing needs"
dpkg -l initramfs-tools initramfs-tools-core busybox-initramfs cryptsetup-bin cryptsetup-initramfs dmsetup libdevmapper1.02.1 overlayroot e2fsprogs fdisk gdisk parted 2>&1 | awk '/^(ii|un|rc|dpkg-query)/ {print $1, $2, $3, $4}' | head -14
for t in mkinitramfs unmkinitramfs update-initramfs veritysetup cryptsetup integritysetup dmsetup resize2fs e2fsck mke2fs sfdisk sgdisk parted cpio zstd gzip; do printf "%-16s %s\\n" "$t" "$(command -v "$t" 2>/dev/null || echo '-')"; done
echo "--- what apt would install for the missing tools (simulation only; the package lists may be empty after the cleaning):"; apt-get -s install cryptsetup-bin dmsetup 2>&1 | grep -E "^(Inst|E:|The following|Reading)" | head -10
sec "mkinitramfs and how reproducible it can be"
dpkg -s initramfs-tools 2>/dev/null | grep -E "^Version"; grep -n -E "SOURCE_DATE_EPOCH|touch -d|cpio|COMPRESS|gzip|zstd" /usr/sbin/mkinitramfs 2>/dev/null | head -12 | cut -c1-150
echo "--- /etc/initramfs-tools/initramfs.conf:"; grep -v '^#' /etc/initramfs-tools/initramfs.conf 2>/dev/null | grep -v '^$'; ls /etc/initramfs-tools /etc/initramfs-tools/hooks /etc/initramfs-tools/scripts 2>&1 | head -12
echo "--- the stock hooks and the script phases:"; ls /usr/share/initramfs-tools/hooks 2>/dev/null | tr '\n' ' '; echo; ls /usr/share/initramfs-tools/scripts 2>/dev/null | tr '\n' ' '; echo
sec "kernel modules and settings (an initrd must carry the modules; built-in ones need nothing)"
for m in dm_verity dm_bufio dm_crypt dm_integrity overlay xts aes_generic sha256_generic hmac authenc crc32c_generic ext4 nvme; do printf "%-18s %s | depends: %s\\n" "$m" "$(modinfo -F filename "$m" 2>/dev/null | sed 's#.*/kernel/##' || echo -)" "$(modinfo -F depends "$m" 2>/dev/null)"; done
for c in DM_VERITY DM_VERITY_VERIFY_ROOTHASH_SIG DM_VERITY_FEC DM_INTEGRITY DM_CRYPT DM_BUFIO OVERLAY_FS EXT4_FS BLK_DEV_NVME NVME_CORE TMPFS CRYPTO_SHA256 CRYPTO_AES CRYPTO_XTS CRYPTO_HMAC CRYPTO_GCM CRYPTO_AEAD CRYPTO_CRC32C CRYPTO_AUTHENC; do grep -E "^(# )?CONFIG_$c[= ]" "/boot/config-$(uname -r)" 2>/dev/null | head -1; done
echo "--- the stock initramfs (modules inside, and its size):"; ls -l /boot/initrd.img-"$(uname -r)" 2>&1 | awk '{print $5, $9}'; lsinitramfs /boot/initrd.img-"$(uname -r)" 2>/dev/null | grep -E "\\.ko" | sed 's#.*/##' | tr '\n' ' ' | cut -c1-700; echo
sec "what the system writes while it boots (a read-only root needs a place for it)"
ls -ld /etc /var /var/lib /var/log /tmp /home /root 2>&1; findmnt -t tmpfs -no TARGET,SIZE 2>&1 | head; echo "machine-id: $(wc -c < /etc/machine-id 2>/dev/null) bytes; hostname file: $(cat /etc/hostname 2>/dev/null)"
echo "scripts of ours that write under /etc or /var:"; grep -l -E "hostnamectl|/etc/hosts|ssh-keygen|/etc/hostname" /usr/local/lib/tc/*.sh 2>/dev/null | tr '\n' ' '; echo
echo "enabled units: $(systemctl list-unit-files --state=enabled --no-legend 2>/dev/null | awk '{print $1}' | grep -E "^(ssh|tc-|systemd-(timesync|resolved|networkd)|google|snapd|unattended|cloud)" | tr '\n' ' ')"
echo "memory that a RAM overlay could take: $(df -h --output=size,avail /dev/shm /run 2>/dev/null | tr '\n' ' ')"
echo; echo "R3-DISKS-DONE"
