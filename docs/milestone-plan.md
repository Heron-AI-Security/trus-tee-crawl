# Milestone plan: Milestones 0 to 6

Date: 7 October 2026; the statuses and the decisions are updated through 19 October 2026. **From 19 October 2026 the plan for the rest of Milestone 5 is the fixed-fleet plan in section 10 (steps F0 to F5)**, taken from the mentor's note of 18 October ([next-steps-fixed-fleet.md](next-steps-fixed-fleet.md)); the steps of this page that it replaces are kept as history, and each new step names the legacy steps that it replaces and why. This is the plan made on 6 October 2026: a pre-flight (Milestone 0) and six milestones. Its structure has not changed: steps were dropped, deferred or split into baby steps by the decisions of 7 and 10 October (section 4), and the statuses below are the current ones. This page records, in one place, what each milestone proves in plain words, its steps and their status, what depends on what, where teammate S's work meets ours, and where the mentor's decisions of 7 October land: as baby steps inside existing steps, not as new milestones or new steps. The reports of the milestones are linked; the decisions are in [decisions.md](decisions.md).

## 1. How to read it

- A milestone is called **Milestone N** and its steps **Step N.k**, with the names already committed. A baby step inside a step is written N.k.j (for example 4.6.1).
- The steps of Milestones 0 to 4 are those of their reports ([milestone-4-storage-integrity.md](milestone-4-storage-integrity.md) section 4 for Milestone 4). The steps of Milestones 5 and 6 are the items of the first plan.
- "Gate A" and "Stage B, C, D" are the handoff's names for groups of its 13 work-plan items ([handoff-attested-hadoop-cluster.md](handoff-attested-hadoop-cluster.md) section 9).
- Status is as of 19 October 2026. Runs 6 to 11 are **not covered by the measurement**; run 12 is the first that is, since the re-measure of 14 October (ADR-040); runs 14 and 15 ran in windows and are not covered (ADR-029, ADR-045).

## 2. The plan in one table

| Milestone | Name | What it proves, in plain words | Handoff items | Status | Report |
|---|---|---|---|---|---|
| 0 | Pre-flight: the clean baseline (run 3) | The starting point is solid: the crawl uses CCBot's real HTTP client and records real server addresses | (pre-flight) | Done, 5 October | [milestone-0](milestone-0-clean-baseline.md) |
| 1 | Measure the code that runs | We can show which program ran: fingerprints of the code are written into the hardware quote | Gate A, item 3 | Done, 5 to 6 October | [milestone-1](milestone-1-code-measurement.md) |
| 2 | Mesh for node-to-node traffic | The machines talk to each other only over an encrypted private network | Gate A, item 1 | Done, 6 October, with limits | [milestone-2](milestone-2-wireguard-mesh.md) |
| 3 | Pass-through wrapper (no crypto yet) | Every storage request goes through our layer, which changes nothing yet | Gate A, item 2 | Done, 6 October | [milestone-3](milestone-3-hdfs-wrapper.md) |
| 4 | Storage integrity (the first plan called it "sign on write, verify on read") | Storage cannot be changed unnoticed: files are fingerprinted when written and checked when read; the signing comes with step 5.1 | Stage B, items 4 to 6 | **Done on 14 October 2026:** steps 4.1 to 4.6 done (baby steps 4.6.4 to 4.6.7 on 13 October), 4.7 dropped on 10 October, 4.8 done (baby steps 4.8.1 to 4.8.3) | [milestone-4](milestone-4-storage-integrity.md) |
| 5 | Identity, ledger, lockdown | Each machine has a key that only an attested machine can use, the machine cannot be fiddled with, and (deferred on 10 October) an outside witness checks an append-only log | Stage C, items 7 to 9 | **In progress: steps 5.1.1 and 5.1.2 done on 15 October 2026, 5.1.3 and 5.2.1 on 16 October 2026 and 5.2.2 on 17 October 2026**; the rest of Milestone 5 is **redefined on 18 October 2026** as the fixed-fleet steps F0 to F5 (section 10), which replace step 5.3 and the rest of step 5.2; F0.1 and F0.2 are done on 19 October 2026, and F0.3a the same day, and F0.3b on 20 October 2026 | [milestone-5](milestone-5-signed-records.md) |
| 6 | Verifier and evidence | Anyone can check a crawl, our attacks on our own system are caught, and the cost is known | Stage D, items 10 to 13 | Not started | none yet |

Milestone 2 is done with limits: the third-machine test used a stand-in, the firewall rules are not saved across a reboot, and the attested admission of peers is step 5.2 (done on a test mesh on 17 October 2026, not yet for the production mesh).

## 3. The steps of Milestones 4, 5 and 6

*The rows for Milestones 5 and 6 below are the legacy plan, kept as history. The current plan for what remains is section 10; each of its steps names the legacy steps that it replaces.*

Milestone 4 (the committed names; the report has the dependencies and results):

