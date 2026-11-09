# Two builds, one commit: the file-tree comparison, the build cleanup and the helper VM (step P4)

**Status check, 4 November 2026.** Step P4 of the mentor's plan is done on the real cloud and is on GitHub: the commits `20267a68d`, `fea794432`, `829e90c2f`, `530237c2f`, `c60995fa4` and `9b4a08fbb` (full ids in section 2). Two builds of commit `c60995fa4` hold identical files, compared through dm-verity with no ignored difference, and the comparison fails on a changed file, an added file, a changed mode and an added capability. Two problems were found and solved on the way, and this page records each with its root cause: two builds differed in 27 files (section 5), and the helper VM of the comparison sometimes did not boot (section 6). Not done: the locked variant of the image was not compared, and a second party has not rebuilt the image (section 7); the kits that ran are in the repository since the commit `15ab399fa` (section 2). The report of the plan is [mentor-plan-report.md](mentor-plan-report.md) section 8, the runs are in [run-comparison.md](run-comparison.md) sections 9.22 to 9.24, and the decisions are ADR-096 to ADR-098 in [decisions.md](decisions.md). On 5 November 2026 the four events behind `explained=4` were named, the kit commit got its full id, and section 5.5 answers the mentor's question why the two root hashes differ.

**Update, 7 November 2026.** The comparison is part of every later kit run, and it passed in the four runs after step P4 (section 4, last rows): the two builds of one commit held identical files each time. Nothing in sections 5 to 9 changed.

**Update, 9 November 2026.** The comparison also passed in the first run of about 1,000 URLs (`k1a`, section 4, last row): in the five runs after step P4 the two builds of one commit held identical files each time. Nothing in sections 5 to 9 changed.

## Contents

