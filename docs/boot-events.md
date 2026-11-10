# The boot events of the sealed image (RTMR1 and RTMR2)

**Status check, 30 October 2026.** This document tabulates every RTMR1 and RTMR2 event of the dummy run of the sealed image `tc-img-rel-1` (commit `16bafb3b19b3`), as step P6 of the mentor's plan asks, and settles where the kernel, its command line, the initrd and the dm-verity root hash land. The tables are the output of `ops/ccel-table.py` on the saved boot log of that run; the evidence is named by its SHA-256 at the end. It replaces the note "verify on our image" under Figure 3 of the paper. The report of the whole mentor's plan, with the numbered sub-steps of step P6, is [mentor-plan-report.md](mentor-plan-report.md). After step P3.2 the same tables are published with every release (the file `boot-tables.md` of the release), made by CI from the boot log of a dummy run.

## What the table settles

- **The kernel lands in RTMR2, not in RTMR1.** RTMR2 holds the kernel file (event 16, `/boot/vmlinuz-6.17.0-1022-gcp`), its complete command line (event 17, `kernel_cmdline`), the initrd (event 18, the grub command, and event 19, the file `/boot/initrd.img-tc`), the grub configuration (event 4) and the grub commands that start the kernel (events 13 and 15).
- **The dm-verity root hash is in the quote.** The kernel command line carries `tc.verity=b80370de63d9c52e355129243f424772ddf7fbeb7c7942fe3c5c6ac7a4a0016c` in RTMR2 events 13, 15 and 17, and that value equals the root hash of the sealed disk (the check of `ops/make-release.py`, [run-comparison.md](run-comparison.md) section 9.19).
- **RTMR1 holds only 7 events:** the call of the EFI application from the boot option, a separator, the GPT, two EFI applications (the boot loaders that the firmware started; the log holds the digest of each image and its device path, which the tool shows as binary data), and the two boot-service actions at exit.
- **RTMR2 also holds the three `Mok` variables** (events 1 to 3), which the shim measures, before the grub events.
- **Which registers change with our content:** MRTD, RTMR0 and RTMR1 are the same for two different images of ours (the firmware and the boot manager do not depend on the image); RTMR2 changed, because the new root hash is on the kernel command line.
- **The log is complete:** it has 45 events (MRTD 2, RTMR0 17, RTMR1 7, RTMR2 19), and the replay of RTMR0, RTMR1 and RTMR2 equals the quote.

## How the table was made

1. The node of the sealed image publishes its firmware boot event log (`/sys/firmware/acpi/tables/data/CCEL`) as guest attributes, in 22 chunks of 12 KB, with its SHA-256 and the count last (ADR-092).
2. `bash ops/reference-run.sh tc-img-rel-1 rel-run` made one TDX VM from the image without a fleet list, read the chunks, checked the hash, saved `rel-run/ccel.bin` and deleted the VM (ADR-091).
3. `python3 ops/ccel-table.py rel-run --markdown rel-boot-tables-full.md --full` replayed the events of RTMR0 to RTMR2 against the quote and wrote the tables below. Without `--full` the tables show 32 digits of each digest and cut a text at 110 characters.

## The kernel command line

The complete command line of events 13, 15 and 17 is:

`root=/dev/mapper/vroot ro fsck.mode=skip console=ttyS0,115200 overlayroot=tmpfs tc.verity=b80370de63d9c52e355129243f424772ddf7fbeb7c7942fe3c5c6ac7a4a0016c tc.data=67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8 tc.blocks=2621440 tc.salt=8645d23e5b03b8f8595723ceac05c056282c915db5f5ee60903fa1ed270194f1`

`tc.verity` is the dm-verity root hash, `tc.blocks` and `tc.data` are the number of blocks and the data partition that the sealing printed (`blocks=2621440` and `data_partuuid`), and `tc.salt` is the fixed dm-verity salt.

## The RTMR1 events

