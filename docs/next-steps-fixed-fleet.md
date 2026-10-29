# Milestone 5 onward: fixed fleet, smaller trusted code

**Status check, 30 October 2026.** A planning page of an earlier stage; it is not updated line by line. The plan is [milestone-plan.md](milestone-plan.md) (section 12 holds the mentor's review of 28 October 2026) and the state is [session-start.md](session-start.md). Reviewed on 30 October 2026: still an earlier stage's page; the mentor's six steps P1 to P6 are in ADR-090, and P1, P2 and P6 are done.

For Rishab (and your assistant). Written 2026-10-18 by Pingshan's assistant from Pingshan's decisions. Code references are to `Antisource/nutch`, branch `feat/tee-hadoop-cluster`, commit `03ee672`. The assistant read the code but ran nothing. Line counts marked "target" are estimates.

**Status note added on 27 October 2026 (not part of the mentor's text).** Steps 0 to 4 of this note (F0 to F4 in our documents) are done on the real cluster (21 October 2026); step 5 (F5, the cleanup) is next, because the steps R2 to R5 of the mentor's review of 22 October 2026 that it waited for are done ([milestone-plan.md](milestone-plan.md) sections 10 and 11). Of the mentor's review, R0 to R5 are done (R4 done, with one part open), R6 is deferred and R7 is the teammate's (ADR-076). The submission date of 20 November 2026 stands.

## 1. What changed, in one paragraph

The cluster runs on a **fixed fleet** of TDX VMs. No VM joins during a run. Each VM generates its signing key and WireGuard key at boot, in RAM, and gets one quote that binds both public keys. A setup step collects the public keys, writes one read-only list (`fleet.tsv`), and every node installs it and writes its hash into RTMR3. Inside the cluster, a signature is accepted only if its key is in `fleet.tsv`. **There is no quote checking inside the cluster.** Quote checking happens once, at the end, in the consumer's verifier, which is Subhi's piece. The goal is trusted Java of about 950 to 1,150 lines, down from 5,783.

## 2. Why the design is safe without in-cluster quote checks

A signature only proves "the holder of this key signed these bytes". What matters is which keys count. Your key list was a folder that each signing service wrote into, rescanned every 10 seconds, so every reader had to re-check each key's quote. With a fixed list that nothing in the cluster can change, those checks add nothing.

The list itself still has to be provable. If a rogue key were accepted mid-run, an honest VM could read a forged intermediate file and write genuine-signed output from it, and a check of only the final files would not see it. That is why each node extends RTMR3 with the hash of `fleet.tsv`. The consumer then checks that every node used the same list and that every key on it has a valid quote of its own.

All of this assumes **no one can be root inside a node**. That makes the locked image a prerequisite (step 0), not a later hardening step.

## 3. Scope

| Item | Owner / status |
|---|---|
| Wrapper, keys, fleet setup, locked image, measurement | **You** |
| `QuoteVerifier` and all quote checking | **Consumer side, Subhi.** Remove it from the cluster. Don't extend it |
| TLS checking, the Python verifier, the performance study | **Subhi** |
| Ledger, witness, Merkle log | **Skipped** |
| Deletion and rollback | Out of scope, stated as limits (unchanged) |

Answers to your open questions:

- **Disposable TDX VMs:** yes. Create VMs generously, and use a fresh VM for each test instead of changing live nodes.
- **Driver parameters and startup script:** both baked into the image, so they are fixed and measured.
- **"Lock" and SSH:** the lock means the operator cannot log in to or change a running node. SSH matters because with SSH and `sudo` the operator can read keys in RAM and rewrite `fleet.tsv`.
- **TLS checking:** Subhi's.

## 4. Steps, in order

Each step has a pass condition.

### Step 0: the locked, measured image

| # | Change | Pass condition |
|---|---|---|
| 0.1 | The default kernel supports RTMR3 extension (6.16 or later; 6.17 is what you used). Today RTMR3 is extended only by a manual script after a one-off boot into 6.17, and a normal boot goes back to 6.8 | After a plain reboot, RTMR3 is non-zero and matches a replay of the event log |
| 0.2 | Measurement runs as a systemd unit ordered **before** any Hadoop daemon. It keeps the "RTMR3 is zero at start" check | The unit's log shows it finished before the NameNode and DataNode started |
| 0.3 | Bake into the image: the JDK, Hadoop, the final `core-site.xml` and `hdfs-site.xml`, the job and wrapper jar, the boot script, and the crawl driver with its parameters | Starting a VM from the image runs the crawl with no operator command |
| 0.4 | Remove login: no sshd, no OS Login, no guest agent that adds SSH keys from instance metadata, and serial console login off | `gcloud compute ssh` and serial console login both fail |
| 0.5 | Close doors around the wrapper: set `dfs.webhdfs.enabled=false` (final), and bind the NameNode, DataNode, ResourceManager and NodeManager ports to `wg0` only | A WebHDFS read and a YARN job submission from outside the mesh both fail |
| 0.6 | Build a separate **debug image** with login enabled, under a different name. It is never used for evidence | The two images have different measurements, and the evidence run names the locked one |

Measurement policy: **record, don't enforce.** The consumer verifier reports MRTD and RTMR0 to RTMR3 and replays the RTMR3 event log, but does not reject on mismatch yet. Produce the reference values from the final baked image so they can be locked in later for production.

### Step 1: keys at boot and the fleet list

**`tc-boot.sh`** (in the image, measured, runs as root after the measurement unit and before Hadoop; about 45 lines):

1. Signing key: generate EC P-256 with `openssl` into `/run/tc/sign.key`. `/run` is RAM-only. Set owner `hadoop` and mode `0400`.
2. WireGuard key: `wg genkey > /run/wg/key`, then `wg set wg0 private-key /run/wg/key`. Never write the private key into a `.conf` file or to disk.
3. Write statement A: host, signing public key, WireGuard public key, nonce. Get quote A with the existing `quote.sh`, with REPORTDATA = SHA-512 of statement A.
4. Publish statement A and quote A where the setup script can fetch them **without SSH**. Use GCE guest attributes or a GCS bucket; check the size limit for guest attributes first. Both channels are untrusted, which is fine because the contents are public and verified at the end.
5. Wait for `fleet.tsv`, delivered by instance metadata or the same bucket. Read it once and install it as `/etc/tc/fleet.tsv` (or under `/run/tc/`), owner `root`, mode `0444`.
6. Refuse to continue if this node's own keys are not in the list.
7. Extend RTMR3 with SHA-384 of `fleet.tsv` (logged as event `fleet`), take quote B, and publish it.
8. Configure the `wg0` peers from `fleet.tsv`, then start Hadoop.

**`fleet-setup.sh`** (operator machine, NOT trusted; about 40 lines; replaces `m513-keylist-sync.sh` and `mesh-admit.sh`):

1. Collect statement A and quote A from each of the N VMs.
2. Write `fleet.tsv` with one line per node: `host keyid signpub wgpub meship`.
3. Deliver `fleet.tsv` to every node.
4. Collect the quote B values and archive the whole run for Subhi's verifier: statements, both quotes per node, the event logs and `fleet.tsv`.

| # | Pass condition |
|---|---|
| 1.1 | No private key exists on disk or in any `.conf` file. Search the disk image after a run |
| 1.2 | Every node's RTMR3 event log contains the same `fleet` hash, and it equals SHA-384 of the archived `fleet.tsv` |
| 1.3 | Booting a node with a `fleet.tsv` that omits its own key stops the boot before Hadoop starts |
| 1.4 | The full mesh comes up with no SSH used at any point |

### Step 2: `FleetKeys` replaces the key code

One class, about 70 to 90 lines:

- Loads `/run/tc/sign.key` and `/etc/tc/fleet.tsv` once per JVM. There is no time limit and no rescan.
- Exposes `signingKeyId()`, `sign(bytes)` (in-process, with `java.security.Signature`) and `publicKey(keyId)`, which returns null when the key is not listed.
- Has no quote handling.

**Delete:**

| Code | Lines |
|---|---|
| `KeyService` | 386 |
| The socket half of `ServiceKeys` | |
| `KeyList` (10-second rescan) | |
| `KeyBundle` | |
| `BundleCheck` | 35 |
| `QuoteAdmission` | 129 |
| `AdmissionReference` | 124 |
| `QuoteVerifier` | 282 |
| `NodeBundle` | 126 |
| `MeshPolicy` | 96 |
| `MeshAdmission` | 118 |
| `wg1-node-up.sh` and `wg1-node-down.sh` | |
| The `wg1` path in `mesh-admit.sh` | |
| The 15 `attested.keys.*` settings | |

**Move out of trusted code** (into tests or tools): `TestKeys` (a test key is just a different key file) and `AttestedKeyTool`.

`QuoteVerifier` can go to Subhi as a starting point if she wants it; that is her call.

Pass condition: a record signed by a valid P-256 key that is not in `fleet.tsv` fails the read. Repeat this in a fresh YARN container started after the file was written.

### Step 3: simplify the data path

Keep these behaviours:

- sign on write;
- verify each 16 KiB chunk before releasing its bytes;
- folder binding;
- a missing record fails the read;
- append, concat and truncate refused;
- renames re-sign.

Make these changes:

| # | Change | Pass condition |
|---|---|---|
| 3.1 | **Remove all switches and modes.** All 30 `attested.*` settings, the three allow/warn/fail modes and `AttestedSettings` go. Behaviour is fixed and secure. The chunk size becomes a constant | `-D` with any old `attested.*` setting has no effect. A file with no record fails both reads and status calls |
| 3.2 | **One record format** for file records: folder ID, file name, chunk size, length, chunk-hash list, key ID, signature. One format for folder identities: folder ID, own name, parent ID, key ID, signature. Merge `AttestedRecordCodec`, `AttestedFolderCodec`, `AttestedSidecar` and `AttestedSignatures` into `Records.java` (about 180 to 230 lines). Drop the old record formats ATTEST01, ATTEST02 and ATTEST03 | Contract tests pass. A truncated or oversized record fails the read cleanly |
| 3.3 | **Replace the Merkle tree with a flat hash list.** Sign SHA-256 over the concatenated chunk hashes; no Merkle proof is used anywhere. `MerkleHasher` becomes about 35 lines. Update `ops/attested/merkle_root.py` to match | A one-bit flip in any chunk fails at that chunk |
| 3.4 | **The root `/` gets a fixed all-zero ID** that is never stored. Remove the "top folder with full path" identity kind | The nested-rename case recorded in the milestone 5 report passes. Files directly under `/` are bound |
| 3.5 | **Fix `copyToLocalFile`**, which today forwards with verification bypassed ([`AttestedHdfsFileSystem.java` L933 to L941](https://github.com/Antisource/nutch/blob/03ee672e67dce3ba18d81d5eff0c5ed1c1b3236c/src/java/org/apache/nutch/attested/AttestedHdfsFileSystem.java#L933-L941)). Route it through the verifying open | Copying a tampered file to local disk fails |
| 3.6 | **Drop the observe-only extras:** the metadata and listing length checks (about 273 lines), about 125 lines of logging-only overrides (attributes, ACL, snapshots, storage policy, symlinks), `AttestedAudit` and `AttestedRecords` | Contract tests still pass |
| 3.7 | Optional (about 10 lines): `hasPathCapability` returns false for append, concat and truncate | Hadoop's capability probe reports none of the three |

Keep these exactly (removing any of them reopens a known hole or failure):

- **Never sign from something unverified.** Every re-sign (moving a file or a folder) first verifies the old record, or the whole folder chain at the source. It also makes sure the destination parent has an identity.
- **The folder-identity race and wait loop.** A reader can find an identity file another task is still writing. Without the wait, parallel tasks fail at random, as in the m512 run 1 failure.
- **Builder routes and the second Hadoop storage API:** the `createFile` and `appendFile` builders go through the wrapper, and the FileContext adapter (`AttestedHdfs`) stays. Both lookups are marked final in `core-site.xml`.
- **Refusals:** the refusals of the PathHandle opens and of `getRawFileSystem`.
- **Hidden companion files:** records and identity files are hidden from wrapper listings.
- **Pass-through stream calls:** `hflush`, `hsync`, seek, positioned read and `unbuffer`.
- **`dfsadmin`:** admin scripts that call `hdfs dfsadmin` use the plain implementation.

Rerun the listing of `FilterFileSystem` pass-through methods against Hadoop 3.4.3, and again after any upgrade.

**Line budget for trusted Java:**

| File | Today | Target |
|---|---|---|
| Wrapper | 1,349 | 380 to 450 |
| `AttestedHdfs` | 57 | 25 |
| `HashingOutputStream` | 120 | 70 |
| `VerifyingInputStream` | 222 | 140 to 160 |
| `Records` | 1,012 across 5 files | 180 to 230 |
| `Folders` | 364 | 160 to 200 |
| `FleetKeys` | 658 across 5 files | 70 to 90 |
| Total | 5,783 | about 950 to 1,150 |

Shell: about 110 lines (boot, quote, RTMR3). If you land well over budget, flag it rather than cut a kept behaviour.

### Step 4: tests

- **Keep:** the Hadoop contract tests.
- **Cut** the smoke test to the attacks that still apply, all of which must be refused:
  - flip a byte;
  - replace a file together with its record;
  - remove a record;
  - move a signed file into another folder;
  - swap two same-named files between folders;
  - copy a whole folder elsewhere;
  - move a folder with the plain client, then rename it through the wrapper;
  - add an unsigned file;
  - sign with a key that is not in `fleet.tsv`;
  - `copyToLocalFile` on a tampered file.
- **Show the two documented limits** honestly, both expected to go undetected: delete a file with its record; put back an older signed copy.
- **Test a fleet-list mismatch:** give one node a different `fleet.tsv`. The cluster may run, but the archived RTMR3 logs must show the mismatch.

### Step 5: stop the process scaffolding

- **Stop:** per-step kits, windows, `.patch` copies, the document-status checker and the preflight. Delete the `.patch` files (9,624 lines that nothing runs).
- **Change:** `ops/rebuild/` becomes the image build. Test on a new VM instead of a window.
- **Keep:** at most one facts list, for the numbers the paper cites.

## 5. What Subhi's verifier receives

From `fleet-setup.sh`, per run:

- every statement A and quote A;
- every quote B;
- the RTMR3 event logs;
- `fleet.tsv`.

Her verifier checks:

1. each quote's Intel chain;
2. that each quote A binds its statement;
3. that every key in `fleet.tsv` has its own valid quote A;
4. that every node's RTMR3 log contains the same `fleet` hash;
5. the final files' signatures and chunk hashes against `fleet.tsv`.

It records the measurements, without enforcing them yet. Send her the record and identity byte formats once step 3.2 is fixed.

## 6. Limits to state in the paper

- Deletion and rollback are not detected.
- The design rests on the locked image: anyone who is root inside a node can read keys and rewrite the list.
- Any code running as the Hadoop user, including every YARN container, can sign. The measured code is the only code that runs, because jobs start from the baked driver.
- A node that reboots mid-run gets new keys. The run is then redone on new VMs. A side effect is that records from earlier boots or runs can never verify, which blocks cross-run replay.
- Measurements are recorded, not enforced, during development.
- The record format changed, so files written by `03ee672` will not verify. Use a fresh HDFS per run.

## 7. Order and timing

Submission is due by 20 November 2026.

- **This week:** step 0 (image, kernel, lock, debug image) and step 1.
- **Next week:** steps 2 and 3.
- **Then:** step 4, and a full crawl on the locked image for evidence.

Share the branch after step 3 so the wrapper review can start; a smaller wrapper is what makes a close review possible. Step 5 can happen at any time.
