# Milestone 6: verifier and evidence (handoff Stage D)

Date: 21 October 2026. Times are UTC. Status: **step 6.2 is done on the real cluster (21 October 2026, with all ten attacks); steps 6.1 (the standalone verifier) and 6.3 (performance) are the teammate's, and she has what she needs from us (the formats, the evidence, the reference values of the locked image and the MapReduce settings); step 6.4 is open.** Submission is due on 20 November 2026.

This report was split from the Milestone 5 report on 21 October 2026. The plan had F4 replace steps 6.2.1 and 6.2.2, so their results were first written into [milestone-5-signed-records.md](milestone-5-signed-records.md) (section 17); each milestone has its own report, so they are here now.

## 1. Goal, in plain words

Milestone 6 answers three questions: can anyone check a crawl (the verifier, 6.1), are our attacks on our own system caught (the tamper harness, 6.2), and what does the custody layer cost (performance and scale, 6.3 and 6.4). The system under test is the fixed fleet of Milestone 5: two or more VMs made from one measured image, a wrapper without settings ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 16), and a locked image with a firewall (section 17).

## 2. The steps and their status

| Step | What | Whose | Status on 21 October 2026 |
|---|---|---|---|
| 6.1 | The standalone verifier of the final files (signature, key, quote, measurements, hash), then a second independent one | the teammate's (Subhi) | She has what she needs from us (section 6): the byte formats are in [milestone-5-signed-records.md](milestone-5-signed-records.md) section 16.3 and the evidence of the runs is bundled; the reference values of the locked image are in `ops/image/reference-values-tc-img-lock-1.json` (section 6) |
| 6.2.1 | The tamper demonstrations with a clean control | ours | **Done:** `F4-ATTACKS-OK` on the real cluster, twice, the second time with A10 (section 3) |
| 6.2.2 | The two documented limits, shown honestly | ours | **Done:** both go undetected, as documented (section 3) |
| 6.2.3 | A review of what is readable or changeable outside the TEE, and a red-team harness | ours | The review is done (section 5); the red-team harness is not built |
| 6.3 | Performance. The teammate's task of the week of 21 October: the vanilla CCBot baselines on two machines of the same size as our TDX VMs, at 1K, 10K and 100K URLs, measuring wall-clock time, CPU time, bytes in and out, CPU and memory, with the MapReduce settings of our driver | the teammate's (the plan, section 10.4: "not ours") | With her. We provide the settings (`params.env` and the Hadoop configuration templates of the fleet, section 8). Running the same crawl with the custody layer on our TDX fleet at her sizes would give her baseline something to compare with: offered to her and the mentor, not started |
| 6.4 | Scale up as far as the budget allows | the mentor's decision | Asked of the mentor on 19 October 2026 |

## 3. The tamper demonstrations (6.2.1) and the documented limits (6.2.2)

They run on the debug fleet (`tc-img-dbg-1`), because they need a login: it has the same wrapper, job and configuration as the locked image and differs in the lock and in port 22 (limitations row 170). `w` is the wrapper, `p` is the plain HDFS client, that is someone with the HDFS credentials behind the wrapper's back. Every attack must be refused with a verification message; the clean control must read; the two limits must go undetected.

| Case | What is done | Result on the cluster |
|---|---|---|
| control | four untouched files read through the wrapper | read back byte for byte |
| A1 | a byte flipped in chunk 3 (plain client) | **refused at that chunk** ("chunk 3 (hash does not match the record)") |
| A2 | a file and its record replaced by another file's file and record | **refused** ("the record belongs to another folder than the one this file is in") |
| A3 | a signed file and its record moved to another folder | **refused** (same message) |
| A3b | two files of the same name swapped between two folders, with their records | **both refused** |
| A4 | a whole folder copied elsewhere, identity and records included | **refused** ("the identity in … is for a folder named 'a', not 'a-copy'") |
| A5 | an unsigned file added | **refused** ("the file has no record") |
| A6 | a record signed with a valid key that is in no `fleet.tsv` | **refused** ("the record is signed by a key that is not trusted here") |
| A7 | the record deleted | **refused** |
| A8 | the folder's identity deleted | **refused** ("the folder … has no identity") |
| A9 | bytes appended behind the wrapper's back | **refused** ("length is 400000 in storage but 200000 in its record") |
| A10 | a folder moved with the plain client to another parent | **refused** on the read ("the identity in … points to another parent folder") |
| A10b | the wrapper's own rename of that moved folder | **refused** ("Attested rename refused for the folder …"): the wrapper does not bless a move that was made behind its back |
| `copyToLocalFile` | a tampered file copied to the local disk | **refused** (the check `f2-check.sh`, [milestone-5-signed-records.md](milestone-5-signed-records.md) section 16.5) |
| L1 | a file deleted together with its record | **undetected, as documented** (the answer is simply: no such file) |
| L2 | an older signed copy put back (the old file and its old record, both genuine) | **undetected, as documented** (the wrapper returns the old version) |