| # | Event type | What it measures | Digest (SHA-384) |
|---|---|---|---|
| 1 | EV_EFI_ACTION | Calling EFI Application from Boot Option | `77a0dab2312b4e1e57a84d865a21e5b2ee8d677a21012ada819d0a98988078d3d740f6346bfe0abaa938ca20439a8d71` |
| 2 | EV_SEPARATOR | (binary, 4 bytes: 00000000...) | `394341b7182cd227c5c6b07ef8000cdfd86136c4292b8e576573ad7ed9ae41019f5818b4b971c9effc60e1ad9f1289f0` |
| 3 | EV_EFI_GPT_EVENT | (binary, 484 bytes: 4546492050415254...) | `501fee7696207fc23c2eb780934fb42cb5c1970992a80653f693bc4d48b0fabe5baebc570bf981ef0e522cdb4c3f82da` |
| 4 | EV_EFI_BOOT_SERVICES_APPLICATION | (binary, 164 bytes: 184036bd00000000...) | `4637fb5cd30847e5f09ae24f8a50ce1611c4d21afd0ecb69c8ec40bc82dc11bc48abda1f8044fe340bfb70b29606eb47` |
| 5 | EV_EFI_BOOT_SERVICES_APPLICATION | (binary, 88 bytes: 181001bd00000000...) | `07f1ba413ca8861d911cc890ef2f954bf8990328d872b101aaa0f2e6415943c412fd1140608db0f5ddb7082fdd517c1c` |
| 6 | EV_EFI_ACTION | Exit Boot Services Invocation | `214b0bef1379756011344877743fdc2a5382bac6e70362d624ccf3f654407c1b4badf7d8f9295dd3dabdef65b27677e0` |
| 7 | EV_EFI_ACTION | Exit Boot Services Returned with Success | `0a2e01c85deae718a530ad8c6d20a84009babe6c8989269e950d8cf440c6e997695e64d455c4174a652cd080f6230b74` |

## The RTMR2 events

