# ops/image: the image build of the fixed fleet (step F0)

This folder holds the sources of the **locked, measured image** of the fixed-fleet plan (milestone-plan.md section 10, steps F0.1 to F0.6). It replaces the rebuild kit `ops/rebuild/` at step F5. This is part 1: **F0.1** (kernel 6.17 is the default, so a plain reboot keeps RTMR3 extendable) and **F0.2** (the measurement runs as a unit at every boot, before any Hadoop daemon).

In plain words: at every boot the machine hashes a fixed list of its own files into the hardware register RTMR3, one line per item, before anything else starts, and keeps a log of those lines. A hardware quote then vouches for the register, and anyone can replay the log and get the same register. If the files are the same, the register is the same on every boot; if one file changed, the register changes. Nobody has to run a script by hand any more.

| File | What it is |
|---|---|
| `build/tc-image-prep.sh` | run on a builder or test VM: installs the pinned 6.17 kernel as the **default** (not a one-time boot), freezes automatic upgrades, and installs and enables the measurement unit; it never reboots |
| `rootfs/usr/local/lib/tc/tc-measure.sh` | the boot measurement: refuses to run unless RTMR3 is zero, measures the list in order, stops if a path is missing |
| `rootfs/usr/local/lib/tc/tc-extend.sh` | extends RTMR3 with the SHA-384 of a file or folder and logs it (the old `rtmr3-extend.sh` without `sudo`) |
| `rootfs/etc/tc/measured-paths.txt` | the list of measured paths: one line each, edit it to change what is measured |
| `rootfs/etc/systemd/system/tc-measure.service` | the unit, ordered before `multi-user.target` |
| `rootfs/etc/systemd/system/tc-placeholder.service` | TEST ONLY: stands in for the Hadoop daemons to prove the order |
| `test/f01-check.sh` | after each boot: 6.17 is the default and running, RTMR3 is not zero, the unit finished before the stand-in daemons, the log replays to RTMR3, a quote is bound to the log |
| `test/f01-compare.py` | compares two boots: the same files give the same RTMR3, one changed file changes only its event |
| `test/f01-drive.sh` | drives all of this on a disposable TDX VM from Cloud Shell |
| `test/f01-rehearse.sh` | the sandbox rehearsal with stand-ins (a fake register that extends like the hardware) and every fault made on purpose |

The scripts `attest/quote.sh`, `attest/measure/treehash.sh` and `attest/measure/rtmr3_replay.py` are reused unchanged and copied into the image by the prep script.

**What replaces what:** F0.1 replaces the one-time boot into 6.17 and the manual measurement of Milestone 1 (`ops/worker-kernel-prep.sh`, `attest/measure/`); F0.2 replaces the manual `measure-all.sh` runs and the re-measure after a reboot (step 4.8.2).

**What it does not show (limits).** The measurement unit is not itself measured by an earlier stage: someone who can write to the disk between boots could change `tc-measure.sh` to report the digests that they want. Closing that needs a read-only root with dm-verity or a measured initramfs; the mentor has been asked (limitations row 131), and until she answers the default is to measure the boot script, the units, `openssl` and `wg` and to state this limit. It is also tested on one disposable VM, with a stand-in for Hadoop; the real daemons, the keys and `fleet.tsv` come with steps F0.3 and F1.
