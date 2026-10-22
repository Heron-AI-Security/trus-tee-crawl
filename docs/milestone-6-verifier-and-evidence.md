# Milestone 6: verifier and evidence (handoff Stage D)

Date: 21 October 2026. Times are UTC. Status: **step 6.2 is done on the real cluster (21 October 2026, with all ten attacks; step R1 added four more on 22 October, A11 to A14); step 6.1 (the standalone verifier) is the teammate's, and she has what she needs from us (the formats, the test vectors, the rules for enforcing the reference values, the evidence and the reference values of the locked image); step 6.3 (performance) is split by the mentor's review of 22 October: the teammate writes one benchmark spec and we run both sides on our fleet; step 6.4 (scale) is wanted, with more machines.** Submission is due on 20 November 2026.

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
| 6.3 | Performance. The mentor's review of 22 October 2026: Subhi writes one benchmark spec (the URL list, the parameters, the topology, the same hour), and we run both the vanilla side and the custody side on our fleet, so that the machines are identical; 1K, 10K and 100K URLs, TDX against non-TDX as a 2 x 2 (custody layer on and off) at 1K and 10K, measuring wall-clock time, CPU time, bytes in and out, CPU and memory | Subhi (the spec) and us (the runs) | Not started: it waits for her spec, and it needs a plain-HDFS image and the larger sizes (step R6, [milestone-plan.md](milestone-plan.md) section 11) |
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
| A11 | a file written through the wrapper into a folder that was copied with the plain client (its identity still says 'a') | **refused at the write**, nothing is written ("the identity in … is for a folder named 'a'") |
| A12 | a file renamed through the wrapper into that folder | **refused** ("Attested rename refused …"), and the file stays where it was |
| A13 | create, make a folder, open, delete, rename to and rename from a name like `.good.bin.attested` | **all refused** (7 of 7, with `-cat` and `-text` as the two ways of reading: "reserved for the record of a file"), and the record and the file are untouched |
| A14 | a configuration file loaded after `core-site.xml` that sets the plain file system | **ignored** (the two keys are final): the wrapper still refuses a tampered file; the control, the same switch with `-D` on the command line, reads it (limitations row 172) |
| `copyToLocalFile` | a tampered file copied to the local disk | **refused** (the check `f2-check.sh`, [milestone-5-signed-records.md](milestone-5-signed-records.md) section 16.5) |
| L1 | a file deleted together with its record | **undetected, as documented** (the answer is simply: no such file) |
| L2 | an older signed copy put back (the old file and its old record, both genuine) | **undetected, as documented** (the wrapper returns the old version) |

A10 and A10b are the handoff's attack "move a folder with the plain client, then rename it through the wrapper" (the table above). A11 to A14 are the attacks of step R1 (22 October 2026, ADR-071); they ran on the debug fleet of three nodes made from `tc-img-dbg-2` ([run-comparison.md](run-comparison.md) section 9.10), after the sandbox with the real Hadoop shell, where A13 found that the Hadoop shell opens a file through the `openFile` builder, a path that the first version of the reserved-name check did not cover. They were missing from the first attack script, were tried first in the sandbox with the real Hadoop shell, and then ran on the cluster.

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

From the mentor's note of 18 October ([next-steps-fixed-fleet.md](next-steps-fixed-fleet.md) section 5), per run: every statement A and quote A (our announcement of each node, which binds its two public keys and its log), every quote B (the final quote), the RTMR3 event logs, and `fleet.tsv`. They are in the operator's folders `evidence-f5b`, `f5d`, `f5l` and `f5m` on the Cloud Shell, bundled as `evidence-f5.tar.gz` (SHA-256 `d63a9896…`, 46 files) and, later and with everything, including the folder `evidence-f6d` and `reference-values.json`, as `evidence-all.tar.gz` (SHA-256 `cbbb7e0b…`, 118 files), both made on the Cloud Shell; the copy of `evidence-all.tar.gz` that was downloaded to the laptop is byte-identical to it (SHA-256 `cbbb7e0b88d78ac17f68596aad5551c09a1fd3085ead512270497e91eb436977`, 135,304 bytes, checked on 21 October 2026). Her verifier checks each quote's Intel chain, that each quote A binds its statement, that every key in `fleet.tsv` has its own valid quote A, that every node's log holds the same `fleet` hash, and the final files' signatures and chunk hashes against `fleet.tsv`. It records the measurements without enforcing them yet. The layout of the files that she receives is in [milestone-5-signed-records.md](milestone-5-signed-records.md) section 15.8.