A10 and A10b are the handoff's attack "move a folder with the plain client, then rename it through the wrapper" (the table above). They were missing from the first attack script, were tried first in the sandbox with the real Hadoop shell, and then ran on the cluster.

**The fleet-list mismatch.** Two nodes were given different lists (the worker's had one more, invented node; each list held the node's own keys, so both joined). Their signed logs show it: fleet events `b8c9ffcedafe80aa…` and `85317137102407ef…`, final RTMR3 `f5dc1c634e5ed44e…` and `9a47b3948a64d4af…`.

## 4. How it was run, and what went wrong

`ops/image/test/f4-attacks.sh` runs on the master of a formed debug fleet; the operator side is the stage `fleet-attacks` of `f1-drive.sh`. The first run found one failure that was mine: A4 used `hdfs dfs -cp -r`, which does not exist (`Illegal option -r`), and the script hid the error, so a failed setup looked like an attack that was not refused (mistake log row 162, rule 57). Since then the real script runs in the sandbox with Hadoop's own shell (`f4-local.sh`) and a failing plain command is printed next to its verdict. A second run on 21 October 2026 (10:12 UTC, fleet SHA-384 `99bc577bb2ee6c3e…`) added A10 and a wait for HDFS to answer: `F4-ATTACKS-OK`, with the same results for A1 to A9, L1 and L2.

## 5. What an operator can still read or change outside the TEE (the review of 6.2.3)

| What | Readable | Changeable | Effect |
|---|---|---|---|
| Guest attributes, instance metadata, serial console output | yes: public keys, the quote, the log, the self-report | metadata can be changed by anyone with the project permission (for example `tc-fleet`) | a changed fleet list is a different `fleet` event in the signed log, so it is visible, not prevented |
| Memory, the signing key, the WireGuard key | no (TDX, and the keys live only in memory) | no | this is what the locked image protects |
| The disk (HDFS blocks, records, the image) | yes, by someone who can snapshot or attach the disk: the data is not encrypted by us | yes, but a change of data or records is caught on the read (A1 to A10) | detection, not secrecy, and not rollback (L2) |
| Starting, stopping and deleting VMs, the firewall of the VPC | yes | yes | availability, not integrity |
| A new image under the same name | n/a | yes, by the project owner | the final quote's RTMR3 does not match the expected one (the two images differ in RTMR3: [milestone-5-signed-records.md](milestone-5-signed-records.md) section 17.4) |

The red-team harness that the mentor named is not built; this table is the review.

## 6. What the verifier receives, and when (6.1)

From the mentor's note of 18 October ([next-steps-fixed-fleet.md](next-steps-fixed-fleet.md) section 5), per run: every statement A and quote A (our announcement of each node, which binds its two public keys and its log), every quote B (the final quote), the RTMR3 event logs, and `fleet.tsv`. They are in the operator's folders `evidence-f5b`, `f5d`, `f5l` and `f5m` on the Cloud Shell, bundled as `evidence-f5.tar.gz` (SHA-256 `d63a9896…`, 46 files) and, later and with everything, including the folder `evidence-f6d` and `reference-values.json`, as `evidence-all.tar.gz` (SHA-256 `cbbb7e0b…`, 118 files), both made on the Cloud Shell. Her verifier checks each quote's Intel chain, that each quote A binds its statement, that every key in `fleet.tsv` has its own valid quote A, that every node's log holds the same `fleet` hash, and the final files' signatures and chunk hashes against `fleet.tsv`. It records the measurements without enforcing them yet.

The note's two dates for us were "send her the record and identity byte formats once step 3.2 is fixed" and "share the branch after step 3 so the wrapper review can start": both fall on 21 October 2026, when steps 0 to 4 were done (the handoff planned them for the two weeks after 18 October). The formats are in [milestone-5-signed-records.md](milestone-5-signed-records.md) section 16.3 and the branch is `feat/tee-hadoop-cluster`.

