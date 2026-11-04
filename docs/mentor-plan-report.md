# The mentor's six-step plan (steps P1 to P6): report

**Status check, 4 November 2026.** Steps P1, P2, P4 and P6 are done on the real cluster, and step P3 is split in three: P3.1 (CI signs in to Google Cloud) and P3.2 (CI publishes the reference) are done and verified, and P3.3 (CI builds the image) was **dropped** by the mentor's review of 1 November 2026; P5 is not started. Step P4 (`verify-reference` and the file-tree comparison) is section 8: two builds of one commit hold identical files, and two problems found on the way are solved (27 differences between two builds, and a helper VM that sometimes did not boot). This is the report of the plan, in the form of the milestone reports: what we wanted, why, what we built step by step (the sub-steps are numbered), how it was tested, what went wrong, what is not done, and where the evidence is. The facts behind each step are in [run-comparison.md](run-comparison.md) sections 9.19 to 9.24, [tree-comparison.md](tree-comparison.md), [boot-events.md](boot-events.md), [ci-publishing.md](ci-publishing.md) and ADR-090 to ADR-098 in [decisions.md](decisions.md).

## 1. Goal, in plain words

The cluster produces a **quote**: a fingerprint of what is running, signed by the CPU. A stranger can only trust a quote if they know which numbers an honest node must show (the **reference values**) and can tie those numbers to our source code. Until 28 October 2026 the reference values came from the same fleet run that they were meant to judge, like marking your own exam with your own answers. The mentor's plan of 28 October (US time) fixes this in six steps:

1. a **dummy run**: one VM made from the image alone, to produce the reference;
2. **tie the commit to the image**: the image is built from a `git archive`, carries the commit in its first measured event and in its labels, and has a `release.json`;
3. **CI publishes** the reference from the dummy run, so that it is not only we who can say what it is;
4. a **verifier command** `verify-reference COMMIT` that makes its own dummy run and compares the file tree of the published image with its own build;
5. the **verifier from the crawl's records to the quote** (Intel's signature chain, the record signatures, the debug bit, Google's endorsement of the firmware);
6. the **table of the RTMR1 and RTMR2 events**, to settle where the kernel lands.

## 2. Background (first principles)

- A **register** (MRTD, RTMR0 to RTMR3) is a running hash: each measurement is mixed into the old value, so the final number depends on everything measured, in order. The **boot event log** lists the measurements, and the **replay** recomputes the registers from it. Layer 10 of the [first-principles guide](guide-first-principles.md) explains this with an analogy (a till tape and its total).
- An **image** is a stored copy of a disk. Every node made from it starts with the same bytes, so one set of reference values can fit every node.
- **dm-verity** protects the root disk with a tree of fingerprints; its top value, the **root hash**, is written on the kernel command line, which is measured into RTMR2, so the quote commits to the whole root disk.
- A **dummy run** makes one node from the image with the settings of a fleet node but without a fleet list. Its numbers are the reference, because nothing about the fleet can influence them.
- A **release** is the file `release.json`: this commit made this image, whose disk has this root hash, and here is the reference.
- **CI** (continuous integration) is a job that a server runs for us from a commit. Here it matters because a reference that a server publishes from a commit can be checked by a stranger, while a reference that we paste from our own Cloud Shell cannot.

## 3. How the plan was decided

- **The mentor's note** of 28 October 2026 (US time) replaced how the reference values are made. It also said that a bit-identical sealed disk is not needed, because the file-tree diff of step 4 does that job. We adopted it on 29 October as ADR-090, which cancelled step R4.8 (ADR-088).
- **The order.** Steps 2 and 6 were built first and together, because both change the image and an image change is expensive (tens of minutes of building and sealing); step 1 came before them, because the later steps use the dummy run. Step 3 builds on the final image.
- **Step 3 was split** (ADR-095). The mentor's line says only "CI publishes the reference from the dummy run". Building the whole image inside CI is a large separate task (our image run depends on a persistent seed builder and on two drivers), so P3.1 is the plumbing, P3.2 the publication, and P3.3 the build in CI.
- **The mentor's review of 1 November 2026** (it follows this report of 30 October) dropped **P3.3**: P4 ties the image to the commit for a verifier who does not trust us and works whoever built the image, while building in CI would only move the trust from Cloud Shell to GitHub and the seed builder; in the paper we say that our team builds the image and verifiers check it with P4 (ADR-096). It also said that P4.1 is fine as designed only together with P4.2, that this report was behind the code, and that `main` was created from the tip of this branch (`20267a68d`) and each later change is branched off `main` and merged by pull request.
- **The CI system** is not named by the mentor. We chose GitHub Actions with Workload Identity Federation (ADR-094); the reasoning and the alternatives are in [ci-publishing.md](ci-publishing.md), and every setting can be changed.

