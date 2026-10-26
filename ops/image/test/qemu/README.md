# The real-kernel rehearsal (QEMU)

What it is: a boot of the sealed disk under QEMU (software emulation, no KVM) with the real kernel, the real initramfs (built by `tc-image-sealbake.sh` inside an Ubuntu 22.04 root with the same initramfs-tools, cryptsetup and busybox versions as the image), the real sealing script, and a two-namespace NVMe device like GCE's. `tc-test-init` runs after the initramfs hands over and checks every property of the sealed boot, including a tamper attempt on the raw scratch disk.

Why it exists: the first two boots on GCE failed for reasons that only a real kernel shows (cryptsetup hanging in a late initramfs stage; mke2fs refused by dm-integrity because of the first read of a never-written sector). No stand-in-based test could have found either.

How it was used (step R3, 23 October 2026): debootstrap jammy into /tmp/jam, install linux-image-6.8.0-1070-gcp, put tc-test-init at /sbin, run `tc-image-sealbake.sh` in a chroot, `reseal.sh` (builds the disk image and seals it), `run.sh INITRD LOG` (boots and waits). The scripts expect those paths; they are a record of the procedure, not a one-command tool.
