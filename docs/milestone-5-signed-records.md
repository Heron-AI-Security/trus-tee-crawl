# Milestone 5: signed records

**Status on 17 October 2026: steps 5.1.1, 5.1.2 and the combined crawl (15 October), step 5.1.3 (16 October), step 5.2.1 (16 October, offline and live) and step 5.2.2 (17 October, on the test mesh) are done.** Open: the rest of step 5.2 (the doorman as the source of the key list's bundles, and its adoption for the production mesh, which is the mentor's decision) and step 5.3 (the locked image, the fixed driver, TLS checking on); **both are replaced from 18 October 2026 by the fixed-fleet steps F0 to F5** ([milestone-plan.md](milestone-plan.md) section 10, [next-steps-fixed-fleet.md](next-steps-fixed-fleet.md)); sections 6 to 9 below describe the design that the fixed fleet replaces, and they stay as history. Steps F0.1 and F0.2 of the fixed fleet are done on 19 October 2026 (section 10). The recon of step F0, the inventory of the nodes, is in section 11. Step F0.3a, the software layer of the image, is in section 12. Step F0.3b, the job and the wrapper jar, is in section 13. Step F0.3c, the crawl that runs by itself, is in section 14. Step F1, the fleet boot flow, is in section 15. Steps F2 and F3, the fixed-behavior wrapper, are in section 16. Phase 4 (the locked image and the firewall) is in section 17; step F4 belongs to Milestone 6 and is in [milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md). The detail follows, step by step.

**Status on 21 October 2026: Milestone 5 is closed except step F5 (the cleanup), which now waits for decisions 1, 2, 4 and 5 of the mentor's review of 22 October 2026 (steps R2 to R5, [milestone-plan.md](milestone-plan.md) section 11).** The two items that were open on 17 October (the rest of step 5.2 and step 5.3) were replaced on 18 October by the fixed-fleet steps F1 and F2 and by F0.1 to F0.6, and all of them are done on the real cluster (sections 10 to 17); the attacks of step 6.2 are in [milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md). The status of 17 October below is kept as history.

**Status on 27 October 2026: Milestone 5 is closed except step F5 (the cleanup), which is next:** the steps R2 to R5 of the mentor's review of 22 October 2026 that it waited for are done ([milestone-plan.md](milestone-plan.md) section 11; R4.1 to R4.6 are done; R4 as a whole waits for the mentor's answers on the sealed disk and the retention lock and for the teammate's rebuild (limitations rows 186, 176 and 188)). The statuses of 17 and 21 October above are kept as history.

Detail by step: **steps 5.1.1 and 5.1.2 are done on 15 October 2026**: every record can be signed with a labelled test key, a file rewritten together with its record, without the key, fails the read (section 3), and every file is bound to its folder and its name, so that a signed file moved or copied elsewhere fails the read too (section 4); both are shown on the real HDFS. The combined crawl, with signing and folder binding on and required, ran on the real cluster the same day and its whole output verifies offline with the public key only (section 5). **Step 5.1.3, the real key, is done on 16 October 2026**: each VM makes its own signing key in the memory of a small signing service, the hardware quote vouches for exactly that key, and a crawl with the real keys verifies offline against a key list (section 6). **Step 5.2.1, the admission of keys by their quote, is done on 16 October 2026**: a key is trusted only if its hardware quote verifies in Java and its measurements are in an editable reference file; offline, both real keys of run 15 are admitted and the whole run-15 output verifies with only admitted keys (section 7); live, on the two real VMs, both fresh keys were admitted by their live quotes and a rogue key with a fake quote was refused (section 8). **Step 5.2.2, the doorman of the mesh, is done on 17 October 2026, on the test mesh**: a node joins the mesh only if a quote made just now binds its WireGuard key and requested address to the machine, the quote is genuine, its measurements are in the reference file, and the host and the address are in a policy table; both real nodes were admitted, a rogue node with a fake quote was refused, and the test mesh came up with exactly the admitted peers while the production mesh and the measured stack stayed untouched (section 9). The rest of step 5.2 and step 5.3 are open ([milestone-plan.md](milestone-plan.md)). It is extended as the later steps close. All times are UTC.

## 1. What this milestone does, in plain words

Until now every file in HDFS has a tamper sticker, its record. The sticker proves little, because anyone who can write the file can also rewrite its record. Milestone 5 replaces the sticker with a **signature**: a stamp that only a holder of the key can make. Step 5.1 gives each machine a signing key and ties every file to its folder, and step 5.2 makes readers accept only the keys of machines whose hardware quote has been checked, and lets a node join the mesh only after its quote has been checked too. The mentor's note of 10 October (section 3) is the design: sign on write, verify on read.

## 2. The steps

| Step | What | State |
|---|---|---|
| 5.1.1 | records are signed with a test key, clearly labelled and never used in evidence | **Done on 15 October 2026** (section 3) |
| 5.1.2 | folder identity files bind each file to its folder (ADR-035) | **Done on 15 October 2026** (section 4) |
| 5.1.2b | the combined crawl with signing and folder binding on and required (`run14`) | **Done on 15 October 2026** (section 5) |
| 5.1.3 | the real key: generated per VM at boot, held by a small signing service, bound to the quote through REPORTDATA | **Done on 16 October 2026** (section 6) |
| 5.2.1 | readers accept only keys of attested machines | **Done on 16 October 2026**, offline (section 7) and live (section 8) |
| 5.2.2 | mesh admission: a node joins the mesh only after its quote is verified (the doorman), proven on a test mesh | **Done on 17 October 2026**, on the test mesh (section 9) |
| 5.2 (rest) | the doorman as the source of the key list's bundles, and its adoption for the production mesh | Replaced on 18 October 2026 by F1 and F2 (ADR-056) |
| 5.3 | locked image, fixed driver, TLS checking on | Replaced on 18 October 2026 by F0 (ADR-057); 5.3.3 is the teammate's |
| F0 to F5 | the fixed-fleet steps of the mentor's note of 18 October 2026: the locked image, keys at boot and the fleet list, `FleetKeys`, a simpler data path, the tests and the end of the scaffolding | Done on 21 October 2026 except F5 (it is next; R2 to R5 are done, 27 October 2026): F0.1 and F0.2 done on 19 October 2026 (section 10), the recon in section 11, F0.3a done on 19 October 2026 (section 12), F0.3b done on 20 October 2026 (section 13), F0.3c done on 20 October 2026 (section 14), F1 done on 20 October 2026 (section 15), F2 and F3 done on 21 October 2026 (section 16), F0.4, the rest of F0.5 and F0.6 done on 21 October 2026 (section 17), F4 done on 21 October 2026 (the Milestone 6 report); [milestone-plan.md](milestone-plan.md) section 10 |

## 3. Step 5.1.1: signing the records with a test key

### 3.1 What it does

With signing switched on, the wrapper signs the record of every file it writes, and before it returns any byte of a file it checks the signature of that file's record. A record whose signature does not verify is **always** refused. With signatures required, a record in the old format is refused too, so a file that someone rewrote together with a matching record, without the key, fails the read. Everything is switched off by default: nothing changes until the site configuration says so.

### 3.2 The decisions, and where they come from

The note of 10 October answers the design but not these four choices. I took the recommended defaults on 15 October, the mentor not having answered them (ADR-044).

| Question | Answer | Source |
|---|---|---|
| What a record covers | the folder's ID, the file's name, the content hash and the length (not the full path); in 5.1.1 the signature covers the key id, chunk size, length and root, and 5.1.2 adds the folder ID and name | the mentor's note, section 3 |
| A test key is allowed | clearly labelled, never used in evidence | the mentor's note, B1 |
| Signature scheme | **ECDSA with P-256 and SHA-256**, built into the Java 11 on the cluster | default (ADR-044) |
| Old unsigned records | readable as legacy while `attested.signature.required` is off | default (ADR-044) |
| How the test key is labelled | its id always starts with `TEST-`, and a setting refuses test keys in the real-key mode | default (ADR-044) |
| The identity file's name | `_attested-folder` (the note requires only a `_` prefix); used from 5.1.2 | default (ADR-044) |

### 3.3 The record and what the signature covers

A record in the new format `ATTEST02` is the old `ATTEST01` record (8 bytes of header, chunk size, length, the Merkle root, the number of chunks and the 32-byte hash of every chunk) followed by a signature block: one byte for the key id's length, the key id, two bytes for the signature's length, and the signature (ECDSA P-256 with SHA-256, in DER, at most 200 bytes). The signed statement is a fixed tag, the key id, the chunk size, the length and the root; the root commits to every chunk hash, so the hashes need no second signature. Every field of the statement has a fixed length or a length in front of it, so two different records can never give the same bytes. The old format is still written when signing is off, byte for byte, and both formats are read. A test key's id is `TEST-` followed by the first 16 hex characters of the SHA-256 of its public key (21 characters); the key file holds the id, the public key and, for a key that can sign, the private key, with mode 600.

### 3.4 The settings and the rules

| Setting (core-site.xml only; job settings are ignored, ADR-039) | Default | Meaning |
|---|---|---|
| `attested.signature.enabled` | false | sign every record that is written |
| `attested.signature.required` | false | refuse a file whose record is not signed |
| `attested.signature.allow.test.keys` | true | accept records signed with a test key (the real key turns this off) |
| `attested.signature.test.key.file` | `~/tc-test-key/test-key.txt` of the user the JVM runs as | the test key file |

The rules: a signature that does not verify is refused whatever the settings say; a record signed by a key that is not trusted here is refused; a record signed with a test key is refused when test keys are not allowed; an unsigned record is refused only when signatures are required. Signing on without a key file, signing without records, and signing with a test key when test keys are not allowed all refuse to start. The audit log shows the result: `verify=ok sig=ok-test` on a read, `sidecar signed=<key id>` on a write, and `sign=`, `sigrequired=`, `testkeys=` and `key=` in the INIT line; our audit tools read the result with `verify=(\w+)`, so the new field cannot break them.

### 3.5 How it was built and tested

1. **In the sandbox**, against the real Hadoop 3.4.3 jars (a pack taken from the master) and at Java 11 level: the repository's own smoke test passes 141 of 141 with its own code and **167 of 167** with the change (26 new checks), the signing core passes **48 of 48** (40 runs without a failure), and deliberate breaks of the code are caught (four in the core, three in the integration).
2. **Kit 1** (`m511-test`, on the master, 15 October 07:42:09): the branch tip with the teammate's patch and ours in a scratch clone, tested with the repository's own `build-and-test.sh` and the core tests: fake mode 167 of 167, hash mode 18 of 18, **the real-HDFS mode 140 of 140 with the new code**, signing core 48 of 48 (`M511-TEST-OK`). The cluster was not touched.
3. **Kit 2** (`m511-build`, 07:56:00): the job built with ant in 36 s and compared with the job of 4.8.1: 6 classes changed, 6 are new, none unexpected (`JOB-DIFF-ONLY-THE-PATCH`); the wrapper jar `f20364cf2ba34639…` has 20 classes (14 installed now), and against the installed jar only our classes differ.
4. **Kit 3** (`m511-window`, the real cluster): the window described in section 3.7.

The rehearsals of the kits run the real scripts with the real wrapper code, over a local folder that plays HDFS where a cluster is needed. The first rehearsal found a flaky test of mine (the key id of a "wrong key" test was altered by replacing a letter that a random id sometimes does not contain); it was made deterministic before anything ran on the cluster (mistake log 102).

### 3.6 The demonstration on the real HDFS

On 15 October at 08:28:26 the demonstration wrote a file through the wrapper and then played the attacker with the plain client, which the wrapper cannot stop. Every read through the wrapper failed, with the right reason:

