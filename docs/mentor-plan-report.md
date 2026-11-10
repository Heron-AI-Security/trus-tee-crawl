# The mentor's six-step plan (steps P1 to P6): report

**Status check, 30 October 2026.** Steps P1, P2 and P6 are done on the real cluster, and step P3 is split in three: P3.1 (CI signs in to Google Cloud) and P3.2 (CI publishes the reference) are done and verified, P3.3 (CI builds the image) is planned; P4 and P5 are not started. This is the report of the plan, in the form of the milestone reports: what we wanted, why, what we built step by step (the sub-steps are numbered), how it was tested, what went wrong, what is not done, and where the evidence is. The facts behind each step are in [run-comparison.md](run-comparison.md) section 9.19 and 9.20, [boot-events.md](boot-events.md), [ci-publishing.md](ci-publishing.md) and ADR-090 to ADR-095 in [decisions.md](decisions.md).

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
- **The CI system** is not named by the mentor. We chose GitHub Actions with Workload Identity Federation (ADR-094); the reasoning and the alternatives are in [ci-publishing.md](ci-publishing.md), and every setting can be changed.

## 4. Steps and status

| Step | What | Status | Commits |
|---|---|---|---|
| P1 | The dummy-run script and its comparison with a reference | Done on 29 October 2026 | `9a3e9a845` |
| P2 | `release.json`, the image labels, the commit tied to the image, the root hash tied to the quote | Done on 29 October 2026 | `16bafb3b1`, `a950bf882` |
| P3.1 | CI signs in to Google Cloud without a key, and its rights are checked | Done on 30 October 2026 | `0f235f446` |
| P3.2 | CI runs the dummy run of an image and publishes the reference and `release.json` | Done on 30 October 2026 | `a70f3ff2c` |
| P3.3 | CI builds the image from a `git archive` | Planned (open: limitations row 216) | none yet |
| P4 | `verify-reference COMMIT` | Planned | none yet |
| P5 | The verifier from the records to the quote | Planned | none yet |
| P6 | The table of the RTMR1 and RTMR2 events | Done on 29 October 2026 | `a950bf882`, `6572340da` |

The kit of the image run is `86f84c901` and the documents of P1, P2 and P6 are `c9fb51748`. Every code commit ran on the real system before it was pushed.

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

### 7.3 Step P3.3: CI builds the image (planned, open)

Building and sealing the image from a `git archive` inside CI needs the builders to be prepared from nothing (today a persistent seed builder holds the downloads) and the two drivers to run without a login from our side. Until then CI proves the reference of an image that we built, and the second party's rebuild (step P4) is what ties the build to the commit (limitations row 216).

## 8. Steps P4 and P5 (not started)

- **P4, `verify-reference COMMIT`:** a command that a stranger runs. It makes its own dummy run from the published image and compares it with the published reference, and it compares the file tree of the published image with the file tree of its own build of the same commit (this is the job that the bit-identical sealed disk was meant to do). The limitation will be stated: option 1 needs a GCP account with TDX.
- **P5, the verifier from the records to the quote:** the signed records of the crawl (Milestone 5) are checked against the quote with Intel's signature chain, the record signatures, the debug bit (already checked by `ops/reference-compare.py`), and Google's endorsement of the firmware (MRTD).

## 9. Tests and rehearsals

| Rehearsal | Covers | Checks | Mutants caught |
|---|---|---|---|
| `p1-rehearse.sh` | the dummy-run script and its comparison | 30 | 8 |
| `p2a-rehearse.sh` | the node's publication of its boot event log | 15 | 6 |
| `p2b-rehearse.sh` | the boot event table and the release tools, with `--full` | 28 | 7 |
| `ops/ci/rehearse.sh` | the CI workflows' safety rules (now also for `ci-publish.yml`), `smoke.sh`, `setup-gcp.sh` | 72 | 33 |
| `ops/ci/rehearse-publish.sh` | the reference tool and the publication script | 44 | 27 |

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

## 11. What was not done (limits)

The image is still built by our kit and not by CI (row 216); a second party has not rebuilt it (step P4, row 186); the release is as private as the repository, so a stranger cannot yet fetch the published files (row 222); the reference comes from one machine type and one zone (row 221); the CI account holds more compute rights than it needs (row 218); anyone who can push a matching tag can use the CI identity (row 215); the 17 RTMR0 events are not tabulated; and whether the registers depend on the scratch disk is not tested (row 212). The full list is in [limitations-and-trust.md](limitations-and-trust.md), rows 186 and 212 to 222.

## 12. Evidence and how to run it again

| What | Where |
|---|---|
| The dummy run, the reference and the release of the image `tc-img-rel-1` | the evidence folders of Cloud Shell, named by SHA-256 in [boot-events.md](boot-events.md) |
| The CI run | the tag `ci-smoke-0f235f446` and the run `ci-smoke #1` on GitHub; it printed `CI-SMOKE-OK commit=0f235f446076011b9bcfd15419848c58eb3bbeff` |
| The publication of the reference (P3.2) | the release `publish-ref-16bafb3b1` and its tag on GitHub; the run `ci-publish` on the commit `a70f3ff2c`; the files of the hand run in the Cloud Shell folder `p32-out` |
| The commands | `bash ops/reference-run.sh IMAGE DIR`, `python3 ops/reference-compare.py DIR REFERENCE.json`, `python3 ops/ccel-table.py DIR --markdown FILE --full`, `python3 ops/make-release.py ...` ([cluster-rebuild.md](cluster-rebuild.md) section 8); for CI, section 9 of the same page and [ci-publishing.md](ci-publishing.md) |

## 13. Decisions taken for this plan

ADR-090 (the plan, and the reference from a dummy run), ADR-091 (the dummy run), ADR-092 (the published boot event log), ADR-093 (the release), ADR-094 (the CI system) and ADR-095 (P3 in three stages, tags as triggers, what is published).

## 14. Lessons from this plan

Rules 99 to 109 of [guide-pitfalls-and-lessons.md](guide-pitfalls-and-lessons.md): keep printing during a long block; a cleanup respects the state of the run; add a gate only after it ran in the real environment; a fake can only enforce the rules its author knows; check names and rights before the first change, also in a dry run; start every scenario clean; read the vendor's own code for how a tool hands over credentials; and before pushing a tag that starts a workflow, check that Actions are on and that no old upload of the same name is lying around; read the whole line before an automatic edit; make every test reach the check that it names; and describe a retry path only after replaying it.