## 4. Steps and status

| Step | What | Status | Commits |
|---|---|---|---|
| P1 | The dummy-run script and its comparison with a reference | Done on 29 October 2026 | `9a3e9a845` |
| P2 | `release.json`, the image labels, the commit tied to the image, the root hash tied to the quote | Done on 29 October 2026 | `16bafb3b1`, `a950bf882` |
| P3.1 | CI signs in to Google Cloud without a key, and its rights are checked | Done on 30 October 2026 | `0f235f446` |
| P3.2 | CI runs the dummy run of an image and publishes the reference and `release.json` | Done on 30 October 2026 | `a70f3ff2c` |
| P3.3 | CI builds the image from a `git archive` | **Dropped** by the mentor's review of 1 November 2026 (ADR-096; limitations row 216) | none |
| P4 | `verify-reference COMMIT` and the file-tree comparison | Done on 4 November 2026 | `20267a68d`, `fea794432`, `829e90c2f`, `530237c2f`, `c60995fa4`, `9b4a08fbb` |
| P5 | The verifier from the records to the quote | Planned | none yet |
| P6 | The table of the RTMR1 and RTMR2 events | Done on 29 October 2026 | `a950bf882`, `6572340da` |

The kit of the image run is `86f84c901` and the documents of P1, P2 and P6 are `c9fb51748`. Every code commit ran on the real system before it was pushed. The full ids of the P4 commits are in [tree-comparison.md](tree-comparison.md) section 2; the kit of the accepted run of P4 (`cl2-kit`), the block of the tools test and the resume script are in the repository since commit `15ab399fa` (`ops/kits/`; limitations row 230).

## 5. Step P1: the dummy run

*In plain words: a photograph of what an honest node looks like, taken without any fleet around it.* Sub-steps:

1. **The script** `ops/reference-run.sh IMAGE [DIR]` creates one TDX VM (`c3-standard-4`, 16384 MB, a 30 GB boot disk, the 10 GB scratch disk, no service account) exactly like a fleet node but without the `tc-fleet` metadata, so the node makes its keys and publishes one quote as the guest attribute `tc/announce`, and waits. The script saves the announcement, the quote (8000 bytes), the RTMR3 log, the settings, and deletes the VM on every way out.
2. **The comparison** `ops/reference-compare.py RUNDIR REFERENCE` compares whole MRTD and RTMR0 to RTMR2 values and every stable RTMR3 event with a reference, requires the debug bit to be off, and prints the settings used.
3. **The rehearsal** `p1-rehearse.sh` has 30 checks and 8 mutants that are caught; it reads the creation flags out of the fleet driver, so the dummy run cannot drift away from the fleet.
4. **The real run** on the image `tc-img-psl-1` (the VM `tc-ref-1029-142825`, created and deleted): MRTD, RTMR0, RTMR1 and RTMR2 equal the reference of the real fleet, 15 of 15 stable events equal, debug bit off.
5. **The commit** `9a3e9a845` was pushed only after that run, with the commit id typed from the run's output, and checked on GitHub.

## 6. Steps P2 and P6: the release and the boot events

*In plain words: write on the image which commit made it, and read the firmware's list of everything it measured, so that we can show where the kernel and the disk's root hash land.* The two steps share one image change. Sub-steps:

