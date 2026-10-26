#!/bin/bash
# boot.sh INITRD LOG [extra kernel args]: boot the sealed disk image under QEMU (software emulation) with two NVMe namespaces (boot disk, spare disk) like GCE
INITRD="$1"; LOG="$2"; shift 2
CL="$(grep -E '^\s+linux ' /tmp/rep/esp/EFI/ubuntu/grub.cfg | sed -E 's#^\s+linux /boot/vmlinuz-[^ ]+ ##')"
rm -f "$LOG"; if [ -z "${KEEP_SCRATCH:-}" ]; then cp /tmp/rep/scratch.blank /tmp/rep/scratch.img 2>/dev/null || truncate -s 4G /tmp/rep/scratch.img; fi
timeout "${QTIMEOUT:-280}" qemu-system-x86_64 -accel tcg -cpu max -m 1024 -smp 1 -display none -monitor none -serial "file:$LOG" -no-reboot \
  -kernel /tmp/jam/boot/vmlinuz-6.8.0-1070-gcp -initrd "$INITRD" -append "$CL init=/sbin/tc-test-init $*" \
  -drive file=/tmp/rep/disk.img,if=none,id=d0,format=raw -drive file=/tmp/rep/scratch.img,if=none,id=d1,format=raw \
  -device nvme,id=nvme0,serial=tcseal0 -device nvme-ns,drive=d0,bus=nvme0 -device nvme-ns,drive=d1,bus=nvme0
echo "qemu exit: $?" >> "$LOG"