- [1. What this is, in plain words](#1-what-this-is-in-plain-words)
- [2. What was built, commit by commit](#2-what-was-built-commit-by-commit)
- [3. How the comparison works](#3-how-the-comparison-works)
- [4. The runs, in order](#4-the-runs-in-order)
- [5. Problem 1: two builds of one commit differed in 27 files](#5-problem-1-two-builds-of-one-commit-differed-in-27-files)
  - [5.1 What we saw](#51-what-we-saw)
  - [5.2 The root causes, one by one](#52-the-root-causes-one-by-one)
  - [5.3 Why the earlier checks did not show it](#53-why-the-earlier-checks-did-not-show-it)
  - [5.4 The decisions](#54-the-decisions)
  - [5.5 The result](#55-the-result)
- [6. Problem 2: the helper VM that did not boot](#6-problem-2-the-helper-vm-that-did-not-boot)
  - [6.1 What we saw](#61-what-we-saw)
  - [6.2 The root cause](#62-the-root-cause)
  - [6.3 Why waiting and faster disks could not help](#63-why-waiting-and-faster-disks-could-not-help)
  - [6.4 The fix and its tests](#64-the-fix-and-its-tests)
  - [6.5 What is still not proven](#65-what-is-still-not-proven)
- [7. What it shows, and what it does not](#7-what-it-shows-and-what-it-does-not)
- [8. How to repeat each check](#8-how-to-repeat-each-check)
- [9. Where the evidence is](#9-where-the-evidence-is)

## 1. What this is, in plain words

The cluster's quote says which image a node runs. A stranger who does not trust us needs to know that the image is the product of **our commit**, and not of something else with the same name. Think of two bakers who follow the same recipe: you cannot compare the two cakes by the exact minute they came out of the oven (the **root hash** of a disk changes with every build, because file times and block layouts differ), but you can **cut both cakes and compare every slice**: what is inside, its shape, who made it. That is the file-tree comparison of step P4 of the mentor's plan.

The mentor's review of 1 November 2026 states what it must show: it **passes on two builds of one commit** and **fails on an image with one changed file, one added file and one changed mode**; any difference other than times fails, with the list printed. The mentor also dropped step P3.3 (CI builds the image): P4 works whoever built the image, so we say in the paper that our team builds it and verifiers check it with P4 ([decisions.md](decisions.md) ADR-096).

A second idea, **dm-verity**, is needed to trust what is compared. The root disk comes with a tree of fingerprints; its top value, the root hash, is written on the kernel command line, which the hardware measures into RTMR2. So the quote says which root disk is right. Before the helper reads a disk, it checks **every block** against that root hash, like checking that the seal on a box matches the number on the receipt before you open it.

## 2. What was built, commit by commit

All commits are on the branch `feat/tee-hadoop-cluster` of the private repository `Heron-AI-Security/nutch-private`. Every commit ran on the real cloud before it was pushed.

| Commit (full id) | Date | What it adds | What the real run showed |
|---|---|---|---|
| [`20267a68d7b54b776fb4789f610630cf339b72c6`](https://github.com/Heron-AI-Security/nutch-private/commit/20267a68d7b54b776fb4789f610630cf339b72c6) | 30 October 2026 | P4.1: `ops/verify-reference.sh`, part A (the published evidence, no cloud) and part B (your own dummy run) | part A passed 27 checks on the real published set; all 13 grub and kernel command events hash to their text; `gh release download` works; the positive control was equal; the negative control (`tc-img-psl-1`) failed on the `source` event |
| [`fea794432364c1b1234266db13a9bb35ffd522cd`](https://github.com/Heron-AI-Security/nutch-private/commit/fea794432364c1b1234266db13a9bb35ffd522cd) | 2 November 2026 | P4.2: the file-tree comparison (`ops/tree-manifest.py`, `ops/tree-diff.py`, `ops/tree-diff.sh`) with a read-only helper VM | two disks of one image were identical (65,078 files); `tc-img-rel-1` against `tc-img-psl-1` gave 76 differences (builder leftovers and the real differences of two commits) |
| [`829e90c2ff49bcd4e705e10b2c1f666cf4ecce8d`](https://github.com/Heron-AI-Security/nutch-private/commit/829e90c2ff49bcd4e705e10b2c1f666cf4ecce8d) | 2 November 2026 | P4.2b and P4.3: the disks are opened through dm-verity with parameters read from authenticated boot events; extended attributes and capabilities; one command | `VERIFY-REFERENCE-OK … explained=0 trees=identical image-run=exact` on `tc-img-rel-1`; a root hash that was wrong by one character was refused |
| [`530237c2f5d4c840007b507cd666fde623e66bea`](https://github.com/Heron-AI-Security/nutch-private/commit/530237c2f5d4c840007b507cd666fde623e66bea) | 2 November 2026 | the tamper test on real disks, and a partition lookup per disk | `TAMPER-TEST-OK image=tc-img-rel-1 cases=5`: four tampered copies were each rejected for exactly one named difference |
| [`c60995fa4bc585223f4d3690690188d075d79bc0`](https://github.com/Heron-AI-Security/nutch-private/commit/c60995fa4bc585223f4d3690690188d075d79bc0) | 4 November 2026 | the build cleanup: gate 6b of the sealing (`ops/image/build/tc-image-normalize.sh`), the live cleanup fixed, snapd purged | two builds of this commit hold **identical files**: `TREE-DIFF-IDENTICAL files=64612 dirs=8461 symlinks=5197 ignored=0 verity=checked` |
| [`9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81`](https://github.com/Heron-AI-Security/nutch-private/commit/9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81) | 4 November 2026 | the helper tools: the disks are attached after the boot, faster disks, a longer wait with the console of a VM that does not answer, and a `probe` mode | four boot probes in a row were clean; the comparison of the two builds took 16 minutes |
| [`1c30fc65fd13322e48c69e56e187280e0cccefdb`](https://github.com/Heron-AI-Security/nutch-private/commit/1c30fc65fd13322e48c69e56e187280e0cccefdb) | 4 November 2026 | the documents of step P4: this page and the update of every other document except the first-principles guide | the audit of the repository passed on the pushed commit (`PREFLIGHT-OK`), and 29 of 29 files were identical on a fresh clone in Cloud Shell |
| [`15ab399fa6368af566aee370aa5f6f62e1447826`](https://github.com/Heron-AI-Security/nutch-private/commit/15ab399fa6368af566aee370aa5f6f62e1447826) | 4 November 2026 | the kits that ran: `ops/kits/cl2-kit/` (12 files), `ops/kits/p4g-tools-test/p4g-block.sh` and `ops/kits/cln-resume/cln-resume-fleet2.sh` | before the commit, a check in Cloud Shell compared every file with the file that ran (`P4KIT-HAND-OK`, 14 files); the kit manifest matched (11 of 11 scripts); 14 of 14 files were identical on a fresh clone |

Anyone can see exactly this state: `git clone` the repository, then `git checkout 9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81` (or any commit above). The image of the accepted comparison was built from `c60995fa4bc585223f4d3690690188d075d79bc0`; the later commit changes only tools, not the image.

## 3. How the comparison works

`bash ops/verify-reference.sh COMMIT (--published DIR or --release TAG) [--published-image [PROJECT/]IMAGE] [--own-image IMAGE] [--no-trees] [--work DIR]` makes one verdict from four parts:

| Part | What it does | What must hold |
|---|---|---|
| A. The published evidence | no cloud: the sums of the files, the `source` event (it must be the SHA-384 of the commit text), the quotes, the replay of RTMR3 and of the boot log, the root hash, the tables | all checks pass; the texts of the grub and kernel command events are **authenticated**: they must hash to their digest in the log, so a forged text next to a genuine digest cannot pass |
| B1. The published image | a dummy run of the published image against the published reference | exactly equal |
| B. Your own build | a dummy run of your own image against the published reference | equal, except that RTMR2 may differ in events that carry the root hash or partition ids; these are counted and printed as `explained=N` |
| C. The files | the root disks of the two images, each opened through dm-verity, and every file compared | `TREE-DIFF-IDENTICAL`, with `ignored=0` |

How part C works, in order:

1. **One throwaway helper VM** (an ordinary Ubuntu VM, not a TDX VM) is made, and the two disks are made from the two images and attached to it (since commit `9b4a08fbb73d`, **after** its boot: section 6).
2. **The parameters of dm-verity** (root hash, number of blocks, salt, partition id) are read only from the **authenticated boot events** of the dummy runs (`ops/verify-reference.py --verity-of`), never from the image. The helper runs `veritysetup verify` over every block (no superblock, SHA-256, 4096-byte blocks, the hash tree at block count times 4096), and only then opens the disk with `veritysetup open` and mounts it **read-only**. A disk that does not match is refused with `VERITY CHECK FAILED` (exit code 3) and no manifest is made.
3. **A manifest** of each file tree is made (`ops/tree-manifest.py`, version 2): for every entry its path, type, mode, owner and group, extended attributes and capabilities, symlink target, size and the SHA-256 of its contents. **Times are ignored.**
4. **The comparison** (`ops/tree-diff.py`) reports every kind of difference per path. The verdict line is `TREE-DIFF-IDENTICAL` or `TREE-DIFF-DIFFERENT`, with `verity=checked`; with `--require-verity` a manifest that was not made from a checked disk is refused. An optional `--ignore FILE` exists, its default is empty, and the number of ignored differences is always printed.
5. The helper VM and the disks are deleted, also when something fails.

The one verdict line of the whole command is `VERIFY-REFERENCE-OK commit=… image=… own=yes explained=N trees=identical image-run=exact`.

The tamper test (`ops/image/test/tamper-test.sh IMAGE --verity "ROOTHASH BLOCKS SALT PARTUUID"`) shows that the comparison can fail: one helper VM gets the original disk read-only and five copies read-write; four copies get one change each, are sealed again with a new hash tree, and all are read through dm-verity; each must be rejected for exactly one named difference, and the untouched control must give back **the original root hash**, which proves that our sealing parameters are exactly those of the real sealing.

## 4. The runs, in order

The tables with every number are in [run-comparison.md](run-comparison.md) sections 9.22 to 9.24. In short:

| Date (UTC) | What | Result |
|---|---|---|
| 2 November 2026, 15:37 to about 17:00 | the tamper test on real disks of `tc-img-rel-1` (commit `530237c2f5d4`) | passed: five cases, ten checks; it took about 1.5 hours because six disks of the slowest type were read at once |
| 2 and 4 November 2026 | the first run of the kit, which built **two builds of a first version of the cleanup** (a local commit that was never pushed) | the builds and the sealing passed; the file-tree comparison **failed with 27 differences** (section 5) |
| 4 November 2026, from 10:46 | the kit again, on commit `c60995fa4bc5` | the comparison **passed**: identical files; one helper VM did not accept SSH within 24 attempts, and the stage was repeated with a longer wait |
| 4 November 2026, the helper of test 2 was made at 15:48 | the first candidate for the helper tools (a version that was never committed) | test 1 passed, **test 2 failed**: the helper VM was in emergency mode (section 6) |
| 4 November 2026, the helper of test 3 was made at 17:24 | the tools commit `9b4a08fbb73d` | all three real tests **passed** |
| 6 November 2026 | the kit runs `fl2` (commit `da3938bfd`) and `fl3` (commit `ded1e1658`) | the comparison is a stage of each run, and both runs ended in a pass (`FL2-PASS`, `FL3-PASS`) |
| 7 November 2026 | the kit runs `e15a` and `e15r2` (the local test commits `95553d8d7` and `619eb3d94`; the image with the 15-site profile; 11 nodes) | both passed (`VERIFY-REFERENCE-OK … trees=identical image-run=exact`); the second: `TREE-DIFF-IDENTICAL files=64612 dirs=8390 symlinks=5197 ignored=0 verity=checked` |
| 9 November 2026 | the kit run `k1a` (the local test commit `350c7c09b` on `947b47896`; the image with the 908-seed profile; 11 nodes) | passed: `VERIFY-REFERENCE-OK`, `P4-ACCEPT-OK` and `TREE-DIFF-IDENTICAL files=64612 dirs=8390 symlinks=5197` ([perf/Test_Run_1K_URL_2026_11_09_Run_1](perf/Test_Run_1K_URL_2026_11_09_Run_1/README.md)) |

## 5. Problem 1: two builds of one commit differed in 27 files

### 5.1 What we saw

The first real comparison of **two builds of one commit** (not two images of two different commits, as before) ended `TREE-DIFF-DIFFERENT differences=27 ignored=0 verity=checked`, after both disks had been checked through dm-verity, so the 27 differences are real file differences and not read errors. Everything before it passed: the two builds agreed in 15 of 15 events and in the 601 packages, the fleet crawled, and the reference was published. The strict rule (any difference fails, no ignore list) did its job.

| Kind | Count | Paths (an account name is written as `<account>`) |
|---|---|---|
| owner differs | 18 | the four home folders `/home/dev`, `/home/<author>`, `/home/<teammate-1>`, `/home/<teammate-2>`, and their dotfiles (`.bash_logout`, `.bashrc`, `.profile`, and for one account `.cache` and `.cache/motd.legal-displayed`); the owner ids were 1001 to 1004 in one build and the same four accounts had other ids in the other (for example 1002:1003 against 1001:1002) |
| content differs | 9 | `/etc/passwd`, `/etc/shadow`, `/etc/group`, `/etc/gshadow`, `/etc/subuid`, `/etc/subgid` (same sizes, other contents); `/var/lib/google/google_users`; `/boot/initrd.img-6.17.0-1022-gcp` (35,367,076 against 35,367,222 bytes); `/etc/ssl/certs/java/cacerts` (136,103 bytes in both) |

### 5.2 The root causes, one by one

| # | Cause | Why it happens | Files | The fix | Where |
|---|---|---|---|---|---|
| 1 | The operator accounts | the Google guest agent creates a Linux account for every SSH key in the project metadata when the builder first starts, and it creates them **in another order on every builder**, so the same four accounts get ids 1001 to 1004 in another order; the accounts also carry the real names of the people who work on the project, which must not be in an image that is published | 25 of the 27 (the six account files, the list `google_users`, 18 home folder entries) | gate 6b removes exactly the accounts that the agent lists in `google_users`, with their home folders, group entries and `subuid` and `subgid` lines; it refuses a listed account with a system id (below 1000) or an odd name, and stops if any file is still owned by a removed user or group; the agent makes the accounts again at boot from the keys in the metadata, which is all that a debug fleet needs (SSH worked on both sealed images and in the fleet) | [`tc-image-normalize.sh` lines 62 to 142](https://github.com/Heron-AI-Security/nutch-private/blob/c60995fa4bc585223f4d3690690188d075d79bc0/ops/image/build/tc-image-normalize.sh#L62-L142) |
| 2 | The plain initramfs | `update-initramfs` rebuilds `/boot/initrd.img-<kernel>` with other bytes in every build (here 146 bytes), and the sealed boot does **not** use it: it uses `initrd.img-tc`, which is measured (the initrd event of RTMR2 was equal in both builds) | 1 | gate 6b removes every `/boot/initrd.img-*` except `initrd.img-tc*` and the links that pointed at them, only if `initrd.img-tc` exists | [lines 145 to 149](https://github.com/Heron-AI-Security/nutch-private/blob/c60995fa4bc585223f4d3690690188d075d79bc0/ops/image/build/tc-image-normalize.sh#L145-L149) |
| 3 | The Java trust store | a JKS file keeps a creation time for every certificate and a checksum over them, so its bytes change with every build although the 120 certificates are the same (the measured event `java-ca-fingerprints` is the sorted list of their fingerprints and was equal) | 1 | gate 6b rewrites the file with the same certificates sorted by name, **one fixed creation time** and the checksum recomputed with the standard password; it refuses a file that is not a JKS, whose checksum does not match, or that holds a private key, and it checks that the set of certificates is unchanged; a real `keytool` opens the result and shows the same fingerprints | [lines 150 to 180](https://github.com/Heron-AI-Security/nutch-private/blob/c60995fa4bc585223f4d3690690188d075d79bc0/ops/image/build/tc-image-normalize.sh#L150-L180) |
| 4 | Leftovers of the builder (already handled by the first version of the cleanup, 228 entries) | the logs and the journal of the build session, temporary files, caches, state files, and the identity of the builder (host name, instance id, cloud-init files, account backups) | the 76 differences of the earlier comparison of two commits | gate 6b removes them offline, after the shrink and before the hash tree, then checks that every group is empty | [`tc-image-seal.sh` lines 81 to 92](https://github.com/Heron-AI-Security/nutch-private/blob/c60995fa4bc585223f4d3690690188d075d79bc0/ops/image/build/tc-image-seal.sh#L81-L92) |
| 5 | The grub backups, a real bug | the live cleanup ran `rm -rf /root/grub-backup-*` as the normal user, and a shell expands the pattern **before** the command runs; that user cannot read `/root` (mode 0700), so the pattern matched nothing and the backups stayed in the image | part of cause 4 | `find` runs as root; the report of the real build had no `grub` group at all, which shows that nothing was left for the offline step | [`tc-image-clean.sh` line 19](https://github.com/Heron-AI-Security/nutch-private/blob/c60995fa4bc585223f4d3690690188d075d79bc0/ops/image/build/tc-image-clean.sh#L19) |
| 6 | snapd | its device key, its assertions and its state are different in every build, and a confidential node does not need it; nothing in our code depends on it | part of cause 4 | the live cleanup purges snapd (the simulated purge listed only `snapd`, version 2.76.3, and nothing else); the offline step stops if any trace is left; `TC_KEEP_SNAPD` keeps it, and then the sealing needs `--allow-snapd` | [`tc-image-clean.sh` lines 29 to 35](https://github.com/Heron-AI-Security/nutch-private/blob/c60995fa4bc585223f4d3690690188d075d79bc0/ops/image/build/tc-image-clean.sh#L29-L35) |

### 5.3 Why the earlier checks did not show it

The earlier comparison of two **different commits** found 76 differences, and nobody could tell the builder's leftovers from the real changes. A comparison of an image with itself is identical by construction. Only **two builds of one commit** isolate what the build adds by itself. The checks of step R4 compared the 15 measured events and the initramfs, which do not cover the rest of the root disk.

### 5.4 The decisions

- **Not step F5.** The build cleanup here removes what a build adds to an image; step F5 of the plan, "the cleanup", stops the scaffolding of the repository and the process, and is a different item that is still open.
- **No ignore list.** The mentor's rule is that any other difference fails. An earlier plan for a fixed list of ignored paths was dropped; the option `--ignore` stays, its default is empty, and `ignored=0` is printed in the result.
- **The cleanup happens offline, last.** Gate 6b runs on the helper's copy of the disk after the shrink and before the hash tree, so nothing runs on the disk afterwards. The sealed image is therefore not the bytes that the builder produced; this is a limit (limitations row 225).
- **Remove, do not exempt.** The accounts, the initramfs and the snapd state are removed. The trust store is **rewritten with a fixed time**, not exempted from the comparison: a rule that says "any difference fails" is honest only if every exception is absent. The rewrite changes no certificate (it is checked in the script, and a real `keytool` shows the same fingerprints).
- **snapd is purged.** This is a decision with a switch (`TC_KEEP_SNAPD`); [decisions.md](decisions.md) ADR-097 records it.

### 5.5 The result

On commit `c60995fa4bc5` the two builds gave sealed root hashes `981d7d72f9359a01…` (A) and `796b7faaaeeefbee…` (B), which **differ**, as expected (file system times and layout), and the files are **identical**: `TREE-DIFF-IDENTICAL files=64612 dirs=8461 symlinks=5197 ignored=0 verity=checked`, with `VERIFY-REFERENCE-OK … explained=4 trees=identical image-run=exact`. The normalization removed the same 284 entries from both builds (logs 19, initramfs 4, scratch 17, identity 9, caches 171, state 12, accounts 52) and rewrote the 120 certificates of the trust store. A sealed fleet of the image then crawled (`fetched=8 segments=3 rounds=3`) and passed the whole verification.

**Why the root hashes differ.** The root hash is the top of the dm-verity tree over every 4 KB block of the root partition, so it fingerprints the bytes of the disk and not only the files on it. The sealing copies the builder's live ext4 file system, checks it, removes the journal, shrinks it and computes the hash with a fixed salt (`ops/image/build/tc-image-seal.sh`). The salt and the file system and partition ids are fixed (ADR-088), and the files are identical, so the difference has to be in bytes of the file system itself that the file comparison does not look at: it never compares times, free space or the layout. The cause that the decision log gives is the timestamps and the block layout that installing onto a live disk leaves. This is an **inference by elimination and not a measurement**, because the two sealed disks have never been compared block by block (limitations row 186). The verifier sees the difference in exactly four RTMR2 events, numbered as in [boot-events.md](boot-events.md): event 4 (the measurement of `grub.cfg`, which holds the root hash) and events 13, 15 and 17 (the `menuentry`, the `linux` command and the `kernel_cmdline`, which carry `tc.verity=`). Event 12, which carries a file system id, is identical in both builds. The table of that document is the one of the dummy run of `tc-img-rel-1`, an image of the same structure; the log of this run (`cl2-p4/verify.log`) names the four events by number only.

**What it means for reproducibility.** The content is reproducible (the same files and the same measured events), the bytes of the disk are not: a stranger cannot recompute the root hash or the RTMR2 register from the source, and has to compare the files of their own build with the published disk through dm-verity (this page), which needs a helper VM and the shared image. The mentor's plan of 28 October (ADR-090) decided that a bit-identical disk is not needed for this reason, and on 5 November 2026 she asked why the hashes differ. Three ways forward are open for her to choose: keep it and state the limit in the paper; measure which blocks differ (one helper VM run of about 20 minutes and a small addition to the helper tools); or make the file system deterministic (fixed times, ids, hash seed and file order, or a read-only format made for it), which changes the sealing step and needs new runs.

## 6. Problem 2: the helper VM that did not boot

### 6.1 What we saw

| Time (UTC, 4 November 2026) | What happened |
|---|---|
| 14:13 (the helper was made) | the helper VM of the file-tree step did not accept SSH within 24 attempts (about 7 minutes); the SSH error was "System is booting up. Unprivileged users are not permitted to log in yet" (`pam_nologin`) |
| 14:31 to 15:00 | the same stage was repeated with `TREE_SSH_TRIES=80` (about 24 minutes of waiting); this time the helper booted, and the comparison passed |
| 15:48 (the helper was made) | the first candidate for the fix, with 80 attempts and faster disks, **failed**: the helper VM did not accept SSH in 80 attempts |
| the same run | the console of the VM, which the new candidate printed before it deleted the VM, showed that the VM was in **emergency mode** |

### 6.2 The root cause

The console of the failed VM shows, in this order: the kernel saw three disks (the helper's own disk of 10 GiB and the two sealed disks of 30 GiB); systemd found `/dev/disk/by-label/UEFI` and `/dev/disk/by-label/BOOT`; the check of the file system on `/dev/disk/by-label/UEFI` **failed**; `boot-efi.mount` and then `local-fs.target` could not start (`Dependency failed`); the VM reached `emergency.target` after 10 seconds, and said "You are in emergency mode". In emergency mode SSH never accepts a login, however long you wait.

Why: the helper's own disk is an Ubuntu cloud image, and its table of file systems mounts `/boot/efi` by the **label `UEFI`** (and `/boot` by `BOOT`). Our sealed disks are made from the same kind of image, so partition 15 of each sealed disk carries the label `UEFI` too (the probe lists `sdb15 106M vfat UEFI` and `sdc15 106M vfat UEFI`; the sealed disks have no `BOOT` label, only `cloudimg-rootfs` for the root). With three disks, `/dev/disk/by-label/UEFI` can point at any of the three partitions, and which one wins is a **race** between the disks that depends on the order in which the system finds them. When it points at a sealed disk (attached read-only), the file system check fails and the boot stops. It is a race, so it worked in some runs (the tamper test with six disks, the earlier comparisons) and failed in others.

What the console proves and what it does not: it proves the failing check, the order of events and the emergency mode. It does **not** show which disk the label pointed at. That part is an inference from the facts that the failure appears only with the extra disks attached, that the labels are duplicated, and that the fix below (no extra disks at boot) gave clean boots every time. The first failure of 14:13 had the message "System is booting up"; its console was not kept, so it is **probably** the same trouble, but this is not proven.

### 6.3 Why waiting and faster disks could not help

The first reaction was to wait longer (24, then 80 attempts) and to use faster disks, because the helper's disks were of the slowest type (a 30 GB disk of that type gets only about 4 MB/s, which we measured in the tamper test) and the first failure looked like a slow boot. Neither could work: a VM in emergency mode never accepts SSH. The faster disks (`pd-balanced`) are still useful: the comparison of the two builds took 16 minutes in the final test, against 28 minutes for the whole stage of the kit, but those two numbers are not like for like, so the speed-up is **not measured on its own**.

### 6.4 The fix and its tests

The helper VM is now created **without** the two sealed disks, and they are attached **after** it has booted, so its boot sees only its own disk and cannot meet a duplicate label ([`tree-diff.sh` lines 82 to 83](https://github.com/Heron-AI-Security/nutch-private/blob/9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81/ops/tree-diff.sh#L82-L83) and [`tamper-test.sh` line 48](https://github.com/Heron-AI-Security/nutch-private/blob/9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81/ops/image/test/tamper-test.sh#L48)). The scripts on the VM wait up to 60 seconds for a disk that appears late ([`tree-helper.sh` line 32](https://github.com/Heron-AI-Security/nutch-private/blob/9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81/ops/tree-helper.sh#L32), setting `TREE_DISK_WAIT`). Kept from the first candidate: `pd-balanced` disks for the disks and the boot disk (`TREE_DISK_TYPE`, [line 77](https://github.com/Heron-AI-Security/nutch-private/blob/9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81/ops/tree-diff.sh#L77)), 80 attempts by default ([line 80](https://github.com/Heron-AI-Security/nutch-private/blob/9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81/ops/tree-diff.sh#L80)), and the console of a VM that does not answer, printed and saved before the VM is deleted, with a note when the VM is still booting ([line 81](https://github.com/Heron-AI-Security/nutch-private/blob/9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81/ops/tree-diff.sh#L81)). A new command, `bash ops/tree-diff.sh probe IMAGE_A IMAGE_B` ([line 85](https://github.com/Heron-AI-Security/nutch-private/blob/9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81/ops/tree-diff.sh#L85)), makes the helper, attaches the two disks after the boot, checks that both are visible and deletes everything in about 3 minutes, as a cheap test of the boot.

| Test | Version | Result |
|---|---|---|
| the first candidate (a zip with SHA-256 starting `75b3a270`, **never committed or pushed**) | 80 attempts, `pd-balanced`, console dump | test 1 (a real helper VM with an injected SSH fault) passed; test 2 (the real comparison) **failed**: emergency mode, as in section 6.2 |
| commit `9b4a08fbb73da0da4c7ad7c733e99f90dad3eb81` (a zip with SHA-256 starting `f31a5a5f`) | disks attached after the boot | test 1 passed; test 2, **four probes in a row**, passed in 188, 161, 162 and 198 seconds, each with `boot: running`; test 3, the real comparison of the two builds, passed in 16 minutes; the block ended `P4G-HAND-OK zip=f31a5a5f`; the commit was pushed only after this |

The rehearsals of the commit have 117 checks (`p42-rehearse.sh`), 47 (`tamper-rehearse.sh`, as root) and 103 (`p4-rehearse.sh`), and 38 mutants are caught. One mutant showed that my own test of the late disk was **empty**: its `cd` failed, so it passed on correct and on broken code; it was repaired with a positive check (mistake 230).

### 6.5 What is still not proven

Five clean boots in a row are evidence, not proof, because the failure was intermittent: if it had happened one time in three, five clean runs would still occur by luck about one time in six. The stronger argument is the mechanism: with one disk at boot, a duplicate label cannot exist. Other helper VMs of ours that attach disks of these images at creation (the sealing helper) have not been checked for the same race (limitations row 231).

## 7. What it shows, and what it does not

**It shows** that two builds of commit `c60995fa4bc5` of the debug image, made by one operator from one dated copy of the Ubuntu archive, hold the same files (path, type, mode, owner, extended attributes, symlink target, SHA-256), both read through dm-verity against the root hash that the quote commits to; that the comparison fails on one changed file, one added file, one changed mode and one added capability; and that the sealing parameters of the tamper test equal the real ones.

**It does not show** (limitations rows 223 to 231): that the locked, production variant of the image was compared; that a second party or another day gives the same files (the rebuild by the teammate is still open, row 188); that the free space and the other partitions of the disk are equal (only the root partition is covered by the root hash; the boot partition is covered by RTMR2 events); that the cleanup removed nothing that matters beyond what the fleet test exercised; that the two sealed disks differ only where we think they do (the cause of the different root hashes is inferred, not measured: they were never compared block by block, row 186); and that a stranger can run the kit without adapting it (the kit is in the repository, but the names of the project and of the runs are fixed in its scripts).

## 8. How to repeat each check

| What | Command (from a clone at the commit) |
|---|---|
| the rehearsals, no cloud | `bash ops/image/test/p4-rehearse.sh`, `p42-rehearse.sh`, `tamper-rehearse.sh` and `p4d-rehearse.sh` (the cleanup, with real file systems when run as root) |
| the cleanup of a mounted root | `bash ops/image/build/tc-image-normalize.sh --root DIR [--report FILE] [--allow-snapd]`; in the sealing, `--no-normalize` skips it (the control that makes two builds differ) |
| the boot test of the helper | `bash ops/tree-diff.sh probe IMAGE_A IMAGE_B --work DIR` (about 3 minutes, a few cents) |
| the comparison of two images | `bash ops/tree-diff.sh diff IMAGE_A IMAGE_B --verity-a "ROOTHASH BLOCKS SALT PARTUUID" --verity-b "…" --work DIR`; offline again: `python3 ops/tree-diff.py DIR/a.manifest DIR/b.manifest` |
| the whole verdict | `bash ops/verify-reference.sh COMMIT --release publish-ref-<9 characters> --published-image IMAGE --own-image IMAGE2` (or `--published DIR` for the files of a release in a folder); it ends with `VERIFY-REFERENCE-OK …` |
| the whole accepted run | the kit `ops/kits/cl2-kit/` (commit `15ab399fa`): copy the folder to the home folder of Cloud Shell as `cl2-kit`, upload the archive `src-cl2-<9 characters of the commit>.tgz` made by `git archive` of the commit, and start it with `EXPECT=<9 characters of the commit> setsid nohup bash cl2-kit/cl2-run.sh > ~/cl2-run-nohup.out 2>&1 &`; it needs the seed builder with the Hadoop tarball and the quota, and it ends `CL2-PASS`; the block of the tools test is `ops/kits/p4g-tools-test/p4g-block.sh` and the resume script of a lost run is `ops/kits/cln-resume/cln-resume-fleet2.sh` |
| the tamper test | `bash ops/image/test/tamper-test.sh IMAGE --verity "ROOTHASH BLOCKS SALT PARTUUID" --work DIR` |

Settings that can be changed by environment: `TREE_SSH_TRIES` and `TREE_SSH_WAIT` (SSH attempts and the pause between them, 80 and 15 seconds), `TREE_DISK_TYPE` (`pd-balanced`), `TREE_DISK_WAIT` (60 seconds), `ZONE`, `HELPER_TYPE`, `HELPER_FAMILY`, `HELPER_IMAGE_PROJECT` and `TREE_HB` (the heartbeat line, 60 seconds).

## 9. Where the evidence is

The logs of the real runs are in Cloud Shell and in the laptop's evidence folder `tdx-evidence\p4-evidence\`, named by SHA-256. The hashes below are of the files as they were on 4 November 2026.

| What | SHA-256 |
|---|---|
| the 27 differences of the first strict comparison (`differences.tsv`) | `973972f9368d0f6bf791fbcb8ca7b422aeaa4b80000fb34ddcc14f9f4cd29512` |
| the evidence bundle of the accepted run (`evidence-cl2-final.tar.gz`) | `7bd3af51c83a37edc1a34b37a5b1b0138587ef13c47cfc4a343cf2394af1b8d5` |
| the log of the verification of the accepted run (`verify.log`) | `9caece4ea7e52ec661e83dad2333edfa45a27a62600657270a0f5ec5acb30003` |
| its verdict (`tree-verdict.txt`) | `02b9813e393ffa9e365e9ee2b0c9ac961d0590bc8b22b538320fee5a08e1df52` |
| the times of the stages of the accepted run (`timings.txt`) | `3daf8e62462770844ff8bf51298edf539d0674ccce7bb799068548bac2296217` |
| the output of the test of the commit `9b4a08fbb73d` (`p4g-run.out`) | `9079842c2a8f52bd6dcc24fe9203e179162d963ae01d56c34f8db066e545160b` |
| the evidence bundle `p4-evidence-bundle.tar.gz` (the whole collection, see below) | `3b98653a89dab4a792289d8e8a3d6c5f3290517c620ce3f7e0ce13cc6f39eca8` |
| the output of the failed second test of the first candidate (`p4f-t2.txt`) | `35f19642ba5bb59efbd3b0f706c263b8dab04cb2264b0a2e9d0ecb8aaaaf4d2f` |
| the console of the helper VM in emergency mode (`serial.log`) | `c27101a2687beb1a6810068d55f243f2b45d9a779ffb7369fcd4af2dd49b2a23` |
| the console of the helper VM of the injected-fault test (`serial.log`) | `be3a2d062e94df7f82415fc0d4f8ec7564ed5772588f7e4dfe373d5584a44cb1` |

The bundle `p4-evidence-bundle.tar.gz` is the copy of what the home folder of Cloud Shell held on 4 November 2026 under these names: the files and folders that start with `p4`, `cln-` or `cl2-` (the clones of the repository, which end in `-test`, are left out), the folder `p32-out`, and the folders `evidence-cln-*` and `evidence-cl2-*`; it includes the two kits (`cln-kit` and `cl2-kit`) and the scripts of the resume. Its file `SHA256SUMS` lists 962 files, and all of them were checked on the laptop after the download (0 problems); the nine hashes of the table above are in it. The bundle holds 971 files: the 962 that are listed and nine files that are named `SHA256SUMS` (the top one, and eight that the tools of earlier runs made in their own folders: `cl2-p4/pub/publish`, `cln-p4/pub/publish`, `evidence-cl2-A/r4`, `evidence-cl2-B/r4`, `evidence-cln-A/r4`, `evidence-cln-B/r4`, `p32-out/publish` and `p4-work-r/published`), which the collection leaves out of its list by construction. The bundle holds project identifiers and addresses, so it is kept outside the repository and is not published.