1. **The node publishes its boot event log** (image commit `16bafb3b1`). A new function `ccel()` in `tc-fleet.sh` reads `/sys/firmware/acpi/tables/data/CCEL` and publishes it as guest attributes in chunks of 12 KB, then its SHA-256, and last the count (so a reader that sees the count knows every chunk is there). `reference-run.sh` reads the chunks back, checks the hash and saves `ccel.bin`. Rehearsal `p2a`: 15 checks, 6 mutants.
2. **The tools** (`a950bf882`): `ops/ccel-table.py` parses the log, replays RTMR0 to RTMR2 against the quote and writes the tables; `ops/make-release.py` makes five checks (the reference is of the commit, its `source` event is the SHA-384 of the commit text, it is of this image, the dummy run equals it, the root hash equals the `tc.verity=` value in RTMR2), writes `release.json` and labels the image with the commit and the two halves of the root hash (a label is limited to 63 characters, a root hash has 64). Rehearsal `p2b`: 24 checks, 4 mutants.
3. **The image run** of the new commit, with the kit `ops/kits/rel-fix-kit/` (stages: prepare, build on two builders, compare, seal-prep, seal-disk, seal-image, fleet, verify, clean). It was stopped once at its first stage by a rehearsal that fails in Cloud Shell (removed from the kit's list), and once by a Cloud Shell reset during a silent step (resumed from the kit's progress files). On 29 October 2026 the stages from the sealing to the end took about 34 minutes (UTC: seal-prep 17:38, seal-disk 17:40 to 17:47, seal-image 17:47 to 17:52, fleet 17:52 to 18:11, verify and clean 18:11 to 18:12). Result: the sealed image `tc-img-rel-1`.
4. **The dummy run of the new image** (the VM `tc-ref-1029-181218`, created and deleted) against the reference of the new fleet: equal in MRTD, RTMR0 to RTMR2 and all 15 stable events, debug bit off. MRTD, RTMR0 and RTMR1 are the same as for the previous image, and only RTMR2 changed (`b22a7643…` to `279e9417…`), because the new root hash is on the kernel command line.
5. **The boot event table** (P6): the log has 262,144 bytes in 22 chunks and 45 events (MRTD 2, RTMR0 17, RTMR1 7, RTMR2 19); the replay of RTMR0, RTMR1 and RTMR2 equals the quote. **The kernel, its command line and the initrd land in RTMR2**, and the three `Mok` variables are there too; RTMR1 holds only the boot manager chain. The tables are in [boot-events.md](boot-events.md).
6. **The release** (P2): all five checks passed for commit `16bafb3b19b3` and image `tc-img-rel-1`; the root hash `b80370de63d9…` equals the `tc.verity=` value in RTMR2 events 13, 15 and 17; `release.json` and the labels were written.
7. **The `--full` option** (`6572340da`): the first tables showed 32 of the 96 digits of each digest and cut texts at 110 characters, so the tool got `--full` for complete digests and texts and always prints the SHA-256 of its evidence. Rehearsal `p2b`: 28 checks, 3 more mutants.
8. **Commits and documents:** the image side `16bafb3b1`, the tools `a950bf882`, the full option `6572340da`, the kit `86f84c901`, and the documents `c9fb51748`.

## 7. Step P3: CI publishes the reference

*In plain words: a robot that anyone can read the log of makes the dummy run and publishes the result, so that the published reference does not depend on our word.* It is built in three stages (ADR-095).

### 7.1 Step P3.1: CI signs in to Google Cloud (done, 30 October 2026)

1. **The decision and its reasoning** (ADR-094, [ci-publishing.md](ci-publishing.md)): GitHub Actions with Workload Identity Federation, so that no key exists to leak. The alternatives (a key in a secret, Cloud Build, a self-hosted runner, our own Cloud Shell blocks) and their trade-offs are in that document.
2. **The staging** (ADR-095): P3.1 the plumbing, P3.2 the publication, P3.3 the build in CI. A run starts by pushing a tag, because a manual run needs the workflow file on the default branch.
3. **The pinned actions.** Each action is pinned to a full commit hash that was read from GitHub itself: `actions/checkout` v7.0.1 (`3d3c42e…`, 17 July 2026) and `google-github-actions/auth` v3.0.0 (`7c6bc77…`, 28 August 2025). Their definitions at those commits were read to use only inputs that exist.
4. **The files** (6, all new): `.github/workflows/ci-smoke.yml`, `ops/ci/ci.env` (every setting), `ops/ci/permissions.txt` (the rights to check), `ops/ci/setup-gcp.sh` (the one-time setup), `ops/ci/smoke.sh` (the check), `ops/ci/rehearse.sh` (the offline rehearsal).
5. **The rehearsal:** 60 checks, 33 mutants caught, ShellCheck and actionlint clean. It checks the safety rules of the workflow (pinned actions, tags only, minimal permissions, no secret, no injection) and runs the two scripts against a fake `gcloud`.
6. **The one-time setup in Cloud Shell** took three tries, and each failed for a reason that the fake could not show: the default service account name `tc-ci` had 5 characters and Google needs 6 to 30 (renamed `tc-github-ci`); the account that ran the setup lacked the rights to create the pool (the setup now checks the rights before any change, even in a dry run, and prints the command that grants a missing role); the third try succeeded. It created the service account `tc-github-ci` with the roles `roles/compute.instanceAdmin.v1` and `roles/compute.storageAdmin`, the pool `github`, the provider `nutch-private` (it admits only this repository and only tags that start with `ci-smoke-` or `publish-ref-`), and the binding that lets only this repository act as the service account. Afterwards the two temporary roles were removed from the account that ran the setup.
7. **The GitHub variables** `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER` and `GCP_SERVICE_ACCOUNT` were set (no secret).
8. **The first run.** A tag `ci-smoke-0f235f446` was pushed on the local commit; the first push was made while GitHub Actions were still off, so no run started (a push that happened while Actions are off is not replayed). The tag was deleted and pushed again after Actions were on, and the run `ci-smoke #1` passed in 23 seconds.
9. **The results of the run:** signed in as `tc-github-ci@training-custody.iam.gserviceaccount.com`; all 21 needed rights are held; the account also holds one right that it does not need, `compute.projects.setCommonInstanceMetadata` (it comes with the instance-admin role; limitations row 218), and it does not hold the rights to change IAM, create service accounts or keys, or create firewalls; the quota `C3_CPUS` has 24 of 24 free (one dummy run needs 4); the zone is up; the machine type is right; 17 images named `tc-img-*` are listed and the labels of `tc-img-rel-1` can be read.
10. **The push of the branch** only after that run, with the commit id typed from its output (`CI-SMOKE-OK commit=0f235f446…`), and the check on GitHub: 6 of 6 files identical, the audit passes. (The first check failed only because an old `ci-code.zip` was still in the Cloud Shell home, and the verifier also compares that zip; it passed after the old zip was removed.)