The note's two dates for us were "send her the record and identity byte formats once step 3.2 is fixed" and "share the branch after step 3 so the wrapper review can start": both fall on 21 October 2026, when steps 0 to 4 were done (the handoff planned them for the two weeks after 18 October). The formats are in [milestone-5-signed-records.md](milestone-5-signed-records.md) section 16.3 and the branch is `feat/tee-hadoop-cluster`.

**The reference values of the locked image.** The note says to record the measurements without enforcing them, and to produce the reference values from the final baked image so that they can be locked in later. `ops/image/reference-values-tc-img-lock-1.json` holds MRTD `c1ee9c16e3af…`, RTMR0 `e242a9b441c2…`, RTMR1 `7bf1f4c1b53a…` and RTMR2 `5deb8bd855af…` (the same four as in step F0.3a: the platform measures them) and the 15 events that the image measures into RTMR3 at every boot, in order (`tc-lib`, `tc-conf`, `tc-units`, `openssl`, `wg`, `jdk`, `java-settings`, `java-ca-fingerprints`, `hadoop-code`, `hadoop-conf`, `nutch-deploy`, `crawl-params`, `crawl-seeds`, `fleet-props`, `firewall`) with their SHA-384 digests. The two events `fleet` and `fleet-conf` depend on the run (the keys of the fleet), so RTMR3 itself differs per run and the verifier rebuilds it from the events. `f1-fleet.py reference` made the file from the final quotes of the nodes of the locked fleet and refuses nodes that disagree (it takes any number of nodes); the file also names the machine type (`c3-standard-4`), because the platform's registers belong to the image and the machine type.

### 6.1 The rules for enforcing the reference values (decision 1 of the mentor's review of 22 October 2026)

Without this rule a node that was booted from the debug image and added to `fleet.tsv` would pass every check: it can log in, read its key and write into HDFS. The rule: **every row of `fleet.tsv` needs a quote A and a quote B that match the reference values exactly.** The reference values belong to the image and the machine type, so new nodes of the same kind need no extra measuring. These are the exact rules, as the tool `ops/image/test/f1-fleet.py enforce` applies them and prints them on a failure:

| Rule | What must hold, for every row of `fleet.tsv` |
|---|---|
| E1 | the row has a quote A (`announce-<node>.txt`) and a quote B (`final-<node>.txt`); a row without both is refused |
| E2 | each file names the node of its row, and its signing key and its WireGuard key are the keys of that row |
| E3 | the quote binds the name, both public keys and the log (REPORTDATA), and the log's chain is consistent and replays to the RTMR3 of the quote |
| E4 | MRTD and RTMR0 to RTMR2 of the quote equal the reference values exactly |
| E5 | the log of quote A has exactly the stable events of the reference, in order, and each digest equals the reference digest |
| E6 | the log of quote B has the same stable events, then `fleet`, then `fleet-conf`, and nothing else |
| E7 | the event `fleet` of quote B is the SHA-384 of `fleet.tsv`, the same for every node |
| E0 | (the verifier's, not the tool's) the Intel signature chain of every quote verifies |