| Step | Name | Status |
|---|---|---|
| 4.1 | Recon of what the crawl writes and reads | Done |
| 4.2 | Hash every written file and record its Merkle root (observe only) | Done |
| 4.3 | Keep a record next to each file and verify every read against it | Done |
| 4.4 | Run Hadoop's file-system contract tests against the wrapper | Done |
| 4.5 | Answer length, existence and listings from records, never from storage | Done. Baby steps: 4.5.1 metadata from records (done); 4.5.2 the NameNode's audit log turned on and compared with the wrapper's log (done) |
| 4.6 | Check the job file and configuration digests at the start of each task | Done (9 October; baby steps 4.6.4 to 4.6.7 on 13 October). Changed by the mentor on 7 October (ADR-027). Baby steps: 4.6.1 the wrapper's classes on Hadoop's classpath (done); 4.6.2 both lookups set as final, with a switch back to the plain configuration (done); 4.6.3 the NodeManager's read of the job file checked against its record, and a swapped file refused (done); 4.6.4 `append`, `concat` and `truncate` refused (done); 4.6.5 a file with no record cannot be opened (done); 4.6.6 the wrapper's settings count only when the site configuration set them (done); 4.6.7 the doors to the plain file system closed (done) |
| 4.7 | Task records and job manifests; speculative execution off | **Dropped** (10 October, ADR-034): no task records, job manifests or per-file history; what they were for, tying outputs to attested code, is done by the signed per-file records of step 5.1. The recon ([milestone-4](milestone-4-storage-integrity.md) section 21) stays as history |
| 4.8 | Milestone report; re-measure after a reboot (ADR-020) | **Done on 14 October 2026.** Baby steps: 4.8.1 the job built with the teammate's patch, the collection policy and the first integration crawl (run 11); 4.8.2 the reboot and the re-measure, with the patched job and the policy as measured parts (ADR-040); 4.8.3 the first timing pair, runs 12 and 13 (ADR-041). Scripts in `93745032c`, `169c3887b`, `77fd89180` and `09ebe8565`; report: [milestone-4](milestone-4-storage-integrity.md) section 23 |

Milestone 5 and Milestone 6 (the items of the first plan; the report of Milestone 5 lists the details of its steps, and Milestone 6 has no report yet):