### 7.2 Step P3.2: CI publishes the reference (done, 30 October 2026)

*In plain words: a robot that anyone can read the log of makes two dummy runs of the image, builds the reference from them only if they agree, and publishes the result, so that the published reference does not depend on our word.* Sub-steps:

1. **The design** (ADR-095). A tag `publish-ref-<commit>` starts the workflow `ci-publish`. The commit is the one that **built** the image, and the image is found by its `commit` label; the code of the workflow comes from the tagged commit. An optional suffix after the commit (`publish-ref-<commit>-r2`) makes a new tag for a new publication, because a release is never overwritten.
2. **The new tool `ops/make-reference.py`** makes the reference values from two dummy runs. For each run it checks the announcement (the REPORTDATA of the quote binds the keys and the RTMR3 log, and the log replays to the RTMR3 of the quote) and that the debug bit is off. The two runs must agree on MRTD, RTMR0 to RTMR2, every RTMR3 event and the settings; a difference means that the dummy run is not reproducible, and no reference is made. The `source` event must be the SHA-384 of the commit text. It writes the format that `reference-compare.py` and `make-release.py` already read, so those two needed no change.
3. **The script `ops/ci/publish-ref.sh`** does the publication in seven steps: it finds exactly one image with the label (and reads the labels `commit` and the two halves of the root hash); makes the two dummy runs one after the other (waiting out a stockout, with a heartbeat line every minute); makes the reference; compares each run with it; makes `release.json` with the root hash of the labels checked against the kernel command line that RTMR2 measured (no relabelling); builds the boot tables with `--full`; and gathers the files to publish, with a check that nothing names the project and with `SHA256SUMS`. It ends with `PUBLISH-REF-OK ... by=<commit of the workflow>`. It also runs by hand.
4. **The workflow `ci-publish.yml`** checks the three variables, reads the commit from the tag name, checks out the tagged commit, signs in, lets `gcloud` use the credentials, remembers the reference VMs that exist, runs the script, creates the GitHub release with `gh release create` (the tag must exist), and always deletes the reference VMs that the run left behind. Its permissions are `contents: write` and `id-token: write`, it has a 60-minute timeout, and runs cannot overlap.
5. **The rehearsals.** `ops/ci/rehearse-publish.sh` has 44 checks (22 for the tool and 22 for the script) with synthetic dummy runs, a fake `gcloud` and a fake dummy-run script; the CI rehearsal has 72 checks, because its workflow safety rules now also apply to `ci-publish.yml`, and a new rule says that a workflow that makes VMs always deletes the ones it left behind. 27 mutants are caught; the first pass caught 24, and the other three gaps were closed.
6. **The real test by hand in Cloud Shell** (30 October 2026, 14:26 to 14:32 UTC, as the account of the author): the image `tc-img-rel-1` was found by its label; the two dummy runs took about 3 to 4 minutes each (their VMs were created and deleted); `REFERENCE-MADE` with 15 events; both runs equal the reference (MRTD `f21e6b48…`, RTMR0 `d413e692…`, RTMR1 `942469f1…`, RTMR2 `279e9417…`); the root hash equals `tc.verity=` in RTMR2 event 13; 11 files with a verifying `SHA256SUMS`; no VM was left behind.
7. **The run in CI.** The local commit `a70f3ff2c` was made, and only the tag `publish-ref-16bafb3b1` was pushed, with GitHub Actions on. The main step ran from about 14:42 to 14:47 UTC as `tc-github-ci` (two dummy runs, no stockout) and ended `PUBLISH-REF-OK commit=16bafb3b19b3… image=tc-img-rel-1 files=11 … by=a70f3ff2c…`. The release `publish-ref-16bafb3b1` was created, the cleanup step found no VM to delete, and the job removed its credentials file. So the CI account can create and delete TDX VMs (limitations row 220 is closed).
8. **What is published** (the 11 files of the release):