The operator also applies E1 to E5 when it builds the fleet (`f1-fleet.py build … REFERENCE.json`, or `REFERENCE=... f1-drive.sh fleet-build`), so a node that does not match is refused before it enters `fleet.tsv`, and the stage `enforce` checks the finished fleet. **It ran on the real evidence on 22 October 2026:** the locked run (`evidence-f5l`) is accepted ("all 2 nodes of `fleet.tsv` have a quote A and a quote B that match the reference values of `tc-img-lock-1` on `c3-standard-4` exactly"), and both debug runs (`evidence-f5d` and `evidence-f6d`) are refused with 8 problems each, because the events `tc-conf` and `firewall` differ (rules E5 and E6). The rule is for the evidence run, and the reference values must be those of the commit that is pinned for the run (decision 4, step R4).

### 6.2 Test vectors for ATTEST04 and ATTEST05

`ops/attested/testvectors/attest-vectors-v1.json` holds 18 vectors that the wrapper's own code made with a fixed key pair (for the vectors only): 6 valid (three file sizes, a non-ASCII file name, a folder under the root and a nested folder) and 12 that must fail, each at a named check (`decode`, `signature`, `binding-folder`, `binding-name`, `binding-parent`, `length`, `chunk-hash`, in this order). Each vector has the record in hex, what the verifier knows (the folder id, the name, the parent), the file (a rule: byte i is i mod 251, with an optional changed byte or extra byte), the statement that is signed, and the verdict. A second implementation, written only from [milestone-5-signed-records.md](milestone-5-signed-records.md) section 16.3 and not using any Java code, is `ops/attested/testvectors_check.py`; it gives every vector the verdict that the vector says and reproduces the signed statement byte for byte, which also checks that the specification is accurate (it ran on 22 October 2026, in the sandbox and on the Cloud Shell: `TESTVECTORS-OK: 18 vectors (6 valid, 12 that must fail)`). A verifier of the teammate's is right when it gives the same 18 verdicts. A new file of vectors is made by `ops/attested/TestVectors.java`; the build-and-test script regenerates and checks them.

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

The mentor's review of 22 October 2026 settles who does what. **Subhi writes one benchmark spec** (the URL list, the parameters, the topology, and the rule that both sides run in the same hour), and **we run both the vanilla side and the custody side on our fleet**, so that the machines are identical. The wrapper has no off switch, so the vanilla side needs a **plain-HDFS image**. The comparison is TDX against non-TDX at 1K and 10K URLs, as a 2 x 2 with the custody layer on and off (the mentor wrote this answer, and the one about who runs the custody side, in square brackets in his reply, so we confirm both with him). **100K URLs are wanted**, with more machines: a fixed URL list sampled from a Common Crawl index across many hosts and fetched in one round, so that both sides fetch the same pages. Each crawl size gets its own baked parameter set, image and reference values. For every run that we report: at least two workers (replication is `min(workers, 2)` in `tc-fleet.sh`, and the master runs no DataNode, so one worker has no redundancy), and a disk larger than 30 GB for 100K URLs. A node that reboots is out for the rest of the run, because its keys are in memory and its replicas are gone.

What we owe Subhi and have: the MapReduce, YARN and HDFS settings of the fleet (`params.env`, the crawl driver `tc-crawl.sh`, and the templates in `ops/image/rootfs/etc/tc/fleet-props/`), her sizes' machine type (`c3-standard-4`, 4 vCPU and 16 GB), and the evidence and the rules of section 6. What does not exist yet: her spec, the plain-HDFS image, the parameter sets and the 2 x 2 runs; this is step R6 of the plan ([milestone-plan.md](milestone-plan.md) section 11).

## 9. Evidence and how to run it again

The scripts are `ops/image/test/f4-attacks.sh` and the stages of `ops/image/test/f1-drive.sh` (`fleet-attacks`, `reference-values`, `enforce`), rehearsed by `f4-rehearse.sh` and `f4-local.sh`. The evidence bundles are `evidence-f5.tar.gz` (`d63a9896…`) and `evidence-all.tar.gz` (`cbbb7e0b…`). The mistake log rows 161 to 164 and the rules 56 to 59 are the lessons of the cluster runs that led here.