| Step | Name | Status |
|---|---|---|
| 5.1 | Per-VM signing key bound to the quote (a test key behind a key-provider interface first) | **Done on 16 October 2026.** Baby steps: 5.1.1 records are signed with a test key, clearly labelled and never used in evidence (**done on 15 October 2026**: [milestone-5](milestone-5-signed-records.md) section 3, ADR-044); 5.1.2 folder identity files bind each file to its folder (ADR-035) (**done on 15 October 2026**: [milestone-5](milestone-5-signed-records.md) section 4, ADR-046); 5.1.3 the real key: generated per VM at boot, held by a small signing service, bound to the quote through REPORTDATA (**done on 16 October 2026**: [milestone-5](milestone-5-signed-records.md) section 6, ADR-047 to ADR-049) **From 18 October 2026 the designs of 5.1.1 to 5.1.3 are replaced** (formats and settings by F3, the key by F1 and F2; section 10.4); what they showed stays as history. |
| 5.2 | Mesh admission only after verifying a peer's quote | **In progress.** Baby step 5.2.1, readers accept only keys of attested machines: **done on 16 October 2026**, offline and live ([milestone-5](milestone-5-signed-records.md) section 7, ADR-050 to ADR-052, and section 8 for the live window); baby step 5.2.2, mesh admission through the doorman: **done on 17 October 2026 on the test mesh `wg1`** ([milestone-5](milestone-5-signed-records.md) section 9, ADR-053 to ADR-055); open: the doorman as the source of the key list's bundles, and its adoption for the production mesh `wg0` (the mentor's decision) **The rest of step 5.2 and the designs of 5.2.1 and 5.2.2 are replaced from 18 October 2026 by F1 and F2** (section 10.4). |
| 5.3 | Locked image (no SSH or shell), fixed driver with typed parameters, TLS checking on. Baby steps: 5.3.1 the locked image; 5.3.2 the fixed driver; 5.3.3 TLS checking on, with per-fetch TLS evidence (teammate S's patch) | **Replaced from 18 October 2026:** 5.3.1 by F0.1 to F0.5, 5.3.2 by F0.3; 5.3.3 is the teammate's (section 10.4) |
| 5.4 | Merkle log with signed checkpoints and an off-cloud witness (a witness interface and a local stand-in first) | Deferred (10 October, ADR-034) |
| 5.5 | "Start" records logged before work begins | Dropped (10 October, ADR-034) |
| 6.1 | The standalone verifier of the final files (signature, key, quote, measurements, hash), able to check a single record from its byte range (ADR-037), then a second independent one that must agree (the second one is not changed by the decisions of 10 October) | Not started **From 18 October 2026 this is the teammate's consumer-side verifier**; we send her the formats after F3.2 (section 10.4). |
| 6.2 | The tamper harness with a clean control. Baby steps: 6.2.1 the tamper demonstrations (a byte flipped; a file and its record replaced; a signed file moved to another folder, or two files of the same name swapped; a whole folder copied elsewhere; an unsigned file added; a record signed with a key that is not attested); 6.2.2 the two documented limits shown honestly (a file deleted together with its record, and an older signed copy put back, both expected to go undetected); 6.2.3 a review of what is readable or changeable outside the TEE (which keys exist, where they live, what crosses the VM boundary unprotected) and a red-team harness, both named by the mentor | Not started **Replaced by F4 for 6.2.1 and 6.2.2** (section 10.4). |
| 6.3 | Performance with and without the custody layer, and TDX against non-TDX. Baby steps: 6.3.1 paired runs in the same hour, with wall time and bytes fetched for every wrapped and unwrapped pair, against a vanilla CCBot control; 6.3.2 the same measured piece by piece (the WireGuard mesh, the wrapped HDFS, the TLS capture, TDX), because the experiment is about where the cost comes from (ADR-037) | Not started **From 18 October 2026 this is the teammate's performance study.** |
| 6.4 | Scale up as far as budget allows, and report the scale honestly | Not started **Asked of the mentor on 19 October 2026** (is scale-up still wanted). |

The handoff items map as follows: step 5.1 and 5.2 are item 7, step 5.3 is item 8, steps 5.4 and 5.5 are item 9, and steps 6.1 to 6.4 are items 10 to 13.

## 4. What the mentor decided on 7 October, and where it lands

The decisions are recorded in ADR-026 to ADR-029 of [decisions.md](decisions.md), with the mentor's words.

| The mentor said | Where it lands |
|---|---|
| Gate A is accepted | Milestones 1 to 3 stand |
| Run the unwrapped control in the same hour from Stage B on; record wall time and bytes fetched for every wrapped and unwrapped pair (performance matters most, per Amir) | A rule for every crawl from now on (ADR-028). The first pair is the crawl after the re-measurement (step 4.8); the results table is step 6.3 |
| Turn on the NameNode audit log in Stage B | Baby step 4.5.2 (done 8 October) |
| Defer the re-measurement, as long as nothing unmeasured is described as measured | Step 4.8 and ADR-029 |
| A task hashing its own job file is not a security check: move the wrapper onto Hadoop's classpath and set both lookups final | Step 4.6, baby steps 4.6.1 to 4.6.3 (ADR-027; done 9 October) |
| Per-fetch TLS evidence is teammate S's patch; coordinate on building the job with it | Baby step 5.3.3 |
| Apply the handoff corrections now, in one commit with a corrections list at the top | Done: the corrected handoff |
| Defaults for the rest: HDFS; a test key behind an interface; hash everything with a path filter; a witness interface with a local stand-in; contract tests first | Steps 5.1, 5.4 and 4.4 (done) |
| Nothing new until the 16 October list; plan for mid-November to 20 November, 5 pages plus 2 | Section 7 |

### What the mentor decided on 10 October, and where it lands

The decisions are recorded in ADR-034 to ADR-039 of [decisions.md](decisions.md); the mentor's note is [next-steps-storage-signing.md](next-steps-storage-signing.md). This table follows the note's own order and also lists what it leaves as it was.

| The mentor said | Where it lands |
|---|---|
| Storage integrity rests on one mechanism, sign on write and verify on read, with the VM's signing key | Step 5.1 (baby steps 5.1.1 to 5.1.3): the per-file signed records replace the first plan's signed task record (ADR-034) |
| No task records, job manifests, per-file history or folder tracking; step 4.7 is dropped; the wrapper stays a plain file-system layer | Step 4.7 dropped; its recon stays as history |
| In scope: tampering, forgery, and a validly signed file in another folder or under another name | Steps 5.1.1 and 5.1.2; the tamper demonstrations in 6.2.1 |
| Deletion and rollback are noted and out of scope; retries, re-runs and intermediate steps are not visible | Limitations rows 68 to 71; shown honestly in 6.2.2 |
| Folder identity files | Baby step 5.1.2 (ADR-035) |
| Close the fail-open cases (A1 to A4) | Baby steps 4.6.4 to 4.6.7 (done, 13 October) |
| The real key bound to the quote; readers accept only attested keys | Baby steps 5.1.3 and 5.2.1 |
| The Merkle log, the witness and the checkpoints are deferred; "start" records are dropped | Step 5.4 deferred; step 5.5 dropped |
| The verifier checks the final files (signature, key, quote, measurements, hash), not the chain back to the seed list | Step 6.1; the second independent verifier is not mentioned and stays |
| Evidence: tamper demonstrations, the two limits shown honestly, performance pairs, a review of what is exposed | Baby steps 6.2.1 to 6.2.3 and 6.3.1 |
| Unchanged: the WireGuard mesh, the measured image and RTMR3, plain TDX VMs with our own image, the fixed driver, locking down the image | Milestones 1 and 2; step 5.3 |
| teammate S's patch: build the job with it and re-measure | Steps 4.8 and 5.3.3 |
| Apply the handoff corrections with section 6 of the note, in one commit with a corrections list at the top | Done: the corrected handoff (C22 to C28 and D9) |
| Not mentioned, so as before: step 6.4 (scale), the same-hour pairs and TDX against non-TDX (6.3), the results of steps 4.1 to 4.6, and the decisions of 7 October (except the witness stand-in, which waits with step 5.4) | Unchanged |

## 5. What each milestone needs before it can start

| Milestone | Needs | Why |
|---|---|---|
| 5 | 1, 2, 4 | The key is bound to a quote (Milestone 1), machines are admitted through the mesh (Milestone 2), and the signed records are those of the wrapper of Milestone 4 (the log is deferred) |
| 6 | 4, 5 | The verifier checks the records, the log and the TLS evidence; the performance pairs need the wrapper (Milestone 3) and the final job |

## 6. Teammate S's work and ours

Teammate S writes the per-fetch TLS evidence: when the crawler fetches a page, her code records who the server really was (certificate chain, TLS version, cipher, server address). Ours is the layer that protects what is written and ties it to tasks and jobs. In the claim "this record was fetched over TLS from host X, by this exact build, inside a genuine VM, as part of job J, and nothing changed afterwards", hers is the "over TLS from host X" part and ours is the rest.

She can start now: the code she needs is on the branch `feat/tee-hadoop-cluster` and nothing on our side blocks her. Where the two workstreams depend on each other:

| Step | Depends on her work? | What exactly |
|---|---|---|
| 4.5, 4.6 | No | |
| 4.7 | Dropped | Step 4.7 is dropped (ADR-034). Her attempt-scoped outputs are covered by the per-file signed records like every other file (her message of 10 October, ADR-036) |
| 4.8 (re-measure) | Yes | The measured job must contain her code and files |
| 5.1 | Small agreement | The signing key stays out of the fetcher JVM; her evidence is bound by the signed commitment to the WARC and to her output files (ADR-036). Her output folders are also the real test of the folder identity files (5.1.2): a task attempt's output is moved from its attempt folder into the final folder when the task commits, and Hadoop merges into folders that already exist, so we need the layout of her output folders and a run of her integration test against the new wrapper |
| 5.2, 5.4, 5.5 | No | Her evidence is more records |
| 5.3 | Yes | TLS checking on and her evidence belong together; her extra files must be in the locked image and her settings must fit the fixed driver |
| 6.1 | Yes | The verifier checks her evidence for each record, so it needs her format, versioned |
| 6.2 | Yes | Attacks on the evidence: forged evidence, an impersonated site, evidence removed |
| 6.3, 6.4 | Yes | The final numbers include the cost of capturing the evidence |

The HTTP client is okhttp (`protocol-okhttp`), as the handoff requires; a change to plain `http` would need the mentor's agreement.

## 7. Timeline

- The workshop paper is planned for mid-November to 20 November, 5 pages plus 2 (the mentor, 7 October). Nothing new for the paper is started before the 16 October list.
- The plan has no dates of its own; the handoff attaches none on purpose. After 10 October the order is baby steps 4.6.4 to 4.6.7 (done on 13 October), then step 5.1 (the signed records, the folder identity, the real key) and step 5.2, with step 4.8 (the re-measure) done on 14 October, then Milestone 6 (section 8 maps the mentor's labels to the steps). Any dates are proposals until the mentor confirms them.
- The handoff's rule applies: security work is not cut to meet a date. What is not done in time is written down as a limitation, and the paper claims only what exists:

| When it is done | What can honestly be claimed |
|---|---|
| Milestone 4 | Files in storage cannot be changed unnoticed (the records are not yet signed) |
| Milestone 5 | The records are signed inside attested machines, readers accept only keys whose quote verifies, and nodes join the mesh only through the doorman (the log and the witness are deferred, ADR-034) |
| Milestone 6 | An outsider can check a crawl, each tested attack is caught or recorded as a miss, and the cost and the scale are reported |

## 8. The steps after 10 October (A1 to C4)

The mentor's decisions of 10 October (ADR-034 to ADR-039) drop step 4.7 and change what the signing covers. The labels A1 to C4 are the ones of [next-steps-storage-signing.md](next-steps-storage-signing.md), which has the full pass conditions; they are kept here only as a cross-reference. Each item is a baby step of a committed step, so that the plan has one structure: the signing is Milestone 5, as the plan always had it ("the signing comes with step 5.1"), and Milestone 4 keeps only the fail-open fixes (done) and step 4.8. The working order is A, then B1 to B3, then B4, then C.

| Step | What | Pass condition in one line | Lands in |
|---|---|---|---|
| A1 | `append`, `concat` and `truncate` throw an error | a full crawl completes, and a direct call fails | Step 4.6, baby step 4.6.4 (done) |
| A2 | A file with no record fails the read; the driver signs the seed file | reading an unrecorded file fails, the crawl still runs | Step 4.6, baby step 4.6.5 (done) |
| A3 | The wrapper's own switches cannot be changed by a job (final in the site configuration, or removed) | a job submitted with `-D attested.verify.reads=false` still has its reads verified | Step 4.6, baby step 4.6.6 (done) |
| A4 | Opening by path handle and the raw inner file system are refused | a direct call to each fails | Step 4.6, baby step 4.6.7 (done) |
| B1 | Records are signed (a test key, clearly labelled, never used in evidence) | a file rewritten with its record, without the key, fails the read | Step 5.1, baby step 5.1.1 (**done on 15 October 2026**) |
| B2 | Folder identity files, and records bound to (folder ID, file name) | a signed file or a whole folder copied elsewhere fails the read; a folder rename re-signs no file record; a normal crawl still passes | Step 5.1, baby step 5.1.2 (**done on 15 October 2026**) |
| B3 | The real key: per VM at boot, held by a small signing service, bound to the quote through REPORTDATA | a record's key resolves to a quote that verifies off-cloud, whose RTMR3 replay matches | Step 5.1, baby step 5.1.3 (**done on 16 October 2026** for the key and the binding of the quote's REPORTDATA; the quote's chain was verified on the laptop; the measurements and the RTMR3 replay for these quotes stay for step 5.2.1) **Replaced from 18 October 2026 by F1 and F2.** |
| B4 | Readers accept only keys of attested VMs (the mesh admission step is the source of the list) | a record signed by a key from outside the cluster fails the read | Step 5.2, baby step 5.2.1 (**done on 16 October 2026**: a key is trusted only if its quote verifies and its measurements are allowed; a rogue key with a fake quote was refused live on the real VMs, and a record signed by it fails the read; the worker's own reads and a MapReduce job with the admission on are not yet exercised) **Replaced from 18 October 2026 by F2 and the consumer's verifier.** |
| C1 | Tamper demonstrations: flip a byte; replace a file and its record; move a signed file or swap same-named files between folders; copy a folder elsewhere; add an unsigned file; sign with a non-attested key | all refused | Step 6.2, baby step 6.2.1 (open) **Replaced by F4.** |
| C2 | The two documented limits shown honestly: delete a file with its record; put back an older signed copy | both go undetected, and are recorded as such | Step 6.2, baby step 6.2.2 (open) **Replaced by F4.** |
| C3 | Wall time and bytes fetched for every wrapped and unwrapped pair in the same hour; then TDX against non-TDX VMs of the same shape | (the number readers look for) | Step 6.3, baby steps 6.3.1 and 6.3.2 (open) **From 18 October 2026 the teammate's performance study.** |
| C4 | Review of what is readable or changeable outside the TEE: which keys exist, where they live, what crosses the VM boundary unprotected | (the most common way such systems fail) | Step 6.2, baby step 6.2.3 (open) **Partly F0 (the lock) and the limits of the paper.** |

The note groups C1 to C4 as evidence, which is Milestone 6; the review in C4 also informs step 5.3 (the locked image). Step 5.3 (locked image, fixed driver, TLS checking on with the teammate's patch) is otherwise unchanged. Our own fail-open findings were in the limitations (row 72, closed on 13 October 2026).

**Status on 13 October 2026: A1 to A4 are done (baby steps 4.6.4 to 4.6.7 of step 4.6)** ([milestone-4](milestone-4-storage-integrity.md) section 22: run 10 and two demos with the new wrapper); the signing starts with step 5.1. **Status on 14 October 2026: step 4.8 is done and Milestone 4 is closed** ([milestone-4](milestone-4-storage-integrity.md) section 23).

**Status on 15 October 2026: step 5.1.1 is done** ([milestone-5](milestone-5-signed-records.md) section 3): records are signed with a labelled test key, and a file rewritten together with its record, without the key, fails the read on the real HDFS; the next step is 5.1.2 (folder identity files).

**Status later on 15 October 2026: step 5.1.2 is done** ([milestone-5](milestone-5-signed-records.md) section 4): every file is bound to its folder by signed identity files and `ATTEST03` records, and ten attacks that move, copy or relabel signed files fail the read on the real HDFS; the next steps are 5.1.3 (the real key) and the combined crawl with signing and folder binding on.

**Status at the end of 15 October 2026: the combined crawl is done** ([milestone-5](milestone-5-signed-records.md) section 5): a real crawl with signing and folder binding on and required wrote 60 files in 55 folders, all of which verify offline with the public key only, and all 265 verified reads in the audit logs had a signature and a folder binding; the next step is 5.1.3 (the real key).

**Status on 16 October 2026: step 5.1.3 is done** ([milestone-5](milestone-5-signed-records.md) section 6): each VM makes its own signing key in the memory of a signing service, a hardware quote vouches for exactly that key (verified on the VMs and, for the Intel signature chain, on the laptop), and a crawl with the real keys on two machines verifies offline against a key list, with a negative control; the next step is 5.2.1 (readers accept only keys of attested machines, through the hook of the key list).

**Status later on 16 October 2026: step 5.2.1 is done offline** ([milestone-5](milestone-5-signed-records.md) section 7): the key list admits a key only if its hardware quote verifies offline in Java (the chain to Intel's root, the signatures) and its MRTD and boot registers are allowed by an editable reference file; both real keys of run 15 are admitted, the whole run-15 output verifies with only admitted keys, and every decision flips with one edit; the live window on the real VMs is the next step.

**Status at the end of 16 October 2026: step 5.2.1 is done offline and live** ([milestone-5](milestone-5-signed-records.md) section 8): on the two real VMs, each fresh key was admitted by its live quote before the daemons restarted, a real file was written and read back with the admission on, a rogue key with a fake quote was refused with its reason, and each decision flipped with one edit on a live quote; the next step is the rest of step 5.2 (the admission step as the source of the accepted keys).

**Status on 17 October 2026: step 5.2.2 is done on the test mesh** ([milestone-5](milestone-5-signed-records.md) section 9): a node is admitted to the mesh only if a quote made just now binds its WireGuard public key and requested address to the machine, the quote is genuine, its measurements are in the reference file, and the host and address are in a policy table; on the two real nodes both were admitted, a rogue node with a fake quote was refused, and the test mesh `wg1` came up with exactly the admitted peers on their own attested keys while `wg0` and the measured stack stayed untouched; the next steps are the doorman as the source of the key list's bundles and its adoption for the production mesh, which is the mentor's decision.

**Status on 19 October 2026: the plan is redefined as the fixed fleet** ([next-steps-fixed-fleet.md](next-steps-fixed-fleet.md), section 10 below): B3 and B4 are replaced by F1 and F2, C1 and C2 by F4, C3 by the teammate's performance study and C4 partly by F0; A1 to A4, B1 and B2 stand as done.

**Status on 19 October 2026 (later): steps F0.1 and F0.2 are done.** On a disposable TDX VM, a plain reboot lands in kernel 6.17 as the saved default, a boot unit measures the fixed stack into RTMR3 by itself before the stand-in daemons, the log replays to the register and a quote is bound to it; the register is identical across plain reboots, changes in exactly one event when one measured file is changed, and returns when the change is undone ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 10, ADR-061). The next step is F0.3, the baked image.

**Status on 19 October 2026 (end of day): step F0.3a is done.** A VM made from the image starts JDK 11 and Hadoop 3.4.3 by itself, from root-owned folders, as a user that cannot log in, after a measurement of 10 items that it requires; the measurement is the same on every boot, changes in exactly one event when one measured file changes, and is the same on two VMs of one image, together with MRTD and RTMR0 to RTMR2. The first image failed its second boot because one systemd setting was written in the wrong section; the rebuilt image passed ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 12, ADR-062). The code of the project also moved on this day to the private repository `Heron-AI-Security/nutch-private` (ADR-063). The next step is F0.3b, the wrapper jar and the job.

**Status on 20 October 2026: step F0.3b is done.** The image holds the crawler's job and the wrapper jar, built once on the builder from a pinned source archive and the teammate's pinned patch, installed read-only in `/opt/tc/nutch` and Hadoop's library folder and measured as the event `nutch-deploy` (11 events); the build tools are removed. Hadoop's Pi example and a Nutch inject job run on YARN at every boot, a change of one launcher script moves only that event, and the 43 wrapper classes are byte-identical to the jar of the earlier build on the master ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 13, ADR-064). The configuration stays plain until keys exist. The next step is F0.3c, the crawl that runs by itself.

## 9. Rules that apply to every milestone

- A commit contains only files identical to the ones that ran on the cluster; documents and programs are committed separately (ADR-024, ADR-025).
- Code that depends on real libraries is rehearsed with them before it is sent (ADR-025).
- Nothing that ran outside the measured set is called measured (ADR-029).
- Every wrapped crawl has an unwrapped control in the same hour, and wall time and bytes fetched are recorded (ADR-028).
- A check is only trusted after it has caught a known fault ([guide-pitfalls-and-lessons.md](guide-pitfalls-and-lessons.md), rule 20).


## 10. The fixed-fleet plan (current, from 19 October 2026)

### 10.1 What it is, and where it comes from

The mentor's note of 18 October 2026 ([next-steps-fixed-fleet.md](next-steps-fixed-fleet.md), kept verbatim; SHA-256 `a7f812624ca375ac…`) replaces the design of steps 5.1.3 to 5.3 with a **fixed fleet** of TDX VMs: no VM joins during a run; each VM makes its signing key and WireGuard key at boot, in memory, and gets one quote that binds both public keys; a setup step writes one read-only list, `fleet.tsv`, and every node measures its hash into RTMR3; inside the cluster a signature counts only if its key is in that list; **nothing in the cluster checks quotes**, which is done once, at the end, in the consumer's verifier (the teammate's piece). The aim is trusted Java of about 950 to 1,150 lines, down from 5,783. The design needs a locked image, because anyone who is root in a node could read keys and rewrite the list, so the locked image is the first step.

### 10.2 The numbering rule

The mentor's steps 0 to 5 are written **F0 to F5** here (F for fixed fleet) so that they do not clash with Milestones 0 to 6, and their sub-steps are F0.1 and so on, as in her note. A legacy step keeps its number (for example 5.2.1) and is never reused: the legacy tables above stay as history, and every new step below says **which legacy steps it replaces and why**. The same rule applies to every document that mentions a step (ADR-059). To change the prefix, edit this section and `ops/attested/docs-status-expected.tsv`; the numbers are the mentor's.

### 10.3 The steps

**F0.1 and F0.2 are done (19 October 2026, on a disposable TDX VM; [milestone-5-signed-records.md](milestone-5-signed-records.md) section 10), and F0.3a, the first part of F0.3, is done (19 October 2026; report section 12), and F0.3b, the second part, is done (20 October 2026; report section 13); F0.3c is next**, and F0.3c is the only part that is not started. F0.3 is split into four parts so that each one passes on its own real test. The recon of step F0, the inventory of the nodes that is the "before" picture for F0.4 and F0.5, is recorded in report section 11. The pass conditions are the mentor's, shortened (the note has the full text).

| Step | What | Pass condition | Replaces (legacy) | Why it replaces it | Status |
|---|---|---|---|---|---|
| F0.1 | The default kernel (6.17) supports RTMR3 extension, so a plain reboot keeps it | After a plain reboot RTMR3 is non-zero and matches a replay of the event log | The one-time boot into 6.17 and the manual measurement of Milestone 1 (`ops/worker-kernel-prep.sh`, `attest/measure/`; ADR-003, ADR-010) | A normal boot goes back to kernel 6.8, and RTMR3 is extended by a script that an operator runs; the image must do it by itself | **Done on 19 October 2026** (report section 10) |
| F0.2 | Measurement runs as a systemd unit before any Hadoop daemon, keeps the "RTMR3 is zero at start" check, and also measures the boot script, the units, `openssl` and `wg` from a list file (our default, ADR-060) | The unit's log shows that it finished before the NameNode and DataNode started | The manual `measure-all.sh` runs, and the re-measure after a reboot (step 4.8.2, ADR-040) | Measurement becomes part of the boot, with no operator command | **Done on 19 October 2026** (report section 10) |
| F0.3a | JDK 11 and Hadoop 3.4.3 (checksum verified) in root-owned system folders, a service user `hadoop` that cannot log in, the plain configuration for a single node on the loopback address, systemd units for the four daemons that require and follow the measurement, and the longer measured list (10 events) | A VM from the image starts the four daemons by itself after the measurement, as `hadoop`; HDFS answers; RTMR3 covers the new events | The rebuild stages `base` and `hadoop` (a person's home, daemons started by hand) and the by-hand measurement of the JDK and Hadoop of Milestone 1 | The software must not sit in a person's home or depend on a person's commands | **Done on 19 October 2026** (report section 12) |
| F0.3b | The wrapper jar and the job, built once from pinned inputs (a source archive and the teammate's patch, both pinned by SHA-256) with the libraries at pinned commits, installed read-only, and measured as `nutch-deploy`; the build tools are removed; the configuration stays plain until keys exist (F1 and F2) | The wrapper loads and initializes (its self-test), Hadoop's Pi example runs on YARN, and a Nutch inject job from the baked job writes a crawl database to HDFS | The rebuild stages `build` and `wrapper`, and the per-window installs of jars and the job (ADR-045) | The code that runs is the code that is measured, and it is built once, not on each node | **Done on 20 October 2026** (report section 13) |
| F0.3c | The crawl driver, its parameters file and the seeds, started by a unit after the daemons | Starting a VM from the image runs the crawl with no operator command | Step 5.3.2 (the fixed driver with typed parameters), and the hand-run `run-crawl-attested.sh` | The parameters and the startup script are baked, so they are fixed and measured | Planned |
| F0.3d | Two VMs made from one image | Their RTMR0 to RTMR2 are compared and their RTMR3 is equal | nothing (new) | It answers whether a verifier needs one reference per image or one per VM (limitations row 138) | **Done on 19 October 2026** (report section 12.5, on the F0.3a image) |
| F0.4 | Remove login: no sshd, no OS Login, no guest agent that adds SSH keys, serial console login off | `gcloud compute ssh` and serial console login both fail | Step 5.3.1 (the locked image, no SSH or shell) | With SSH and `sudo` an operator can read keys in RAM and rewrite `fleet.tsv` (note, section 2) | Planned |
| F0.5 | Close the doors around the wrapper: `dfs.webhdfs.enabled=false` (final), and the NameNode, DataNode, ResourceManager and NodeManager ports bound to `wg0` only | A WebHDFS read and a YARN job submission from outside the mesh both fail | Milestone 2's host firewall as the only closure of the Hadoop ports | The firewall rules are not saved across a reboot (section 2 of this page); binding to `wg0` is part of the image | Planned |
| F0.6 | A separate debug image with login enabled, under a different name, never used for evidence | The two images have different measurements, and the evidence run names the locked one | Nothing (new); it replaces debugging on the measured nodes through SSH and windows (ADR-045) | Debugging needs a login and the evidence image must not have one | Planned |
| F1.1 | No private key exists on disk or in any `.conf` file (keys live in `/run`, in memory) | A search of the disk image after a run finds none | Step 5.1.3's signing service (the key in a service's memory) and Milestone 2's key files in `/etc/wireguard` | Both keys are made at boot by `tc-boot.sh` and never written to disk | Planned |
| F1.2 | Every node's RTMR3 event log holds the same `fleet` hash, equal to the SHA-384 of the archived `fleet.tsv` | The hashes are equal | Step 5.1.3's key list of bundles and its sync script `m513-keylist-sync.sh`, and step 5.2.1's admission of keys | A fixed list that every node measures replaces a folder that is rescanned; the consumer checks it at the end | Planned |
| F1.3 | A node booted with a `fleet.tsv` that omits its own key stops before Hadoop starts | The boot stops | Step 5.2.1's refusal of an unlisted key at read time | The check happens once, at boot | Planned |
| F1.4 | The full mesh comes up with no SSH used at any point, with the `wg0` peers taken from `fleet.tsv` | The mesh is up and no SSH was used | Step 5.2.2's doorman, `mesh-admit.sh` and the `wg1` test mesh, and the Milestone 2 mesh scripts | No node joins during a run, so no admission decision is needed at run time | Planned |
| F2 | `FleetKeys` (about 70 to 90 lines): loads the key and `fleet.tsv` once per JVM, signs in-process, has no quote handling; the key code leaves the cluster | A record signed by a valid P-256 key that is not in `fleet.tsv` fails the read, also in a fresh YARN container | Step 5.1.3 (`KeyService`, `KeyList`, `KeyBundle`, the socket half of `ServiceKeys`), step 5.2.1 (`QuoteAdmission`, `AdmissionReference`, `QuoteVerifier`, `BundleCheck`) and step 5.2.2 (`NodeBundle`, `MeshPolicy`, `MeshAdmission`) | A list that nothing in the cluster can change makes in-cluster quote checks add nothing; quote checking moves to the consumer's verifier (the teammate's) | Planned |
| F3.1 | Remove all switches and modes: the 30 `attested.*` settings, the allow, warn and fail modes, and `AttestedSettings` | `-D` with any old setting has no effect; a file with no record fails both reads and status calls | Step 4.6.6 (settings count only from the site configuration, ADR-039), ADR-038's two settings, ADR-023, and the off-by-default switches of 5.1.1 to 5.2.1 | Behaviour is fixed and secure, with less trusted code | Planned |
| F3.2 | One record format for files and one for folder identities, in one `Records.java` (about 180 to 230 lines) | The contract tests pass; a truncated or oversized record fails the read cleanly | The formats ATTEST01 (step 4.3), ATTEST02 (5.1.1) and ATTEST03 (5.1.2) and their five codec classes | One format is easier to review and to give to the verifier | Planned |
| F3.3 | A flat hash list replaces the Merkle tree: sign SHA-256 over the concatenated chunk hashes | A one-bit flip in any chunk fails at that chunk | Steps 4.2 and 4.3 (the Merkle root per file, `MerkleHasher`, `merkle_root.py`) | No Merkle proof is used anywhere | Planned |
| F3.4 | The root `/` gets a fixed all-zero ID that is never stored | The nested-rename case of the milestone 5 report passes; files directly under `/` are bound | Step 5.1.2's "top folder bound to its full path" identity kind (limitations rows 98 and 104) | One rule for the root removes a special case and a known limit | Planned |
| F3.5 | `copyToLocalFile` goes through the verifying open | Copying a tampered file to local disk fails | The documented bypass of step 4.3 (limitations row 46, `verify=bypassed`) | A hole in the read path | Planned |
| F3.6 | Drop the observe-only extras: the metadata and listing length checks, the logging-only overrides, `AttestedAudit` and `AttestedRecords` | The contract tests still pass | Step 4.5 (metadata from records, the NameNode audit comparison) | They observe and enforce nothing | Planned |
| F3.7 | Optional: `hasPathCapability` returns false for append, concat and truncate | The capability probe reports none of the three | Step 4.6.4 (refusal by exception only) | A cleaner signal to callers | Planned (optional) |
| F4 | Tests: keep the Hadoop contract tests; cut the smoke test to the attacks that still apply; show the two documented limits; test a fleet-list mismatch | Each attack is refused; the two limits go undetected as expected; the RTMR3 logs show a mismatch | Steps 6.2.1 and 6.2.2, and the core tests of the deleted classes (`SigCoreTest`, `KeyCoreTest`, `AdmissionCoreTest`, `NodeCoreTest`) | The tests follow the smaller code | Planned |
| F5 | Stop the process scaffolding: per-step kits, windows, `.patch` copies and facts lists (at most one facts list, for the paper's numbers); `ops/rebuild/` becomes the image build; test on a new VM instead of a window | Nothing that is no longer used is still run | ADR-042 (a kit per step), ADR-045 (windows), ADR-024 and ADR-025 (gated commits of kits) | They were scaffolding for a design that changed. **Exception, our decision of 19 October 2026 (ADR-059): the preflight and the audit of the whole docs folder stay as long as they are needed** | Planned (can happen at any time) |

**Not ours:** the consumer's verifier with all quote checking (the teammate's; it takes over the quote parts of 5.2 and the whole of 6.1), TLS checking with per-fetch evidence (5.3.3), and the performance study (6.3).

### 10.4 Where each legacy step went

| Legacy step | What it was | Fate from 18 October 2026 | Now |
|---|---|---|---|
| Milestone 1 | Measure the code that runs (RTMR3, done 5 and 6 October; re-measured 14 October) | Stays as the evidence of the method; its manual steps are replaced | F0.1 and F0.2 |
| Milestone 2 | The WireGuard mesh and a closed ordinary network | The tunnel stays; its key files and scripts are replaced | F1 and F0.5 |
| 4.2 to 4.6 | Hashing, records, verified reads, the contract tests, the fail-open fixes | The behaviours stay, the code is simplified | F3 and F4 |
| 4.5 | Metadata from records and the NameNode audit comparison | Dropped as observe-only | F3.6 |
| 5.1.1 | Signed records with a test key (ATTEST02) | Done, as history; the format and the signing code are replaced | F3.2 and F2 |
| 5.1.2 | Folder identity files (ATTEST03) | Done, as history; the behaviour is kept, the formats and the top-folder kind are replaced | F3.2 and F3.4 |
| 5.1.3 | The real key per VM at boot, in a signing service | Done, as history; replaced | F1 and F2 |
| 5.2.1 | Readers accept only keys whose quote verifies, with a reference file | Done, as history; replaced by the fixed list; the quote checks go to the consumer's verifier | F2 and the teammate's verifier |
| 5.2.2 | The doorman of the mesh, on a test mesh | Done, as history; replaced | F1.4 |
| 5.2 (rest) | The doorman as the source of the key list's bundles; adoption for `wg0` | Closed: replaced | F1 |
| 5.3.1 | The locked image | Replaced | F0.1 to F0.5 |
| 5.3.2 | The fixed driver | Replaced | F0.3 |
| 5.3.3 | TLS checking with per-fetch evidence | The teammate's | not ours |
| 5.4 | The Merkle log, signed checkpoints, the witness | Deferred on 10 October; now skipped | none |
| 5.5 | "Start" records | Dropped on 10 October | none |
| 6.1 | The standalone verifier and a second one | The teammate's consumer-side verifier; we send her the formats after F3.2 | not ours |
| 6.2.1, 6.2.2 | The tamper demonstrations and the two documented limits | Replaced | F4 |
| 6.2.3 | A review of what is readable outside the TEE | Partly done by F0 and by the limits of the paper; no separate review is planned | F0 |
| 6.3 | Performance with and without the custody layer | The teammate's | not ours |
| 6.4 | Scale up as far as budget allows | Asked of the mentor | open |

### 10.5 Decisions taken by default, where the note is silent

Each is easy to change (ADR-060); the mentor has been asked about the ones that matter most.

| Decision | Default | How to change it |
|---|---|---|
| Image base and kernel | Ubuntu 22.04 with the pinned 6.17 packages as the default kernel, the combination that is already shown to work | the kernel package variable of the image build |
| Image build and names | A builder VM and `gcloud compute images create`; `tc-locked-DATE` and `tc-debug-DATE` | the image prefix variable |
| Fleet size | 2 nodes (master and worker) for the evidence run | the host list file of `fleet-setup.sh` |
| `fleet.tsv` columns | Host, key id, signing public key, WireGuard public key and mesh IP, as in the note | one function in `fleet-setup.sh` and in `FleetKeys` |
| Publishing the statements and quotes | Guest attributes first (no service account), in chunks if over the size limit; a bucket only with a dedicated write-only service account, which is asked of the mentor | the channel variable of `tc-boot.sh` |
| Extra measured files | The boot script, the units, `openssl` and `wg` | one line per path in the list file |
| Who may read the key | As in the note: the key file is read in-process; a helper under another user is asked of the mentor | ADR-058 |
| Old data | A fresh HDFS per run; the data of runs 14 and 15 is test data, deleted at the end of Milestone 5 | none needed |