| File | What it is |
|---|---|
| `reference.json` | the reference values: MRTD, RTMR0 to RTMR2, the 15 RTMR3 events, the settings, the debug-bit rule and the quote hashes of both runs |
| `release.json` | ties the commit to the image and to the root hash of its disk, with the settings of the dummy run |
| `publication.json` | what made this publication: the image commit, the commit of the workflow, the tag, the run address and the SHA-256 of every tool used |
| `quote-run1.bin`, `quote-run2.bin` | the TDX quotes of the two dummy runs (8,000 bytes each) |
| `announce-run1.txt` | the announcement of the first run: its public keys, the quote and the RTMR3 log |
| `rtmr3-events.tsv` | the 15 RTMR3 events with their register values |
| `ccel.bin` | the firmware boot event log (262,144 bytes) |
| `boot-tables.md` | every RTMR1 and RTMR2 event with its complete digest |
| `settings.json` | the settings of the first dummy run |
| `SHA256SUMS` | the SHA-256 of the files above |

   `instance.json` and `image.json` are not published, because they name the project.
9. **The push and the check.** The branch was pushed only after the run, with the commit id of the workflow typed from its output (`a70f3ff2c`); the GitHub check: 5 of 5 files identical, and the audit passes.

### 7.3 Step P3.3: CI builds the image (dropped on 1 November 2026)

Building and sealing the image from a `git archive` inside CI needs the builders to be prepared from nothing (a persistent seed builder holds the downloads) and the two drivers to run without a login from our side. We had planned it as the last part of step P3. The mentor's review of 1 November 2026 **dropped it for now** (ADR-096): step P4 is what ties the image to the commit for a verifier who does not trust us (rebuild, then compare the file trees), and it works whoever built the image, while building in CI would only move the trust from our Cloud Shell to GitHub and the seed builder, for a lot of work. CI therefore proves the reference of an image that we built, and limitations row 216 says so.

## 8. Step P4 (done) and step P5 (not started)

### 8.1 Step P4: `verify-reference` and the file-tree comparison (done, 4 November 2026)

*In plain words: a stranger rebuilds the image from our commit, and a command compares every file of their disk with every file of ours, after checking that each disk is the one that the quote commits to; if one file, one mode or one owner differs, the command says which.* The full story, with the commands and the evidence, is in [tree-comparison.md](tree-comparison.md); the tables of the runs are in [run-comparison.md](run-comparison.md) sections 9.22 to 9.24. Sub-steps:

1. **The design** (ADR-096). The mentor's review of 1 November 2026 made the file-tree comparison a condition of the verifier's own dummy run, and said that it must pass on two builds of one commit and fail on a changed file, an added file and a changed mode, with any difference other than times failing and the list printed.
2. **P4.1, `ops/verify-reference.sh`** (commit `20267a68d`). Part A checks the published files without any cloud; parts B1 and B make a dummy run of the published image and of your own build and compare them with the reference, where RTMR2 may differ only in events that carry the root hash or partition ids. The real run passed 27 checks on the published set of `tc-img-rel-1`, and its negative control failed where it must. A weakness was found and fixed: the replay of the boot log used only the digests, so a forged command text next to a genuine digest passed; the texts are now authenticated by their hashes.
3. **P4.2, the file-tree comparison** (commit `fea794432`): a read-only helper VM, a manifest of each file tree (path, type, mode, owner, symbolic link target and SHA-256 of the contents; times are ignored) and a comparison. The first real result was identical for two disks of one image and 76 differences for two images of two commits.
4. **P4.2b and P4.3** (commit `829e90c2f`): the disks are opened through dm-verity with parameters read from the authenticated boot events, every block checked against the root hash first; extended attributes and capabilities are in the manifest; one command gives one verdict line. The real run passed (`explained=0 trees=identical image-run=exact`), and a root hash that was wrong by one character was refused.
5. **The tamper test** (commit `530237c2f`): on real disks, four tampered copies were each rejected for exactly one named difference (a changed file, an added file, a changed mode and an added capability), and the untouched copy gave back the original root hash, which shows that our sealing parameters are the real ones.
6. **Problem 1: the first strict comparison of two builds of one commit found 27 differences.** The builds were of a first version of the cleanup (a local commit that was never pushed). The causes were the operator accounts that the Google guest agent creates in another order on every builder (25 differences), the plain initramfs (1) and the Java trust store (1); [tree-comparison.md](tree-comparison.md) section 5 has the root causes and says why the earlier checks had not shown them.
7. **The build cleanup** (commit `c60995fa4`, ADR-097): an offline step of the sealing (gate 6b) removes the leftovers of the builder, the accounts of the agent and the plain initramfs, and rewrites the trust store with one fixed creation time; the live cleanup now removes the grub backups as root (a shell pattern had matched nothing) and purges snapd. There is no ignore list. The rehearsal has 52 checks, and 59 of 60 mutants are caught.
8. **The accepted run** (4 November 2026, commit `c60995fa4`): two builds sealed with different root hashes and **identical files** (`TREE-DIFF-IDENTICAL files=64612 dirs=8461 symlinks=5197 ignored=0 verity=checked`); a sealed fleet crawled and the whole verification passed, and the kit ended `CL2-PASS`.
9. **Problem 2: the helper VM of the comparison sometimes did not boot.** It failed to accept SSH twice, first within 24 attempts and then within 80. The console of the failed VM, which the next candidate printed, showed emergency mode: the sealed disks carry the file system label `UEFI` that the helper's own disk carries too, and a race decided which partition the helper mounted as `/boot/efi`. A longer wait and faster disks could not help. The first candidate for the fix (never committed or pushed) failed its second real test; the fix of commit `9b4a08fbb` (ADR-098) makes the VM without the disks and attaches them after it has booted. The real tests: the console and the cleanup with an injected fault, four boots in a row (188, 161, 162 and 198 seconds) and the real comparison in 16 minutes.
10. **The push and the checks.** Each commit was pushed only after its real run. The GitHub checks: `c60995fa4` 5 of 5 files identical and `9b4a08fbb` 7 of 7, and the audit passes. The kits that ran were committed afterwards (`15ab399fa`), after a check in Cloud Shell that every file is the file that ran (14 files); the kit, the resume script and the block that failed are not committed.