**The reference values of the locked image.** The note says to record the measurements without enforcing them, and to produce the reference values from the final baked image so that they can be locked in later. `ops/image/reference-values-tc-img-lock-1.json` holds MRTD `c1ee9c16e3af…`, RTMR0 `e242a9b441c2…`, RTMR1 `7bf1f4c1b53a…` and RTMR2 `5deb8bd855af…` (the same four as in step F0.3a: the platform measures them) and the 15 events that the image measures into RTMR3 at every boot, in order (`tc-lib`, `tc-conf`, `tc-units`, `openssl`, `wg`, `jdk`, `java-settings`, `java-ca-fingerprints`, `hadoop-code`, `hadoop-conf`, `nutch-deploy`, `crawl-params`, `crawl-seeds`, `fleet-props`, `firewall`) with their SHA-384 digests. The two events `fleet` and `fleet-conf` depend on the run (the keys of the fleet), so RTMR3 itself differs per run and the verifier rebuilds it from the events. `f1-fleet.py reference` made the file from the final quotes of both nodes of the locked fleet; it refuses two nodes that disagree.

## 7. Limits to state in the paper (section 6 of the mentor's note)

| Limit | Where it is shown or documented |
|---|---|
| Deletion and rollback are not detected | L1 and L2 in section 3; the decisions of ADR-034 to ADR-036 |
| The design rests on the locked image: anyone who is root inside a node can read keys and rewrite the list | [milestone-5-signed-records.md](milestone-5-signed-records.md) section 17 and limitations row 167; the debug image keeps a login and is never used for evidence |
| Any code running as the Hadoop user, including every YARN container, can sign; the measured code is the only code that runs, because jobs start from the baked driver | ADR-058 (the key file is read in-process); the F2 check, where an outsider's key is refused in a fresh container |
| A node that reboots mid-run gets new keys, so the run is redone on new VMs; records of earlier boots or runs can never verify, which blocks cross-run replay | [milestone-5-signed-records.md](milestone-5-signed-records.md) section 15 (step F1, the negative test of a rebooted node) |
| Measurements are recorded, not enforced, during development | section 6 |
| The record format changed, so files written by `03ee672` do not verify: use a fresh HDFS per run | [milestone-5-signed-records.md](milestone-5-signed-records.md) section 16 |

The attack-to-check table, the informal properties and the limits of both of the mentor's notes (10 and 18 October), combined, are in [security-argument.md](security-argument.md).

## 8. Performance (6.3) and scale (6.4)

The plan (section 10.4 of [milestone-plan.md](milestone-plan.md)) gives step 6.3 to the teammate, "not ours", and her task of the week of 21 October is the **vanilla CCBot baseline**: the original crawler without the custody layer, on two machines of the same size as our TDX VMs (`c3-standard-4`, 4 vCPU and 16 GB), at 1K, 10K and 100K URLs, measuring wall-clock time, CPU time, bytes in and out, CPU and memory, with the MapReduce settings of our driver. What we owe her is those settings, and they exist: `params.env` (rounds, fetch-list size, threads, time limit, the HDFS folders), the crawl driver `tc-crawl.sh`, and the Hadoop, YARN and HDFS configuration templates of the fleet (`ops/image/rootfs/etc/tc/fleet-props/`). Two things she needs for sizes beyond the baked crawl are her own: a seed list (the two baked seeds cannot reach 1K URLs) and her parameters per size.

Offered, not started: the same crawl with the custody layer on our TDX fleet at her sizes and with her measurements (and, to separate the cost of TDX from the cost of the wrapper, once with the wrapper switched off), so that her baseline has something to compare with. It needs her seeds and parameters first, and it is the mentor's to ask for. TDX against non-TDX would need a third image without the measurement stack, never used for evidence. **6.4:** whether 100K URLs and further scale are wanted was asked of the mentor on 19 October 2026 and is open.

## 9. Evidence and how to run it again

The scripts are `ops/image/test/f4-attacks.sh` and the stages of `ops/image/test/f1-drive.sh` (`fleet-attacks`, `reference-values`), rehearsed by `f4-rehearse.sh` and `f4-local.sh`. The evidence bundles are `evidence-f5.tar.gz` (`d63a9896…`) and `evidence-all.tar.gz` (`cbbb7e0b…`). The mistake log rows 161 to 164 and the rules 56 to 59 are the lessons of the cluster runs that led here.