| # | Event type | What it measures | Digest (SHA-384) |
|---|---|---|---|
| 1 | EV_IPL | MokList | `053357ea65185f010b8caa1fc265cfd5e80c7cc781254fa3f1e5ea9d345a87003cf761472a2f0423f15297f55cfe248f` |
| 2 | EV_IPL | MokListX | `80ee2571334a57bf90238d21964447e542079d4805fa87887817a97dcb720906683a09b1ac634c76c0c0be1177f76110` |
| 3 | EV_IPL | MokListTrusted | `8d2ce87d86f55fcfab770a047b090da23270fa206832dfea7e0c946fff451f819add242374be551b0d6318ed6c7d41d8` |
| 4 | EV_IPL | (hd0,gpt15)/EFI/ubuntu/grub.cfg | `9ef75087d1021c9a27e0af988ee26e66c1475bdfde5db9e5d1f4a99ff67e8b93559c79ccfe7f3cb809f77c43c6cb2e59` |
| 5 | EV_IPL | grub_cmd: set default=0 | `6bf6242f8eb0ca7217c6e3a5d4c6a62e5858440264e84696cd67306ef2db8cf625952d5fd9061daadefd181039479740` |
| 6 | EV_IPL | grub_cmd: set timeout=0 | `54836d3465339db08f1fc8c7cc2630918a486ca4447f416dd5a267e337308f07b898c6dd7a2586a382ac40917f1ac222` |
| 7 | EV_IPL | grub_cmd: serial --unit=0 --speed=115200 | `b9fc111835399eeb6c6728ef176f30433424955a90d64a2ca4e24ca22b5616ee36494ea5662ecd8ba31c3602eaa587c6` |
| 8 | EV_IPL | grub_cmd: terminal_input serial | `65eb406f919a441f3e4bedc5b35c2b69006249c7fd2262732df04c6b069fcca6be82c46e95c423e60ac2b09ccfa95e8e` |
| 9 | EV_IPL | grub_cmd: terminal_output serial | `065548d700589f5f793bff88c34ba265be1919f23811f9914f4b136bcb6cfa25c9dd5a7519fbfbdc5e51b3a0114a7914` |
| 10 | EV_IPL | grub_cmd: insmod part_gpt | `cac0f0b93ee7eaa45e36cda3faf3d0a5f5fc92ec4d24c3af4ad9584669598f34b603c211b220e56be52bdbc3a2f74ffb` |
| 11 | EV_IPL | grub_cmd: insmod ext2 | `e142a594d988fda5a65b1424a4a48c2cf4b036dd779d4ae299af45b7d33b0bfe07a4a969d3c0da72c2ba53f9eeeaf7a6` |
| 12 | EV_IPL | grub_cmd: search --no-floppy --fs-uuid --set=root 07ef7f9d-ec71-439a-b24d-439c483e944f | `67b26f0c49e075a83676c312b2a067223b7fa4595040475988e48e53dfef2c021b451e9a5f141848289341c396b8495f` |
| 13 | EV_IPL | grub_cmd: menuentry tc sealed {   linux /boot/vmlinuz-6.17.0-1022-gcp root=/dev/mapper/vroot ro fsck.mode=skip console=ttyS0,115200 overlayroot=tmpfs tc.verity=b80370de63d9c52e355129243f424772ddf7fbeb7c7942fe3c5c6ac7a4a0016c tc.data=67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8 tc.blocks=2621440 tc.salt=8645d23e5b03b8f8595723ceac05c056282c915db5f5ee60903fa1ed270194f1   initrd /boot/initrd.img-tc } | `ca9030619513c741a81a73787a75a008f05798b102ea47f1ae31dad4807e6e26f592129b579501b628c8b05e7271c7ab` |
| 14 | EV_IPL | grub_cmd: setparams tc sealed | `3fd3b549f54966e535d48e925d177a8ebb5a21078bdc3f3d873c9fbaf0f503eafc08be4dcab5d18229c87e628117cbed` |
| 15 | EV_IPL | grub_cmd: linux /boot/vmlinuz-6.17.0-1022-gcp root=/dev/mapper/vroot ro fsck.mode=skip console=ttyS0,115200 overlayroot=tmpfs tc.verity=b80370de63d9c52e355129243f424772ddf7fbeb7c7942fe3c5c6ac7a4a0016c tc.data=67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8 tc.blocks=2621440 tc.salt=8645d23e5b03b8f8595723ceac05c056282c915db5f5ee60903fa1ed270194f1 | `7911801db57d642de7de908c6a5c00a3f2a57249a2829ff0e929505967e53e8283a292393169c68dde0a9da687c6e7b0` |
| 16 | EV_IPL | /boot/vmlinuz-6.17.0-1022-gcp | `d0bc4df3c4439be584307ae86186919b9ede90997265a74236b7885295cb4b068608611991c087204fc17e482ace8cb8` |
| 17 | EV_IPL | kernel_cmdline: /boot/vmlinuz-6.17.0-1022-gcp root=/dev/mapper/vroot ro fsck.mode=skip console=ttyS0,115200 overlayroot=tmpfs tc.verity=b80370de63d9c52e355129243f424772ddf7fbeb7c7942fe3c5c6ac7a4a0016c tc.data=67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8 tc.blocks=2621440 tc.salt=8645d23e5b03b8f8595723ceac05c056282c915db5f5ee60903fa1ed270194f1 | `cd7bf3b2a2f804404750496897092a407ef1680653789bcd2e6db74b6116a56aa0f6d15a1a412aecf938d8e2c789b714` |
| 18 | EV_IPL | grub_cmd: initrd /boot/initrd.img-tc | `c447e987223ebce9c26e4bb5a910032d09324d529fad78dfb1d9810adb5c26cb088c3ff242cb684b9b8218e4f9f703d1` |
| 19 | EV_IPL | /boot/initrd.img-tc | `605c99b8fb95fac96ee3b492e0e6ba7ebfbcc25dd8929963f9d80d361aa8cf2365b1715e983f04c90d31a26ea8f0a9ed` |

## The evidence

| File | SHA-256 |
|---|---|
| `rel-run/ccel.bin` (the boot event log, 262,144 bytes) | `553789f86be3858f550dabcab2c856c3493545d349eea8d0431969239a409c5d` |
| `rel-run/quote.bin` (the TDX quote, 8,000 bytes) | `8dac151f4394d607744576f53911ca662fcf5570812d1697d476c354bd0c1f75` |
| `rel-run/settings.json` (the settings of the dummy run) | `32aaf6bb069e4f76fe3e0ddfe19a16b810e806b5376db22003ab7dcb262f6fdc` |
| `rel-release/release.json` | `3daa43b2d43c0223c02b8020eaa29f380f763295ab44c377094e3b79a939ffdc` |
| `evidence-rel-f/reference-values-pinned.json` (the reference of the real fleet) | `96e33d9aa5e74a4a3a37c6101a3d2f4d750042a7cf0621003a62977e275cf6fc` |

## What this does not show

The 17 RTMR0 events and the 2 MRTD events are not tabulated; the data of the two EFI applications and of the GPT event is shown as binary, because the tool decodes only text. The table is one dummy run of one image: it shows what the firmware and grub measured on that run, and it does not by itself show that another party gets the same events, which is step P4 of the mentor's plan.