What the step shows and does not show: [tree-comparison.md](tree-comparison.md) section 7 and limitations rows 223 to 231.

### 8.2 Step P5: the verifier from the records to the quote (not started)

- **P5, the verifier from the records to the quote:** the signed records of the crawl (Milestone 5) are checked against the quote with Intel's signature chain, the record signatures, the debug bit (already checked by `ops/reference-compare.py`), and Google's endorsement of the firmware (MRTD). The mentor's review of 1 November 2026 adds the details (reuse the teammate's chain check, verify every record and folder signature of the export, every receipt against the signed receipts file, the Roughtime responses offline with pinned keys), four bug fixes, and an end-to-end run of about 1,000 URLs from the tip of `main` with eight tamper cases ([milestone-plan.md](milestone-plan.md) section 13).

## 9. Tests and rehearsals

| Rehearsal | Covers | Checks | Mutants caught |
|---|---|---|---|
| `p1-rehearse.sh` | the dummy-run script and its comparison | 30 | 8 |
| `p2a-rehearse.sh` | the node's publication of its boot event log | 15 | 6 |
| `p2b-rehearse.sh` | the boot event table and the release tools, with `--full` | 28 | 7 |
| `ops/ci/rehearse.sh` | the CI workflows' safety rules (now also for `ci-publish.yml`), `smoke.sh`, `setup-gcp.sh` | 72 | 33 |
| `ops/ci/rehearse-publish.sh` | the reference tool and the publication script | 44 | 27 |
| `ops/image/test/p4-rehearse.sh` | `verify-reference`: part A, the parts B and the verdict | 103 | not counted separately |
| `ops/image/test/p42-rehearse.sh` | the file-tree tools and `tree-diff.sh` with a fake `gcloud`, the real `veritysetup` where it exists | 117 | 38 (the helper-VM changes of `9b4a08fbb`) |
| `ops/image/test/tamper-rehearse.sh` | the tamper test and its helpers (the full experiment needs root) | 47 as root | 30 of 31 (the tamper tools of `530237c2f`; one is equivalent) and the 38 above |
| `ops/image/test/p4d-rehearse.sh` | the build cleanup: the groups, the guards, the real sealing on real file systems and a real `keytool` | 52 | 59 of 60 (one is equivalent) |

Every rehearsal ran offline first, then the code ran on the real system before it was pushed. Each laptop script replays its git commands against a stand-in repository, and each push is checked on GitHub by a verifier that compares every file with its expected SHA-256.

## 10. What went wrong