| Attack (behind the wrapper's back) | The wrapper's answer |
|---|---|
| 1. only the file changed | chunk 0 (hash does not match the record) |
| 2. the file and an unsigned record | the record is not signed and signatures are required |
| 3. the file and a record with the old signature copied | the signature of the record does not verify |
| 4. a record signed with the attacker's key under the real key id | the signature of the record does not verify |
| 5. a record signed with the attacker's key under its own key id | the record is signed by a key that is not trusted here |
| 6. the record deleted, the file kept | the file has no record |
| 7. a new file with no record at all | the file has no record |

The audit log held exactly 7 new `VERIFY-FAIL` lines. The honest file and its record read before the attacks and again after they were undone. An offline check of a local copy with the public key only (`M511Tools verify`: signature, chunk hashes and length) accepted the honest copy and found the forgery of attack 4.

### 3.7 The window, and what the measurement covers

Putting the signed wrapper on the cluster changes what Hadoop runs, so it was done in a **window**: the cluster reserved with `tc-busy.sh` (08:19:47), then on each node the installed jar and `core-site.xml` saved, the test key made on the master and copied to the worker, the new jar installed atomically, the measured settings plus three signature settings applied with `cluster-mode.sh` (from a state folder of its own), and the daemons restarted (master open 08:19:47, worker open 08:26:04). After the demonstration each node was restored (master close 08:29:48, worker close 08:33:32): the installed jar `027f29942fe2a69d…` and `core-site.xml` `1c335707555b2427…` are byte for byte the saved ones, the signature settings are no longer in effect, and the measured-set check printed `ALL-UNCHANGED` (9 components on the master, 6 on the worker). The window lasted 14 minutes.

**Nothing from the window is covered by the measurement** (ADR-029): the nodes were not the measured stack while it was open. The measured stack was restored and proved, so the shared client in `/opt/tc-shared` and the measurement stay consistent (ADR-045).

### 3.8 Limits and what stays open

- Signing is off by default, and an unsigned record is accepted as legacy unless signatures are required: a downgrade is accepted until the setting is on (the demonstration ran with it on).
- A status question (a file's length) reads only the record's header and does not check the signature; reading the content does.
- The signature of format `ATTEST02` does not cover the file's name or folder: a signed file and its record copied into another folder or under another name still verify with that format. Step 5.1.2 (section 4) closes this with a new record version, `ATTEST03`.
- The key is a test key, in a file readable by the cluster user on both nodes; it stays there until the combined run and must be deleted afterwards.
- No crawl ran with signing on. Step 5.1.2 changes the record format again, so one combined crawl after 5.1.2 tests signing and folder identity under a real workload; the MapReduce test of the wrapper with signing on runs in a scratch build at every stage.
- Files written by the signed wrapper have records that the measured (old) wrapper cannot read; the data of a window is test data.

### 3.9 Evidence and commits

| Item | Value |
|---|---|
| Code commit | `240df4dca` (9 files: 6 new, 3 modified), exactly the files that were built, tested and run |
| Kit commit | `efc4a730f` (17 files: the three kits under `ops/kits/m511-test`, `m511-build` and `m511-window`) |
| The patch that was tested | `2406f0d0838a6ec5…` (9 files, against branch tip `0b2a7f28e`) |
| Kit zips that ran | `m511t` `95999705…`, `m511b` `4450659a…`, `m511w` `8ad79a9d…` |
| Evidence bundle (outside the repository, `MATCH` on the laptop) | `evidence-m511.tar.gz` (`391d383e…`, 39 files): the test bundle `a746144e…`, the build bundle `7bbb0020…`, the demonstration bundle `ed9efcb4…`, the consoles of both nodes and the window folders |
| The files that ran are the files committed | the nine source files in the tree on the master that was built and run equal the source package `1c9cedc1…` (`SOURCE-IDENTICAL`) |

### 3.10 Lessons

- A test of something random must not depend on the random value's content, and such tests are run many times (mistake log 102).
- A passing fault test must be checked for passing for the right reason, and every fault variable is reset between scenarios (mistake log 103).
- When I say that I am preparing a file, I deliver it in the same reply or say that it follows (mistake log 104).


## 4. Step 5.1.2: binding every file to its folder

### 4.1 What it does

A signed record proves who signed it, not where the file lives: with `ATTEST02` a file and its record could be copied into another folder, or under another name, and still verify. Step 5.1.2 closes this. Every folder gets a small signed identity file, every record names the folder and the file it belongs to, and a read checks the whole chain up to the top folder. A file in the wrong folder, under the wrong name, or in a folder that was copied, renamed or tampered with behind the wrapper's back fails the read. Everything is off by default, like step 5.1.1.

### 4.2 The design

| Part | What it is |
|---|---|
| The identity file | a signed file `_attested-folder` in every folder that the wrapper makes or adopts: a random 16-byte folder ID, the folder's own name, and either its parent's ID (a child) or its full path (a top folder, the root of a wrapper-managed tree); signed with ECDSA P-256 under the same key as the records |
| The record `ATTEST03` | the `ATTEST02` record plus the 16-byte ID of the folder the file is in and the file's name, both covered by the signature |
| What a read checks | the record's signature, that it names this file and the ID of this folder, and every identity up to the top: each verifies, names the folder it sits in and points at the identity of its parent, and the top identity is for the folder's own full path |
| A file rename | signs one new record for the new folder and name from the old record, with no data read, after the old record's signature and binding were checked (a forged record is never signed again) |
| A folder rename | signs only the folder's own identity file again (the same folder ID, the new name and parent); the files and folders inside are untouched |
| The reserved name | `_attested-folder` cannot be created, renamed or deleted through the wrapper, and listings made through the wrapper do not show it |
| Which folders get an identity | folders made through the wrapper, and folders that the wrapper writes into (it adopts them); a folder is a top folder only when no ancestor has an identity, otherwise the unidentified folders in between are adopted as children, so the shape never depends on timing |
| Two writers at once | the first identity file written wins, and the other writer reads it |
| The cache | identity files are cached per process for the metadata cache time (10 s by default) |

| Setting (core-site.xml only; job settings are ignored, ADR-039) | Default | Meaning |
|---|---|---|
| `attested.folder.binding.enabled` | false | write records bound to folders and give folders identities; needs signing, records and hashing |
| `attested.folder.binding.required` | false | refuse a file whose record is not bound to its folder (an older format); a bound record is always checked whatever this says |

### 4.3 How it was built and tested

1. **In the sandbox**, against the real Hadoop 3.4.3 jars at Java 11 level: the smoke test passes **214 of 214** (167 of step 5.1.1 plus 47 for folder binding), the signing core **73 of 73** (25 new checks), and the demonstration tools 22 of 22. The tests include every attack of the mentor's list that moves or copies signed files, played with the plain client, and thirteen deliberate faults of the binding are caught (the folder ID, the file name, the top path, the folder's own name and the parent link are never compared; a rename that signs without checking the old record; a folder rename that does not sign again; the reserved name; binding never required; an identity signature that is not checked; and three for the race and the adoption below).
2. **Three scratch runs on the master** (the kit `m512-test`, which touches nothing on the cluster): run 1 (13:30:40) **failed** in the real-HDFS mode, which found a difference between the real HDFS and my local fake (section 4.4); run 2 (14:00:54) passed (`M512-TEST-OK`: the fake mode 214 of 214, the hash test 18 of 18, **the real-HDFS mode 212 of 212**, the signing core 73 of 73); run 3 (14:12:20) added a mode `mr-bound` that runs Hadoop's real output committer with signing and folder binding on and required, and passed **16 of 16**.
3. **The build** (`m512-build`, 14:24:43): the job `6f98295641a4f559…` (134,868,431 bytes, built in 33 s) differs from the job of step 5.1.1 in exactly 9 changed and 6 new classes with none unexpected, and the wrapper jar `ca96be26b8748125…` has 26 classes (20 in step 5.1.1) and differs from the 5.1.1 jar only in our classes.
4. **The window** (`m512-window`, the real cluster): sections 4.5 and 4.6.

### 4.4 What the real HDFS showed

The first scratch run failed in the race test (four writers making the same new folder at once), and looking into it found two things.

- **The error of the loser.** A writer that loses the race to create an identity file gets, on the real HDFS, "already being created by another client" and not "file exists", so it failed. The wrapper now looks at what is there after any failure to create and uses the winner's identity. My local fake always gave "file exists", which is why the sandbox never showed it; it now behaves like the real HDFS for a loser, with all racers trying at the same moment.
- **A design flaw, found while making that fake exact.** A late writer that found its parent folder without an identity (because another writer was still signing it) guessed that its own folder was a top folder. A top identity binds a folder to its full path, so a top folder nested in an identified tree breaks when an ancestor is renamed, which is what Hadoop's output committer does. Waiting longer would not fix a guess, so the rule is now deterministic (section 4.2).

### 4.5 The demonstration on the real HDFS

On 15 October at 15:46:12 the demonstration made a tree `seg1`, `seg2` with a file in each through the wrapper, and verified a local copy of the whole tree offline with the public key only (3 folders, 2 files). The honest operations worked: a file renamed into another folder got a record signed again for the new folder and name, and a folder rename signed only the folder's own identity file again (the same folder ID, the new name) with the record inside byte for byte unchanged. Then the attacker, with the plain client, behind the wrapper's back:

| Attack | The wrapper's answer |
|---|---|
| 1. two same-named files swapped between the two folders | both reads fail: the record belongs to another folder than the one this file is in |
| 2. a file and its record copied under another name in the same folder | the read fails: the record is for a file named 'part-r-00000', not 'copy-of-a' |
| 3. a file and its record moved into another folder | the read fails: the record belongs to another folder |
| 4. a whole folder copied elsewhere | the read fails: its identity names another folder name |
| 4b. a folder copied under another parent with the same name | the read fails: its identity points to the old parent |
| 5. another folder's identity planted in seg1 | the read fails: the identity names another folder |
| 6. the identity file deleted | the read fails: the folder has no identity |
| 7. seg1's identity signed with the attacker's key under the real key id | the read fails: the signature of the folder identity does not verify |
| 8. a folder renamed behind the wrapper's back | the read fails (its identity names the old name), and the wrapper refuses to sign that folder again when asked to rename it |
| 9. an unsigned file added to a folder | the read fails: the file has no record |
| 10. a forged record (right folder, right name, the attacker's signature) | the wrapper refuses to rename the file (it would sign the forged record again), and the read fails: the signature of the record does not verify |

That is 12 refused reads and 2 refused renames, with exactly 14 new `VERIFY-FAIL` lines in the audit log. After each attack the honest state was put back, the honest reads were logged as `verify=ok sig=ok-test bind=ok`, and the tree verified offline again at the end. The demonstration's folder was removed.

### 4.6 The window

The same method as in step 5.1.1 (ADR-045): the cluster reserved with `tc-busy.sh` (15:38:12), on each node the installed jar and `core-site.xml` saved, the new jar installed atomically and the measured settings plus five applied (signing on and required, test keys allowed, folder binding on and required) with `cluster-mode.sh`, the daemons restarted (master open 15:38:12, worker open 15:41:51; the test key of step 5.1.1 was already on both nodes). After the demonstration each node was restored (master close 15:52:15, worker close 15:56:23): the installed jar `027f29942fe2a69d…` and `core-site.xml` `1c335707555b2427…` are byte for byte the saved ones, the signature and binding settings are no longer in effect, and the measured-set check printed `ALL-UNCHANGED` (9 components on the master, 6 on the worker). **Nothing from the window is covered by the measurement** (ADR-029).

### 4.7 Limits and what stays open

- Folder binding is off by default, and a record in an older format is accepted as legacy unless `attested.folder.binding.required` is on; files of step 5.1.1 (`ATTEST02`) are unbound.
- A change made behind the wrapper's back is seen within the identity cache time (10 s by default), not at once.
- A top folder is bound to its full path: renaming a folder above a top folder through the wrapper does not sign it again.
- The identity files cannot be created atomically with the folder: a writer that crashes while writing one can leave an empty file, which fails closed.
- No crawl ran with signing and folder binding on: the combined crawl follows in a second window, and `nn_audit_compare.py` must treat `_attested-folder` like a record file before that.
- Files written by the new wrapper have records that the measured wrapper cannot read; the data of a window is test data.

### 4.8 Evidence and commits

| Item | Value |
|---|---|
| The patch that was tested | `f1904142168e8193…` (9 files, against branch head `9f4409d44`) |
| The code commit | `feat(attested): bind every file to its folder with signed folder identities and ATTEST03 records (step 5.1.2)` (9 files: 2 new, 7 modified), exactly the files that were built, tested and run |
| The kits commit | `feat(ops): add the test, build and window kits of the folder binding (step 5.1.2)` (17 files: `ops/kits/m512-test`, `m512-build`, `m512-window`) |
| Evidence bundles (outside the repository) | the three scratch runs (`88b8901b…` failed, `0f1ecf02…`, `9dbaf244…`), the build `08149b8b…`, the demonstration `5e0ff5ff…`, with the consoles of both nodes and the window folders |
| The files that ran are the files committed | the nine source files in the tree on the master equal the source package (`SOURCE-IDENTICAL`) |

### 4.9 Lessons

- When code handles an error that depends on the real system, the fake must produce the real system's errors, and a planted fault must show that the test catches the missing handling (mistake log 105 and 107).
- A structural fact (top or child) is decided by a rule that does not depend on timing; waiting longer does not fix a guess (mistake log 106).
- A planted fault that survives means a missing test: two survived in the first set of binding tests and became two tests (mistake log 108).


## 5. The combined crawl (`run14`, 15 October 2026)

### 5.1 What it is

One real crawl with the job of step 5.1.2, with signing and folder binding **on and required** on both nodes, in a reserved window, to see what happens when a real Nutch job writes through the wrapper in this mode: every file it writes, including everything that Hadoop's output committer moves between folders, must end with a signed record bound to its folder. It is the crawl command of the earlier runs with receipts on (run 12's settings), started by `m512c-run.sh` after it had checked that the window was open, the cluster reserved, the test key present, the job exactly `6f98295641a4f559…` and the policy file the verified one. Right after the crawl the script made a copy of the whole output with the plain client and verified it **offline with the public key only**.

### 5.2 What ran

| Item | Value |
|---|---|
| The window | the cluster reserved at 18:29:57, the master opened at 18:30:22, the worker at 18:33:07, the master closed at 18:58:04, the worker at 19:01:55 (about 32 minutes, `ALL-UNCHANGED` 9 and 6 after the closes) |
| The crawl | started 18:37:50, finished with exit code 0 after 770 s |
| The listings | 3,409 paths before the crawl and 3,802 after (393 added); the NameNode's audit window has 10,011 events |
| The offline verification | the seeds folder: 1 folder, 1 file, clean; the crawl output: **55 folders and 60 files, all clean**; the plain copy held 175 files (60 data files, 60 record files and 55 identity files, 1,260 KB) |

### 5.3 What the analysis found

The analysis (`m512c-analyze.sh`, in Cloud Shell, read-only) ran the standard checks with the committed tools of commit `5bedce243` and two of them replaced by the updated versions of this step (section 5.4):

| Check | Result |
|---|---|
| The audit comparison | `AUDIT-CLEAN`: 393 added, all explained by the wrapper's log |
| The expected records | `RECORDS-COMPLETE`: 61 files judged, 61 with a matching record |
| The verification summary | `VERIFY-CLEAN`: 265 opens |
| The NameNode comparison | `NN-AUDIT-COMPARE-CLEAN`, with 27 folders made with their identity file explained; the negative control (the biggest wrapper log removed) reports 108 findings, so the comparison can fail |
| Every verified read | **265 reads with `sig=ok-test` and `bind=ok`**, none with `sig=none` or `bind=none`, and no `VERIFY-FAIL` line in any audit log |
| The identity files | 57 identity files in the after listing (55 in the crawl output, the rest in other folders that the wrapper made during the run) |

**One finding:** "no task logs from the worker". It is a gap in my kit, not in the wrapper. The earlier runs' worker packs held the YARN task logs (`userlogs`) next to the wrapper logs, and version 1 of the worker script packed only the wrapper logs. They could not be added afterwards: the NodeManager deletes the old container logs when it restarts, which the window's close does; version 2 of the script, with a `repack` that adds the task logs of the applications started during the window, found none. The task logs are not part of any check of this step, so run 14 was not repeated for them; its analysis ends with this one finding, explained (limitations row 106). Version 2's `pack` takes the task logs during the window and refuses to pack without them.

### 5.4 The tools

Folder binding changes what the NameNode shows, so two analysis tools were updated and tested before the run: `nn_audit_compare.py` skips the NameNode's opens of `_attested-folder` files (like those of record files) and explains a NameNode `mkdirs` only when the wrapper's log shows the creation of the identity file in that very folder (the wrapper makes the missing folders of a file's path itself and does not log that `mkdirs`); `records_expected.py` treats an identity file as a companion of the data, not as data. Their tests pass 46 of 46 and 7 of 7, with negative controls, and planted faults are caught. The run showed the first rule at work: 27 folders explained, nothing else excused. Limitations row 99 is resolved.

### 5.5 What it does not show

- One run: no timing claim is made. Run 14 (770 s) is not a controlled pair with run 12 (709 s, a wrapped crawl) or run 13 (672 s, a plain control): different jobs and settings, and timing pairs follow the method of ADR-041 in Milestone 6.
- The signing key is a test key, and nothing from the window is covered by the measurement (ADR-029).
- The data of the run (`/user/rishabsdp17/crawl-run14` and `seeds-run14`, about 1.3 MB) stays in HDFS with `ATTEST03` records that the measured wrapper cannot read; it is readable only in a window (limitations row 107).
- The teammate's verifier has still not been run on an export of this run.

### 5.6 Evidence and commits

| Item | Value |
|---|---|
| The tools commit | `fix(ops): treat the folder identity files like record files in the analysis tools (step 5.1.2)` (4 files under `ops/attested/`, with their tests) |
| The kit commit | `feat(ops): add the combined crawl kit (run, worker and analysis scripts with their rehearsals)` (`ops/kits/m512c`, both versions of the worker script) |
| Evidence (outside the repository) | the run's folder with its fingerprints and verification results, the consoles of both nodes and of the windows, the worker pack (`0e8ed9ee…`), the repack attempt and both analyses; the two consoles of the self-test of the kit on the master |
| The files that ran | on the cluster: `m512c-run.sh` (master), `m512c-worker-v1.sh` and `audit.sh` (worker), `m512c-analyze.sh`, `nn_audit_compare.py` and `records_expected.py` (Cloud Shell, which printed the fingerprints of the two tools), `M512Tools.java` (compiled and used by the run), and the `repack` of `m512c-worker.sh` (its `pack` has not run on the cluster); they are byte for byte the files of the kits that were delivered (`ad55e910…` and `c33c9bd0…`). The three rehearsal scripts, `M512ToolsTest.java`, `M512TreeGen.java` and the two test files were run on the master afterwards, in a self-test of the final kit (`b5dc7eb3…`) on 15 October at 19:59: all six results pass (22 of 22, 46 of 46, 7 of 7 and the three rehearsals). The first self-test, at 19:47, had failed in the rehearsal of the run script, which read the master's real configuration through `HADOOP_HOME`; the rehearsal was made hermetic (mistake log 111) |

### 5.7 Lessons

- A claim about what a restart keeps must be checked before it is relied on for evidence (mistake log 109).
- A rehearsal fixture is made from what the script produces, not from the shape of an older run (mistake log 110).
- A rehearsal must be hermetic against the environment of the machine it runs on, and its first run on the real machine is a test of the test (mistake log 111).


## 6. Step 5.1.3: the real signing key (`run15`, 16 October 2026)

### 6.1 What it does

Until now the signing key was a **test key**: a file on both nodes, which anybody who could read the file could copy and use. Step 5.1.3 replaces it, for real runs, by a key that no file ever holds. On each VM a small **signing service** makes the machine's key when it starts and keeps it in memory only; it signs on request over a loopback socket and dies with its process. The hardware then vouches for the key: the service asks for a TDX quote whose `REPORTDATA` field is the SHA-512 of a short **key statement** (the key id, the public key, the host, the time and a random nonce), exactly the rule that `attest/quote.sh` and `attest/verify-binding.sh` already use. The result is a **key bundle** (the statement and the quote). A reader trusts a key only if its bundle is in its **key list** and passes the checks (ADR-047 to ADR-049).

### 6.2 The design

| Part | What it is |
|---|---|
| The signing service (`KeyService`, in the wrapper jar) | a process of its own on each VM: the key (ECDSA P-256) is made at start and never written; a loopback socket with a token; it signs only the three statement formats of the wrapper and only for its own key id, so it is not a general signing oracle; every request is logged (time, result, a short digest, never the statement or the signature) |
| The key bundle (`KeyBundle`, `*.attestkey`) | the statement and the quote; the key id is `TDX-` and 16 hex digits of the SHA-256 of the public key; a TDX key is never made without its quote; a service key without a quote (`SVC-`) exists for tests only |
| The key list (`KeyList`, `BundleCheck`) | a folder of bundles; a bundle is trusted only if the key id is the hash of the public key and the quote's `REPORTDATA` is the SHA-512 of the statement; a key without a quote is refused unless the list says otherwise; an extra check class (`attested.keys.list.check.class`) is the hook where step 5.2.1 verifies the quote's signature chain and the measurements |
| The wrapper's side (`ServiceKeys`, `AttestedKeyFactory`) | one new setting; signing goes to the service, public keys come from the list; reading needs only the list, writing needs the service and fails closed with a message that names the service |
| The key tool | `bundle-info` and `bundle-verify` |

| Setting (core-site.xml only, ADR-039) | Default | Meaning |
|---|---|---|
| `attested.keys.provider` | `test` | `test` is the test key of step 5.1.1; `service` is the real key |
| `attested.keys.service.address` | none | `HOST:PORT` of the local signing service (needed to sign) |
| `attested.keys.service.token.file` | `~/tc-keyservice/token` | the token of the service |
| `attested.keys.list.dir` | `~/tc-keys/list` | the key list |
| `attested.keys.list.allow.unquoted` | false | accept `SVC-` keys (tests only) |
| `attested.keys.list.cache.seconds` | 10 | how long the list is kept before it is read again |

### 6.3 How it was built and tested

1. **In the sandbox:** 68 core checks (bundle, service, key list, the signed formats, a restart, eight threads at once), 21 new wrapper-level checks in the smoke test (real service and list; attacks with a test key, with another machine's real key that is not in the list, and with one flipped bit; the service stopped; a restart; a key without a quote), the signing core still 73 of 73, and 18 planted faults, all caught (the first run found three blind spots in my own tests, which were fixed).
2. **On the master, in a scratch clone** (the kit `m513-test`, 08:46:09): the fake-mode smoke test **235 of 235**, Hadoop's real committer with signing and binding **16 of 16**, the hash test **18 of 18**, **the real HDFS 233 of 233** (the 212 of step 5.1.2 plus the 21 new checks), the signing core **73 of 73**, the key core **68 of 68**.
3. **The build** (`m513-build`, 08:47:30): the job `3a55e21d17c07d78…` (134,891,448 bytes, built in 34 s) differs from the job of step 5.1.2 in 4 changed and 6 new classes, none unexpected; the wrapper jar `36324a608d9d1a2c…` has 32 classes (26 before) and starts a throw-away signing service that makes a key bundle that verifies.
4. **The self-test of the window kit on the master** (11:03 to 11:05, read-only): six parts, all passing (the offline verifier and bundle extraction 11 of 11, the key exchange, the analysis, the run script, the window script and the worker script, with their planted faults).

### 6.4 The window

The cluster was reserved at 11:17:03. The master was opened at 11:17:42 and its signing service started at 11:18:43 with the key `TDX-428f3734fdb03238`; the worker was opened at 11:27:50 and its service started at 11:28:50 with the key `TDX-5fdb825500807c66`. On each VM the hardware quote is **8,000 bytes**, its `REPORTDATA` equals the SHA-512 of the key statement (our check, and `attest/verify-binding.sh` says `MATCH`), and the service answered on `127.0.0.1:7461` with its token. At 11:36:43 the two bundles were exchanged in Cloud Shell and checked there again (`M513-SYNC-OK`; a first attempt had stopped safely because Cloud Shell had no `xxd`). On the laptop, go-tdx-guest's `check` verified the Intel signature chain of **both quotes**. The master was closed at 12:11:27 and the worker at 12:14:20: each signing service was stopped (its key disappeared with it), its port closed, the measured jar and settings restored byte for byte, `ALL-UNCHANGED` 9 and 6. **Nothing from the window is covered by the measurement** (ADR-029).

### 6.5 The crawl `run15`

| Item | Value |
|---|---|
| The crawl | started 11:46:59, exit code 0 after 736 s, with signing and folder binding on and required, the keys from the signing services, test keys not allowed |
| The listings | 3,806 paths before and 4,036 after (230 added); the NameNode's audit window has 8,551 events |
| The offline verification against the key list | the seeds folder (1 file) clean; the crawl output (**55 folders and 60 files**) clean; the plain copy held 175 files (1,264 KB) |
| The keys in the output | the tree was signed by exactly **2 keys**, the master's and the worker's, both in the key list |
| The negative control | with only the master's bundle in the list, the worker's files are refused (**13 findings, not trusted here**) |
| The services | the master's signed **180** statements and the worker's **436**, neither refused any, both with a hardware quote |
| The analysis | `M513C-ANALYSIS-CLEAN`: `AUDIT-CLEAN` (230 added), `RECORDS-COMPLETE` (61 of 61), `VERIFY-CLEAN` (211 opens), `NN-AUDIT-COMPARE-CLEAN` (27 folders made with their identity), every one of the **211 verified reads with `sig=ok` and `bind=ok`**, none with a test key, no `VERIFY-FAIL`, and the worker's task logs present (671 files) |

### 6.6 What it does not show

- The signing service runs under the same user as the fetcher in this first window: the key is in no file, but a compromised fetcher could read the service's memory and could ask for signatures while the service runs (limitations row 109).
- The key list is a folder that the node trusts; the wrapper does not itself verify the quote's signature chain or the measurements (rows 110 and 111): the chain of both quotes was verified on the laptop. Step 5.2.1 builds this into the list through the hook.
- One crawl only: no timing claim (row 116).
- The data of the run (`/user/rishabsdp17/crawl-run15` and `seeds-run15`, about 1.3 MB) stays in HDFS (row 115).
- The worker script's `pack` stopped by mistake and the pack of this run was made by hand (row 114).

### 6.7 Evidence and commits

| Item | Value |
|---|---|
| The patch that was tested | `2534afa5b62423fc…` (10 files, against branch head `ee6571e6f`) |
| The code commit | `feat(attested): the real signing key: a signing service, key bundles bound to the hardware quote, and a key list (step 5.1.3)` (10 files: 7 new, 3 modified), exactly the files that were built, tested and run |
| The kits commit | `feat(ops): add the test, build and window kits of the real key (step 5.1.3)` (`ops/kits/m513-test`, `m513-build`, `m513-window`) |
| Evidence bundles (outside the repository) | the test and build on the master (`evidence-m513`, `dc5a1d93…`), the self-test of the window kit (`evidence-m513w-selftest`, `a667b5a9…`), and the window, the run, the exchange, the analysis and the laptop's quote check (`evidence-run15`, `9cd82ec0…`, 292 files) |
| The files that ran | the ten source files in the tree on the master equal the source package (`SOURCE-IDENTICAL`); the scripts that ran on the cluster are the files of the kit zips that were delivered (`m513tb` `5f45dcc4…`, `m513w` `c483f023…`); the rehearsals ran in the self-test on the master; the worker script's `pack` ran on the cluster for the first time and stopped by mistake |

### 6.8 Lessons

- A rehearsal fixture must be as large as the real thing: a check of a big archive that failed because of a broken pipe never showed on a small one (mistake log 114).
- A tool needed by a step must be checked on every machine that runs the step, not only on the nodes (mistake log 113).
- A helper used by a test must be compiled by the script that compiles the test (mistake log 112), and a script must look at the folder of the step that it belongs to (mistake log 115).


## 7. Step 5.2.1: readers accept only keys of attested machines (16 October 2026)

### 7.1 What it does

Until now the key list trusted a key when its bundle was in the folder and its quote bound the key (the quote's `REPORTDATA` is the SHA-512 of the key statement). That proves that *somebody* put that statement into a quote, not that the quote is a genuine Intel-signed TDX quote: a fake quote of the right shape passes (the control in section 7.4 shows the same list without admission trusting a key whose quote is a 632-byte fake). Step 5.2.1 closes this. The key list now runs a second check on every bundle: the quote must be a **genuine TDX quote, verified offline in Java**, and the machine's measurements must be **allowed by a reference file**. After that, how a bundle arrives no longer matters for safety: a forged or altered bundle fails the checks by itself.

### 7.2 The design

| Part | What it is |
|---|---|
| `QuoteVerifier` | reads a TDX quote (version 4, ECDSA P-256) and verifies it without any network: the certificate chain inside the quote must lead to a pinned Intel root, the PCK certificate's key must have signed the quoting enclave's report, that report must name the attestation key, and the attestation key must have signed the quote's header and body |
| `AdmissionReference` | the reference measurements: a plain text file, one line per allowed value (`REGISTER VALUE [HOST]`, with MRTD and RTMR0 to RTMR3, for one host or for any) |
| `QuoteAdmission` | the check that the key list runs on every bundle through the hook of ADR-048: a genuine quote, and every **enforced** register allowed by the reference for the host of the key's statement; registers that are not enforced are shown in the audit and decide nothing |
| The key list's audit | each admission (with the registers that were checked) and each rejection (with its reason) is written once to a file next to the list, so that a rejection is never silent |
| The key tool | `quote-info` prints the registers of a bundle's quote, and `bundle-admit` admits a bundle against a reference |

### 7.3 The decisions, and how to change each one

Every decision is a setting in core-site.xml or a line of the reference file, so that the mentor can ask for a change and it is one edit (ADR-050 to ADR-052). Each row is shown to flip by a test.

| Decision (default) | How to change it |
|---|---|
| Admission is off (`attested.keys.admission.enabled` false) | set it to true and give `attested.keys.admission.reference.file` |
| Which registers must match (`attested.keys.admission.enforce` = `mrtd,rtmr0,rtmr1,rtmr2`) | change the list, for example add `rtmr3` once the reference has RTMR3 lines, or remove `rtmr1` |
| What values are allowed | add or delete lines of the reference file; a line can name a host |
| The trusted Intel root (`attested.keys.admission.root.sha256` = the SGX Root CA) | give another SHA-256, or several separated by commas |
| Certificate dates (`attested.keys.admission.check.dates` true) | set it to false |
| Locking the reference file (`attested.keys.admission.reference.sha256`, unset) | give the file's SHA-256; the wrapper then refuses to start if the file changed |
| RTMR3 is shown, not enforced | add the RTMR3 lines to the reference and put `rtmr3` into the enforce setting; without the lines it fails closed, with the reason |

### 7.4 How it was built and tested

1. **In the sandbox:** 73 admission checks with **two real quotes of run 15 as test vectors**: both verify; one flipped bit in every part of a quote is found (the quote's signature, the header, MRTD, RTMR3, the attestation key, the quoting enclave's report, its signature and authentication data, and each certificate); a chain without a root, another machine's chain, certificate dates before and after validity, a wrong version, an SGX quote, a bad length, and a changed attestation key are refused; the reference file's errors are reported with line numbers; every decision of section 7.3 is shown to flip with one edit. **21 planted faults in the new code, all caught** (the first run left one survivor, the date setting, which was closed by a settable clock and two checks). The smoke test in fake mode passes **239 of 239** (4 new wrapper checks: with admission on, a key whose quote has no Intel chain is not trusted, even by its own writer; the control without admission trusts it), and the signing core (73 of 73) and the key core (68 of 68) are unchanged.
2. **On the master, in a scratch clone** (the kit `m521-test`, 13:57:41): the fake-mode smoke test **239 of 239**, Hadoop's real committer with signing and binding **16 of 16**, the hash test **18 of 18**, **the real HDFS 237 of 237** (the 233 of step 5.1.3 plus the 4 new checks), the signing core **73 of 73**, the key core **68 of 68**, the admission core **73 of 73**.
3. **The build** (`m521-build`, 13:59:10): the job `8f21a37f933ee2ca…` (134,909,332 bytes, built in 34 s) differs from the job of step 5.1.3 in 4 changed and 5 new classes, none unexpected; the wrapper jar `ef611d1260b3b427…` has 37 classes (32 before), and the built jar admits a real bundle of run 15.
4. **The real-data check** (`m521-realdata`, 13:59:59, read-only, on the files of run 15 that are on the master): both real keys are admitted by their quotes; the **whole run-15 output verifies with only admitted keys** (the seeds folder, and the crawl output of 55 folders and 60 files); each decision flips with one edit; a quote changed by one bit of MRTD is refused.

### 7.5 What the real quotes showed

Both quotes are version 4 TDX quotes (tee type 0x81, ECDSA P-256) of 8,000 bytes, of which 4,935 are the quote and the rest is zero padding. Each carries a chain of three certificates: the PCK certificate of the physical processor, Intel's SGX PCK Platform CA, and Intel's SGX Root CA (valid until 2049), whose SHA-256 fingerprint is pinned in the code as the default. **MRTD is the same on the two machines** (`c1ee9c16e3af…`), RTMR0 to RTMR2 differ per machine (`036d0bf4b669…` and `5e276dcf6867…` for RTMR0), and RTMR3 differs. These are the values already documented for these machines.

### 7.6 What it does not show

- **Revocation lists, the TCB status and the quoting enclave's identity** need Intel's online collateral and are not checked offline; go-tdx-guest's `check` with the collateral on the laptop remains the second opinion (limitations row 117).
- **The reference records what these two machines reported.** The firmware is the cloud provider's, so the file is a record, not an independent reference (row 118).
- **RTMR3 is shown, not enforced:** the measured stack is therefore not yet proved by the quote (row 119).
- **At the time of section 7 the admission had run on the real machines only offline**; the live window of section 8 followed, and its file operations ran through the master's wrapper only (row 121).
- The same-user limits of section 6.6 stay.

### 7.7 Evidence and commits

| Item | Value |
|---|---|
| The patch that was tested | `26469ac65ba3a1c4…` (12 files, against branch head `6051b375c`) |
| The code commit | `feat(attested): admit keys by their quote: an offline TDX quote verifier, a reference file and an admission check for the key list (step 5.2.1)` (12 files: 7 new, 5 modified; two of the new files are the real bundles of run 15, used as test vectors) |
| The kits commit | `feat(ops): add the test, build and real-data kits of the quote admission (step 5.2.1)` (`ops/kits/m521-test`, `m521-build`) |
| Evidence bundle (outside the repository) | `evidence-m521` (`8b7a034a…`, 9 files): the three consoles, the two bundles of the scratch runs, the real-data results, both zips, and the check that the twelve source files of the tree that ran equal the source package (`SOURCE-IDENTICAL`) |
| The files that ran | the scripts that ran on the master are the files of the kit zip that was delivered (`m521tb` `1be67c3b…`) |

### 7.8 Lessons

- A script that counts files must list them one by one: `git status` collapses a new folder into one line, and the rehearsal found that 22 had been counted instead of 23 (mistake log 117).
- A setting is not tested until a test can see it change something: the date setting survived the first planted faults because the clock was not settable (mistake log 118).
- A tool check in a non-interactive ssh command does not see the path of a login session; the real session was fine (mistake log 119).


## 8. Step 5.2.1, the live window (16 October 2026)

### 8.1 What it showed

Section 7 proved the admission on real quotes and real data, offline. This window proved it **live**: the wrapper with the admission switched on ran on both real VMs, with keys and hardware quotes that did not exist an hour earlier. Each node's own key was admitted by its fresh quote before anything restarted; a real file was written and read back through the wrapper; and a rogue signing service with a fake quote, which puts its bundle into the live key list, was refused with its reason. This is the rule that the step exists for: a key whose quote is not a genuine Intel-signed TDX quote is not trusted.

### 8.2 The window

| Time (UTC) | What |
|---|---|
| 15:29:13 to 15:31:02 | the self-test of the window kit on the master (nothing on the cluster is touched): the window script rehearsal 47 checks, the live script rehearsal 22, the key list exchange rehearsal 16, both real bundles of run 15 admitted by the built jar, 21 of 21 files identical to the list |
| 15:32:45 | the master's window opened with 13 settings (the ten of step 5.1.3 plus the admission on, the reference file, and the SHA-256 of that file, all final); the reference file (7 values, SHA-256 `03965e5af0a199c1…`) was put in place and pinned |
| 15:33:47 | the master's signing service started with the key `TDX-d98a94e537f5282b`; its quote (8,000 bytes) binds the key (our check and `verify-binding.sh` say `MATCH`), and **the node's own bundle was admitted by its fresh live quote** before the daemons restarted |
| 15:35:37 and 15:36:36 | the worker's window opened and its service started with the key `TDX-775de83fe87625ad`, admitted the same way |
| 15:39:43 | the two bundles were exchanged in Cloud Shell (`M513-SYNC-OK`); a first attempt had stopped safely because Cloud Shell had lost `xxd` |
| laptop | go-tdx-guest's `check` verified the Intel signature chain of both fresh quotes |
| 15:42:22 | the live check (section 8.3) |
| 15:43:58 and 15:47:12 | the master and the worker were closed: each signing service stopped (its key disappeared with it), the measured jar and settings restored byte for byte, `ALL-UNCHANGED` 9 and 6; the reservation was released after both closes |

**Nothing from the window is covered by the measurement** (ADR-029).

### 8.3 The live check

| Check | Result |
|---|---|
| A real file through the wrapper with the admission on | a 20 KB file was written into `/user/rishabsdp17/adm-run16` and read back byte for byte |
| The key list's audit | an `ADMIT` line for each key of the window, with the registers that were compared: MRTD `c1ee9c16e3af`, RTMR0 `036d0bf4b669` for the master and `5e276dcf6867` for the worker, RTMR3 shown only |
| The new folder, copied with the plain client | verifies offline with only admitted keys (1 folder, 1 file; the live key list held 4 keys, all admitted: run 15's two and this window's two) |
| **A rogue key with a fake quote** | a signing service `TDX-31c4d7d14d16cc13` put its bundle into the live key list; the list **refused it and wrote why** (the quote is too short, 632 bytes), the honest file still read, `bundle-admit` refused it too, and the rogue bundle and service were removed |
| One edit flips the decision on this node's own live quote | an edited reference refused it (the reason names MRTD), taking `mrtd` out of the enforce list admitted it again, and one flipped bit in MRTD of the live quote was refused |

### 8.4 What it does not show

- The file operations of the live check ran through the **master's** wrapper; the worker's own wrapper reading with the admission on, and a MapReduce job with the admission on, were not exercised in this window (limitations row 121).
- One real file of 20 KB; no timing claim.
- The checks that need Intel's online collateral, the reference being a record of what the machines reported, and RTMR3 not being enforced are unchanged (rows 117 to 119).
- A signing service that cannot bind its port has already written its bundle into the key list (row 123), and the live script printed a harmless shell message about an audit file that did not exist yet (row 124).

### 8.5 Evidence and commits

| Item | Value |
|---|---|
| Evidence bundle (outside the repository) | `evidence-m521w` (`a474181e…`, 85 files): the consoles of the self-test, both opens, the exchange (with the stopped first attempt), the live check and both closes, the window folders of both nodes (bundles, quotes, audit logs, settings), the key list's audit log, the live results, the laptop's quote check, and the kit zip |
| The kit | `m521w` (`5cfd9dfd…`, 21 files), committed as it ran under `ops/kits/m521-window` |
| The kit commit | `feat(ops): add the window kit of the live quote admission (step 5.2.1)` (20 files under `ops/kits/m521-window`) |
| The dry-run commit | `feat(ops): add a dry run for the gate scripts that checks every source file and fingerprint without PowerShell` (`ops/attested/gate_dryrun.py`: it resolves every source file of a gate the way the gate does, and compares fingerprints) |
| The documents | the facts list of this window, this section, and the limitations, plan, configuration and lessons |

### 8.6 Lessons

- The facts of a step must be tested against the consoles as they really are, verbatim: a stand-in more generous than the real console hid a failing fact (mistake log 120).
- A delivery script that cannot be run where it is made needs a faithful dry run: the gate's row without its `zip:` prefix could not be caught by counting braces (mistake log 121).
- A tool that a step needs must be in the runbook as a command, not only in the mistake log: Cloud Shell forgets installs (mistake log 122).
- A rehearsal's whole output must be read, not only its last line (mistake log 123), and every upload the runbook needs is its own item (mistake log 124).


## 9. Step 5.2.2: the doorman of the mesh (17 October 2026)

### 9.1 What it does

In Milestone 2 the mesh authenticated its peers by static WireGuard keys that an operator script wrote into the configuration: nothing connected a node's mesh key to its hardware, so a copied key would have been let in. Step 5.2.2 puts a **doorman** in front of the mesh. A node is admitted only if a hardware quote, made just now, binds **its WireGuard public key and the mesh address it asks for** to the machine, the quote is a genuine Intel-signed TDX quote, its measurements are in the reference file of step 5.2.1, the host and the address are in a policy table, and the statement is fresh. Nothing on the network changes before the decision, and a refused node never becomes a peer.

### 9.2 The design

| Part | What it is |
|---|---|
| `node-attest.sh` (on a node) | reads the node's WireGuard public key (the folder `/etc/wireguard` is root only, so with sudo) and checks it against the key of the running interface; asks the TDX guest for a quote whose REPORTDATA is the SHA-512 of a statement (host, WireGuard public key, requested mesh address, time, random nonce); writes a node bundle (the statement and the quote) |
| `NodeBundle` | the strict parser of that bundle and the check of the binding (the quote's REPORTDATA is the SHA-512 of the statement) |
| `MeshPolicy` | the policy table, a plain text file with one line per host: `HOST MESH_IP [VPC_IP]`; the address is decided by the table, not by the node |
| `MeshAdmission` | the doorman's decision, in this order: the binding, the policy table, freshness (900 s, clock skew 60 s), and then the genuine-quote and reference check of step 5.2.1; and a roster that admits a host or a mesh key once only |
| The key tool | `node-admit` (one bundle) and `node-admit-all` (several; writes the table of admitted nodes) |
| `mesh-admit.sh` (in Cloud Shell) | `admit` asks each host of the table for a fresh bundle and lets the doorman decide (optionally with a rogue node added), `build` brings the test mesh up with exactly the admitted peers and proves it, `down` takes it down |
| `wg1-node-up.sh` and `wg1-node-down.sh` (on the nodes) | bring the test interface `wg1` up (the node's own attested key, its table address as /24, UDP port 51821) and down |

### 9.3 The decisions, and how to change each one

Each decision is a line of a file, an option or a variable, so that the mentor can ask for a change and it is one edit (ADR-053 to ADR-055).

| Decision (default) | How to change it |
|---|---|
| Who may join, at which address | edit the policy table `ops/attested/mesh-peers-m522.txt` (one line per host) |
| How old a statement may be (900 s) | set `MA_MAX_AGE` when running `mesh-admit.sh`, or `--max-age` with the key tool |
| Allowed clock skew (60 s) | `--skew` through `MA_OPTS` |
| What the quote must show | the same reference file, enforce list, root and date options as step 5.2.1 (`--enforce`, `--root`, `--no-dates` through `MA_OPTS`; the lines of the reference file) |
| The test mesh's UDP port (51821) | the variable `PORT` at the top of `wg1-node-up.sh` |
| The first proof on a test mesh, not on production | the same scripts with another interface name would adopt the doorman for the production mesh `wg0`; that is not done and is the mentor's decision |

### 9.4 How it was built and tested

1. **In the sandbox:** 62 node core checks with **two real node bundles as test vectors**: both are admitted; a swapped mesh key, a changed address, host or time, a flipped REPORTDATA bit, and a flipped MRTD bit are refused; the freshness boundaries are exact (900 s admitted, 901 s refused, skew); the policy table and its errors; the reference and root edits flip the decision; the parser is strict; a host or a mesh key is admitted once only; and **a rogue node with a fake quote is refused by the quote check alone** (it passes the binding, the policy and the freshness, and the test shows that it would be admitted if the quote check were removed). **25 planted faults in the new code were all caught.** The rehearsal of the scripts (29 checks, 15 faults, with fake nodes that can misbehave) shows that a rogue node never becomes a peer and that every proof of the build can fail; the capture script rehearses with 18 checks and 10 faults.
2. **On the master, in a scratch clone** (the kit `m522-test`, 09:25:31): the fake-mode smoke test **239 of 239**, Hadoop's real committer **16 of 16**, the hash test **18 of 18**, **the real HDFS 237 of 237**, the signing core **73 of 73**, the key core **68 of 68**, the admission core **73 of 73**, the node core **62 of 62**.
3. **The build** (`m522-build`, 09:27:01): the job `ff73a7c281ac5299…` (134,921,739 bytes, built in 33 s) differs from the job of step 5.2.1 in 2 changed and 6 new classes, none unexpected; the wrapper jar `77bbdda0a2b57028…` has 43 classes (37 before); and the built jar's doorman admits the two real node bundles.

### 9.5 The runs on the real machines

**The capture** (no change to the cluster): on each node the script read the real WireGuard public key (the key file equals the key of the running `wg0`) and asked the hardware for a quote that binds it. The statements are dated 08:14:27 (master, host `tdx-lab`, address 10.20.0.1) and 08:14:50 (worker, `tdx-lab-worker`, 10.20.0.2); each quote is 8,000 bytes and its REPORTDATA equals the SHA-512 of its statement; go-tdx-guest's `check` verified the Intel signature chain of both quotes on the laptop. These two bundles are the test vectors of the tests above, and their registers equal the reference file that was made from the run-15 quotes a day earlier.

**The test mesh run** (not a window: no jar, daemon or setting changed): after the check that the measured stack was unchanged, `admit` at 10:01:17 made a fresh bundle on each node and the doorman **admitted both nodes and refused a rogue node** (`the quote is too short (632 bytes)`), and only it; `build` at 10:02:04 brought `wg1` up on both nodes with exactly the admitted peers on their own attested keys: **the key that `wg1` runs is the key that the quote attested**, the peers are exactly the admitted ones, each node reaches the other (3 of 3 packets), the peers have handshaken, and **`wg0` is untouched**; `down` at 10:05:05 removed `wg1`. Afterwards `wg0` still had its peer, `wg1` was gone, and the measured stack was `ALL-UNCHANGED` (9 components on the master, 6 on the worker). On the laptop go-tdx-guest's `check` verified the Intel signature chain of the two fresh quotes. The Google firewall already allows UDP between the two machines (`default-allow-internal`).

**A false alarm that I caused:** before the run, my check of the measured stack said `SOMETHING-CHANGED` on the master. The check's default Nutch folder is `~/ccbot-work/nutch-cc`, while the baseline log of the master records the patched tree `~/m481/patched`, which every window passes as `NUTCH_DIR`; I had left that out of my command. With it, the master was `ALL-UNCHANGED` (9 components). Nothing had changed (mistake log 128).

### 9.6 What it does not show

- **The operator is the trust root:** `mesh-admit.sh` runs in Cloud Shell and applies the decision (limitations row 125).
- **The WireGuard private key is on the node's disk**, in a root-only folder; the quote proves that a genuine measured machine presented the public key, not that the private key never left it (row 126).
- **The decision is made once**, at the admission; there is no re-check and no automatic revocation (row 127).
- **The production mesh `wg0` was not rebuilt through the doorman**; the run showed that the keys it trusts are the attested ones as of 17 October (row 128).
- A genuine statement can be replayed within its 900 seconds, which only re-admits the same key (row 129).
- A real machine with other measurements was not available, so that refusal is shown with an edited reference only (row 130).

### 9.7 Evidence and commits

| Item | Value |
|---|---|
| The patch that was tested | `de76947096641cc6…` (9 files, against branch head `7ff9a2d84`) |
| The code commit | `feat(attested): the doorman of the mesh: a node bundle, a policy table and an admission by quote (step 5.2.2)` (9 files: 7 new, 2 modified; two of the new files are the real node bundles used as test vectors) |
| The kits commit | `feat(ops): add the capture, test, build and window kits of the mesh doorman (step 5.2.2)` (`ops/kits/m522-capture`, `m522-test`, `m522-build`, `m522-window`) |
| Evidence bundles (outside the repository) | `evidence-m522c` (`7c95bcb8…`, 13 files: the capture), `evidence-m522` (`a849b3f6…`, 7 files: the test and the build, with `SOURCE-IDENTICAL` for the nine source files), and `evidence-m522w` (`39694aff…`, 26 files: the test mesh run, the firewall rules, the checks of the measured stack, the quote check on the laptop) |
| The files that ran | the scripts that ran are the files of the kit zips that were delivered: `m522c` `3568765a…`, `m522tb` `56268956…`, `m522w` `813e2c16…` |

### 9.8 Lessons

- A folder's mode matters even when the file inside is world-readable: `/etc/wireguard` is root only, and my first capture stopped on both nodes (mistake log 125).
- `gcloud compute scp` cannot take sources from two machines in one command (mistake log 126).
- `ssh` and `scp` read the standard input, so inside a loop they swallow its list; a stand-in that does not do this hides the bug, and making the stand-in reproduce it proved the fix (mistake log 127).
- The command that I give for a check must set what the real script sets (mistake log 128).
- A rehearsal that passes at once is checked for weak checks; this one had a mislabelled check, a planted fault outside the patch, a date clash with its fixed clock, and a full sandbox disk (mistake log 129).


## 10. Steps F0.1 and F0.2: the first half of the locked image (19 October 2026)

### 10.1 What it does, in plain words

Today a normal reboot of our nodes returns to kernel 6.8, and an operator has to run the measurement by hand. The image now does both by itself. Kernel 6.17 is the **permanent default**, and at every boot a unit, `tc-measure.service`, hashes a fixed list of files into the hardware register RTMR3, one event per line (`tc-lib`, `tc-conf`, `tc-units`, `openssl`, `wg`), before anything that requires it can start, and it keeps the log of those events. A hardware quote then vouches for the register, and anyone can replay the log and get the same value. If the files are the same, the register is the same at every boot; if one file changes, only its event and the register change. The unit refuses to run unless RTMR3 is zero, and it stops if a listed path is missing. The sources are in `ops/image/`, which takes over from `ops/rebuild/` at step F5.

### 10.2 What it replaces, and why

| New step | Replaces (legacy) | Why |
|---|---|---|
| F0.1 | The one-time boot into 6.17 and the manual measurement of Milestone 1 (`ops/worker-kernel-prep.sh`, `attest/measure/`; ADR-003, ADR-010) | A normal boot returned to kernel 6.8, and RTMR3 was extended by a script that an operator ran |
| F0.2 | The manual `measure-all.sh` runs, and the re-measure after a reboot (step 4.8.2, ADR-040) | The measurement is part of the boot, with no operator command |

### 10.3 How it was tested

On a disposable TDX VM, `tc-f01-test`: `c3-standard-4`, a 30 GB boot disk and no service account, made from the Ubuntu 22.04 image that the two nodes were made from (`ubuntu-2204-jammy-v20260918`, which Google has marked deprecated; a deprecated image can still be used to create VMs). It was driven from Cloud Shell by `ops/image/test/f01-drive.sh`: create, ship the kit, prepare (the kernel as the default, the unit, the automatic upgrades stopped; at 11:04 UTC), and then four boots: a plain reboot, a second plain reboot, a deliberate change of one measured file, and its undo. A stand-in unit, `tc-placeholder.service`, stands in for the Hadoop daemons to prove the order. The VM was deleted afterwards. Before the run the scripts passed a rehearsal with stand-ins (69 checks, every fault made on purpose).

### 10.4 The result

| Boot | When (UTC) | What happened | RTMR3 | The measurement finished at / the stand-in daemons started at (µs) |
|---|---|---|---|---|
| 1 | 11:08:25 | the first plain reboot after the preparation | `e4af2ef040d51e12` | 8916948 / 9971215 |
| 2 | 11:13:58 | a second plain reboot | `e4af2ef040d51e12` | 8572481 / 8635841 |
| 3 | 11:17:00 | one measured file changed on purpose (`tc-extend.sh`) | `1c00ccdcd8f15560` | 7707538 / 9648483 |
| 4 | 11:18:26 | the change undone | `e4af2ef040d51e12` | 7484801 / 8612271 |

Every check passed on every boot: kernel 6.17 running, the saved (permanent) default is 6.17 with no one-time entry, RTMR3 is not zero, the unit is active with the result `success`, the measurement finished before the stand-in daemons started, the event log's chain is consistent and replays to the register, and a hardware quote carries the same RTMR3 and a REPORTDATA that is the SHA-512 of the log. The comparisons of the logs say: boots 1 and 2, the same (reproducible); boots 1 and 3, only the event `tc-lib` differs and the final RTMR3 differs; boots 1 and 4, the same again. The events, in order, are: events: tc-lib, tc-conf, tc-units, openssl, wg.

The four quotes carry MRTD `c1ee9c16e3af`, RTMR0 `036d0bf4b669`, RTMR1 `6ac1fe7b106a`, RTMR2 `e3b0a9f3fe26` on every boot, so only RTMR3 moves, as designed; and the Intel signature chain of all four quotes verified on the laptop with go-tdx-guest's `check`. MRTD is the same as on our two nodes. RTMR0 equals the master's (`036d0bf4b669`) and not the worker's (`5e276dcf6867`). RTMR1 and RTMR2 differ from both nodes, which differ from each other (RTMR1 `05718f1d5381` on the master and `b8837821022e` on the worker, at kernel 6.17).

### 10.5 What it shows, and what it does not

It shows the pass conditions of F0.1 and F0.2 of the mentor's note: after a plain reboot RTMR3 is non-zero and matches a replay of the event log, and the unit's log shows that it finished before the (stand-in) daemons started. It does not show:

- **The unit is measured by itself.** The measurement unit and its scripts are not measured by an earlier stage: someone who can write to the disk between boots could change them to report chosen digests. Closing that needs a read-only root with dm-verity or a measured initramfs, which is asked of the mentor (limitations rows 131 and 137).
- **The real daemons.** The test used a stand-in for Hadoop, one disposable VM and a deprecated base image. Step F0.3 builds the real image from the current Ubuntu 22.04 image and repeats these checks; the keys and `fleet.tsv` come with step F1 (row 139).
- **Whether RTMR1 and RTMR2 are shared by VMs made from one image.** The nodes already differ from each other and from the test VM, and a plausible cause is the kernel command line, which contains the disk's `PARTUUID`; this is a hypothesis. F0.3 tests it with two VMs made from one image. The consumer's verifier records the registers and does not enforce them (ADR-057), so nothing blocks on it (row 138).
- **A slip in the first console.** The check of boot 1 printed "(6 events)" for a log of 5, because its pattern also counted the replay tool's summary line; the journal line of the same console says `events=5`, and the check was fixed for boots 2 to 4 (mistake log 134).

### 10.6 Evidence and commits

| Item | Value |
|---|---|
| Evidence bundle (outside the repository) | `evidence-f01`, `d3b42e06…`, 44 files: the consoles of the creation, the preparation, the four checks and the comparisons; the events and the quote of each boot; `quote-registers.txt` (the registers of the four quotes); `quote-check-f01-laptop.txt` (the signature check on the laptop); and the three versions of the kit zip |
| The code commit | `f0b2c95be` `feat(image): the default 6.17 kernel and the boot-time RTMR3 measurement of the fixed-fleet image (steps F0.1 and F0.2)` (12 files: 11 new under `ops/image/` and one exception line in `.gitignore`, because its rule `build/` hides the folder `ops/image/build/`) |
| Which version of the kit ran what | `e78fc874…` was the first (the preparation stopped at its package-job guard, and the VM was untouched); `8e6e4071…` ran the preparation and boot 1; `6a8f3222…` ran boots 2 to 4 and is the committed version. The preparation and the measured files are identical in all three; the check script differs by the pattern that counts events |

### 10.7 Lessons

Six mistakes of mine, each with its lesson, are in the mistake log (rows 133 to 138) and in the guide's rule 39: a guard that matched a daemon that always runs, a pattern that counted a summary line, a pattern that accepted `NO MATCH`, a folder name that `.gitignore` hides, a runbook block that needed a file that did not exist yet, and flaws of my rehearsal and generators.


## 11. The F0 recon: what the cluster nodes look like today (17 October 2026)

### 11.1 What it is, in plain words

Before locking a house you list every door, window and key. This is that list for our two nodes: what can log in, what listens, what runs, what is writable, and what the kernel offers for integrity. It is the "before" picture for steps F0.4 (remove login) and F0.5 (close the doors), and it is the reason why those steps remove things and do not configure them. It is a snapshot of 17 October 2026 and it changes nothing: the two scripts that made it only read, print no key (key files are only counted), refuse to overwrite their output and delete it if anything key-like got in (`ops/image/recon/`).

### 11.2 How it was made

Two scripts ran on both nodes on 17 October: the first at 14:03 UTC (the master at 14:03:35, the worker at 14:03:43) and the second at 14:38 UTC (14:38:54 and 14:39:07). The first ran without root, so it could not see other accounts' key files or the firewall; it counted keys only for the account that ran it. The second ran with `sudo` and read what the first could not: the firewall rules, `fstab`, every unit enabled at boot, the key count of every account, OS Login, and the names (never the values) of the metadata. The Google facts of the master and its boot disk come from read-only `gcloud` calls.

### 11.3 What the nodes show, and what the locked image does about it

| Area | What the nodes show | What the locked image does |
|---|---|---|
| Kernel and boot | Ubuntu 22.04.5 and kernel 6.17.0-1022-gcp on both, reached by a one-time boot; the kernel command line says `ro` while the root file system is mounted `rw`; Secure Boot is off and the virtual TPM is on | F0.1 (done): 6.17 is the permanent default |
| Who can log in | Five accounts with a login shell (`root`, `ubuntu`, `dev` and two personal accounts). **Four are in a root group**: `ubuntu` in `sudo`, and `dev` and the two personal accounts in `google-sudoers`; all four are also in `lxd`. **Three hold an ssh key**: `dev` 1, a personal account 1, and the other personal account 2 on the master and 1 on the worker; `ubuntu` and `root` have none | F0.4: no login at all |
| The doors | `sshd` on port 22 (keys only: no passwords), `getty` on tty1 and `serial-getty` on the serial console, the Google guest agent and the OS-config agent running, `google-startup-scripts` and `cloud-init` enabled. The project's metadata has `ssh-keys` and OS Login is not used, so the guest agent makes the accounts from the project's keys | F0.4: no sshd, no serial login, no guest agent, no startup scripts |
| The service account | The default Compute Engine service account, with scopes for storage read, logging, monitoring, Pub/Sub, service management, service control and trace; the firewall accepts the metadata server | F0.4: none (the test VM of F0.1 and F0.2 already had none) |
| What listens | Master: port 22 and the NameNode's web port 9870 on all interfaces, the YARN and HDFS ports on the mesh address 10.10.0.1 only. Worker: the DataNode and NodeManager ports (13562, 42049, 8040, 8042, 9864, 9866, 9867) on all interfaces | F0.5: every daemon bound to `wg0` only, and WebHDFS off |
| The firewall | INPUT policy DROP; accepted: loopback, established connections, `wg0`, UDP 51820, TCP 22, ICMP and the metadata server; an explicit DROP of the Hadoop ports that counted 0 packets, on both nodes | F0.5; the rules are not saved across a reboot (section 2 of the plan), and they are the only thing that closes the ports above |
| Writable and changeable | The root file system is ext4 `rw` (50 GB on the master, 10 GB on the worker) with no separate `/tmp`; automatic upgrades, `snapd` and `packagekit` run; 89 unit files are enabled; 791 packages on the master and 722 on the worker, with `gcc` and `make` on the master only, and `curl`, `wget`, `nc`, `perl`, `python3`, `vim`, `git` and `tmux` on both | F0.3 and F0.4: a minimal image with no upgrades |
| How Hadoop runs | Under a person's account, started by hand: no unit and no crontab entry; its data is under that account's home (`hadoop-data`) | F0.3: a system account and systemd units |
| What the kernel offers | dm-verity (as a module) with root-hash signature checks, squashfs, overlayfs (as a module), IMA with appraisal, module signing, and the lockdown module present with the state `[none]` | asked of the mentor (dm-verity, limitations row 137) |
| What the quote covers | 9 events on the master and 6 on the worker, measured by hand in a window | F0.2 (done): a boot unit, 5 events so far |

The machines are `c3-standard-4` TDX VMs on Intel Sapphire Rapids, made from the Ubuntu 22.04 image `ubuntu-2204-jammy-v20260918`, with a `pd-balanced` boot disk.

### 11.4 What it means, and what it does not show

- **Every way in is a thing to remove,** not a setting to change: the login paths, the agents, the startup scripts, the accounts in root groups, the service account and the upgrade jobs. That is how steps F0.3 to F0.5 are written.
- **The firewall is the only closure today.** The Hadoop daemons listen on all interfaces and rely on a firewall whose rules are not saved across a reboot; F0.5 binds them to `wg0`.
- **A correction.** Earlier messages said that three accounts have root. The files show **four accounts in a root group, three of them with an ssh key**.
- **One unexplained difference:** one personal account has 2 keys on the master and 1 on the worker.
- **It does not show** whether the firewall rules return after a reboot (the unit list has no unit for them, but the check did not look for a persistence package), who may edit the project's metadata (an IAM question outside the nodes), or anything about the two measured stacks other than their event names.

### 11.5 Evidence and commits

| Item | Value |
|---|---|
| Evidence bundles (outside the repository) | `evidence-m523i` (`172145a7…`: the first inventory of both nodes, and the Google facts of the master and its disk) and `evidence-m523j` (`28985bd1…`: the second inventory of both nodes and the project's metadata names) |
| The code commit | `4659a07f0` `feat(image): add the read-only inventory scripts of the F0 recon (they ran on the two nodes on 17 October 2026)` (7 files under `ops/image/recon/`) |
| The kits that ran | `m523i` `4b7ee59d…` and `m523j` `d6581efe…`, identical to the committed scripts |

### 11.6 Lessons

The first inventory could not see the other accounts' keys or the firewall because it ran without root, which I noticed only by reading its output before using it (mistake log 139); its key counter prints `0` twice for an empty file (mistake log 140); and I counted the accounts with root from a summary instead of from the file (mistake log 141).


## 12. Step F0.3a: the software layer of the image (19 October 2026)

### 12.1 What it does, in plain words

An image is the disk copy from which every VM starts. Until now ours held the operating system and the measurement of step F0.2, and a person installed Hadoop by hand afterwards. Now the image is delivered like a kitchen that is fully fitted and switched on. JDK 11 and Hadoop 3.4.3 sit in a folder that belongs to `root`, so the program that runs Hadoop cannot rewrite its own code. A service user called `hadoop`, which cannot log in, owns only the data and log folders. Four systemd units start the NameNode, the DataNode, the ResourceManager and the NodeManager at boot, and each one **requires** the measurement of step F0.2 and **follows** it: if the measurement fails, Hadoop does not start. The measured list grew from 5 items to 10: the JDK, its settings, its list of trusted certificate authorities, Hadoop's code and Hadoop's configuration were added. This part is a single node: everything runs on one VM, on the loopback address. The two-node run needs the keys and the fleet list (steps F1 and F2). The sources are in `ops/image/` (commit `139bfb81f`).

### 12.2 What it replaces, and why

| New | Replaces (legacy) | Why |
|---|---|---|
| The JDK and Hadoop in root-owned system folders, a non-login service user and units | The rebuild stages `base` and `hadoop` (a person's home folder, daemons started by hand) | Nothing may sit in a person's home or depend on a person's commands, or the measured stack is not the running one |
| A measured list of 10 items, read at boot | The by-hand measurement of the JDK and Hadoop in Milestone 1 (`attest/measure/`) | The measurement is part of the boot, so every VM of the image reports the same thing |
| A cleaning script that removes the builder's identity and data before its disk becomes an image | nothing (new) | Without it every VM would share a machine id, ssh host keys, and the builder's HDFS |

The decision is ADR-062.

### 12.3 How it was built and tested

A disposable TDX VM, the builder, was made from the current Ubuntu 22.04 image (kernel 6.8.0-1070-gcp). Three scripts ran on it: the preparation of F0.1 and F0.2 (6.17 as the default kernel and the measurement unit), the bake (the software layer) and the cleaning. Its disk then became an image, and test VMs made from the image were checked after each boot by `ops/image/test/f03a-check.sh`. Two images were made. The first, `tc-img-f03a-1`, failed its second boot (section 12.4). The second, `tc-img-f03a-2`, passed everything (section 12.5) and is kept for the next step; the first and the test VMs were deleted. The scripts also passed a rehearsal with stand-ins before the first run (72 checks for the bake, the cleaning, the check and the registers tool, and 7 for the driver; every fault was made on purpose), but the stand-ins could not show how systemd really behaves, which is why the real second boot is part of the plan.

The Hadoop tarball (491 MB) is the part that went wrong first: the first server, `archive.apache.org`, gave about 36 KB/s (measured in the session, not stored in the bundle), so the download would have taken about four hours. The bake now measures the server's speed first and refuses a download of more than 40 minutes, shows its progress, resumes a partial file, and takes the checksum file always from the primary archive, whichever server the tarball comes from. The rebuilt image's bake downloaded at 5166 KB/s from a mirror and matched the primary archive's checksum.

### 12.4 The first image failed its second boot, and why

| Boot | Check at (UTC) | RTMR3 | Measurement | Result |
|---|---|---|---|---|
| 1 | 13:34:51 | `cbb239a2e2978202` | 11 s | passed: the four daemons started after the measurement as `hadoop`, HDFS answered |
| 2 | 13:44:38 | `cbb239a2e2978202` | 10 s | **failed (25 checks):** none of the four daemons had started |
| 3 | 14:32:23 | `eebbb25ff153d40a` | 11 s | passed, after the faulty unit file was replaced in place on that VM |

The measurement itself was fine and reproducible: boot 2 has the same RTMR3 as boot 1. The cause was one line in one unit file. The format unit, which formats the NameNode on the first boot, was meant to be skipped on every later boot, by `ConditionPathExists=!/var/lib/hadoop/namenode/current`. That line was written under `[Service]`, but systemd reads conditions only under `[Unit]` and ignores the line elsewhere. On the real VM systemd said so itself: `Unknown key name 'ConditionPathExists' in section 'Service', ignoring.`, and the unit's `ConditionResult` was `yes`, as if there were no condition. So the format unit ran again on boot 2, refused to format an existing NameNode and ended with status 1 (`ExecMainStatus=1`). The journal of that boot, which I read in the session and did not store in the bundle, says `Not formatting` for the first and `Dependency failed` for the four daemons that require the format unit.

My first guess was the opposite mechanism (a skipped dependency blocking the daemons), and the journal showed that it was wrong. The rehearsal could not catch the real cause because it checked the unit with a `grep` that matches the line in any section. The fixes: the condition moved into `[Unit]`; the rehearsal now reads each unit section by section, and it catches the first image's real unit file; and both the bake and the boot check now ask `systemd-analyze verify`, which runs on the real machine. The same real output showed an unrelated warning about Ubuntu's own `snapd.service`, so both checks count only warnings that name our own units.

### 12.5 The rebuilt image: the result

| VM | Boot | Check at (UTC) | What happened | RTMR3 | Measurement | Result |
|---|---|---|---|---|---|---|
| `tc-f03a-test2` | 1 | 17:40:09 | the first boot of the rebuilt image | `eebbb25ff153d40a` | 10 s | passed |
| `tc-f03a-test2` | 2 | 17:49:34 | a plain reboot | `eebbb25ff153d40a` | 11 s | passed |
| `tc-f03a-test2` | 3 | 17:53:49 | one comment line appended to `hadoop-env.sh` | `377adb4c3890e4a8` | 10 s | passed |
| `tc-f03a-test2` | 4 | 17:56:26 | the change undone | `eebbb25ff153d40a` | 10 s | passed |
| `tc-f03a-test3` | 1 | 18:01:30 | a second VM from the same image | `eebbb25ff153d40a` | 11 s | passed |

Every boot passed the same checks: the F0.2 checks still hold; the log holds the 10 events of the list, in order; systemd reads all 5 unit files without an unknown key or section; the four daemons are active, run as `hadoop` and started after the measurement finished; the format unit's result is `success` (it formats once and is skipped later, which is what failed before); `hdfs dfs -ls /` works and a file written to HDFS reads back the same; `/opt/hadoop` is owned by root and not writable by group or others; the user `hadoop` has no login shell; and ten ports (the NameNode, the DataNode and the ResourceManager) listen on `127.0.0.1`.

**The control.** The check can fail when it should: at boot 3 the one comment line made the log comparison report `digests that differ: ['hadoop-conf']` and `F01-COMPARE-OK (the change of hadoop-conf is seen and nothing else changed)`. The digest of `hadoop-conf` went from `f1a626424093` to `bae33be4c9bd`, and no other event moved. The undo printed Hadoop's own last line (`# export HADOOP_REGISTRYDNS_SECURE_EXTRA_OPTS="-jvm server"`), so the file was restored exactly, and boot 4 returned to `eebbb25ff153d40a`.

**The registers.** MRTD `c1ee9c16e3af`, RTMR0 `e242a9b441c2`, RTMR1 `7bf1f4c1b53a` and RTMR2 `5deb8bd855af` are equal on all four boots of the first VM and on the second VM; only RTMR3 changes, and only at boot 3. So **two VMs made from one image share all five registers at their first boot** (limitations row 138). The claim is as narrow as the test: two VMs, one machine type (`c3-standard-4`), one zone (limitations row 147).

**The rebuild reproduces the measurement.** RTMR3 `eebbb25ff153d40a` is the value of every boot of the rebuilt image and also of boot 3 of the first image's VM, where only the unit file had been replaced. So a rebuild from the same inputs reproduced all 10 measured items (limitations row 148 gives the limit). The first image's boot 1 had `cbb239a2e2978202` only because its format unit was the faulty one.

**An independent re-check.** For all five quotes of the rebuilt image I re-read the registers with my own tool and replayed the five event logs against the quotes in the sandbox: each chain is consistent, the RTMR3 in the quote matches the replay, and REPORTDATA is the SHA-512 of the log. On the laptop, the Intel signature chain of all five quotes verified (`TDX Quote verified successfully`, with the strict flags); that output was seen in the session and is not in the bundle.

**What listens.** Besides the ten loopback ports, the only listeners that are not on `127.0.0.1` are the system's name-resolution stub, `sshd` on port 22, and Java's MapReduce shuffle port 13562 on all interfaces. The shuffle port cannot be bound by configuration; step F0.5 closes it with a firewall (limitations row 144).

### 12.6 What it shows, and what it does not

It shows that a VM made from the image starts the whole Hadoop stack by itself, from root-owned code, after a measurement that covers it, with no operator command, and that the measurement is reproducible, sensitive to a change, and the same on two VMs of one image. It does not show:

- **The wrapper jar, the job and the crawl driver** are not in the image yet (steps F0.3b and F0.3c), so the pass condition of F0.3, a crawl that runs by itself, is not met yet.
- **Two nodes.** This is a single node on the loopback address; the keys and the fleet list come with F1 and F2.
- **The login paths.** The test VMs were reached by `ssh`; `sshd`, the guest agent and the serial console are still in the image (F0.4, limitations row 140).
- **The unit and its scripts are measured by themselves,** not by an earlier stage (limitations row 137).
- **The Hadoop tarball** is trusted through the checksum file of the primary Apache archive, and its hash is recorded in `/etc/tc/bake-versions.txt` so that it can be pinned (limitations row 146).
- **The same-day limit.** The two bakes were made on the same day and gave the same 10 digests; the JDK package version moves with Ubuntu's updates (limitations row 148).

### 12.7 Evidence and commits

| Item | Value |
|---|---|
| Evidence bundle (outside the repository) | `evidence-f03a` (`fa7c4d07…`, 107 files): the first image's consoles, its proof file and its VM's state; the rebuilt image's consoles, checks, comparisons and registers; and the state of the two test VMs (event logs, quotes, listeners, versions); it also holds the kit that ran, `f03a-files-9e2fee02.zip` |
| The code commit | `139bfb81f` `feat(image): the software layer of the fixed-fleet image: JDK, Hadoop, a service user and the daemons as units, the clean-up and the checks (step F0.3a)` (18 files: 17 new and the README of `ops/image`) |
| The images | `tc-img-f03a-1` (faulty, deleted) and `tc-img-f03a-2` (30 GB, `TDX_CAPABLE`, kept for F0.3b) |
| The kit that ran | version 7 (`9e2fee02…`), identical to the committed files; the bake ran from version 6 and 5, whose bake, cleaning, check and registers scripts are byte-identical, and only the driver differs |

### 12.8 Lessons

The mistake log has the rows 142 to 147 and the guide has the rules 40 to 43: a setting is tested where the real system reads it (the section, not the text); a pattern that filters real output is tried on real output before it is delivered; a download needs a speed check and a checksum from a different server; a remote job is stopped by process number and its end proved by a measurement; and a fix for a condition that can arise in two ways needs a test for each, shown to fail against the old code.


## 13. Step F0.3b: the job and the wrapper jar of the image (19 and 20 October 2026)

### 13.1 What it does, in plain words

After step F0.3a the image could run Hadoop, but it did not yet hold the program that does the crawling. This step adds two things. The first is the crawler's **job**, a 135 MB packed program that Hadoop runs on its machines. The second is the **wrapper jar**, the small library of 43 classes that will later sign what is written to HDFS. Both are built **once**, on the builder, from two sealed inputs whose fingerprints (SHA-256) are checked before anything is built: an archive of our source code at one fixed commit, and the teammate's patch. Think of a builder who accepts only two sealed envelopes, checks the seals, builds the machine, and then takes the tools away when he leaves: the image keeps only the machine. The configuration of the image stays plain: the wrapper is installed, but nothing uses it until the keys exist (steps F1 and F2). The sources are in `ops/image/` (commit `ae0055d7b`).

### 13.2 What it replaces, and why

| New | Replaces (legacy) | Why |
|---|---|---|
| The job and the wrapper jar, built once on the builder from pinned inputs, then installed read-only | The rebuild stages `deps`, `build` and `jar` of `ops/rebuild/node-wrapper.sh`, and the per-window installs of jars and the job (ADR-045) | What runs must be what was measured, and it must not be built again on each node |
| The deploy folder `/opt/tc/nutch`, measured as the event `nutch-deploy` (11 events in all) | The `nutch-deploy` item of the by-hand measurement of Milestone 1 | The job and the launcher scripts are part of every boot's measurement |
| The removal of the build tools and caches before the image is made | nothing (new) | A compiler and a package manager in a measured image are tools for whoever breaks in |

The decision is ADR-064.

### 13.3 How it was built

The builder, restarted from the F0.3a state, received two inputs (since step R1 of 22 October 2026 there is one: the patch is in the source tree, ADR-071). The first is a source archive made in Cloud Shell by `git archive` of the commit `8a3b1535a` of the private repository (SHA-256 `8dee5edaa7a2f056…`). The second is the teammate's patch at her commit `841c1d3`, rebuilt from her upload with its line endings normalized (SHA-256 `61dbff2eca98cc7b9934f8e5e51e34265298aa22eb6cecf4d22c3bef44ad5516`); it is not in our repository. The script then built the two libraries of the crawler at their pinned commits (`crawler-commons` at `13118882ddfe` and `language-detection-cld2` at `38efccdc1ec1`), applied the patch (11 files changed or made), and ran `ant runtime`, which took about 7.5 minutes. The wrapper jar is built from the job's own classes by `ops/attested/wrapper-jar.sh`, which is deterministic and needs no compiler. The result: the job `2b374459f19c5933…` (134922129 bytes, 1079 entries, 43 wrapper classes, including the patch's `CustodyReceipt` class) and the jar `77bbdda0a2b57028…` (43 classes). Then `ant`, `maven`, `git` and `patch` were removed together with the build folder and the caches (`libcld2-0` stays, because the job needs it at run time), the measured list grew from 10 to 11 events, and every fingerprint was recorded in `/etc/tc/job-versions.txt`. The cleaning and the image `tc-img-f03b-1` followed.

**The wrapper jar is reproducible across machines.** The jar `77bbdda0a2b57028…` of this build is byte-identical to the jar that was built on the master on 17 October from the same wrapper source (step 5.2.2, `~/m522b`, the jar `77bbdda0a2b57028…`). The job file differs from that build's job (`ff73a7c281ac5299…`, 134,921,739 bytes), by 390 bytes, as expected for a file that carries timestamps; the identical jar shows that the classes inside are the same. So every image build has its own `nutch-deploy` reference (limitations row 150).

### 13.4 The first check failed once, and why

The first check of the image, on 19 October at 19:54 UTC, failed one check of about twenty: the wrapper's self-test, with `Permission denied` on the helper script. The check ran that script as the user `hadoop`, but the script lay in the home folder of the person who had shipped the kit, which `hadoop` cannot read. The image was fine, and the rehearsal could not see the problem because its stand-in for `runuser` does not enforce file permissions. The fix runs a copy of the helper from `/tmp`; the new rehearsal tests fail against the old check and pass with the fix. The same VM was checked again the next morning.

### 13.5 The result

| Boot | Check at (UTC) | What happened | RTMR3 | Measurement | Result |
|---|---|---|---|---|---|
| 1 | 08:38:25 | the first boot, checked again after the fix | `03adc1d2e77b8097` | 12 s | passed |
| 2 | 08:44:13 | a plain reboot | `03adc1d2e77b8097` | 11 s | passed |
| 3 | 08:49:06 | one comment line appended to the launcher `bin/crawl` | `a62683ad4def1838` | 11 s | passed |
| 4 | 08:53:28 | the change undone | `03adc1d2e77b8097` | 11 s | passed |

Every boot passed the checks of F0.3a, and in addition: the installed job equals the recorded one; the installed wrapper jar equals the recorded one and holds the 43 recorded classes; `/opt/tc`, `/opt/tc/nutch`, the job, `bin/nutch` and the jar are owned by root and not writable by group or others; the jar is on Hadoop's classpath and its classes are identical to the job's; the wrapper loads from the library folder and initializes (`wrapper-jar.sh selftest`, run as `hadoop`); **Hadoop's own Pi example runs on YARN** (`Estimated value of Pi is 3.80000000000000000000`); and **a real Nutch `inject` job from the baked job file runs on YARN**, injects the 2 seed URLs (`Total new urls injected: 2`) and leaves a crawl database in HDFS. These were the first real YARN jobs in the image.

**The control.** At boot 3 the one comment line in `bin/crawl` made the comparison report `digests that differ: ['nutch-deploy']` and `F01-COMPARE-OK (the change of nutch-deploy is seen and nothing else changed)`. The digest of `nutch-deploy` went from `1e395413cdbe` to `a144cdb157b5`, and no other event moved. The undo restored the file from a backup: its SHA-256 (first 16 digits) was `193ba72f2352d637` before the change and after the undo, with the same owner and mode (`-rwxr-xr-x root`), and boot 4 returned to `03adc1d2e77b8097`.

**The registers.** MRTD, RTMR0, RTMR1 and RTMR2 are equal on all four boots, and only RTMR3 differs, at boot 3. They are also the same values as on the F0.3a image (MRTD `c1ee9c16e3af`, RTMR0 `e242a9b441c2`, RTMR1 `7bf1f4c1b53a`, RTMR2 `5deb8bd855af`), as they should be, since only files that are measured in RTMR3 were added.

### 13.6 What it shows, and what it does not

It shows that the image holds the crawler's job and the wrapper jar, built once from pinned inputs and owned by root; that Hadoop runs jobs on YARN in it; that the 43 wrapper classes are reproducible across machines; that the measurement covers the new files and notices a change; and that the build tools are not left behind. It does not show:

- **The wrapper in use.** The configuration is plain, so the data path of the image is not signed yet (limitations row 152); signing needs keys (F1) and the wrapped configuration (F2). The plan's wording for this step, "the wrapped configuration", is corrected accordingly.
- **The crawl driver and the seeds** are not baked yet (step F0.3c), so the pass condition of F0.3 is not met yet.
- **The teammate's patch** is pinned by its fingerprint and carried by the kit, not by the repository (limitations row 149), and **the source archive** is made in Cloud Shell from a private repository (limitations row 151).
- **The crawler's identity URL** inside the baked job is still the address of the old fork; it is to be decided and changed before the evidence crawl.

### 13.7 Evidence and commits

| Item | Value |
|---|---|
| Evidence bundle (outside the repository) | `evidence-f03b` (`03fe5036…`, 70 files): the consoles of the job build, the cleaning and the image, the failed first check and the four passing checks, the comparisons, the control and the registers; the state of the test VM (event logs, quotes, the Pi and inject outputs, the job record); the source archive that was built; and the kit that ran, `f03b-files-9eb8fc07.zip` |
| The code commit | `ae0055d7b` `feat(image): the job and the wrapper jar of the fixed-fleet image, built from pinned inputs, with their check (step F0.3b)` (7 files: 4 new and 3 modified) |
| The image | `tc-img-f03b-1` (30 GB, `TDX_CAPABLE`); the test VM was deleted |
| Laptop check | the Intel signature chain of the four quotes verified (`TDX Quote verified successfully`, four times); the output was seen in the session and is not in the bundle |

### 13.8 Lessons

The mistake log has the rows 148 to 150 and the guide has the rules 44 to 46: an instruction block never contains a placeholder that the user must edit between two steps; a property that a rehearsal's stand-in cannot enforce, such as who may read a file, is tested by the first real run; and a negative test is proved by breaking the code on purpose and seeing it fail.


## 14. Step F0.3c: the crawl that runs by itself (20 October 2026)

### 14.1 What it does, in plain words

Until now a person had to start the crawl by typing a command with its parameters. Now the image carries the **recipe** and starts it by itself: a driver script, its parameters and its seeds are baked in, and a systemd unit, `tc-crawl.service`, starts the driver after the measurement and the four Hadoop daemons. The parameters are the ones of the earlier runs (at most 10 fetch attempts over 3 rounds, on the two practice sites `books.toscrape.com` and `quotes.toscrape.com`, which obey `robots.txt`). The driver reads them as **data**: a line is `KEY=VALUE` with a plain value, and nothing from the file is ever run. Both files are measured (the events `crawl-params` and `crawl-seeds`, which makes 13 events), so a verifier sees exactly what the VM was told to crawl. When the crawl succeeds the driver leaves a marker, and the unit's skip condition (in `[Unit]`, where systemd reads it) keeps a later boot from crawling again. This replaces the hand-run `ops/run-crawl.sh` with typed parameters (legacy step 5.3.2). The decision is ADR-065, and the sources are in `ops/image/`.

### 14.2 The first boot: nobody ran a command

A VM made from the image `tc-img-f03c-1` booted on 20 October, and the check **only waited and read**. The crawl started at 09:20:57 UTC, HDFS answered after 15 seconds, the seeds were put into HDFS, and the driver wrote `done: 8 urls fetched, 3 segments` at 09:33:22, after 12 minutes and 25 seconds. The unit ended with `success`, after the measurement and after the four daemons had started. The crawl database holds 261 URLs: 8 fetched, 2 permanently redirected (which makes the cap of 10 fetch attempts) and 251 found but not fetched. The crawl's own log has 3162 lines. The check then ran the F0.3b checks (the job, the wrapper's self-test, Hadoop's Pi example and a Nutch inject job) and they passed.

### 14.3 Boots 2 to 4, and the control

| Boot | Check at (UTC) | What happened | Crawl unit | RTMR3 |
|---|---|---|---|---|
| 1 | 09:22:27 | the first boot | ran by itself, `success` | `a3646395c721…` |
| 2 | 09:50:17 | a plain reboot | skipped (the marker exists) | `a3646395c721…` |
| 3 | 09:54:55 | one comment line appended to the driver `tc-crawl.sh` | skipped | `a26b29bef1c8…` |
| 4 | 09:59:14 | the change undone | skipped | `a3646395c721…` |

The 13 events are the same on boots 1, 2 and 4 (`F01-COMPARE-OK (reproducible)`). At boot 3 the comparison names **only `tc-lib`** (`digests that differ: ['tc-lib']`), because the driver lives in the measured folder `/usr/local/lib/tc`; the undo was exact (the SHA-256, first 16 digits, `a8abf84486dd7e06` before and after, same mode and owner). MRTD, RTMR0, RTMR1 and RTMR2 are equal on all four boots and equal to those of the earlier images; only RTMR3 differs, at boot 3. The Intel signature chain of the four quotes verified on the laptop (seen in the session, not stored in the bundle). The parameters file sits inside the measured folder `/etc/tc` and is measured twice by design (as `tc-conf` and as `crawl-params`), so a control on it would move two events; the log comparison tool takes one, which is why the control was made on the driver.

### 14.4 What it shows, and what it does not

It shows that a VM made from the image runs a whole crawl with no operator command, from measured, root-owned files, and does not repeat it on a later boot, and that the measurement notices a change in the driver. It does not show:

- **Scale.** Ten fetch attempts on two practice sites show the mechanism, not performance (limitations row 153).
- **Signing.** The crawl runs in plain mode; the wrapper is installed but not used until keys exist (F1 and F2).
- **Identity.** The baked job still names the old fork in `http.agent.url` and `warc.export.software` (limitations row 154); it is changed in the source commit of the next job rebuild.

### 14.5 Evidence and commits

The evidence bundle is `evidence-f03c` (`6abea8e5…`, 70 files: the crawl's log and statistics, the checks and comparisons, the state of the VM, and the kit that ran, `f03c-files-797f1f63.zip`). The code commit is the one with the subject `feat(image): the crawl that runs by itself: a baked driver, its parameters and seeds, and a unit that starts it after the daemons (step F0.3c)`, just before the commit of this section. The rehearsal of the step has 48 checks, including attempts to inject commands through the parameters file, and three deliberate breakages that it caught. The test VM and the previous image were deleted; `tc-img-f03c-1` stays.


## 15. Step F1 (and the binding half of F0.5): the fleet boot flow (20 October 2026)

### 15.1 What it does, in plain words

Until now every VM of the image was alone. Now two VMs become a fleet, and nobody logs in to make that happen. Think of a locked workshop where each guest arrives and writes their name and two secret codes on a **whiteboard that is wiped when they leave** (the keys live in memory, never on disk). A notary then stamps **one** paper for each guest that binds three things together: the guest's name, both codes (the public halves), and the guest's diary of everything that was measured so far. The operator collects the stamped papers, checks the stamps, and writes the **guest list** (`fleet.tsv`). Each guest looks at the list. If their own codes are not on it, **they stop before the kitchen (Hadoop) opens**. If they are, they write the list's fingerprint into their diary, open the private tunnels (WireGuard) to the other guests exactly as the list says, set up Hadoop from the list, and have the notary stamp a second paper, so that the final diary and the list can be checked together.

In technical terms, `tc-fleet.service` runs after the measurement and before any Hadoop daemon, as root: it makes a signing key (P-256) and a WireGuard key in `/run/tc` (a memory file system), makes one TDX quote whose REPORTDATA is the SHA-512 of a binding text (node name, both public keys, SHA-512 of the RTMR3 event log), and publishes it as the guest attribute `tc/announce`. The operator's driver verifies each announcement (the quote binds the keys and the log, and the log replays to the quote's RTMR3), writes `fleet.tsv` and sets it as instance metadata. The node checks the list's format and that its own two keys are in it, extends RTMR3 with the events `fleet` (SHA-384 of `fleet.tsv`) and `fleet-conf`, brings up `wg0` with the other nodes as peers, renders the Hadoop configuration from the list into `/run/tc/conf` (every daemon bound to the node's `wg0` address, WebHDFS off), marks its role, and publishes a final quote as `tc/final`. The decisions are ADR-066 and ADR-067, and the sources are in `ops/image/` (the code commit just before the commit of this section).

### 15.2 What it replaces, and why

| New | Replaces (legacy) | Why |
|---|---|---|
| Keys made in memory at boot, one quote that binds both keys and the log | Step 5.1.3's signing service and Milestone 2's key files in `/etc/wireguard` | No private key can be found on disk, and one quote vouches for both keys |
| A fixed `fleet.tsv` that every node measures | Step 5.1.3's key list and its sync script, and step 5.2.1's admission of keys | A list measured once replaces a folder that is rescanned; the consumer checks it at the end |
| A node stops at boot if its keys are not in the list | Step 5.2.1's refusal of an unlisted key at read time | The check happens once, before Hadoop starts |
| The mesh from the list, with no admission at run time | Step 5.2.2's doorman, `mesh-admit.sh`, the `wg1` test mesh and the Milestone 2 mesh scripts | No node joins during a run |

### 15.3 What was run

Three images were built and tested on two TDX VMs each (`c3-standard-4`, no service account, guest attributes on): `tc-img-f1-1` (the first run and the negative test), `tc-img-f1-2` (the second run) and **`tc-img-f1-3`** (the run that passed). The master is `tc-f1-m` (`10.10.0.1`) and the worker is `tc-f1-w` (`10.10.0.2`). The rehearsal of the step has 45 checks: two nodes run the real fleet script, and the real operator script then verifies their output; ten kinds of bad fleet list are refused, and the new tests were shown to fail on the previous kit's files. Section 15.6 tells what the first two runs found.

### 15.4 The result of the third run

| Check (on both nodes unless noted) | Result |
|---|---|
| `tc-fleet.service` | success; the master joined at 13:27:15 UTC and the worker at 13:27:25 |
| F1.1: where the keys live | on `tmpfs`; a search of the node's disk (`/etc /var /opt /home /root /usr/local /boot /srv`) found no private key and neither of this boot's key values |
| F1.2: the fleet event | the same in both logs, equal to the SHA-384 of `fleet.tsv` (`697679b0b53f6b1d…`), confirmed by the operator script and by each node's own check |
| The log | 16 events (the 14 measured at boot, then `fleet` and `fleet-conf`); the chain replays to the RTMR3 of the final quote |
| The final quote | its REPORTDATA is the SHA-512 of a binding text with the node's two public keys and the SHA-512 of its log |
| F1.4: the mesh | `wg0` has the other node as its only peer, and each node reaches the other by ping over `wg0`; the mesh was formed from `fleet.tsv` with no SSH (SSH was used afterwards only to read the results) |
| F0.5, binding half | the NameNode (9000, 9870) and the ResourceManager (8030 to 8033, 8088) listen on `10.10.0.1`, and the DataNode (9866, 9864, 9867) and the NodeManager (8042, 8040) on `10.10.0.2`; WebHDFS is off in the template |
| Fresh state | the NameNode namespace was created during this boot (13:27:17), and the DataNode storage too (13:27:29) |
| HDFS | 1 live DataNode, as the fleet has 1 worker |
| The crawl | started by itself on the master at 13:27:15 and ended at 13:39:52 (12 min 37 s) with `success`: `fetched=8 segments=3 rounds=3` |

**F1.3, the negative test.** On the first image both nodes were rebooted. A reboot makes new keys, so the old `fleet.tsv` in the metadata no longer holds them. Result: on both nodes `tc-fleet` ended with `exit-code`, all four Hadoop units stayed `inactive`, and the journal said `TC-FLEET-FAIL: this node's keys are not the keys listed for tc-f1-m in fleet.tsv (a rebooted node makes new keys): stopping before Hadoop starts` (master at 12:53:33, worker at 12:54:08, with the matching name). The test was not repeated on the third image because the fleet script did not change after the first image (the later kits changed the templates, the crawl driver, the cleaning and the checks).

The Intel signature chain of the four quotes of the third run (the announcements and the final quotes) verified on the laptop; this was seen in the session and is not in the bundle.

### 15.5 What it shows, and what it does not

It shows that two VMs of one image form a fleet from a measured list with no login, that keys exist only in memory, that a node whose keys are not listed does not start Hadoop, and that Hadoop on the fleet is bound to the mesh and runs a whole crawl. It does not show:

- **The wrapper in use.** The signing key is made and bound, but nothing signs with it yet (F2); the configuration still uses plain HDFS (limitations row 157).
- **A fleet larger than two nodes**, which the code supports but was not run (row 158), and **an offline disk search** after a run (row 159).
- **The closed doors.** SSH is still open for the tests, and the Java processes still listen on a wildcard port (13562 and two ephemeral ports); the baked firewall and the removal of login are phase 4 (row 160).
- **Who writes the fleet list.** The operator builds `fleet.tsv` from announcements it verified, and instance metadata can be changed by anyone with project access; a rogue entry would be visible in the measured `fleet` event, but it is not prevented; the consumer's verifier must check each key of the list against a quote (row 161).

### 15.6 What the first two runs found

The first two fleet runs failed, and the causes were not in the glue that the rehearsal tests. Each was diagnosed from the nodes' own logs before any change (mistake-log rows 151 to 154, rules 47 to 50).

1. **A false alarm of my check.** The check reported a private key on disk, and the file it found was the check itself, whose search text contained the words it searched for. The patterns are now built from two pieces.
2. **The DataNode was refused.** The NameNode answered `DisallowedDatanodeException … hostname cannot be resolved (ip=10.10.0.2)`: Hadoop checks that a DataNode's address has a reverse name, and the fleet uses bare mesh addresses (the single-node images used `127.0.0.1`, which always resolves). A live test confirmed it: after the setting was turned off, `Live datanodes (1)`. The fleet's template now sets `dfs.namenode.datanode.registration.ip-hostname-check=false`; membership is enforced by `fleet.tsv` and by the `allowed-ips` of `wg0`, so the reverse-name check adds nothing here. The crawl failing in this run was only a consequence.
3. **The builder's HDFS had travelled in every image since step F0.3a's second image.** The second run's crawl failed with `SafeModeException` at its first write, because the NameNode had loaded 7 inherited blocks and waited in safe mode. The odd number was the clue: the block pool was `BP-1324903135-10.128.0.16-1792423263762`, which names the **builder's** address and a time of 19 October 15:21 UTC, and the worker's DataNode carried the same cluster identity (`CID-37eb73b1…`), read on the running VMs. The cause was a line of the cleaning script that tested `/var/lib/hadoop` (mode `0750`, owner `hadoop`) as the normal ssh user: the test said "no such directory" and the deletion was silently skipped; the rehearsal ran as root and could always look inside. The images from F0.3a's second image to `tc-img-f1-2` therefore carried the builder's namespace. The measured registers and events of those steps are not affected (HDFS data is not measured), and their crawls ran correctly because the driver wipes its own folders first, but "a new VM starts a new cluster" was not true for them. The cleaning now stops the Hadoop units, deletes with `sudo` and **aborts** if any data is left, and the check requires that the namespace was created during the boot. The crawl driver also now waits for HDFS to leave safe mode and for a live DataNode per worker, and retries its first write.

### 15.7 Evidence

The evidence is the bundle `evidence-f1.tar.gz` (outside the repository; its fingerprint is in the session log): the operator's files of the three runs (announcements, final quotes, `fleet.tsv`, the checks), the negative test, the read-only diagnoses, and the kit that ran (version 13).



### 15.8 The evidence files, for the verifier

Per run, the operator keeps these files (the folders `evidence-f3`, `evidence-f4`, `evidence-f5d`, `evidence-f5l` and `evidence-f6d` of the Cloud Shell): `announce-<node>.txt` (the node's statement A and its quote A), `final-<node>.txt` (its quote B, made after the fleet is joined) and `fleet.tsv`; the locked image also has `report-<node>.txt`, which is a convenience of the VM and not evidence (limitations row 168). The reference reading of all of them is `ops/image/test/f1-fleet.py` (the functions `parse` and `verify`).

| What | Layout |
|---|---|
| `announce-<node>.txt`, `final-<node>.txt` | text lines `key=value` with the keys `name` (the instance name), `sign` (the signing public key, base64 of its X.509 form, P-256), `wg` (the WireGuard public key), `log_sha512` (the SHA-512 of the log, in hex), `quote_b64` (the raw TDX quote, base64, at least 632 bytes) and `log_b64` (the RTMR3 event log, base64) |
| the binding | the quote's REPORTDATA (bytes 568 to 632 of the quote) is the SHA-512 of this text, each line ending with a newline: `tc-bind-v1`, `name=<name>`, `sign=<sign>`, `wg=<wg>`, `log=<log_sha512>` |
| the event log | one line per event, tab-separated: the event name, its digest, the register before, the register after (all SHA-384, in hex); the first register is 48 zero bytes, and `after` is the SHA-384 of `before` followed by the event's digest; the last `after` is the RTMR3 of the quote (bytes 520 to 568) |
| the other registers | in the quote: MRTD at bytes 184 to 232, RTMR0 at 376 to 424, RTMR1 at 424 to 472, RTMR2 at 472 to 520 |
| `fleet.tsv` | the first line is `# tc-fleet v1`; then one line per node, tab-separated: the name, the role (`master` or `worker`), the WireGuard address, the endpoint (`ip:51820`), the signing public key and the WireGuard public key; the event `fleet` of every node's log is the SHA-384 of this file |
| the reference values | `ops/image/reference-values-tc-img-lock-1.json`: `image`, `machine_type`, `mrtd`, `rtmr0` to `rtmr2`, `events_in_order`, `stable_events` (name to digest) and `per_run_events` (`fleet` and `fleet-conf`, which depend on the run); see [milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md) section 6 |

The key id of a signing key (`FLEET-` and 32 hex digits) is defined in section 16.3. What the operator's script checks, and what the teammate's verifier must check again, is in [milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md) section 6.

## 16. Steps F2 and F3: the fixed-behavior wrapper (20 and 21 October 2026)

### 16.1 What it does, in plain words

The wrapper is the layer between the crawler and HDFS that hashes every file, keeps a signed record beside it, and refuses to hand out a file that does not match its record. Before these steps it was a **machine with 30 switches** (hash on or off, verify on or off, "missing record: allow, warn or fail", and so on), and the position of the switches was read from a configuration file. That sounds flexible, and it was the problem: a job could arrive with its own copy of the configuration. The first run of the fleet showed it. The MapReduce ApplicationMaster builds its configuration from the job's own `job.xml`, the wrapper's rule "a setting counts only if `core-site.xml` set it last" threw every setting away there, so the ApplicationMaster had **no keys** and refused a file that the master had signed correctly. The cure is to remove the switches, not to move them. The wrapper now has **none**: it always signs, hashes, keeps records, verifies reads and binds files to folders, in every JVM, so no job file can weaken it. Its source went from 5,783 lines in 43 classes to 2,120 lines in 18, and 41 files of old tools and tests were retired.

### 16.2 What changed, and what it replaces

| Step | What the wrapper does now | Replaces |
|---|---|---|
| F2 | `FleetKeys` (about 110 lines) reads this node's key, its public key and `fleet.tsv` once per JVM; a record signed by a valid key that is not in `fleet.tsv` is refused ("not trusted here") | `KeyService`, `KeyList`, `KeyBundle`, `ServiceKeys`, `QuoteAdmission`, `AdmissionReference`, `QuoteVerifier`, `BundleCheck`, `NodeBundle`, `MeshPolicy`, `MeshAdmission` |
| F3.1 | No settings, modes or switches; behaviour is fixed and secure | `AttestedSettings`, the 30 `attested.*` settings, ADR-039, the test keys |
| F3.2 | One file record and one folder identity, both in `Records.java` (specification in 16.3) | ATTEST01, ATTEST02, ATTEST03 and their five codec classes |
| F3.3 | A flat SHA-256 per chunk, and the signature covers the SHA-256 of the concatenated list | the Merkle tree and `MerkleHasher` |
| F3.4 | The root `/` has the fixed all-zero id and no file | the "top folder bound to its full path" kind of identity |
| F3.5 | `copyToLocalFile` (and `moveToLocalFile`, and the raw variant) read through the verifying open | the documented bypass of step 4.3 |
| F3.6 | The audit log, the observe-only record log, the metadata and listing-length checks and the logging-only overrides are gone | step 4.5 and its NameNode audit comparison, and the scripts that read those logs |
| F3.7 | The capability probe says no to append, concat and truncate | refusal by exception only |
| (found by the contract tests) | `delete(folder, false)` removes the folder's identity file first when it is all that the folder holds | nothing (a defect of the first F3 design) |

### 16.3 The record format, for the teammate's verifier

All numbers are big-endian, there is no padding, and a record has no trailing bytes. A reader must refuse a record that is too short, too long, or inconsistent, with "record is damaged".

**File record** (`ATTEST04`), stored beside its file as `.NAME.attested`:

| Field | Size | Rule |
|---|---|---|
| magic | 8 | the ASCII text `ATTEST04` |
| chunk size | 4 | an integer of at least 1 (the wrapper writes 16384) |
| length | 8 | a long of at least 0 |
| key id length, key id | 1, then that many | 1 to 64 characters from `A-Z a-z 0-9 - _ .` |
| folder id | 32 | the id of the folder that holds the file (all zeros for the root) |
| name length, name | 2, then that many | 1 to 1024 bytes of UTF-8, the file's name |
| chunk count | 4 | equal to ceil(length / chunk size), at most 33,554,432 |
| chunk hashes | 32 each | SHA-256 of each chunk's bytes (the last chunk may be shorter) |
| signature length, signature | 2, then that many | 1 to 128 bytes, ECDSA P-256 with SHA-256, in DER |

The signature is over: the UTF string `tc-attest-file-v1` (a 2-byte length and its bytes), the key id as a UTF string, the folder id, the name length as a 4-byte integer and the name, the chunk size (4 bytes), the length (8 bytes), and the SHA-256 of the concatenated chunk hashes. The signer's public key must be the signing key of a row of `fleet.tsv`; the key id is `FLEET-` and the first 32 hex digits of the SHA-256 of the key's X.509 form.

**Folder identity** (`ATTEST05`), stored in the folder as `_attested-folder`: magic `ATTEST05` (8) | folder id (32) | name length (2) and name | parent id (32; all zeros for a folder directly under the root) | key id length (1) and key id | signature length (2) and signature. The signature is over the UTF string `tc-attest-folder-v1`, the key id as a UTF string, the folder id, the name length (4 bytes) and the name, and the parent id.

**Checking a file:** the record decodes and its signature verifies against a key of the fleet; its name is the file's name; its folder id equals the id of the file's folder, whose identity chain (each folder's name, each folder's parent id equal to the identity of the folder above, up to the root with all zeros) verifies; its length equals the file's length; and each chunk's SHA-256 equals its hash in the list.

### 16.4 How it was proved

**In the sandbox** (JDK 11 and Hadoop 3.4.1's client jars, so the code is compiled and run before it reaches a VM): 195 checks pass: 21 of the keys, 36 of the record format and the flat hash list (every one of the shorter prefixes of a record is refused cleanly, 300 random strings too), 129 of the wrapper over a fake file system (every old attack list, an outsider as writer and as signer, a hostile `job.xml`, an empty configuration, a copy to local disk, the capability probe, the fixed root, eight writers racing five times), and 9 of a MapReduce job through the wrapper. Five deliberate breakages of the wrapper are each caught by one of the new checks.

**On the cluster**, three images were tried before the last one, and each failure was diagnosed from the nodes' own logs before any change:

1. `tc-img-f2-1`: the crawl failed in the ApplicationMaster with "signed by a key that is not trusted here" (the cause in 16.1). It was found by reading the worker's container log, and my smoke test could not have shown it, because it started with a hook that switched the very rule off (mistake-log row 155).
2. `tc-img-f3-1`: the fleet, the crawl through the wrapper, F3.4, F3.5 and the control job passed. The outsider test failed because my own check had made the folder with the fleet's wrapper (a folder of the fleet cannot be written by an outsider, which is the folder-binding rule working; the check was changed so that the outsider makes its own folder). The contract tests then did not compile (two stale imports of deleted classes), and when they ran they found **two real defects**: `delete(folder, false)` failed for a folder that holds only its identity file; and nine tests failed on plain HDFS too because the NameNode refused their 1 KiB blocks, so they had never exercised the wrapper (the fleet's template now lowers the minimum).
3. The racing-writers scenario was flaky in the sandbox. The cause was the stand-in file system (its exclusive create is not atomic and its overloads cannot be overridden in one place); with the atomicity switched off the scenario fails in 4 of 4 runs, with it 12 of 12 pass.

### 16.5 The result of the last run (21 October 2026, image `tc-img-f4-1`)

| Check | Result |
|---|---|
| The build | the job `315980c3c8abbc5d…` (134,844,039 bytes, 1054 entries, 18 wrapper classes), the wrapper jar `0c903841bb0134ff…` (18 classes); the contract tests compiled on the builder right after the job (16 classes) |
| The fleet | formed, `FLEET-DIGEST-EQUAL` (SHA-384 `e27d65304c342738…`), both nodes `F1-CHECK-OK`, including the crawl through the wrapper |
| F2 | `F2-CHECK-OK`: the configuration holds no setting of the wrapper; a file with the fleet's own key; a file directly under `/` is bound; a file changed behind the wrapper's back **cannot be copied to local disk** (the plain client copies it without a word); an outsider's valid key wrote a file that the fleet's wrapper **refuses to read**, and a wordcount job on it **fails in its container** with "not trusted here"; the control job succeeds |
| Contract tests | 199 tests per run: plain HDFS 177 pass, 9 fail, 13 skipped; through the wrapper 176 pass, 9 fail, 14 skipped; `CONTRACT-SAME-AS-HDFS (1 explained difference)`: `testSyncable` (a file still being written has no record yet). The 9 failures are the same on both sides (etags, stream statistics, and a block size that is not a multiple of the checksum size), and the append test that fails on plain HDFS is skipped through the wrapper |

### 16.6 What it shows, and what it does not

It shows that the wrapper behaves the same in a client and in a container, that a valid key outside `fleet.tsv` is refused everywhere, that a changed file cannot leave through any read path including a copy to local disk, and that it matches plain HDFS in Hadoop's own contract tests. It does not show: that the plain HDFS that sits under it is protected from deletion by someone with its credentials (the wrapper detects, it does not prevent: limitations rows already filed); that the 9 failing contract tests are fine on the wrapper (they say nothing, limitations row 164); or the stream statistics (the wrapper reads whole chunks, row 163).

### 16.7 Evidence and commits

The evidence bundle is `evidence-f4.tar.gz` (`580d1afb…`, 21 files, outside the repository): the operator's files of the last run (announcements, final quotes, `fleet.tsv`, the F1 and F2 checks, the contract console and comparison) and the kit and package that ran. The kit is `3972f8a9…` and the package `12988bff…` (the code commit: 28 files, and 41 files deleted). The source archive of the build is `d8fbfd5a…`: the archive of the earlier run plus the package's files (not a commit, because the rule is run first and commit after); the committed tree equals it by construction (the same overlay, the same 1569 files). The code commit has the subject `feat(wrapper): FleetKeys and the fixed-behavior wrapper: no settings, one record format with a flat hash list, a fixed root, a verified copy to local disk, the crawler's identity as data, and the F2 and F3 checks (steps F2 and F3)`.

### 16.8 Lessons

The mistake log has rows 155 to 160 and the guide has the rules 51 to 55.


## 17. Phase 4: the locked image and the firewall (21 October 2026)

### 17.1 What it does, in plain words

The fleet nodes had a door that an operator could use: SSH and `sudo` can read keys from memory and rewrite `fleet.tsv`. This phase **removes the door from the image that the evidence run names** and closes the network around it. There are two images made from one builder, and they differ only in the lock: `tc-img-dbg-1`, the **debug** image (login kept, port 22 open, for debugging and for the attacks of [milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md), never named by evidence), and `tc-img-lock-1`, the **locked** image (no `sshd`, no guest agent, no OS Login, no login prompt on the serial console). Because a locked VM cannot be asked anything, it **reports on itself** (a guest attribute and the serial console), and the lock is not just baked: the measurement **refuses to go on at boot** if a forbidden path such as `/usr/sbin/sshd` exists, so no Hadoop daemon starts on an image that has a way in.

### 17.2 What was built

| Step | What | Where |
|---|---|---|
| F0.4 | `tc-image-lock.sh locked` purges the login packages and masks the login prompts; `forbidden-paths.txt` (measured) lists what must not exist, and `tc-measure.sh` stops the boot if one does | `ops/image/build/tc-image-lock.sh`, `ops/image/rootfs/etc/tc/forbidden-paths-*.txt` |
| F0.5 (rest) | the host firewall, baked and measured as the 15th event `firewall`: input is dropped except loopback, answers, DHCP, the mesh (`wg0`) and the WireGuard port; the debug image adds port 22 | `ops/image/rootfs/etc/tc/nftables-*.conf` |
| F0.6 | the debug image and the locked image, one builder; the locked image is sealed in one session (lock, cleaning and power-off), because the lock removes the SSH that a second stage would need | `tc-image-lock.sh`, stage `seal-locked` |
| report | `tc-report.sh` and its unit publish `tc/report` and write to the console, also when the fleet unit fails | `ops/image/rootfs/usr/local/lib/tc/tc-report.sh` |
| host name | with cloud-init off (its network file names the builder's MAC address) nothing set each VM's name, and Hadoop bound ports to the VPC address; `tc-fleet.sh` now sets the name from the metadata and stops the boot if it cannot | `tc-fleet.sh`, check in `f1-check.sh` |

Step F4, the attacks and the fleet-list mismatch, belongs to Milestone 6 and is in [milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md).

### 17.3 How it was proved, and what went wrong on the way

Every cluster script is run once in the sandbox with Hadoop's own shell (`f4-local.sh`: the real wrapper over a fake HDFS, the real keys, the real `runuser`), and the drivers' `gcloud` commands and stage sequence are linted by the rehearsal (`f4-rehearse.sh`). Three failures were found by the first real run of cluster-only code and are in the mistake log (rows 161, 163 and 164): with cloud-init off both nodes kept the builder's host name and several ports bound to the VPC address (the cause was proved on the live VMs: after `hostnamectl set-hostname` and a restart every port bound to `wg0`); the lock removed the `sshd` that the next stage needed; and a shell expansion put a stray image name on a `gcloud` command.

### 17.4 The results (21 October 2026)

| Check | Result |
|---|---|
| Debug fleet (`tc-img-dbg-1`) | `F1-CHECK-OK` on both nodes with every port on its `wg0` address and the host name equal to the instance name; the crawl through the wrapper `fetched=8 segments=3 rounds=3`; `F2-CHECK-OK`; fleet SHA-384 `d87e3be2c925cd2c…` |
| From outside the mesh | a plain VM in the same network: on the debug image only port 22 is open; on the locked image **no port is open** (22, 9000, 9870, 9864, 9866, 9867, 8030 to 8033, 8088, 8042, 8040, 13562); a WebHDFS read and the YARN REST interface both get no answer |
| Locked fleet (`tc-img-lock-1`) | `REPORT-OK` (26 facts per node: no sshd, no guest agent, no OS Login, nothing on port 22, serial login masked, firewall policy drop, daemons of the role, the host name, the fleet event equal to the SHA-384 of `fleet.tsv`, the crawl `fetched=8 segments=3 rounds=3`); `gcloud compute ssh` fails; the serial console shows no login prompt and carries the VM's own report; fleet SHA-384 `f4c36b779301f3ad…` |
| Two images, two measurements | the events `firewall`, `tc-conf` and `fleet` differ; final RTMR3 `9d07d736ce240006…` (debug) against `76f01a092689616a…` (locked) |
| Reference values of the locked image | MRTD `c1ee9c16e3af…`, RTMR0 `e242a9b441c2…`, RTMR1 `7bf1f4c1b53a…`, RTMR2 `5deb8bd855af…` (the same four as in step F0.3a) and the 15 events that the image measures into RTMR3, written to `ops/image/reference-values-tc-img-lock-1.json` ([milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md) section 6) |

### 17.5 What it shows, and what it does not

It shows that the evidence image has no way in (reported, refused at boot, and tried from outside: SSH, the serial console, every port) and that the two images are told apart by their measurements. It does not show: that nothing else on the disk gives a login (the measurement lists the forbidden paths, it does not hash the whole root disk, limitations row 167); or secrecy of the data at rest (limitations row 169). What an operator can still read or change outside the TEE is the review of 6.2.3 in [milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md) section 5.

### 17.6 Lessons

The mistake log has rows 161, 163 and 164 and the guide has the rules 56, 58 and 59.