| # | What happened | Cause | What changed |
|---|---|---|---|
| 1 | The first image run stopped at its first stage | A rehearsal that had never run in Cloud Shell was in the kit's list | It is out of the list (limitations row 214, mistake 210) |
| 2 | A Cloud Shell reset during the image run | The block hid 60 minutes of output, so the session looked idle | A heartbeat line every minute (rule 99) |
| 3 | A cleanup would have deleted the sealed disk after an interruption | It did not look at the state of the run | It runs only when the disk sealing is not finished (rule 100) |
| 4 | The CI rehearsal failed with a relative folder | A check changed directory and lost the path | The folder is made absolute first |
| 5 | The CI setup failed at the first command | The service account name had 5 characters; the fake `gcloud` could not know Google's rule | A valid default, local validation of every name, and the fake enforces the rule (mistake 213) |
| 6 | The CI setup stopped halfway | The account lacked the pool rights; the setup did not check before changing | A preflight of the rights, also in a dry run (mistake 214, rule 103) |
| 7 | A scenario test hid a weakness | A marker file leaked from one scenario to the next | Every scenario starts clean (mistake 215, rule 104) |
| 8 | Found before the first CI run: `gcloud` might list no account | The sign-in action does not register one; Google's own companion action runs a login command | The workflow runs that command, and the smoke test accepts a working token (mistake 216, rule 105) |
| 9 | No run started for the first tag | The tag was pushed while GitHub Actions were still off | The tag was pushed again (mistake 217, rule 106) |
| 10 | The GitHub check failed on the first try | An old zip with the same name was still in the Cloud Shell home | The old zip was removed (mistake 218, rule 106) |
| 11 | A cleanup command deleted two commands that were on one line | I removed the line by a pattern without reading the whole line; ShellCheck cannot see a command that is missing | The file was repaired and read to its end; the rehearsal checks `SHA256SUMS` (mistake 219, rule 107) |
| 12 | Two test doubles were wrong | The fake `gcloud` cut a prefix from each argument and not from the joined text; one test built a root hash of the wrong length and so tested another check | Both were fixed (mistake 220, rule 108) |
| 13 | Three checks were missing or weak | The tests asserted the end result and not the step that stopped; nothing checked that the cleanup always runs; the mutants found them | The tests assert the stopping step; a safety rule for the cleanup (mistake 221, rule 108) |
| 14 | A retry path was described wrongly | I said that a second attempt uses the suffix of the prepare script, which cannot work once the local commit exists | Corrected: tag by hand, and the push script accepts any `publish-ref-*` tag (mistake 222, rule 109) |
| 15 | Two builds of one commit differed in 27 files | The earlier comparisons mixed the builder's leftovers with real differences, or compared an image with itself; the guest agent's accounts, the plain initramfs and the trust store had never been compared | A strict comparison of two builds, a cleanup step in the sealing, and no ignore list (mistake 224, rule 111) |
| 16 | A control test of the cleanup rehearsal passed for the wrong reason | A variable kept the mount point of an earlier image, so an empty folder was compared with a full tree | The variable is reset, and both trees must hold the kernel file (mistake 223, rule 110) |
| 17 | A resume of the fleet check failed three checks on the master | The checks that compare the master's log with the final quote were run again after the crawl, when the master had added more events | The first run's evidence is checked, and only the stages that remain are run (mistake 225, rule 112) |
| 18 | A second image creation failed with "already exists" | Google answered the first request with a 502 after it had made the image, and the driver retried | The stage is run again and skips the finished image; the retry is not fixed (mistake 226, rule 113; limitations row 229) |
| 19 | The kit stopped at once | The hash of the zip was typed where the commit id belongs | The commands say which value is meant (mistake 227, rule 114) |
| 20 | A laptop script did not parse | The commit subject had an apostrophe inside a single-quoted string | No apostrophes, and the scripts are parsed with the real PowerShell (mistake 228, rule 115) |
| 21 | A pasted command waited for a closing quote | A long one-line message was cut when pasted | Long text is given as a file (mistake 229, rule 116) |
| 22 | A test of the helper's wait passed on broken code | Its `cd` failed, so the helper never ran, and the test checked only that an error message was absent | A positive check was added (mistake 230, rule 110) |
| 23 | The helper VM did not accept SSH twice | It was in emergency mode, because the sealed disks carry the label `UEFI` of its own disk; I first took it for a slow boot | The disks are attached after the boot, and the console is printed when SSH never works (mistake 231, rule 117) |
| 24 | A long run was killed twice | The terminal or the session was lost while the run was attached to it | Long runs are started detached and can be started again (mistake 232, rule 118) |
| 25 | I named two labels where the evidence showed one | I wrote `UEFI` and `BOOT` for the sealed disks; the probe showed only `UEFI` on them | The cause is stated as exactly as the evidence shows (mistake 233, rule 119) |
| 26 | The kits that ran were not committed when step P4 closed | I never put a kit commit in the plan; the kit and the blocks were built beside the code commits and handed over as zips | They were committed afterwards, after a byte for byte check against the files that ran; the ones that failed are not committed (mistake 234, rule 120) |
| 27 | A corrected package was run with the old package | I gave the regenerated documents package the same names as the first one | Nothing was pushed; it was built again under new names (mistake 235, rule 121) |
| 28 | A destructive command was run when its condition did not hold | I put `git reset --hard` in the same block as a harmless command | Destructive commands are given alone, after their condition (mistake 236, rule 122) |

## 11. What was not done (limits)

The image is still built by our kit and not by CI, and P3.3 is dropped (row 216); the file trees of two builds of one commit are identical, but a second party has not rebuilt the image (row 188), the locked variant was not compared (row 223) and the cleanup is an offline step that changes the sealed image (row 225); the release is as private as the repository, so a stranger cannot yet fetch the published files (row 222); the reference comes from one machine type and one zone (row 221); the CI account holds more compute rights than it needs (row 218); anyone who can push a matching tag can use the CI identity (row 215); the 17 RTMR0 events are not tabulated; and whether the registers depend on the scratch disk is not tested (row 212). The limits of step P4 are rows 223 to 231 (the earlier tools that still trust the command text, the helper VM that is trusted, the two fixes not made, the kits that are in the repository but fixed to our project, and the label race for other helper VMs). The full list is in [limitations-and-trust.md](limitations-and-trust.md), rows 186, 188, 212 to 222 and 223 to 231.

## 12. Evidence and how to run it again

| What | Where |
|---|---|
| The dummy run, the reference and the release of the image `tc-img-rel-1` | the evidence folders of Cloud Shell, named by SHA-256 in [boot-events.md](boot-events.md) |
| The CI run | the tag `ci-smoke-0f235f446` and the run `ci-smoke #1` on GitHub; it printed `CI-SMOKE-OK commit=0f235f446076011b9bcfd15419848c58eb3bbeff` |
| The publication of the reference (P3.2) | the release `publish-ref-16bafb3b1` and its tag on GitHub; the run `ci-publish` on the commit `a70f3ff2c`; the files of the hand run in the Cloud Shell folder `p32-out` |
| The comparison of two builds of one commit (P4) | the commits of section 8.1; the evidence bundle `evidence-cl2-final.tar.gz` (SHA-256 `7bd3af51c83a37edc1a34b37a5b1b0138587ef13c47cfc4a343cf2394af1b8d5`), the 27 differences of the first strict comparison (SHA-256 `973972f9368d0f6bf791fbcb8ca7b422aeaa4b80000fb34ddcc14f9f4cd29512`), the console of the helper VM in emergency mode (SHA-256 `c27101a2687beb1a6810068d55f243f2b45d9a779ffb7369fcd4af2dd49b2a23`) and the other files in [tree-comparison.md](tree-comparison.md) section 9 |
| The commands | `bash ops/reference-run.sh IMAGE DIR`, `python3 ops/reference-compare.py DIR REFERENCE.json`, `python3 ops/ccel-table.py DIR --markdown FILE --full`, `python3 ops/make-release.py ...` ([cluster-rebuild.md](cluster-rebuild.md) section 8); for CI, section 9 of the same page and [ci-publishing.md](ci-publishing.md); for P4, `bash ops/verify-reference.sh COMMIT …`, `bash ops/tree-diff.sh probe IMAGE_A IMAGE_B` and `bash ops/image/test/tamper-test.sh IMAGE …` ([tree-comparison.md](tree-comparison.md) section 8) |

## 13. Decisions taken for this plan

ADR-090 (the plan, and the reference from a dummy run), ADR-091 (the dummy run), ADR-092 (the published boot event log), ADR-093 (the release), ADR-094 (the CI system) ADR-095 (P3 in three stages, tags as triggers, what is published), ADR-096 (the plan after the mentor's review of 1 November 2026: P3.3 dropped, how P4 compares), ADR-097 (the build cleanup) and ADR-098 (the helper VM gets its disks after the boot).

## 14. Lessons from this plan

Rules 99 to 122 of [guide-pitfalls-and-lessons.md](guide-pitfalls-and-lessons.md): keep printing during a long block; a cleanup respects the state of the run; add a gate only after it ran in the real environment; a fake can only enforce the rules its author knows; check names and rights before the first change, also in a dry run; start every scenario clean; read the vendor's own code for how a tool hands over credentials; and before pushing a tag that starts a workflow, check that Actions are on and that no old upload of the same name is lying around; read the whole line before an automatic edit; make every test reach the check that it names; and describe a retry path only after replaying it; for step P4: a test must assert a positive effect and not only the absence of an error; compare two builds of one commit with no ignore list; a check that is tied to a moment is run at that moment and a resume proves its evidence; look at the state before a retry; say which value is typed; parse a script with the real interpreter; give long text as a file; when a wait fails twice, look at the console of the thing that is waited for; start long runs detached; and state a cause as exactly as the evidence shows; and commit the kit that ran as soon as it has passed, give a corrected package new names, and give a destructive command alone.
