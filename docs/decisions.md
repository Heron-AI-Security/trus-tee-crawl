# Decision log

Short records of decisions that shape the work, in the style of architecture decision records (ADRs). Each entry says what was decided, why, what it costs, and its status.
Decisions taken before 5 October 2026 (runs 1 and 2) are in [guide-pitfalls-and-lessons.md](guide-pitfalls-and-lessons.md), section 4. Entries here are added as decisions are made; a decision is never edited away, only superseded by a later entry.
Times are UTC.

**Status check, 28 October 2026.** The log holds ADR-001 to ADR-086; ADR-083 to ADR-086 (three defaults taken on 28 October 2026 and the mentor's decision on the package pin, which supersedes ADR-084) are the latest. The numbers follow the order in which the entries were recorded, and the index is in that order. The date of an entry is the date of the decision, or of the question when the decision came later (ADR-009 was raised on 5 October and decided on 21 October, after ADR-008 of 6 October). Entries superseded in part: ADR-009 by ADR-078 (the start-up cache is removed from the image), decisions (1) and (3) of ADR-064 by ADR-071, and ADR-072 by the teammate's receipts change (the export no longer runs `nutch warc`, as its text says).

**From 19 October 2026** the entries ADR-044 to ADR-055 (and ADR-010 and ADR-045 for new work) are superseded as listed in ADR-056 to ADR-058; they stay as the history of the design that ran on the cluster until 17 October 2026.

| ADR | Decision | Status |
|---|---|---|
| 001 | Plain TDX VMs with our own image | Accepted (mentor) |
| 002 | TLS certificate checking stays off for now | Provisional |
| 003 | Kernel route: Ubuntu 24.04's 6.17 kernel on the existing VMs | Accepted; fallback recorded; the one-time boot procedure is replaced for the image by ADR-061 |
| 004 | One RTMR3 event per component, with our own event log | Accepted |
| 005 | Measure the CA store as a sorted fingerprint list | Accepted |
| 006 | Measure JDK settings and the CA store as separate components | Accepted |
| 007 | Run 3 on fresh folders and a rebuilt job | Accepted |
| 008 | Scripts in the repository, evidence outside it | Accepted |
| 009 | JDK start-up cache (`classes.jsa`): decided by the image build | Decided (21 October 2026); the file is removed since 27 October 2026 (ADR-078) |
| 010 | Measure at run time now; lock the image down later | Accepted; superseded for new work by ADR-057 |
| 011 | Use the existing VMs, protected by snapshots; no extra test VM | Accepted |
| 012 | Documentation as we go; README and first-principles guide last | Accepted |
| 013 | WireGuard mesh: addressing and tooling | Accepted |
| 014 | Host firewall and hosts-file names instead of per-daemon binding | Accepted |
| 015 | Map the nodes' internal names to the mesh | Accepted |
| 016 | Refusal test without a third VM | Accepted |
| 017 | Replace the implementation behind `hdfs://` with the wrapper (Option B) | Accepted (mentor) |
| 018 | The storage audit is the proof that the wrapper was used | Accepted |
| 019 | Build and test in scratch folders; commit exactly what ran | Accepted |
| 020 | Defer the re-measurement until the job next changes | Accepted (mentor confirmation asked); carried out on 14 October (ADR-040) |
| 021 | Keep each file's record next to the file | Accepted (mentor confirmation asked) |
| 022 | Records come from the wrapper when a file is closed, not from the commit hook | Accepted (question 13 is moot since ADR-034 dropped the task records) |
| 023 | A file without a record is allowed but logged, for now | Accepted (provisional); superseded in part by ADR-038 (13 October 2026: the default is now `fail`) |
| 024 | Naming, the commit gate, and checking assumptions against real samples | Accepted |
| 025 | Rehearse code with the real libraries; documents and programs in separate commits | Accepted |
| 026 | The mentor's answers of 7 October 2026 | Accepted (mentor) |
| 027 | The wrapper on Hadoop's own classpath, both lookups final | Accepted (mentor) |
| 028 | Every wrapped crawl has an unwrapped control in the same hour; wall time and bytes fetched are recorded | Accepted (mentor) |
| 029 | Nothing that is not measured is described as measured | Accepted (mentor) |
| 030 | Answers about files are checked against the records; findings fail closed by default | Accepted |
| 031 | The audit, admin and demo tools ask for the plain client explicitly | Accepted |
| 032 | Before a crawl, rotate the logs and restart the wrapped daemon; collect the container logs right after | Accepted |
| 033 | The NameNode comparison gets two explicit rules, visible and switchable | Accepted |
| 034 | Storage integrity rests on one mechanism, sign on write and verify on read; step 4.7 and the task records are dropped | Accepted (Pingshan, 10 October) |
| 035 | Folder identity files bind a file to its folder | Accepted (Pingshan, 10 October) |
| 036 | The WARC is the point where teammate S's layer and ours connect | Proposed by teammate S; her patch ran in runs 11 to 13, her verifier has not been run on our exports |
| 037 | The mentor's answers of October 2026 (policy, certificates, single-record verification, performance, TLS capture, threat model) | Accepted as direction; taken into the plan on 13 October 2026 |
| 038 | Reading a file's content and asking about its status are two different questions, with two settings for a file without a record | Accepted |
| 039 | The wrapper's own settings count only when the site configuration set them | Accepted |
| 040 | The re-measure covers the patched job, the policy folder and the repository's ops folder, and needs a one-time boot into 6.17 | Accepted |
| 041 | A timing pair: the wrapped run first, then a plain control with the same job, seeds and settings, then the wrapped settings restored and proved | Accepted |
| 042 | Kits are committed as folders exactly as they ran, without other people's code and without evidence | Accepted; publishing the teammate's files needs her consent |
| 043 | The teammate works on the cluster through a read-only copy of the measured client, her own HDFS folder and a reservation marker | Accepted |
| 044 | Records are signed with ECDSA P-256 under a labelled test key in format ATTEST02; everything is off by default and unsigned records stay readable until signatures are required | Accepted (defaults taken by the author; the mentor has not answered these choices); format and settings superseded by ADR-058 |
| 045 | A window: a reserved, temporary and fully restored change of the measured stack | Accepted; not used for new work from 19 October 2026 (ADR-057) |
| 046 | Every file is bound to its folder by signed folder identity files and ATTEST03 records | Accepted (the design follows the mentor's note and ADR-035; the settings and the adoption rule are the author's); format superseded by ADR-058 |
| 047 | The real key is made per boot inside a separate signing service and kept in memory only | Accepted (the defaults recommended on 15 October, the mentor not having answered); superseded by ADR-056 |
| 048 | Keys are trusted only through a key list of bundles whose quote binds them, with a hook for step 5.2.1 | Accepted; superseded by ADR-056 |
| 049 | One switch for the key provider; the test key stays as a labelled option | Accepted |
| 050 | A key is admitted by its quote, verified offline in Java inside the key list | Accepted (the recommended defaults, the mentor not having answered); superseded by ADR-056 |
| 051 | "Attested" means a genuine quote and MRTD and RTMR0 to RTMR2 allowed by an editable reference file; RTMR3 is shown, not enforced | Accepted; superseded by ADR-056; the measurements are recorded, not enforced (ADR-057) |
| 052 | What is not checked offline, and how a rejection and the bundle delivery are handled | Accepted; superseded by ADR-056 |
| 053 | A node is bound to its hardware by a quote over its WireGuard public key and the mesh address it asks for | Accepted (the recommended defaults, the mentor not having answered); superseded by ADR-056 |
| 054 | The doorman decides in a fixed order and reuses the verifier and the reference file of step 5.2.1 | Accepted; superseded by ADR-056 |
| 055 | The first proof is on a separate test mesh with the operator as the trust root; removal is by hand | Accepted; superseded by ADR-056 |
| 056 | A fixed fleet: keys at boot, one measured list, and no quote checking inside the cluster | Accepted (the mentor's note of 18 October 2026) |
| 057 | The locked image comes first; disposable VMs and a debug image; measurements are recorded, not enforced | Accepted (the mentor's note of 18 October 2026) |
| 058 | One record format, no switches, a flat hash list, and a list of behaviours that stay | Accepted (the mentor's note of 18 October 2026) |
| 059 | New steps get new numbers (F0 to F5), the legacy steps stay as history, and our documents checks stay | Accepted (the numbering follows the mentor's note; the checks are our decision of 19 October 2026) |
| 060 | Defaults taken where the note is silent, each easy to change | Accepted (our defaults of 19 October 2026; the mentor has been asked) |
| 061 | The image measures its fixed stack at every boot from a list, and 6.17 is the permanent default kernel | Accepted (shown on a disposable VM, 19 October 2026) |
| 062 | The software layer of the image is root-owned, runs as a user that cannot log in, and starts only after the measurement | Accepted (shown on VMs made from the image, 19 October 2026) |
| 063 | The code lives in a private repository, and the old public fork is frozen | Accepted (the owner's decision, 19 October 2026) |
| 064 | The job and the wrapper jar are built once on the builder from pinned inputs, and the image keeps only the artifacts | Accepted (shown on VMs made from the image, 20 October 2026) |
| 065 | The crawl is baked as measured data and a driver, and a unit starts it once after the daemons | Accepted (shown on VMs made from the image, 20 October 2026) |
| 066 | The crawler's identity is measured data with a default, changed without a job rebuild | Accepted (the owner's decision to use the defaults, 20 October 2026; built in phase 3) |
| 067 | A fleet node makes its keys in memory, binds them with one quote, and joins only a fleet list that holds its keys | Accepted (shown on two VMs, 20 October 2026) |
| 068 | The wrapper has no settings: its behavior is fixed and secure, with one record format | Accepted (shown on two VMs and in Hadoop's contract tests, 21 October 2026) |
| 069 | The evidence image is locked: no way in, enforced at every boot, a baked firewall, and a separate debug image | Accepted (shown on two VMs, from outside and in the attacks, 21 October 2026) |
| 070 | The threat model is insiders only: Google, Intel and the hardware are trusted | Accepted (the mentor's review, 22 October 2026) |
| 071 | The folder chain is checked on every write and rename, the companion names are reserved, the wrapper's two keys are final, the fleet tooling takes any number of workers, and the receipt code is in the source tree | Accepted |
| 072 | The export: the master exports the crawl once, after it, and a new quote C binds the manifest | Accepted |
| 073 | The scratch disk is dm-integrity (HMAC-SHA256, initialised by discard) under dm-crypt (AES-XTS), with two keys of one boot, formatted at every boot | Accepted |
| 074 | The sealed boot: a dm-verity root under a RAM overlay, the root hash on the measured kernel command line, and an offline sealing of a copy of the builder's disk | Accepted |
| 075 | The rehearsal hooks (`TC_*`) are stripped from the installed scripts when the image is built, and a gate refuses an image that still has one | Accepted |
| 076 | The mentor's review is divided: R7 (the consumer's nonce, read-only access) is the teammate's and R6 (scale and benchmarks) is deferred; our own nonce work is removed | Accepted (the mentor's decision, relayed on 26 October 2026) |
| 077 | The commit is part of the measured state (the first event, `source`), and the verifier is pinned to it (rule E9) | Accepted |
| 078 | A build is made reproducible by removing build-time data that two real builds were seen to differ in, never by hiding a difference | Accepted |
| 079 | The reference values are generated from independent builds and merged with a real run; the platform part stays the real run's | Accepted |
| 080 | The collection policy must not contain the day of the build (its file hash is taken over the keytool text without the Creation date lines) | Accepted |
| 081 | The sealed root is not required to be reproducible bit for bit, its contents are (a default taken on 28 October 2026, for the mentor to confirm or change) | Accepted, as a default |
| 082 | Nothing reaches GitHub before the whole run on the real cluster has passed: a local commit, one command on the cluster, a push that needs the cluster's commit id | Accepted |
| 083 | The initramfs stays inside the sealed root (a default taken on 28 October 2026, for the mentor to confirm or change) | Accepted, as a default |
| 084 | Rebuilds must match over a short horizon, and the package versions are recorded; a longer horizon would use a dated copy of the Ubuntu archive (a default taken on 28 October 2026) | Superseded by ADR-086 on 28 October 2026 |
| 085 | The retention lock of the evidence bucket stays off until a retention period is named (a default taken on 28 October 2026) | Accepted, as a default |
| 086 | The packages are installed from a dated copy of the Ubuntu archive (the mentor's decision of 28 October 2026, built as step R4.6 and verified on commit `1c8a2cc19`) | Accepted |

---

## ADR-001: Plain TDX VMs with our own image

- **Date:** 5 October 2026. **Status:** accepted by the mentor.
- **Context:** the handoff offered plain TDX VMs with our own image, or Google Confidential Space (less image work, but Google's attestation service joins the trust chain; multi-node Hadoop inside it is unproven).
- **Decision:** keep plain TDX VMs.
- **Why:** full control of the kernel, the network and the image; raw quotes can be verified off-cloud by us, as already done.
- **Consequences:** we build and measure our own image; kernel and boot configuration are ours to maintain.

## ADR-002: TLS certificate checking stays off for now

- **Date:** 5 October 2026; updated 6 October. **Status:** provisional; to be settled at the next mentor meeting.
- **Context:** stock CCBot sets `http.tls.certificates.check` to false. With it off, whoever controls the network can impersonate a site, and the measured crawler will archive the fake page. The mentor's instinct was to leave it off and rely on a teammate's code.
- **What the teammate reports (relayed, not tested by us):** their source-receipt code runs in the live fetch path, validates certificates itself and fails closed (they tested wrong host, self-signed, expired and untrusted-root cases with CCBot's checking off), and refuses to issue a receipt for such pages. CCBot may still fetch and archive them without a receipt. They will ask whether their layer is sufficient or whether CCBot's own checking should also be on.
- **Decision:** leave it off in our runs (runs 3 and 4 used the default).
- **Consequences:** archived pages can lack receipts, so a verifier must decide whether to drop, label or reject such records. The teammate's code becomes part of what must be measured once its layout is known. If checking is turned on, the job file changes and the stack is measured again.

## ADR-003: Kernel route: Ubuntu 24.04's 6.17 kernel on the existing VMs

- **Date:** 5 October 2026. **Status:** accepted; fallback recorded.
- **Context:** extending RTMR3 needs kernel 6.16 or later. Ubuntu 22.04 offers Google kernels only up to 6.8; 24.04 offers 6.17 and 7.0. The mentor asked us to confirm the upgrade was needed and, if not too much trouble, to go ahead; later she left the choice to us. We preferred not to create a new VM.
- **Options:** (A) install 24.04's 6.17 kernel packages on the 22.04 VMs; (B) upgrade the whole OS in place; (C) create new 24.04 VMs.
- **Decision:** A. Safeguards: a snapshot of each boot disk first, a GRUB backup, the running kernel pinned as the default, a one-time boot request, checksums for both packages. Fallback: C if A fails.
- **Why:** smallest change, nothing else on the VMs is touched, and the measurement mechanism lives in the kernel, not in the userland on top. The package dependencies were satisfiable on 22.04, the new kernel's drivers needed for an initramfs-less boot are built in, and Secure Boot is off.
- **Consequences:** an unsupported combination, tested only on these two machines. The nodes return to 6.8 on the next reboot unless the default is changed. A clean, reproducible 24.04 image remains a later milestone.

## ADR-004: One RTMR3 event per component, with our own event log

- **Date:** 5 October 2026. **Status:** accepted.
- **Context:** RTMR3 only holds a hash chain, so a verifier needs a log to interpret it.
- **Decision:** extend once per component (JDK, JDK settings, CA list, Hadoop code, Hadoop config, deploy folder, driver, seeds), in a fixed order, recording `name, digest, before, after` in a tab-separated log; request the quote with the log as input so REPORTDATA is the log's SHA-512.
- **Why:** a verifier can see which component is wrong, and the log is bound into the quote.
- **Consequences:** the log must travel with the quote; the chain is lost at reboot and must be rebuilt; the first test marker stays in the master's chain.

## ADR-005: Measure the CA store as a sorted fingerprint list

- **Date:** 5 October 2026. **Status:** accepted.
- **Context:** the two nodes' CA store files differ in bytes but hold the same 121 certificates, with the same package versions.
- **Decision:** measure the sorted list of certificate fingerprints, not the raw file.
- **Why:** pinning the raw file would reject a valid node.
- **Consequences:** if the CA package changes, the list changes and is measured again.

## ADR-006: Measure JDK settings and the CA store as separate components

- **Date:** 5 October 2026. **Status:** accepted.
- **Context:** 26 files inside the JDK folder are symlinks into `/etc`; a folder fingerprint records the link, not the target.
- **Decision:** measure `/etc/java-11-openjdk` and the CA list as their own components.
- **Consequences:** the quote now identifies the Java settings and trust store as well as the binaries.

## ADR-007: Run 3 on fresh folders and a rebuilt job

- **Date:** 5 October 2026. **Status:** accepted.
- **Context:** the configuration is packed into the job file, so the two config fixes needed a rebuild.
- **Decision:** a separate run 3 with its own HDFS and evidence folders; runs 1 and 2 untouched.
- **Consequences:** run 3 is not byte-comparable with runs 1 and 2 (different job hash).

## ADR-008: Scripts in the repository, evidence outside it

- **Date:** 6 October 2026. **Status:** accepted.
- **Context:** the repository is public. Evidence is large, machine-specific (hostnames, IPs, disk identifiers) and derived.
- **Decision:** commit scripts under `attest/measure/` and `ops/`, with the filenames unchanged so each evidence bundle's script fingerprints match the committed files, and a `.gitattributes` forcing LF line endings there. Keep bundles outside the repo and list them, with fingerprints, in the milestone reports.
- **Consequences:** a fresh clone reproduces the tested scripts byte for byte; evidence must be stored and backed up separately.

## ADR-009: JDK start-up cache (`classes.jsa`)

- **Date:** 5 October 2026. **Status:** decided on 21 October 2026 by the image build (option (a)): the nodes of a fleet are made from one image, so they share one copy of the file, and the `jdk` event of their RTMR3 logs is equal on both nodes; the reference values of the locked image require both nodes to agree on all 15 stable events, `jdk` included ([milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md) section 6). **Update, 27 October 2026:** the file is removed from the image since step R4 (ADR-078, which supersedes this decision in part), so that two builds give the same `jdk` event; the nodes of one image still have the same `jdk` digest.
- **Context:** this one file differs between the nodes (generated per machine). Excluding it from the fingerprint would leave a file the JVM may load unmeasured; including it makes the two nodes' JDK digests differ.
- **Options:** (a) build one image and share one copy; (b) disable the cache and exclude the file; (c) keep per-node digests.
- **Decision:** deferred to the image build. Until then, per-node digests (c) are recorded as measured.

## ADR-010: Measure at run time now; lock the image down later

- **Date:** 5 October 2026. **Status:** accepted.
- **Context:** the handoff wants a read-only verified root disk, no login, and the stack extended into RTMR3 before any job runs.
- **Decision:** for Milestone 1, measure after boot and before the crawl, by script, and re-hash after the crawl. The read-only root, no-login image and a boot-time service belong to a later milestone.
- **Consequences:** the measurement shows what was there when measured; it does not prevent a change between measuring and running.

## ADR-011: Use the existing VMs, protected by snapshots

- **Date:** 5 October 2026. **Status:** accepted.
- **Context:** the kernel test could have used a temporary third VM.
- **Decision:** no extra VM. Snapshot each boot disk before any change (`tdx-lab-pre-kernel-1005`, `tdx-lab-worker-pre-kernel-1005`). Delete the snapshots when the kernel work is stable.
- **Consequences:** a small storage cost; a failed boot is recovered by resetting to the pinned kernel or restoring a snapshot.

## ADR-012: Documentation as we go; README and first-principles guide last

- **Date:** 6 October 2026. **Status:** accepted.
- **Decision:** write a milestone report when each milestone closes; update the living documents (limitations table, cluster configuration, quote verification, pitfalls, comparison) as facts change; keep this log. Leave `README.md` and `guide-first-principles.md` until the end of the technical work, because they summarise everything.
- **Consequences:** the README's file list lags until the end.

## ADR-013: WireGuard mesh: addressing and tooling

- **Date:** 6 October 2026. **Status:** accepted.
- **Context:** node-to-node traffic crossed the cloud network in plaintext.
- **Decision:** a two-node WireGuard mesh: master `10.10.0.1/24`, worker `10.10.0.2/24`, UDP 51820, one static peer each, keepalive 25 s. Tools from Ubuntu's signed archive (`wireguard-tools`, no recommended extras). Keys generated on each node; only public keys leave it; the interface starts at boot.
- **Why:** the kernel already includes WireGuard; it is small and simple; Google's internal-traffic rule already lets the UDP through.
- **Consequences:** one extra package on the VMs (outside the measured folders); static keys on the boot disk (root only); peer admission by attestation is a later milestone (the mesh's keys are not tied to quotes).

## ADR-014: Host firewall and hosts-file names instead of per-daemon binding

- **Date:** 6 October 2026. **Status:** accepted.
- **Context:** the master's RPC daemons bind through the name `hadoop-master`, but the NameNode web page and all of the worker's daemons listen on all addresses. Binding each daemon needs configuration differences between nodes.
- **Options:** (a) per-daemon bind settings in Hadoop's configuration files; (b) point the names at the mesh in `/etc/hosts` and close the ordinary interface with a host firewall.
- **Decision:** (b). The firewall accepts loopback, established connections, `wg0`, UDP 51820, SSH, ping and the metadata server, counts and drops the Hadoop ports on other interfaces, and drops everything else. A self-undo timer protects the first application.
- **Why:** Hadoop's configuration files stay identical on both nodes, so the measured configuration does not change; no restart-order subtleties; the counted rule gives evidence.
- **Consequences:** the wildcard listeners remain and depend on the firewall; the rules are not saved across reboot (the script is safe to re-run); the firewall and hosts file are not in the measured set. Per-daemon bind settings remain an optional second layer.

## ADR-015: Map the nodes' internal names to the mesh

- **Date:** 6 October 2026. **Status:** accepted.
- **Context:** after the hosts change the worker's NodeManager registered under Google's internal DNS name, which resolves to the ordinary address that the firewall blocks.
- **Decision:** add the two nodes' internal names (long and short) to `/etc/hosts` on both nodes, pointing at the mesh addresses; restart Hadoop; verify with a real job.
- **Consequences:** any name Hadoop might use for a node must resolve to its mesh address; check `yarn node -list` and run a small job after any network change.

## ADR-016: Refusal test without a third VM

- **Date:** 6 October 2026. **Status:** accepted.
- **Context:** the handoff asks for a job submitted from a third machine outside the mesh to be refused. We preferred not to create another VM (ADR-011).
- **Decision:** test over the ordinary network path between the two existing nodes, in both directions, with port probes and one real job submission aimed at the ordinary address, and read the firewall's counted drop rule before and after.
- **Consequences:** it shows that traffic arriving over the ordinary network is refused; it does not test a separate machine, IPv6, or a firewall that is absent after a reboot.

## ADR-017: Replace the implementation behind hdfs:// with the wrapper (Option B)

- **Date:** 6 October 2026. **Status:** accepted by the mentor; supersedes the author's earlier recommendation of Option A.
- **Context:** the handoff words the wrapper as a class registered under a custom scheme such as `attested://`. Three ways were weighed: A (a new scheme, with path translation), B (replace the implementation behind `hdfs://`), and a hybrid (A with a hidden storage root and an inventory).
- **Decision:** B, with three conditions from the mentor. (1) Swap both lookups, `fs.hdfs.impl` and `fs.AbstractFileSystem.hdfs.impl`; the second needs its own small adapter class, following the pattern Hadoop uses for its built-in file systems (`DelegateToFileSystem`, as S3A does). (2) Inside the wrapper, construct the real HDFS client class directly, never through a lookup by scheme, which would find the wrapper again and loop. (3) Keep the audit: list all of storage before and after a crawl and compare with the wrapper's log (ADR-018).
- **Why:** no path translation (Option A needs a translation layer; Hadoop's `ChRootedFileSystem`, the closest example, overrides 60 methods, and a scheme swap is a known rough edge of `FilterFileSystem`, whose own comment says other things break); every `hdfs://` request in a configured program is covered, including the six places where Nutch asks for the default file system.
- **Consequences:** the wrapper fails open, because a program without the two settings silently uses plain HDFS. Paths no longer show whether the wrapper was used, so the audit is the proof. The NodeManager, the daemons and the crawl script's two `hadoop fs` commands are not covered. The Option A prototype was never committed.

## ADR-018: The storage audit is the proof that the wrapper was used

- **Date:** 6 October 2026. **Status:** accepted.
- **Context:** with ADR-017 the paths look the same whether or not the wrapper handled a request.
- **Decision:** every JVM that loads the wrapper writes a local log line for each request that changes storage, and for opens, before forwarding it; the wrapper refuses to start if it cannot write the log. After a crawl, `audit_compare.py` checks that every difference between a listing of all of HDFS taken before and one taken after is explained by a log line (a path created, renamed, deleted, appended or changed), that moved files keep their size, and that every required host wrote a start-up line. No allow-list is used unless a stated reason exists.
- **Why:** it is the only check that does not depend on the wrapper's own claims; it was tested with planted faults.
- **Consequences:** it shows that no change that remains in storage came from outside the wrapper; it does not show reads, same-size edits, or files created and deleted between the two listings. The logs and listings are plain files on the provider's machines; the final design replaces them with signed records.

## ADR-019: Build and test in scratch folders; commit exactly what ran

- **Date:** 6 October 2026. **Status:** accepted.
- **Context:** the measured tree and the job of run 5 must stay reproducible, and code should enter the repository only after it has run on the cluster.
- **Decision:** unpack new files into a scratch folder on the master and test there; build the job in a scratch clone and compare it with the measured job entry by entry; commit only files whose fingerprints equal those recorded when they ran, and check them from a fresh clone.
- **Consequences:** the job of run 6 is not the measured job, so the measurement chain does not cover run 6; it is redone, after a reboot, when the job next changes (ADR-020). A clean clone builds a different job from the measured one because of an untracked file, `conf/effective_tld_names.dat`, which was copied into the clone.

## ADR-020: Defer the re-measurement until the job next changes

- **Date:** 6 October 2026. **Status:** accepted by the author and the maintainer; the mentor is asked to confirm. **Carried out on 14 October 2026 (ADR-040).**
- **Context:** the measured set is the main tree, and it is unchanged (all ten components `SAME` after run 6). Run 6 ran from a scratch build outside it. `measure-all.sh` refuses to measure twice in one boot, so covering the new job needs a reboot of both nodes. A reboot also removes the firewall rules, stops the daemons that were started by hand, returns each node to the pinned 6.8 kernel (which has no measurement interface) and needs a one-time boot into 6.17.
- **Decision:** do not reboot now. Re-measure, from a clean boot, when the job next changes; the next milestone changes it. Until then, record that run 6 is not covered by the chain and keep running `check-unchanged.sh` to show the measured tree is intact.
- **Why:** a measurement now would cover a state that is about to be replaced, at the price of a reboot's risks; the Gate A measurement item already passed in Milestone 1.
- **Consequences:** run 6 is not in the chain, and the documents say so. The next measurement points `NUTCH_DIR` at the build folder that holds the hashing layer.

## ADR-021: Keep each file's record next to the file

- **Date:** 7 October 2026. **Status:** accepted by the author and the maintainer; the mentor is asked to confirm.
- **Context:** verifying a read needs the file's record at read time, on any machine, and the record must survive the renames Hadoop performs while committing output. There is no ledger and no signing yet (Stage C).
- **Decision:** a hidden companion file `.NAME.attested` in the same folder, written when the file is closed (format `ATTEST01`: length, chunk size, the hash of every chunk and the Merkle root). The wrapper moves it when the file is renamed (a renamed folder carries it along), deletes it with the file, drops it when the file is appended to, truncated or concatenated, and hides it from its own listings.
- **Why:** it is the pattern of Hadoop's own `.NAME.crc` files; it follows renames without a central index; any machine can read it. Alternatives were a central record store (it needs a rename-aware index, and the Stage C ledger will hold the hashes anyway) and records only in local logs (other machines cannot read them).
- **Consequences:** plain HDFS tools list the companion files. Until records are signed, rewriting a file and its record together is accepted (a test states this). If the mentor prefers another store, the read and write code of `AttestedSidecar` is what changes; the format is versioned so that signing adds fields.

## ADR-022: Records come from the wrapper when a file is closed, not from the commit hook

- **Date:** 7 October 2026. **Status:** accepted by the author; to be put to the mentor as question 13 (not asked yet).
- **Context:** the handoff has the task's output committer sign the record. Step 4.1 found that Nutch's fetch, parse and WARC outputs are written directly to their final path, and that the parse output creates its own committer, so the committer hook set by configuration does not see every file.
- **Decision:** the wrapper makes a record for every file when it is closed, tagged with host, process, job id and the task attempt id read from the task's configuration. The committer stays an optional extra for manifests.
- **Why:** the wrapper is the one place that sees every file, whatever output format wrote it.
- **Consequences:** a file whose writer is killed before closing it has no record; the completeness of a job's outputs (step 4.7) has to come from the per-attempt records and Hadoop's counters. If the mentor wants the committer as the main source, a custom committer is needed for the parse output (medium effort), and the wrapper's records can stay as a second line of defence.
- **Update (10 October 2026):** question 13 is moot. ADR-034 drops the task records and the job manifests, so the wrapper is no longer asked to be the source of anything beyond the signed per-file record.

## ADR-023: A file without a record is allowed but logged, for now

- **Date:** 7 October 2026. **Status:** accepted (provisional); superseded in part by ADR-038 (13 October 2026): `attested.verify.missing` now defaults to `fail`, so opening a file without a record is refused, and only the status and listing questions keep a `warn` default.
- **Context:** some data is put into HDFS by the command-line client (the seed file), which does not use the wrapper; the crawl has to run, and the first goal is to find which paths lack a record.
- **Decision:** the setting `attested.verify.missing` defaults to `warn`: the open is logged as `verify=missing` and the file is read unverified. The verification summary lists such reads, and each use of its allow list needs a stated reason (run 8: the seed folder). The default becomes `fail` when every writer goes through the wrapper.
- **Why:** it keeps runs going while the gaps are found, and every gap is visible.
- **Consequences:** until the default is `fail`, a file that has no record, or whose companion file was removed with plain tools, is read unverified; the summary shows it.

## ADR-024: Naming, the commit gate, and checking assumptions against real samples

- **Date:** 7 October 2026. **Status:** accepted.
- **Context:** the working labels B0 to B5 confused the author; a tamper demo and several expected values were wrong because they were written from assumptions about other tools' output and tested with stand-ins built from the same assumptions; code and documents must match what actually ran.
- **Decision:** (1) names are Milestone N and Step N.k with a descriptive title, runs are numbered, and the handoff's item numbers stay as references. (2) A commit gate: committed programs and scripts are checked identical, by fingerprint, to the files that ran, on the cluster, on the laptop and in a fresh clone from GitHub; on any difference the commit and push are aborted. The documents are checked against the procedure followed and against the evidence (`docs_facts_check.py`). (3) Before a check depends on another tool's real output, a read-only sample of that output is read; proofs rely on what our own code writes (audit lines, records).
- **Why:** unverified assumptions cost hours of repeated steps on 7 October.
- **Consequences:** a little slower per step and much fewer repeats; each milestone has a facts file that ties the documents' numbers to the evidence.

## ADR-025: Rehearse code with the real libraries; documents and programs in separate commits

- **Date:** 7 October 2026. **Status:** accepted.
- **Context:** the first version of the contract tests was only type-checked against stand-ins written from the author's own assumptions, and failed at compilation on the cluster. The author asked for documents and programs to be kept apart in the history.
- **Decision:** (1) code that depends on real libraries is rehearsed in the development environment with those libraries (or the nearest available versions) before it is sent to the cluster, and the message says what could not be rehearsed. (2) Documents and programs are committed separately, each with its own gate: programs first, each checked identical to the files that ran; then documents, checked against the evidence by the facts checker. A tool's data file (for example a facts list) is committed as a program. The one earlier exception is commit `d4c5489`, which also carried the facts checker.
- **Why:** the rehearsal found three defects in the wrapper and one in the runner before the cluster run, and a clear separation makes the history easier to read and review.
- **Consequences:** some libraries are not reachable from the development environment, so a rehearsal can use a different version (AssertJ 3.14.0 instead of 3.12.2) or leave one class out (`VectoredRead`); each such gap is stated in the report.

## ADR-026: The mentor's answers of 7 October 2026

- **Date:** 7 October 2026. **Status:** accepted by the mentor.
- **Context:** the questions of 6 October (1 to 5 for Gate A, 6 to 12 for Stage B) were answered. The mentor's reply, as relayed by Rishab (the "(teammate S)" is his note):

  > This seems fine. We might have to fix things afterwards
  >
  > Gate A accepted. (1) Yes; from Stage B on, run the unwrapped control in the same hour. (2) Yes as scoped; turn on the NameNode audit log in Stage B. (3) Defer, as long as nothing unmeasured is ever described as measured. (4) Apply the handoff corrections now, in one commit with a corrections list at the top. (5) Nothing new until the 16 October list; plan for mid-November to 20 November, 5 pages plus 2.
  > For Stage B, use your defaults except 6: a task hashing its own job file can be skipped by a swapped job file, so it isn't a security check. Move the wrapper onto Hadoop's own classpath and set both lookups in the site config as final, so the NodeManager uses it too. 11 is Subhi's (teammate S) patch: please coordinate with her on building the job with it. Per Amir, performance is the result that matters most, so start recording wall time and bytes fetched for every wrapped and unwrapped pair.

- **Decision:** the mentor said:
  1. Gate A is accepted. (1) The evidence for "outputs match" is enough; from Stage B on, run the unwrapped control in the same hour (ADR-028).
  2. (2) The audit's scope is accepted; turn on the NameNode audit log in Stage B (step 4.5, baby step 4.5.2).
  3. (3) The re-measurement is deferred, as long as nothing unmeasured is ever described as measured (ADR-029).
  4. (4) The handoff corrections are applied now, in one commit with a corrections list at the top ([handoff-attested-hadoop-cluster.md](handoff-attested-hadoop-cluster.md)).
  5. (5) Nothing new until the 16 October list; the workshop paper is planned for mid-November to 20 November, 5 pages plus 2.
  6. For Stage B our defaults stand (HDFS; a test key behind an interface; hash everything with a path filter; a witness interface with a local stand-in; contract tests first), except question 6, which becomes ADR-027, and question 11, per-fetch TLS evidence, which is teammate S's patch: the job is to be built with it in coordination with her (Milestone 5, step 5.3).
  7. Per Amir, performance is the result that matters most: wall time and bytes fetched are recorded for every wrapped and unwrapped pair (ADR-028).
- **Why:** these are the mentor's decisions.
- **Consequences:** the plan of six milestones is unchanged ([milestone-plan.md](milestone-plan.md)); the changes land inside existing steps as baby steps (4.5.2, 4.6.1 to 4.6.3, 5.3.3). Question 13 (records from the wrapper or from the commit hook, ADR-022) has not been asked yet and keeps its default.

## ADR-027: The wrapper on Hadoop's own classpath, both lookups final

- **Date:** 7 October 2026. **Status:** accepted by the mentor; changes the content of step 4.6.
- **Context:** step 4.6 was planned as a check of the job file's digest inside the task. The mentor said a task hashing its own job file can be skipped by a swapped job file, so it is not a security check. Until now the wrapper was switched on per job by `-D` options, so the NodeManager (which reads the job file through plain HDFS) and any program without the options bypassed it (ADR-017, ADR-018).
- **Decision:** the mentor said to move the wrapper onto Hadoop's own classpath and set both lookups in the site configuration as final, so the NodeManager uses it too. (1) The wrapper's classes are put onto Hadoop's classpath on both nodes, built from the same sources as the classes in the job file. (2) `fs.hdfs.impl` and `fs.AbstractFileSystem.hdfs.impl` are set as final in the site configuration on both nodes, so a job cannot override them. (3) The NodeManager's read of the job file then goes through the wrapper and is checked against the record made when the client uploaded it. The step keeps its name; these are its baby steps 4.6.1, 4.6.2 and 4.6.3.
- **Why:** it removes the fail-open weakness of ADR-017 for everything that reads the site configuration, and it closes the job-loader gap that the handoff left open.
- **Consequences:** the Hadoop installation and configuration change, so the measured set changes and the re-measurement (ADR-020, ADR-029) must cover them. A failure of the wrapper now affects every client, including the daemons and the command-line tools (whose files get records too), so the change needs a staged rollout, a rollback and a switch between the wrapped and the plain configuration, which the control runs of ADR-028 also need. The settings of the wrapper stay non-final.
- **Outcome (9 October 2026):** done in step 4.6 (commits `fcffad09d`, `bef3a6452`, `9ef0f405d`, `28c811ff4`). The NodeManager's own process opened the four files of each of run 9's 27 jobs through the wrapper (108 opens, all verified) and refused a swapped file it fetched; a first switch failed and rolled back by itself because Hadoop's admin tool refuses the wrapper (ADR-031). A final setting stops a job's settings file but not a command-line `-D` or code in a JVM, so it is not a lockdown (limitations row 59). Report: [milestone-4-storage-integrity.md](milestone-4-storage-integrity.md) section 20.

## ADR-028: Every wrapped crawl has an unwrapped control in the same hour; wall time and bytes fetched are recorded

- **Date:** 7 October 2026. **Status:** accepted by the mentor.
- **Context:** run 6 had no contemporaneous unwrapped run. The mentor said that from Stage B on the unwrapped control is run in the same hour, and, per Amir, that performance is the result that matters most.
- **Decision:** from now on every wrapped crawl is paired with an unwrapped control run in the same hour (the order alternates). For every run the pair table records the wall time, the bytes fetched, and the HDFS bytes read and written. The unwrapped run uses the plain configuration and the measured job. This is a rule for every crawl, not a step; the first pair is the crawl that follows the re-measurement (step 4.8), and the results table belongs to Milestone 6, step 6.3.
- **Why:** pages change between runs (a live site redeploys), so bytes fetched must be recorded to compare times fairly.
- **Consequences:** the cluster needs a switch between the wrapped and the plain configuration (baby step 4.6.2); each pair costs about two crawls.

## ADR-029: Nothing that is not measured is described as measured

- **Date:** 7 October 2026. **Status:** accepted by the mentor.
- **Context:** the re-measurement is deferred (ADR-020); runs 6 and later used jobs outside the measured set. The mentor accepted the deferral as long as nothing unmeasured is ever described as measured.
- **Decision:** every document, table and sentence of the paper that mentions a run says whether it is covered by the measurement; anything that ran outside the measured set is called "unmeasured" or "not covered by the measurement", never "measured". Here "measured" means covered by the attestation measurement of Milestone 1; timing a run is a different thing, and the documents avoid the word for it.
- **Why:** the claim of the project is about the exact build that ran.
- **Consequences:** the facts checks include the phrase for the runs concerned; the re-measurement, when it happens, is described by what it covers.

## ADR-030: Answers about files are checked against the records; findings fail closed by default

- **Date:** 8 October 2026. **Status:** accepted.
- **Context:** the handoff wants all metadata from records, never from storage. Until step 4.5 the wrapper compared a file's length with its record only when the file was opened; its listings only hid the records. A file that was shortened, removed or slipped in behind the wrapper's back was noticed only if something read it.
- **Decision:** (1) `getFileStatus` and the listings are checked against the records: a length that differs from the record, and a record whose file is gone, follow the setting `attested.metadata.mismatch`, default `fail`; a file without a record follows the existing `attested.verify.missing`, default `warn`. (2) The default for a mismatch is to refuse, because a mismatch is the signal this step exists to give; a file without a record stays allowed because files put in by programs that do not use the wrapper, and files still being written, are normal today. (3) A listing is read in full before it is returned, so that the records in it can be seen. (4) A record's length is remembered for 10 seconds and is always read again before a refusal, so that a rewrite by another program is not a finding. (5) A finding is logged once per file per program, and a refusal each time. (6) The NameNode's audit log is switched on (the mentor, ADR-026) and compared with the wrapper's log by operation, path and time, because every client on a machine shows with the same user and address.
- **Why:** it closes the gap between "the file was checked when read" and "the answer about the file was believed"; the contract tests show no false alarm and the real-HDFS tests show the detection.
- **Consequences:** one more small read per file question and one more check per missing path, to be measured in the paired runs (ADR-028); listings of very large folders are read in full; the records are still not signed, so someone who rewrites a file and its record together is not caught (step 4.7, Milestone 5).

## ADR-031: The audit, admin and demo tools ask for the plain client explicitly

- **Date:** 9 October 2026. **Status:** accepted.
- **Context:** since step 4.6 the wrapper is the cluster's default file system (ADR-027), so a plain `hdfs dfs` goes through it. That would hide the record files from the audit's listing, make the independent re-hash read through the wrapper, and turn the tamper demo's change "behind the wrapper's back" into a wrapped write. Hadoop's admin tool (`hdfs dfsadmin`) refuses any file system that is not a `DistributedFileSystem`, the wrapper included (found when the first switch failed on 8 October; Hadoop 3.4.3, `AdminHelper.checkAndGetDFS`).
- **Decision:** every tool that must see HDFS as it is, not as the wrapper shows it, passes `-D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem` itself: `audit.sh`, `records_verify.sh`, `tamper-demo.sh`, `nn-audit.sh`, `nn-audit-probe.sh` and `cluster-mode.sh`. A command-line option can override a final setting (tested), which is the intended use. Admin calls are not data operations, so they use the plain client. The two scripts of `ops/mesh/` were not edited because they cannot be run without a network change; they need plain mode.
- **Why:** an inspector must not depend on the guard it inspects, and a tool must not depend on the cluster's current mode.
- **Consequences:** the 5 changed scripts were run on the cluster in their final form (one branch of `nn-audit.sh` only in rehearsal); a plain client is still available to anyone who asks for it, so `final` is not a lockdown (limitations row 59; the lockdown is Milestone 5).

## ADR-032: Before a crawl, rotate the logs and restart the wrapped daemon; collect the container logs right after

- **Date:** 9 October 2026. **Status:** accepted.
- **Context:** the first rotation after the switch moved the NodeManager's open log file, and the NodeManager went on writing into the archived file, so its reads were missing from the clean folder. Run 9's container logs expired before they were collected, because log aggregation is off and YARN deletes them after its retention time (3 hours by default).
- **Decision:** on the worker, `audit.sh rotate` is followed by `cluster-mode.sh wrapped --restart-yarn` before the crawl, so the NodeManager starts a new log file; `audit.sh rotate` warns about any process that wrote a moved file and is still running; the container logs are collected right after the crawl. No cluster setting is changed for this.
- **Why:** the NodeManager's reads are exactly the evidence step 4.6 exists to produce, and the container logs are the only record of why a task failed.
- **Consequences:** one more command per crawl; the measured runs follow the same procedure.

## ADR-033: The NameNode comparison gets two explicit rules, visible and switchable

- **Date:** 9 October 2026. **Status:** accepted.
- **Context:** the first comparison of a whole crawl had 26 unexplained opens and 27 unmatched wrapper lines. The data showed two causes: one upload writes two wrapper lines (`COPYFROMLOCAL` and `CREATE`) against one NameNode create, and a job's client asks the NameNode where the input's blocks are, which HDFS audits as `open`.
- **Decision:** `nn_audit_compare.py` pairs the two lines of an upload only if the other line was itself matched to a NameNode event, and counts an `open` as a submission lookup only if the same client address created the job's `job.jar` before it and its `job.split` after it (from the NameNode's own log), never for a create, delete or rename. Both are printed as their own lines, never merged into "explained", and `--strict` turns both off. A delete with `allowed=false` is listed as "removed nothing", not as denied, because HDFS writes the result of the delete there.
- **Why:** an exemption written quietly would hide the next real difference; a rule that is printed, bounded and tested does not.
- **Consequences:** the 26 lookups of run 9 rest on timing, because the NameNode cannot tell a lookup from a read and the DataNode does not log reads here (limitations row 60); turning on the DataNode's client trace at run time for the measured runs is an open item.

## ADR-034: Storage integrity rests on one mechanism, sign on write and verify on read; step 4.7 and the task records are dropped

- **Date:** 10 October 2026. **Status:** accepted (Pingshan's decisions after step 4.6, recorded in [next-steps-storage-signing.md](next-steps-storage-signing.md)).
- **Context:** after step 4.6 the wrapper hashes every file at close and verifies every read, with unsigned records. Step 4.7 planned task records and job manifests, and question 13 (may the wrapper be the main source) was open.
- **Decision:** storage integrity rests on **sign on write, verify on read, with the VM's signing key**. There are no per-task records, job manifests, per-file history, folder tracking, "start" records or commit hook, and step 4.7 is dropped. The wrapper stays a plain file-system layer with no Hadoop logic in it. The Merkle log and the witness are deferred (the mentor's view: nice to have, not crucial). The verifier checks the final files: signature, key, quote, measurements and hash, instead of walking the chain back to the seed list.
- **Threat scope for storage.** In scope, to be prevented: tampering with stored bytes; forgery of a file that no attested VM wrote; a validly signed file placed in a different folder or under a different name (Hadoop names output files identically in every folder, so this would otherwise be trivial). Noted and out of scope: deletion (a file removed together with its record) and rollback (an older, validly signed file or folder put back), because neither can tamper with or insert data. A signed per-folder tracking file or ledger was considered and rejected: one shared file serialises every writer in the folder and can itself be rolled back, and per-writer ledgers still need a sealing step.
- **Consequences:** retries, duplicate attempts and re-runs are not visible (a provider can re-run a job and keep the run it prefers; every run is genuine); an outside verifier cannot re-check intermediate steps and trusts that measured code verified its own inputs; a bug in the wrapper's verification would not be caught downstream, so the wrapper is small and reviewed closely. The recon of step 4.7 (report section 21) stays as history. The next steps are A1 to A4, B1 to B4 and C1 to C4 (plan section 8).

## ADR-035: Folder identity files bind a file to its folder

- **Date:** 10 October 2026. **Status:** accepted (Pingshan); the details marked "ours" are to be settled while building (step B2).
- **Decision:** when a folder is created, the wrapper gives it a random ID and writes a small signed identity file inside it, covering the folder's ID, its own name and its parent's ID (the crawl's top folder binds to its full path). A file's signed record covers the folder's ID, the file's name, the content hash (our chunked Merkle root) and the length, and **not** the full path. Renaming a file signs a new record for that one file; renaming a folder re-signs only that folder's identity file, so the files inside and the folders below are untouched and no data is re-read. A read checks the record's signature, that the key belongs to an attested VM, that the record names this file and this folder's ID, the identity chain up to the top, and each chunk against the hash; anything missing or mismatched fails the read.
- **Why:** a full path in every record makes a folder rename re-sign everything below it, and Nutch renames whole folders (it swaps in the new crawl database); signing only the file name makes renames free but lets same-named files be swapped between folders. The folder identity keeps the binding and makes a folder rename one small write.
- **Details to settle:** two tasks may create the same folder at once (the first identity file written wins, created without overwrite); the identity file's name starts with `_` so that Hadoop's input listing skips it, and it is hidden from listings like the companion files; folders that exist before the wrapper is in use (the crawl's top folder, the seed folder) get an identity file from the driver. **Ours:** in run 9 the output committer moved files one by one, some into folders that already existed, so an identity file must never be moved like an ordinary file, or it would replace the destination's identity; this needs a rule and a test.
- **Consequences:** the pass conditions of B2 (a signed file or a whole folder copied elsewhere fails the read; a folder rename writes one identity file and re-signs no file record; a normal crawl with Hadoop's commit renames and Nutch's folder moves still passes).

## ADR-036: The WARC is the point where teammate S's layer and ours connect

- **Date:** 10 October 2026. **Status:** proposed by teammate S in her message of 10 October, consistent with ADR-034 and ADR-035; not yet validated end to end (her patch ran in runs 11 to 13; her verifier has not been run on our exports).
- **Context:** her patch (repository `Heron-AI-Security/training-custody`, branch `subhiksha/source-provenance`, commit `6128bc0`, applies to our `d4d520f`) embeds a source receipt and the TLS handshake evidence in WARC metadata records, and each fetch task writes attempt-scoped files `tc_receipts/receipts-<attempt>.jsonl`, `handshakes-<attempt>.jsonl` and `outcomes-<attempt>.jsonl` in its work output folder.
- **Decision:** the signed commitment to the WARC (its Merkle root, signed with the quote-bound VM key) is the link between the two verification paths, so no separate signing of her evidence is needed; her outcome files are covered the same way, because every file written through the wrapper is signed. Our verifier checks the signed commitment and the attestation binding, hers checks the embedded receipts, response hashes, certificate evidence and policy.
- **Open, with Pingshan:** how the collection policy is authenticated (packaged with the measured workload, or signed by the driver and distributed through HDFS), and whether the measured job lets the crawler reject invalid certificates itself (ADR-002). **To verify, not to assume:** that the trust anchors and the policy used by a task are covered by the measurement; that the baseline runs of the performance pairs do not inherit her key-free capture option (`-Djavax.net.debug=ssl:record:plaintext`, set per job in `mapreduce.map.java.opts`, never globally).
- **Consequences:** her patch changes existing Nutch classes (our branch alone only adds files); the combined validation list is in her message (the patched job builds and runs on our branch, both kinds of evidence are emitted, WARC contents match the signed commitments, failed attempts leave no authoritative evidence, both verifiers accept the same WARC, and the performance pairs use consistent configurations).

## ADR-037: The mentor's answers of October 2026 on policy, certificates, single-record verification, performance, TLS capture and the threat model

- **Date:** October 2026. **Source:** a message from the mentor to the team; it is not a file in the repository. **Status:** accepted as the mentor's direction; the consequences below were taken into the plan on 13 October 2026 (milestone-plan.md, steps 5.3.3, 6.1 and 6.3).
- **Collection policy:** packaged in the measured image. Where it lives in the driver script matters little, because the driver script will also be packaged in the measured image (this closes the open item about the policy in ADR-036).
- **Certificate checking:** CCBot should note an expired certificate in the source receipt and inform instead of rejecting; downstream quality filters decide whether to include that data in training.
- **CDX byte range and record verification:** verification should work on a single record. It is on the whole WARC now and has to be broken down.
- **Performance:** the control is a vanilla CCBot run on the cluster. Benchmarks must compare wrapped and unwrapped runs and more, to find where the cost comes from (the WireGuard mesh, TLS dumping, the wrapped HDFS or something else). This is the core of the experiment; the mentor asked the teammate whether she wants to own part of it.
- **TLS evidence:** parsing messages from the Java debugger is unlikely to be accepted as production code. The options he names: a different TLS library (maybe Bouncy Castle), building our own TLS stack (no), instrumenting Java internals (brittle, probably not production grade), patching the Java library (no), or generating no TLS signature at all and trusting the TEE (the last and least reliable option).
- **Threat model:** TEEs are secure unless there is physical access (the tee.fail attack needs a memory-interposition board soldered on). Our threat is insiders: a bad actor within the CC foundation or a frontier lab tampering with the crawl process. Physical access to the machines is a tall assumption. The signature authority (the TEEs) needs its own assumptions, such as physical security, which are acceptable.
- **Consequences (to apply):** step C3 widens to a piece-by-piece measurement with a vanilla control; the verifier needs a check of a single record (our records hold a hash for every 16 KiB chunk of a file, so a byte range can be checked against the chunks that cover it, but the procedure is not written); the teammate's key-free capture, which needs a JVM debug option, is in question; the certificate setting of her patch (it rejects) should become note-and-continue.

## ADR-038: Reading a file's content and asking about its status are two different questions, with two settings for a file without a record

- **Date:** 13 October 2026. **Status:** accepted (found on the cluster by the contract tests; the mentor's step A2, baby step 4.6.5, asked for the first of the two).
- **Context:** step A2 asked that reading an unrecorded file fail. The first version used the one setting `attested.verify.missing` for that and for status and listing questions; on the real HDFS the contract test `testSyncable` then failed through the wrapper, because a file that is still being written has no record yet and the status question about it was refused.
- **Decision:** `attested.verify.missing` (default `fail`) governs **opening a file** to read it. `attested.metadata.missing` (default `warn`: answer from storage and log once; `allow` and `fail` are the other values) governs **status and listing questions**. A status question exposes no content; opening an unrecorded file is what is refused.
- **Consequences:** a file still being written cannot be read through the wrapper (its record is made at close), and shows as one expected difference in the contract comparison; a listing can show an unrecorded file that cannot be opened (limitations rows 75 and 76).

## ADR-039: The wrapper's own settings count only when the site configuration set them

- **Date:** 13 October 2026. **Status:** accepted; it differs from the mentor's wording for step A3, baby step 4.6.6 ("mark them final in the site configuration, or remove them"), and meets its pass condition.
- **Decision:** a setting of the wrapper (`attested.hash.enabled`, `attested.hash.chunk.size`, `attested.sidecar.enabled`, `attested.verify.reads`, `attested.verify.missing`, `attested.metadata.check`, `attested.metadata.mismatch`, `attested.metadata.cache.seconds`, and `attested.metadata.missing`) is obeyed only when its last source, as Hadoop records it, is `core-site.xml` (or the default resources). A setting from a job file, a `-D` on the command line or code is ignored, the secure default is used, and the `INIT` line of the wrapper's audit log names the setting and its source (`ignored=`).
- **Why not only `final`:** marking a setting final in the site file stops a later settings file but not a `-D` or a call in code; the source rule stops all three, and it lets the smoke tests feed settings from code through a hook that is private to the package.
- **Scope:** the two log-folder settings (`attested.audit.dir`, `attested.records.dir`) are not covered, because four scripts pass them with `-D`. The rule defends against unmeasured settings, not against code in the JVM; a job that shadows `core-site.xml` on the class path would also replace our classes, which the measured job and the fixed driver close (limitations rows 73 and 74).


## ADR-040: The re-measure covers the patched job, the policy folder and the repository's ops folder, and needs a one-time boot into 6.17

- **Date:** 14 October 2026. **Status:** accepted. It carries out ADR-020; the mentor's note of 10 October (section 8) asks for the job to be built with the teammate's patch and re-measured; ADR-029 (nothing unmeasured is described as measured) stays.
- **Context:** the measured job was still the baseline of 5 October, while runs 6 to 11 used other jobs. The teammate's design puts the collection policy into the measured image (ADR-037). A normal reboot returns both nodes to the pinned 6.8 kernel, which cannot extend RTMR3, and the firewall rules are not saved across a reboot.
- **Decision:** (1) point `NUTCH_DIR` at the scratch build of step 4.8.1 (`~/m481/patched`), as ADR-020 planned, so that the old tree is not touched; (2) add one measured component, `tc-policy` (the folder `~/tc-policy` with `policy.json`), on both nodes, so the master has 9 events and the worker 6, and drop the two test events of Milestone 1; (3) before each re-measure ask GRUB for one more boot into 6.17 (`grub-reboot`; the pin on 6.8 stays); (4) after the boot, in this order: the firewall (saved before, applied again under a new backup name and compared with the saved one), the measurement, the quote and its replay, a recompute of every digest, and only then the daemons.
- **Why:** the order proves the measurement before anything runs; the new backup name keeps the original rules that the undo instructions refer to; the policy must have the same digest on both nodes because the receipts check it on whichever node runs a task.
- **Consequences:** the measured `driver` is the repository's whole `ops` folder at the commit (84 files); the kit scripts that start our runs are not in it, and only the fixed driver (step 5.3.2) closes that (limitations row 78). Every re-measure costs a reboot of both nodes and about an hour. The kit is `ops/kits/m482/`; the results are in [milestone-4-storage-integrity.md](milestone-4-storage-integrity.md) section 23.3.

## ADR-041: A timing pair: the wrapped run first, then a plain control with the same job, seeds and settings, then the wrapped settings restored and proved

- **Date:** 14 October 2026. **Status:** accepted. It carries out ADR-028 for the first pair.
- **Context:** the control needs the plain configuration, and switching to it changes `core-site.xml`, which is in the measured set.
- **Decision:** run the wrapped run first and check the measured set right after it; switch both nodes to plain (`cluster-mode.sh plain --restart`, master first); run the control with the same patched job, the same seeds and the same receipt settings (receipts on in both, so that only the file system differs); switch both nodes back and prove with the measured-set check that `core-site.xml` and every other component equal the measurement. The control is outside the measurement and is called so. The numbers are the wall time of the crawl command, the jobs completed, Hadoop's byte counters per file system, the bytes stored in HDFS (new files, the record files separately), the NameNode events of the window, and, from the WARC files, the pages and their payload bytes; a value that cannot be found is printed as "not found", never as 0.
- **Why:** it keeps the covered run covered, it makes the control a real control (same pages), and the proof after the restore shows that the switch left no trace.
- **Consequences:** a pair costs about 40 minutes and two switches of both nodes; the order should alternate in later pairs (ADR-028); the results table belongs to step 6.3 and one pair is not a result.

## ADR-042: Kits are committed as folders exactly as they ran, without other people's code and without evidence

- **Date:** 14 October 2026. **Status:** accepted; publishing the teammate's files needs her consent and the mentor's.
- **Context:** the scripts of step 4.8 ran from kit folders (zips) with fingerprints; the first rule of the project is that committed files are identical to the files that ran. Two kits also held the teammate's patch and her policy builder, which come from her private repository.
- **Decision:** each kit goes under `ops/kits/<kit>/` with its layout unchanged, in script-only commits, after a gate compared every file with the fingerprint of the zip (or of the evidence copy, for the three tools that ran as single files) that ran. Rehearsal transcripts and file lists are evidence and stay outside the repository with their fingerprints. The teammate's patch and policy builder are not committed: they are identified by her repository, commit `841c1d3`, the patch's blob id and SHA-256, and the fingerprints in `ops/kits/m481-policy/m481r-src.sha`; a check of the branch hashes every file and finds none of them. Known flaws stay as they ran.
- **Why:** her work is unpublished and its licence and authorship are hers to decide; a copy committed by us would also show us as its author. The experiment stays identifiable and checkable without it.
- **Consequences:** the build and policy kits cannot be re-run from the repository alone; the paper's artifact will need her consent (preferably through her own commit to our branch, step 5.3.3). A fixed version of a flawed script is a new file that must run before it is committed.


## ADR-043: The teammate works on the cluster through a read-only copy of the measured client, her own HDFS folder and a reservation marker

- **Date:** 15 October 2026. **Status:** accepted. It answers the teammate's request of 14 October (a shared install, per-user HDFS folders, seeds recorded under rule A2, and her rules); the kit is `ops/kits/tcshared`.
- **Context:** the Hadoop install, the client configuration and the wrapper jar lived in the author's private home folder, so nobody else could submit jobs. Hadoop's simple authentication lets any user act under any name, so nothing here can be enforced against a bad actor; the mentor's threat model is about insiders, and the aim is a clear, honest working arrangement between two people.
- **Decision:** (1) a read-only, root-owned **copy** (never a move) of the Hadoop client tree and of the measured job folder in `/opt/tc-shared`, proved equal to the measurement of 14 October by recomputing the measured digests of `hadoop-code`, `hadoop-conf` and `nutch-deploy` on the copy; (2) `tc-user-add.sh` gives a Linux user an HDFS folder `/user/<name>` and makes the YARN staging folder writable for everybody; (3) `tc-seed.sh` puts a seed file into HDFS through the wrapper, so that it has its record; (4) `tc-busy.sh` is a reservation marker (start, stop, status) with the rule that nobody runs anything during someone else's measurement, a timing pair or a reboot; (5) the wrapper's two log folders in `/tmp` are made writable for every user (mode 1777, recreated at every boot by `/etc/tmpfiles.d/zz-tc-shared.conf`, a name that sorts after the system's `tmp.conf`); (6) `tc-check.sh` is a one-command test that a user's setup works.
- **Why:** a copy keeps the measured components where they are, so the measurement stays valid; the proof by digests shows that what she runs is the measured stack; the marker is simple, visible to both, and protects the timing pairs and the reboots.
- **Consequences:** the marker is an agreement and not a lock; the shared client is the measurement of 14 October and must be refreshed when the measured files change (limitations rows 92 to 95); the log folders in `/tmp` are shared; only the measured job may run.

## ADR-044: Records are signed with ECDSA P-256 under a labelled test key in format ATTEST02; everything is off by default and unsigned records stay readable until signatures are required

- **Date:** 15 October 2026. **Status:** accepted. The mentor's note of 10 October answers the design (sign on write, verify on read; a test key is fine for now, clearly labelled and never used in evidence) but not the choices below; the author took the recommended defaults.
- **Context:** step 5.1.1 must show that a file rewritten together with its record, without the key, fails the read. The wrapper must later take the key from a signing service bound to the quote (step 5.1.3) without being rewritten, and the folder binding of step 5.1.2 needs a new record version.
- **Decision:** (1) the scheme is ECDSA with P-256 and SHA-256, built into the Java 11 of the cluster, so that nothing new has to be installed, measured or trusted, and the same scheme can serve the real key; (2) a record in the new format `ATTEST02` is the old record plus a signature block over a statement of key id, chunk size, length and root; the old format is still read, and still written when signing is off; (3) a key id of a test key always starts with `TEST-`, and `attested.signature.allow.test.keys` lets the real-key mode refuse test keys; (4) everything is off by default (`attested.signature.enabled`, `attested.signature.required`), so that nothing changes until the site configuration says so and the files of earlier runs stay readable as legacy; (5) a signature that does not verify is always refused; (6) the key sits behind an interface (`AttestedKeys`), with the test key as its first implementation; (7) the identity file of step 5.1.2 is called `_attested-folder`.
- **Why:** the choices keep the later steps to a change of the key source and of the record version, not of the wrapper; the defaults make the step safe to ship while the demonstration turns the strict settings on.
- **Consequences:** a downgrade to the old format is accepted until `attested.signature.required` is on (limitations row 86); at the end of Milestone 5 unsigned files must be refused (the mentor's C1), so the old data of runs 10 to 13 will not be readable through the wrapper then; the signature does not cover the file's name or folder until 5.1.2 (row 88).

## ADR-045: A window: a reserved, temporary and fully restored change of the measured stack

- **Date:** 15 October 2026. **Status:** accepted. It carries out the method of kit `m511-window` and extends ADR-029.
- **Context:** testing the signed wrapper on the real cluster needs a different jar and different settings, which are measured components; the nodes are shared with the teammate.
- **Decision:** such a test runs in a window: the cluster is reserved with `tc-busy.sh`; on each node the installed jar and `core-site.xml` are saved, the new jar is installed atomically (refused unless its classes equal the job's, or its fingerprint equals the one the master checked), the settings are applied with `cluster-mode.sh` from a state folder of the window, and the daemons are restarted; at the end the saved files are put back, compared byte for byte, and the measured-set check must print `ALL-UNCHANGED`. An open that has changed nothing leaves no window behind; an open that has changed something is undone by `close`.
- **Why:** it keeps the measured stack and the shared client consistent, makes every change reversible, and makes the not-covered time explicit.
- **Consequences:** everything that ran during a window is not covered by the measurement (ADR-029); data written by the new wrapper may be unreadable by the measured one; a window costs about 15 minutes of both nodes; the combined crawl after step 5.1.2 needs another window.


## ADR-046: Every file is bound to its folder by signed folder identity files and ATTEST03 records

- **Date:** 15 October 2026. **Status:** accepted. It carries out ADR-035 and the mentor's note of 10 October (a record covers the folder's ID and the file's name, not the full path; a rename signs one new record; a folder rename signs only its identity file).
- **Context:** with `ATTEST02` a signed file and its record could be copied into another folder, or under another name, and still verify. Hadoop's output committer moves files between folders and renames whole task folders, so the binding must survive renames without reading data.
- **Decision:** (1) every folder that the wrapper makes or adopts has a signed identity file `_attested-folder` (a random folder ID, the folder's own name, and its parent's ID, or for a top folder its full path), hidden from listings and reserved: it cannot be created, renamed or deleted through the wrapper; (2) a record in the format `ATTEST03` is the `ATTEST02` record plus the folder's ID and the file's name, both signed; (3) a read checks the record, the folder ID, the name and the whole chain of identities up to a top folder whose identity is for its own full path; (4) a file rename signs one new record from the old one after checking the old one's signature and binding, so that a forged record is never signed again; a folder rename signs only the folder's identity file again; (5) a folder is a top folder only when no ancestor has an identity; otherwise the unidentified folders in between are adopted as children, so that the shape never depends on timing; (6) when several writers make the same folder, the first identity file wins and the others read it, whatever error the real HDFS gives them; (7) everything is off by default (`attested.folder.binding.enabled`, which needs signing and records, and `attested.folder.binding.required`), a bound record is always checked, and identity files are cached per process for the metadata cache time.
- **Why:** a top identity bound to a path breaks when an ancestor is renamed, so tops must be the roots of managed trees and never nested in one; a rule that does not depend on timing is the only safe one; the first scratch run on the real master showed that the loser of a race gets "already being created", not "file exists".
- **Consequences:** the files of step 5.1.1 (`ATTEST02`) are unbound and readable only while binding is not required; a top folder is not re-signed when a folder above it is renamed (limitations row 98); a change behind the wrapper's back is seen within the cache time (row 97); the identity files need `nn_audit_compare.py` to treat them like record files before the combined crawl (row 99); the crawl's top folders are the folders that the driver makes first.


## ADR-047: The real key is made per boot inside a separate signing service and kept in memory only

- **Date:** 16 October 2026. **Status:** accepted. It carries out step 5.1.3 of the plan and the mentor's note of 10 October (the key is generated per VM at boot, held by a small signing service outside the fetcher's JVM, and bound to the quote through REPORTDATA).
- **Context:** the test key of ADR-044 is a file; whoever can read it can sign. A real key must not be a file, and the hardware must vouch for the machine that holds it.
- **Decision:** (1) a signing service (`KeyService`) is a process of its own on each VM; it makes an ECDSA P-256 key when it starts, keeps it in memory only, and signs on request over a loopback socket protected by a token; (2) it signs only statements that begin with the three tags of the wrapper's signed formats and that name its own key id, so it is not a general signing oracle; every request is logged with a short digest; (3) the key is vouched for by a TDX quote whose REPORTDATA is the SHA-512 of a key statement (key id, public key, host, time, nonce), the rule that `attest/quote.sh` and `attest/verify-binding.sh` already use; (4) it fails closed: a key that claims TDX (`TDX-`) is never made without its quote, and a service key without a quote (`SVC-`) is for tests only; (5) a restart is a new key; the old key stays valid for the records it signed, because its public bundle stays in the key lists.
- **Why:** a key that was never stored cannot be stolen from a disk; reusing the existing quote rule means no new mechanism to trust.
- **Consequences:** the first window runs the service under the same user as the fetcher (limitations row 109); a separate user is a later hardening step; a service that dies makes writes fail closed.

## ADR-048: Keys are trusted only through a key list of bundles whose quote binds them, with a hook for step 5.2.1

- **Date:** 16 October 2026. **Status:** accepted.
- **Context:** a reader must decide which public keys to trust. Step 5.2.1 will admit only keys of attested machines.
- **Decision:** the wrapper resolves a record's key only through the key list (`attested.keys.list.dir`): a bundle is trusted only if the key id is the hash of the public key and the quote's REPORTDATA is the SHA-512 of the statement; a key without a quote is refused unless `attested.keys.list.allow.unquoted` says otherwise; the file name must say the key id; an optional class (`attested.keys.list.check.class`, an implementation of `BundleCheck`) adds checks. Reading needs only the list.
- **Why:** the list is the policy: removing a bundle makes its files unreadable (the negative control of run 15 shows it), and step 5.2.1 needs one place to plug in the verification of the quote's signature chain and of the measurements.
- **Consequences:** the quote's signature chain and the measurements are not verified by the wrapper yet (limitations rows 110 and 111); the chain of both quotes of run 15 was verified on the laptop; the bundles are exchanged between the nodes by a Cloud Shell script until 5.2.1 automates the admission.

## ADR-049: One switch for the key provider; the test key stays as a labelled option

- **Date:** 16 October 2026. **Status:** accepted.
- **Decision:** a single setting, `attested.keys.provider` (`test` by default, `service` for the real key), read from core-site.xml only (ADR-039); everything the earlier steps verified stays as it was, so no earlier evidence or test breaks; test keys are not accepted in the window of step 5.1.3 (`attested.signature.allow.test.keys` false).
- **Why:** the wrapper's `AttestedKeys` interface of step 5.1.1 was made for this, so the change in the wrapper is a few lines; the real key is a new implementation behind the same interface.
- **Consequences:** a later step can add another provider (for example a service on another machine) without changing the signed formats.


## ADR-050: A key is admitted by its quote, verified offline in Java inside the key list

- **Date:** 16 October 2026. **Status:** accepted. It carries out step 5.2.1 through the hook of ADR-048.
- **Context:** the binding of a quote to a key (REPORTDATA) does not prove that the quote is genuine; a fake quote of the right shape passes it.
- **Decision:** a class `QuoteAdmission` is the extra check of the key list. It verifies the quote offline: the certificate chain in the quote leads to a pinned Intel root (the SHA-256 of Intel's SGX Root CA is the default), the PCK certificate's key signed the quoting enclave's report, the report names the attestation key, and the attestation key signed the quote's header and body. It is off by default (`attested.keys.admission.enabled`).
- **Why:** the reader decides by itself, nobody is in the loop, and nothing new has to be installed; go-tdx-guest's `check` stays as an independent second opinion.
- **How to change it:** pin another root or several (`attested.keys.admission.root.sha256`), switch the certificate dates off (`attested.keys.admission.check.dates`), or switch the whole check off (`attested.keys.admission.enabled`). To verify quotes some other way, replace the class named by `attested.keys.list.check.class`; nothing else changes.
- **Consequences:** the quote's verification is Intel's offline procedure, not the whole of it (ADR-052).

## ADR-051: "Attested" means a genuine quote and measurements allowed by an editable reference file; RTMR3 is shown, not enforced

- **Date:** 16 October 2026. **Status:** accepted.
- **Decision:** besides the genuine quote, every **enforced** register (default MRTD, RTMR0, RTMR1, RTMR2) must have a value that the reference file allows for the host named in the key's statement; the reference file is plain text with one line per allowed value, `REGISTER VALUE [HOST]`; the values are those of the two machines' quotes of run 15; a register that is enforced but has no line in the reference fails closed with the reason; RTMR3 is not enforced and is written to the audit.
- **Why:** MRTD and the boot registers can be compared with what the machines reported today; RTMR3 (the measured stack) needs the event log of each node and a bundle format change, which is a separate step.
- **How to change it:** add a line to allow a value; delete a line to forbid one; change `attested.keys.admission.enforce` to choose the registers (for example add `rtmr3` after adding the RTMR3 lines); give the file's SHA-256 in `attested.keys.admission.reference.sha256` to lock it, so that a changed file stops the wrapper.
- **Consequences:** the reference records what these machines reported; the firmware is the cloud provider's, so it is not an independent reference (limitations row 118).

## ADR-052: What is not checked offline, and how a rejection and the bundle delivery are handled

- **Date:** 16 October 2026. **Status:** accepted.
- **Decision:** (1) revocation lists, the TCB status and the quoting enclave's identity need Intel's online collateral and are not checked by the wrapper; (2) every admission, with the registers checked, and every rejection, with its reason, is written once to `attested.keys.list.audit.file` (default `keylist-audit.log` next to the list), a separate file so that the analysis tools never meet an unknown line; (3) the bundles are still delivered by the Cloud Shell script, because the checks make the delivery path irrelevant for safety.
- **How to change it:** to add the collateral checks, add a second `BundleCheck` through `attested.keys.list.check.class` (the factory runs it after the admission); to change the audit file, set its setting; to automate the delivery, replace the script and nothing else.
- **Consequences:** limitations rows 117 to 122.


## ADR-053: A node is bound to its hardware by a quote over its WireGuard public key and the mesh address it asks for

- **Date:** 17 October 2026. **Status:** accepted. It carries out the rest of step 5.2 of the plan (mesh admission only after verifying a peer's quote).
- **Context:** the mesh of Milestone 2 trusts static WireGuard keys that an operator writes into a configuration; nothing says that the machine behind a key is a genuine measured machine.
- **Decision:** on the node, `node-attest.sh` builds a statement (`ATTESTED-NODE-STATEMENT 1`: host, the WireGuard public key, the requested mesh address, the time, a random nonce) and asks the TDX guest for a quote whose REPORTDATA is the SHA-512 of the statement bytes, the rule of the signing keys' bundles (ADR-047); the statement and the quote are the node bundle. The public key is read with sudo (the folder `/etc/wireguard` is root only) and must equal the key of the running interface.
- **Why:** the quote then proves that a genuine machine presented exactly this key now; a copied key cannot be bound to another machine's quote.
- **How to change it:** the statement's fields are one place (`node-attest.sh` writes them, `NodeBundle` reads them); adding a field is a change of both and of the tag.
- **Consequences:** the private key stays on the node's disk (limitations row 126).

## ADR-054: The doorman decides in a fixed order and reuses the verifier and the reference file of step 5.2.1

- **Date:** 17 October 2026. **Status:** accepted.
- **Decision:** `MeshAdmission` checks, cheapest first and refusing at the first problem: (1) the binding of the quote to the statement, (2) the policy table (the host is listed and asks for exactly the address that the table gives it), (3) freshness (at most 900 s old, at most 60 s in the future), and (4) the genuine-quote and reference check of step 5.2.1 (`QuoteAdmission`), with the same reference file, enforce list, root and date options; a host or a mesh key is admitted once only per run; every decision is written to an audit file with its reason.
- **Why:** one verifier and one reference file mean one place for the policy; the address comes from the table so a node cannot claim another's.
- **How to change it:** the policy table, the reference file and the options named in report section 9.3; the order of the checks is in `MeshAdmission.admit`.
- **Consequences:** the quote's online collateral is still not checked (ADR-052).

## ADR-055: The first proof is on a separate test mesh with the operator as the trust root; removal is by hand

- **Date:** 17 October 2026. **Status:** accepted.
- **Decision:** the admitted nodes are brought up as peers of a separate test interface `wg1` (10.20.0.0/24, UDP 51821) so that the production mesh `wg0` and Hadoop are never touched; the doorman runs from Cloud Shell like the mesh scripts of Milestone 2, so the operator is the trust root; removing a node is by hand (take `wg1` down, or delete the peer) and is written to the audit; the build proves the key in use, the peers, the reachability, the handshakes and that `wg0` is unchanged.
- **Why:** a proof that cannot damage production, with the same code that would later run for production.
- **How to change it:** to adopt the doorman for `wg0`, run the same scripts with another interface name and the production port and addresses (the mentor's decision); to move the doorman off Cloud Shell, run `mesh-admit.sh` where the jar and `gcloud` are.
- **Consequences:** limitations rows 125, 127 and 128.


## ADR-056: A fixed fleet: keys at boot, one measured list, and no quote checking inside the cluster

- **Date:** 19 October 2026. **Status:** accepted: the mentor's note of 18 October 2026 ([next-steps-fixed-fleet.md](next-steps-fixed-fleet.md), sections 1 and 2).
- **Supersedes:** ADR-047 (the key made per boot inside a separate signing service), ADR-048 (the key list of bundles), ADR-050 to ADR-052 (a key admitted by its quote, verified in Java), and ADR-053 to ADR-055 (the doorman and the test mesh). They stay as history.
- **Context:** the key list was a folder that each signing service wrote into and every reader rescanned every 10 seconds, so every reader had to re-check each key's quote. With a fixed list that nothing in the cluster can change, those checks add nothing.
- **Decision:** the cluster runs on a fixed fleet: no VM joins during a run. At boot each VM makes its signing key and its WireGuard key in memory and gets one quote that binds both public keys. A setup step writes one read-only list, `fleet.tsv`; every node installs it and extends RTMR3 with its SHA-384; inside the cluster a signature is accepted only if its key is in the list. The quote checking happens once, at the end, in the consumer's verifier, which is the teammate's piece. `QuoteVerifier` and the other quote code leave the cluster (step F2).
- **Why:** it needs far less trusted code (the aim is about 950 to 1,150 lines of Java, down from 5,783) and it keeps what matters: the consumer checks that every node used the same list and that every key on it has a valid quote of its own.
- **How to change it:** the list format is one function in `fleet-setup.sh` and in `FleetKeys`; adding quote checks back would be a change of ADR-056 and of step F2.
- **Consequences:** the design rests on the locked image (ADR-057): anyone who is root in a node can read keys and rewrite the list; a node that reboots in a run gets new keys and the run is redone.

## ADR-057: The locked image comes first; disposable VMs and a debug image; measurements are recorded, not enforced

- **Date:** 19 October 2026. **Status:** accepted: the mentor's note of 18 October 2026 (sections 3 and 4, step 0).
- **Supersedes:** ADR-010 (measure at run time now and lock the image down later) for new work, and the use of windows (ADR-045) for new work: a fresh VM is used for each test instead of changing the live nodes.
- **Decision:** step F0 is the first: a locked, measured image with no login (no sshd, no OS Login, no guest agent that adds keys, no serial login), the measurement as a boot unit before Hadoop, the configuration, the job and the crawl driver baked in, the doors around the wrapper closed, and a separate debug image that is never used for evidence. Disposable TDX VMs may be created generously. The measurement policy is to record and not enforce: the consumer's verifier reports MRTD and RTMR0 to RTMR3 and replays the RTMR3 log, and the reference values are produced from the final baked image.
- **Why:** with SSH and `sudo` an operator can read keys in memory and rewrite the list; recorded measurements are enough while the design is under development.
- **How to change it:** enforcement is a later change in the consumer's verifier; the image's contents are listed in step F0.
- **Consequences:** limitations rows 119, 131 and 134.

## ADR-058: One record format, no switches, a flat hash list, and a list of behaviours that stay

- **Date:** 19 October 2026. **Status:** accepted: the mentor's note of 18 October 2026 (section 4, step 3).
- **Supersedes:** the record format and settings of ADR-044 (ATTEST02, the switches, the test key as a switch), the format of ADR-046 (ATTEST03), ADR-038 and ADR-039 (the settings), and ADR-023 (already superseded in part).
- **Decision:** all 30 `attested.*` settings and the three modes go; behaviour is fixed and secure. There is one record format for files and one for folder identities (about 180 to 230 lines in `Records.java`); the Merkle tree is replaced by a flat hash list; the root `/` has a fixed all-zero ID; `copyToLocalFile` goes through the verifying open; the observe-only extras go. These behaviours are kept exactly: never sign from something unverified, the folder-identity wait loop, the builder routes and the second Hadoop storage API with both lookups final, the refusals of path handles and of `getRawFileSystem`, hidden companion files, the pass-through stream calls, and plain `dfsadmin`. The signing key is read in-process by the Hadoop user.
- **Why:** fewer lines to trust and to review, and one format to give to the verifier.
- **How to change it:** each change is a sub-step of F3; the key reader's alternative (a small helper under another user) is asked of the mentor.
- **Consequences:** files written by commit `03ee672` do not verify, so each run uses a fresh HDFS (limitations row 135).

## ADR-059: New steps get new numbers (F0 to F5), the legacy steps stay as history, and our documents checks stay

- **Date:** 19 October 2026. **Status:** accepted: the numbering follows the mentor's note; keeping the checks is our own decision (the user's, 19 October 2026).
- **Decision:** the mentor's steps 0 to 5 are written F0 to F5, with sub-steps F0.1 and so on. The legacy steps keep their numbers and are never reused. Every new step names the legacy steps that it replaces and why, in the plan and in every document that mentions it ([milestone-plan.md](milestone-plan.md) section 10). The mentor's step 5 says to stop the document-status checker and the preflight; we keep the preflight and the audit of the whole docs folder as long as they are needed, and stop making new kits, windows, patch copies and facts lists for new work.
- **Why:** the plan changed, and a reader of an old document must not mistake a replaced step for a current one; the documents were stale twice in a week without the checks.
- **How to change it:** the prefix is one edit of section 10 and of the status rules; retiring the checks is a decision at step F5.
- **Consequences:** guide rule 38.

## ADR-060: Defaults taken where the note is silent, each easy to change

- **Date:** 19 October 2026. **Status:** accepted (our defaults); the mentor has been asked about the questions that matter most (disk integrity, the publishing channel, the key reader, scale, enforcement and the formats for the teammate).
- **Decision:** the defaults are in [milestone-plan.md](milestone-plan.md) section 10.5: the image base and kernel, the build and names, a fleet of 2 nodes, the `fleet.tsv` columns, guest attributes first for publishing, the extra measured files (the boot script, the units, `openssl` and `wg`), the in-process key reader, and a fresh HDFS per run.
- **Why:** none of them blocks the work, and each is one variable or one line to change.
- **How to change it:** the last column of that table says where.
- **Consequences:** if the mentor answers otherwise, the table, this entry and the affected step change, and the old text stays as history.


## ADR-061: The image measures its fixed stack at every boot from a list, and 6.17 is the permanent default kernel

- **Date:** 19 October 2026. **Status:** accepted: shown on a disposable TDX VM ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 10); steps F0.1 and F0.2.
- **Supersedes:** for the image, the one-time boot procedure of ADR-003 (the nodes return to 6.8 on the next reboot unless the default is changed) and the manual measurement runs of Milestone 1. ADR-003 stays as the record of the kernel choice and of the nodes' procedure.
- **Context:** the fixed fleet needs an image whose measurement happens by itself at every boot (ADR-056, ADR-057).
- **Decision:** (1) kernel 6.17.0-1022-gcp, from the same checksum-pinned packages as ADR-003, is made the permanent default through a GRUB saved entry, with no one-time entry; (2) a one-shot unit, `tc-measure.service`, is ordered before `multi-user.target`, and anything that must follow it uses `Requires=` and `After=`; (3) the unit reads `/etc/tc/measured-paths.txt` (a name, a path and optional paths to skip, one line per event), extends RTMR3 once per line in that order, refuses to run unless RTMR3 is zero, and stops, so that what requires it does not start, if a path is missing or an extension does not give SHA-384(before + digest); (4) the log of each boot is in `/run/tc` and is kept in `/var/lib/tc/events-boot<N>.tsv`; (5) on the build and test VM the automatic upgrades are stopped and masked, because they would change measured files between boots (the locked image will not have them); (6) the first list measures the boot scripts, the configuration, the unit, `openssl` and `wg` (our default, ADR-060).
- **Why:** the register becomes reproducible and predictable without an operator, and a verifier can replay the log.
- **How to change it:** edit the list file (one line per item); the kernel package is set at the top of the prep script; the ordering is in the unit file.
- **Consequences:** limitations rows 137 to 139: the unit is not measured by an earlier stage, whether VMs made from one image share RTMR1 and RTMR2 is not known, and the test used a stand-in for Hadoop.


## ADR-062: The software layer of the image is root-owned, runs as a user that cannot log in, and starts only after the measurement

- **Date:** 19 October 2026. **Status:** accepted: shown on VMs made from the image ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 12); step F0.3a.
- **Supersedes:** for the image, the rebuild stages `base` and `hadoop` (a person's home folder, daemons started by hand) and the by-hand measurement of the JDK and Hadoop of Milestone 1. They stay as history.
- **Context:** the measured stack must be the running stack, and nothing that runs may be changed by the user that runs it (ADR-056, ADR-057, ADR-061).
- **Decision:** (1) JDK 11 comes from the Ubuntu package and Hadoop 3.4.3 is unpacked in `/opt/hadoop`, owned by root and not writable by group or others; (2) a system user `hadoop` with the shell `nologin` owns only `/var/lib/hadoop` and `/var/log/hadoop`; (3) the configuration is rendered from the property files in `/etc/tc/hadoop-props` and checked against them at build time, for a single node on the loopback address (our default, ADR-060; two nodes need F1 and F2); (4) there is one systemd unit per daemon, kept in the measured folder `/usr/local/lib/tc/units` and enabled from there, each requiring and following `tc-measure.service`, and the one-time NameNode format is a separate unit whose skip condition is in `[Unit]` and whose failure blocks the daemons; (5) the measured list has 10 events: the five of ADR-061, then the JDK, the Java settings, the JDK's certificate fingerprints, Hadoop's code (without its configuration folder) and Hadoop's configuration; (6) the Hadoop tarball may come from a fast mirror, but its checksum file always comes from the primary Apache archive, and a download that would take more than 40 minutes is refused; (7) the builder is cleaned before it becomes an image (machine id, ssh host keys, first-boot state, logs, Hadoop's data), and both the bake and the boot check ask `systemd-analyze verify` whether systemd understands the units, counting only warnings that name our own units.
- **Why:** a root-owned tree cannot be rewritten by the program that runs from it; a unit that requires the measurement cannot start Hadoop when the measurement fails; a cleaned builder cannot hand its identity or its HDFS to other VMs; and the first image showed that a setting in the wrong section is silently ignored by systemd, so the real system must be asked.
- **How to change it:** the properties are in `ops/image/rootfs/etc/tc/hadoop-props/`, the units in `ops/image/rootfs/usr/local/lib/tc/units/`, the list in `ops/image/rootfs/etc/tc/measured-paths-f03a.txt`, and the download settings (`HADOOP_URL_BASE`, `HADOOP_MAX_MINUTES`) at the top of `ops/image/build/tc-image-bake.sh`.
- **Consequences:** limitations rows 143 to 148: the image has no login removal yet (F0.4), the shuffle port is not bound (F0.5), the tarball is not pinned, a reference holds per image and machine type, and the build is shown reproducible only for two bakes on one day.

## ADR-063: The code lives in a private repository, and the old public fork is frozen

- **Date:** 19 October 2026. **Status:** accepted: the owner's decision.
- **Context:** the project's code and documents were in the public fork `Antisource/nutch`.
- **Decision:** all commits from 19 October 2026 go to the private repository `Heron-AI-Security/nutch-private`, branch `feat/tee-hadoop-cluster`. The history up to `ab26da172` is the same in both; the fork stays frozen at that commit, and its owner makes it private or deletes it. A person who verifies a commit logs in with `gh auth login` and clones the private repository; no token is ever pasted into a chat.
- **Why:** the documents describe the weak points of the system in detail, which is not for the public before the mentor and the teammate have seen them.
- **How to change it:** the address is in the documents that name the repository (the docs index, the session-start page, the rebuild runbook, the configuration page); the gate and the verification scripts use the checked-out `origin`.
- **Consequences:** a builder VM has no credentials, so for F0.3b the source of the job is shipped to it from a clone made where the user is logged in; the older kit scripts that clone the fork (they ran as they are, and stay as evidence) cannot be used against the private repository, and the rebuild stage `build` is replaced by the image build.


## ADR-064: The job and the wrapper jar are built once on the builder from pinned inputs, and the image keeps only the artifacts

- **Date:** 20 October 2026. **Status:** accepted: shown on VMs made from the image ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 13); step F0.3b.
- **Supersedes:** for the image, the rebuild stages `deps`, `build` and `jar` of `ops/rebuild/node-wrapper.sh` and the per-window installs of jars and the job (ADR-045). They stay as history.
- **Context:** the measured stack must be the running stack (ADR-062), and a job that is built again on each node is a job that nobody measured.
- **Decision:** (1) the inputs are two files pinned by their SHA-256: a source archive made by `git archive` (compressed with `gzip -n`) of a fixed commit, and the teammate's patch at her commit `841c1d3`, with its line endings normalized (`61dbff2e…`); the build refuses to start if either fingerprint differs, and refuses a short fingerprint; (2) the two libraries of the crawler are built at pinned commits; (3) the patch is applied with `patch -p1` and must make or change every file that it names; (4) `ant runtime` builds the job, which must hold the wrapper classes and the patch's `CustodyReceipt` class; (5) the wrapper jar is built from the job's own classes by `ops/attested/wrapper-jar.sh`, which is deterministic and needs no compiler, and is installed in Hadoop's library folder; (6) the whole deploy folder (the job and the launcher scripts) is installed in `/opt/tc/nutch`, owned by root and not writable by group or others, and measured as the event `nutch-deploy`, which makes 11 events; (7) every fingerprint, the two library commits and the tool versions are recorded in `/etc/tc/job-versions.txt`; (8) `ant`, `maven`, `git` and `patch` are purged and the build folder and caches are removed, while `libcld2-0` stays; (9) the configuration stays plain until keys exist; (10) every boot's check runs the wrapper's self-test, Hadoop's Pi example and a Nutch inject job.
- **Why:** pinned inputs make the build checkable by anyone who holds the same files; a deterministic jar makes the wrapper reproducible across machines (the jar of this build is byte-identical to the one built on the master on 17 October); and an image without build tools has fewer tools for an intruder.
- **How to change it:** the pins are the arguments of `ops/image/build/tc-image-job.sh` (the driver stage `job` passes `SRC_SHA` and `PATCH_SHA`), the library commits are `CC_COMMIT` and `CLD2_COMMIT` at its top, and the list of measured paths is `ops/image/rootfs/etc/tc/measured-paths-f03b.txt`.
- **Consequences:** limitations rows 149 to 152: the patch is carried by the kit and not by the repository, each image build has its own job reference, the source archive comes from a private repository, and the data path of the image is not signed yet.
- **Update, 22 October 2026 (ADR-071):** decisions (1) and (3) no longer hold: since step R1 the teammate's receipt code is in the source tree, the build has one input (the source archive) and no patch step, and row 149 is resolved.

## ADR-065: The crawl is baked as measured data and a driver, and a unit starts it once after the daemons

- **Date:** 20 October 2026. **Status:** accepted: shown on VMs made from the image ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 14); step F0.3c.
- **Supersedes:** for the image, the hand-run `ops/run-crawl.sh` with typed parameters (legacy step 5.3.2).
- **Decision:** (1) the parameters (`/etc/tc/crawl/params.env`) and the seeds (`/etc/tc/crawl/seeds.txt`) are root-owned data and measured as the events `crawl-params` and `crawl-seeds` (13 events); (2) the driver `/usr/local/lib/tc/tc-crawl.sh` reads the parameters as data (a line is `KEY=VALUE` with a plain value, nothing is executed), waits for HDFS and a running NodeManager, runs Nutch's own crawl script on the baked job, checks a minimum of fetched URLs and a segment, and writes a marker; (3) `tc-crawl.service` requires and follows the measurement and the four daemons, runs as `hadoop`, has a one-hour time limit, and skips itself when the marker exists, by a condition in `[Unit]` (rule 40); (4) a failed crawl leaves no marker, so the next boot crawls again from scratch; (5) the check only waits and reads, so that "no operator command" is what is tested.
- **Why:** a verifier can see exactly what the VM was told to crawl, and the crawl cannot be changed by a typed command.
- **How to change it:** edit `ops/image/rootfs/etc/tc/crawl/params.env` or `seeds.txt` and rebuild the image; the list of measured paths is `ops/image/rootfs/etc/tc/measured-paths-f03c.txt`.
- **Consequences:** limitations rows 153 to 155.

## ADR-066: The crawler's identity is measured data with a default, changed without a job rebuild

- **Date:** 20 October 2026. **Status:** accepted by the owner (use the defaults, flexibly); to be built in phase 3 together with the job rebuild.
- **Context:** `http.agent.url` is sent to every website that the crawler visits and `warc.export.software` is written into every WARC file; both name the old public fork, which is frozen and about to be deleted (ADR-063, limitations row 154).
- **Decision:** (1) the crawler's name, information URL and WARC software string become the parameters `AGENT_NAME`, `AGENT_URL` and `WARC_SOFTWARE` in `/etc/tc/crawl/params.env`, which is measured (the event `crawl-params`), and the driver passes them to Nutch with `-D`, which overrides the job's own configuration; (2) the default URL is the public page of the organization that runs the crawl, `https://github.com/Heron-AI-Security`; (3) `conf/nutch-site.xml` gets the same values in the source commit of the phase-3 job rebuild, so that nothing names the old fork; (4) before the evidence crawl, the organization's public profile should describe the research crawler and give a contact.
- **Why:** a verifier sees the identity in the measured parameters, and changing it later needs no job rebuild.
- **Consequences:** limitations row 154 is closed when phase 3 is done.

## ADR-067: A fleet node makes its keys in memory, binds them with one quote, and joins only a fleet list that holds its keys

- **Date:** 20 October 2026. **Status:** accepted: shown on two VMs ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 15); step F1.
- **Supersedes:** for the image, the signing service of step 5.1.3, Milestone 2's key files, the key list and its sync script, the admission of keys of step 5.2.1, and the doorman and test mesh of step 5.2.2 (the mentor's note of 18 October, ADR-056 to ADR-058).
- **Decision:** (1) `tc-fleet.service` runs as root after the measurement and before every Hadoop daemon; (2) the signing key (P-256) and the WireGuard key are made in `/run/tc` (memory) and are never written to disk; (3) one TDX quote has as REPORTDATA the SHA-512 of a binding text (`tc-bind-v1`, node name, both public keys, SHA-512 of the RTMR3 event log) and is published as the guest attribute `tc/announce`, which needs no login; (4) the operator verifies each announcement (the quote binds the text, the log hashes to the text, the log replays to the quote's RTMR3), writes `fleet.tsv` (`# tc-fleet v1`, then name, role, mesh address, endpoint, signing public key, WireGuard public key per node) and sets it as the instance metadata `tc-fleet`; (5) the node accepts a list only if its format is exact (one master, unique names and addresses, plain base64 keys, nothing from it is ever executed) and its own two keys are in it, else it stops before Hadoop starts; (6) it extends RTMR3 with `fleet` (SHA-384 of `fleet.tsv`), brings up `wg0` with the other rows as peers, renders the Hadoop configuration into `/run/tc/conf` with every daemon bound to its `wg0` address and WebHDFS off, extends RTMR3 with `fleet-conf`, marks its role, and publishes a final quote as `tc/final`; (7) the daemon units require and follow the fleet unit, read `/run/tc/conf` and run only on their role, and the crawl runs on the master and waits for safe mode to end and for a live DataNode per worker; (8) `dfs.namenode.datanode.registration.ip-hostname-check` is false in the fleet template, because membership is enforced by `fleet.tsv` and the `allowed-ips` of `wg0`; (9) the cleaning of the builder stops the Hadoop units, deletes with `sudo` and aborts if any HDFS data is left, and the first-boot check requires that the namespace was created during the boot.
- **Why:** no private key can be found on disk; one quote vouches for both keys and the log; the list is measured once, so the consumer can check every key against a quote at the end; and nothing joins during a run.
- **How to change it:** the flow is `ops/image/rootfs/usr/local/lib/tc/tc-fleet.sh`, the templates are `ops/image/rootfs/etc/tc/fleet-props/`, and the operator side is `ops/image/test/f1-drive.sh` and `f1-fleet.py`.
- **Consequences:** limitations rows 156 to 161.

## ADR-068: The wrapper has no settings: its behavior is fixed and secure, with one record format

- **Date:** 21 October 2026. **Status:** accepted: shown on two VMs and in Hadoop's contract tests ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 16); steps F2 and F3.
- **Supersedes:** ADR-039 (a setting counts only from the site configuration), ADR-038's two settings, ADR-023, the test keys of step 5.1.1, the formats ATTEST01 to ATTEST03, the Merkle tree, the "top folder bound to its full path" identity, the observe-only logs and checks of step 4.5, and the key service, quote admission and mesh admission classes of steps 5.1.3 to 5.2.2.
- **Context:** the first wrapped fleet run failed because the MapReduce ApplicationMaster builds its configuration from `job.xml`, where ADR-039's rule threw the wrapper's settings away: no keys, so a correctly signed file was refused. A wrapper that reads its behavior from a configuration is only as safe as the weakest configuration that reaches it.
- **Decision:** (1) the wrapper has no settings, modes or switches; the two lines `fs.hdfs.impl` and `fs.AbstractFileSystem.hdfs.impl` only say where it is used; (2) it always hashes in chunks of 16 KiB (SHA-256 of each chunk, a flat list), keeps a signed record beside each file, verifies every read, and binds each file to its folder and name; a file without a record, a record signed by a key that is not in `fleet.tsv`, and a record that does not match are refused; (3) the keys are the fleet keys of `/run/tc` (ADR-067), read once per JVM; (4) one file record (`ATTEST04`) and one folder identity (`ATTEST05`) in `Records.java`, specified byte by byte in report section 16.3, and every malformed record fails with "record is damaged"; (5) the root `/` has the fixed all-zero id and no identity file; (6) every way of copying a file to local disk reads through the verifying open; (7) append, concat, truncate, path handles, local staging and the plain file system under the wrapper are refused, and the capability probe says no to append, concat and truncate; (8) `delete(folder, false)` removes the folder's identity file first when it is all that the folder holds; (9) the fleet's NameNode accepts blocks of 1 KiB (a minimum of 1024 bytes), so that Hadoop's contract tests run against this configuration; (10) the only test hooks are the key directory (`FleetKeys.useDirForTesting`) and the lifetime of the identity cache, and neither switches a rule off.
- **Why:** a job cannot weaken what has no settings, and every JVM behaves the same; one format is easier to review and to give to the verifier; and 3,660 lines fewer is less code to trust.
- **How to change it:** the format is `src/java/org/apache/nutch/attested/Records.java`, the rules are `AttestedHdfsFileSystem.java`, and the tests are `ops/attested/build-and-test.sh` (sandbox) and `ops/image/test/f2-check.sh` and the stage `fleet-contract` of `f1-drive.sh` (cluster).
- **Consequences:** limitations rows 162 to 166.

## ADR-069: The evidence image is locked: no way in, enforced at every boot, a baked firewall, and a separate debug image

- **Date:** 21 October 2026. **Status:** accepted: shown on two VMs, from outside the mesh and in the attacks ([milestone-5-signed-records.md](milestone-5-signed-records.md) section 17 and [milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md)); steps F0.4, the rest of F0.5, F0.6 and F4.
- **Supersedes:** debugging on the measured nodes through SSH and windows (ADR-045), and the plan of step 5.3.1 (a locked image with no SSH or shell) as a separate step.
- **Context:** with SSH and `sudo` an operator can read keys in memory and rewrite `fleet.tsv`; a locked VM cannot be asked anything, so it also has to say what it is.
- **Decision:** (1) two images from one builder: `tc-img-dbg-1` (login kept, port 22 open, never used for evidence) and `tc-img-lock-1` (no `sshd`, no guest agent, no OS Login, serial login masked), and the evidence run names the locked one; (2) the lock is enforced at every boot: `forbidden-paths.txt` is measured as part of `tc-conf`, and `tc-measure.sh` stops the boot, so no Hadoop daemon starts, if any listed path exists; (3) the host firewall (nftables, default drop, only loopback, answers, DHCP, `wg0` and the WireGuard port; the debug image adds port 22) is baked and measured as the event `firewall`; (4) cloud-init is off and a generic network configuration matches any wired card, and `tc-fleet.sh` sets the host name from the instance metadata (a wrong name made Hadoop bind to the VPC address) and puts it into `/etc/hosts` if it does not resolve; (5) the VM reports on itself (`tc/report` and the console) and the report is checked, but the evidence is the quote and the log, not the report; (6) the locked image is sealed in one SSH session (lock, cleaning, power-off), because the lock removes the SSH that a second stage would need; (7) the attacks run on the debug image, which has the same wrapper, job and configuration.
- **Why:** the evidence image must have no way in, the wrapper's refusals must be shown on the real cluster, and a debugging image under another name keeps debugging possible without weakening the evidence image.
- **How to change it:** the lock and the firewall are `ops/image/build/tc-image-lock.sh` and `ops/image/rootfs/etc/tc/`, the checks are `ops/image/test/f1-drive.sh` (stages `locked-check`, `probe`, `fleet-attacks`, `images-compare`, `mismatch-compare`) and `f4-attacks.sh`, and the sandbox rehearsal is `f4-rehearse.sh` and `f4-local.sh`.
- **Consequences:** limitations rows 167 to 170.

## ADR-070: The threat model is insiders only: Google, Intel and the hardware are trusted

- **Date:** 22 October 2026. **Status:** accepted: the decision of the mentor's review of 22 October 2026 ([milestone-plan.md](milestone-plan.md) section 11); it makes the documents agree with ADR-037, which already said insiders.
- **Supersedes:** the first handoff's adversary, "the data provider" with root on the hosts ([handoff-attested-hadoop-cluster.md](handoff-attested-hadoop-cluster.md) section 2), and every row of the limitations that blamed the provider.
- **Decision:** (1) **trusted:** Google (the hypervisor, the firmware, the cloud), Intel and the hardware; (2) **the adversary:** anyone with legitimate access: project IAM, repo write, the image builder, the operator; (3) **the claim:** all crawler code is in one shared repo; each commit has reference measurements that CI generates and that anyone can recompute from that commit; a run publishes its quotes, and the verifier checks each quote's measurements against the reference values of the commit that was announced before the run; a match means that the code that ran is the reviewed commit, and the signatures then show which outputs that code produced; (4) the wrapper stays as it is, and its role in the paper changes: dm-verity and dm-crypt protect each node's local disk, and the wrapper makes the stored data verifiable by anyone, after the VMs are gone and across runs; (5) the signing key is readable by the `hadoop` user: accepted and stated in the paper, because that attack comes from hostile web pages, not from insiders.
- **Why:** the earlier model asked for protection against a party that the platform's own design trusts; the insider model is the one in which the custody layer's claim can be checked.
- **Consequences:** limitations rows 3, 8, 19 and 25 are out of scope; rows 17, 42, 57 and 118 are reworded; the security argument is rewritten ([security-argument.md](security-argument.md)); the steps R1 to R7 of the plan follow from it.

## ADR-071: The folder chain is checked on every write and rename, the companion names are reserved, the wrapper's two keys are final, the fleet tooling takes any number of workers, and the receipt code is in the source tree

- **Date:** 22 October 2026. **Status:** accepted: shown on a debug fleet of three nodes ([run-comparison.md](run-comparison.md) section 9.10); step R1 of the mentor's review ([milestone-plan.md](milestone-plan.md) section 11).
- **Supersedes:** decisions (1) and (3) of ADR-064 (the teammate's patch as a second pinned input of the job build); nothing else.
- **Context:** the mentor's review of 22 October 2026 listed five small items: mark the two file-system keys final, check the folder chain on write and rename, reserve the companion file names, remove the two-node assumption from the tooling, and bring the teammate's receipt patch into the source tree.
- **Decision:** (1) the wrapper calls `verifyChain` for the folder of every file that is created and for the new parent of every rename, so a folder that was copied or moved behind the wrapper's back (its identity still names the old folder) is refused at the write and at the rename, not only at the read; (2) the names of the wrapper's companion files, the folder identity (`_attested-folder`) and the record of a file (a dot, a name, `.attested`), are refused for create, make a folder, open, delete and both ends of a rename; the open is refused in both of its paths, `open(Path, int)` and the `openFile` builder, which is how the Hadoop shell and MapReduce open a file; (3) `fs.hdfs.impl` and `fs.AbstractFileSystem.hdfs.impl` are marked final in the fleet's `core-site.xml` (a line `@final KEY` in the properties file, written as `<final>true</final>` by `hadoop_conf.py`, which also checks it), so a resource that is loaded later cannot replace the wrapper; (4) the fleet tool (`f1-fleet.py build`, `final`, `report`) and the driver (`WORKERS=n`) take a master and any number of workers, `final` refuses a check that misses a node of `fleet.tsv`, and the two-node forms still work; the mismatch demonstrations and the comparison of two images stay two-node; (5) the eleven files of the teammate's patch (her commit `841c1d3`, patch SHA-256 `61dbff2e…`) are in the source tree, the job build takes only the source archive, checks that the tree holds `CustodyReceipt.java` and `TcCanonical.java` and that the job holds the class `CustodyReceipt`, and the patch step and the `patch` input are gone.
- **Why:** a folder copied elsewhere carried a valid identity for another name, and a write into it succeeded and failed only when somebody read; a person could create files named like records through the wrapper; a configuration resource loaded later could have replaced the wrapper; the Hadoop shell opened a record name through the builder and the first test of the reserved names did not cover that path (found in the sandbox with the real shell, which is why the smoke test now covers it); and the build had a second input that only the kit carried.
- **How to change it:** the chain check is in `AttestedFolders.ensureTree` and in the before-move hooks of `AttestedHdfsFileSystem`; the reserved names are in its `denyReserved`; the final keys are the `@final` lines of `ops/image/rootfs/etc/tc/fleet-props/core-site.props`; the build input is the arguments of `ops/image/build/tc-image-job.sh`.
- **Consequences:** limitations row 149 is resolved and rows 172 to 174 are new; the `nutch-deploy` reference of every image built from now on differs from that of the earlier images, because the receipt code is in the tree; four attacks (A11 to A14) are added to the attack script and to [security-argument.md](security-argument.md).

## ADR-072: The export: the master exports the crawl once, after it, and a new quote C binds the manifest

- **Date:** 23 October 2026. **Status:** accepted: shown on a debug fleet of two nodes ([run-comparison.md](run-comparison.md) section 9.11); step R5 (decision 5 of the mentor's review, [milestone-plan.md](milestone-plan.md) section 11). Two items are open: Subhi's verifier on a real export, and the retention lock of the bucket.
- **Supersedes:** nothing. It refines the mentor's wording "quote B bound to the manifest" into a quote C.
- **Context:** the stored data can be verified by anyone only if it leaves the fleet in a form that a verifier can check, and the consumer must be able to tell which export the platform measured.
- **Decision:** (1) a unit `tc-export.service` on the master runs once, after `tc-crawl.service`, without an operator command; (2) it runs Nutch's own WARC exporter (`nutch warc`) so that the WARC files are written into HDFS (`/tc/warc`) through the wrapper [**superseded on 26 October 2026 by the teammate's receipts change (PR 1): the fetcher itself writes the WARC files, with the receipts, through the wrapper into `/tc/warc`, and the export no longer runs a Nutch job; steps (3) to (5) are unchanged**] and get their signed records (the exporter writes plain `.warc` files, with names like `part-r-00000.seg-00000.attempt-00000.warc`); (3) it copies each WARC file to local disk through the wrapper, so that the copy is verified, and copies its record and the identities of its folders with the plain client, as they are; (4) it writes `manifest.tsv` (SHA-256, size and path of every file, sorted) and extends its SHA-384 into RTMR3 as the event `export`, the last event of the log; (5) it takes a new quote C with the same binding text as quotes A and B, so C binds the whole log, and publishes it as the guest attribute `tc/export` (and a failure as `tc/export-error`); (6) if the instance metadata `tc-export-bucket` names a bucket, it uploads every file with create-only requests (`ifGenerationMatch=0`) and finishes with a `DONE` object that holds the manifest's SHA-384; (7) only the master has a service account, and it holds `roles/storage.objectCreator` on that one bucket (the deliberate exception of decision 5); the bucket has uniform access, public access prevention and a retention policy; (8) rule E8 checks quote C and an export folder (`f1-fleet.py export-check`), and `enforce` applies E8 to the quote C of the master when there is one; (9) the export unit has the same service options as the fleet unit, that is none of systemd's sandboxing options.
- **Why a quote C, and not the manifest in quote B:** quote B is taken when the fleet forms, before the crawl, and rule E6 says that its log ends with `fleet` and `fleet-conf`; the manifest does not exist then. A new event and a new quote keep B and the rules E1 to E7 as they ran, and C is B's log plus one event.
- **How to change it:** the script is `ops/image/rootfs/usr/local/lib/tc/tc-export.sh` and its unit `tc-export.service`; the checker is `check_export` in `ops/image/test/f1-fleet.py`; the operator stages are `export-wait`, `export-fetch` and `export-check` of `f1-drive.sh`.
- **Consequences:** limitations rows 175 to 178; the reference values of an image that has the export differ in `tc-lib` and `tc-units`; the first real run found two defects of mine (the unit's `PATH` had no `/usr/sbin`, where `runuser` lives, and the exporter writes `.warc` and not `.warc.gz`), which the guide records (mistakes 172 and 173).

## ADR-073: The scratch disk is dm-integrity (HMAC-SHA256, initialised by discard) under dm-crypt (AES-XTS), with two keys of one boot, formatted at every boot

- **Date:** 23 to 26 October 2026. **Status:** accepted: shown on the real cluster on image `tc-img-seal-5` ([run-comparison.md](run-comparison.md) section 9.13) and on a real kernel under QEMU, where both failures of the first design were reproduced. It implements the mentor's decision 2 ("dm-crypt and dm-integrity in authenticated mode, keyed from RAM, formatted at every boot") with a different mechanism than the one first built.
- **Supersedes:** the first build of step R3, which used LUKS2 with an integrity tag (`--integrity hmac-sha256 --integrity-no-wipe`).
- **Context:** the first build used LUKS2 with an integrity tag (`--integrity hmac-sha256 --integrity-no-wipe`). On the first sealed boots on the cluster the root was verified and the scratch disk then failed: `mke2fs` read a sector that was never written, the kernel answered `INTEGRITY AEAD ERROR` (sector 0, and sector 8225664 before it), and the machine powered itself off, as the script is built to do. A real-kernel boot under QEMU reproduced it and also tried the shortcut of recalculating the tags over the existing data: the kernel refuses that for HMAC (`Recalculating with HMAC is disabled for security reasons`). A full wipe would work, but takes as long as the disk is big.
- **Decision:** from the disk up: (1) dm-integrity with HMAC-SHA256, no journal, a random key of this boot; (2) `blkdiscard --force` on it, the kernel's own way to mark a fresh device as valid zeros, which writes only the tags (about 0.8% of the disk); (3) dm-crypt in plain mode, `aes-xts-plain64`, 4096-byte sectors, a second random key; (4) ext4 with the inode tables written (reading a discarded sector gives garbage after the decryption, not zeros). Both keys are made in `/run` and deleted after use. The disk is formatted at every boot. The scratch disk is the one whole NVMe disk that is not the root's disk and has no partition; a disk that holds anything but an earlier dm-integrity signature of ours is refused. A disk without discard support gets the slow way (`integritysetup` writes the whole disk, with its own longer time limit, and a warning line). The disk work runs in `local-top` (udev still runs), the mounts of `/var/lib/hadoop`, `/var/log` and `/tmp` in `init-bottom`. Every command has a time limit, every step a progress line, and a failure powers the machine off with a `tc-scratch:` line.
- **How to change it:** the scripts are `ops/image/rootfs/etc/tc/initramfs-tools/scripts/local-top/tc-scratch-dev` and `.../init-bottom/tc-scratch-bind`; the limits are one-line assignments at the top (`TMO`, and `WIPETMO` for the slow way); the tools that the initramfs carries are in `hooks/tc-seal`.
- **Consequences:** limitations rows 179 to 181; security rows 29 and 30; mistakes 176 and 178; the layout of the raw disk differs between kernels, so no check may read it from the kernel's table (rule 69).

## ADR-074: The sealed boot: a dm-verity root under a RAM overlay, the root hash on the measured kernel command line, and an offline sealing of a copy of the builder's disk

- **Date:** 22 to 26 October 2026. **Status:** accepted: shown on the real cluster on images `tc-img-seal-3` to `tc-img-seal-5` (section 9.13). It implements the first half of the mentor's decision 2.
- **Supersedes:** nothing. The probe of 22 October showed that the image boots without an initrd (as the mentor said) and that the kernel's `dm-verity`, `dm-crypt` and `dm-integrity` are modules, so `dm-mod.create=` cannot set up a verity root on this kernel; a measured initramfs is used instead (the plan row of step R3 kept the choice as a question for the mentor).
- **Context:** the evidence image must run only what was measured, and its root must not change after the build, including by someone who can write the disk.
- **Decision:** (1) the root partition is a copy of the builder's, shrunk to 10 GiB (2,621,440 blocks of 4096 bytes), without a journal, with the dm-verity hash tree behind the data in the same partition; (2) the root hash, the block count, the salt and the root partition's PARTUUID are on the kernel command line in `grub.cfg` on the EFI partition, which the boot measures into RTMR2; (3) a measured initramfs (built by `tc-image-sealbake.sh` with its own configuration folder, `MODULES=list`, and verified in five gates) opens the root with `veritysetup` in `local-top` and refuses to go on if the hash does not match; (4) the root is mounted read-only and `overlayroot` puts a RAM overlay over it (`fsck.mode=skip`: a read-only verity device cannot be checked); (5) the sealing is done offline by `tc-image-seal.sh` on a COPY of the builder's disk, on a helper VM, in nine gates, of which gates 1 to 5 are read-only (shown by checksum), and it refuses to run without `--destructive-ok`; the builder itself is never changed by the sealing; (6) the image is made from the sealed copy.
- **How to change it:** the plan is the parameters of `tc-image-seal.sh` (`--blocks`, `--salt`, `--kver`) and the template `ops/image/rootfs/etc/tc/grub-sealed.cfg.in`; the initramfs sources are in `ops/image/rootfs/etc/tc/initramfs-tools/` (measured, because `/etc/tc` is).
- **Consequences:** limitations rows 180 to 183; security rows 28 and 30; the initramfs lives inside the sealed root, so a change of it needs a new seal; putting it on the EFI partition would avoid that; decided by default on 28 October 2026 that it stays (ADR-083).

## ADR-075: The rehearsal hooks (`TC_*`) are stripped from the installed scripts when the image is built, and a gate refuses an image that still has one

- **Date:** 24 to 26 October 2026. **Status:** accepted: shown on image `tc-img-seal-5` (the build printed `REFRESH-OK: six scripts installed without TC_ hooks (left: TC_LOG )`). It implements the second half of the mentor's decision 2 ("no `TC_*` rehearsal hooks in the production scripts").
- **Supersedes:** nothing.
- **Context:** the six scripts of the fleet (`tc-measure.sh`, `tc-crawl.sh`, `tc-export.sh`, `tc-extend.sh`, `tc-fleet.sh`, `tc-report.sh`) let their rehearsals redirect paths and commands through environment variables. The rehearsals need that; the production scripts must not have it.
- **Decision:** the sources keep the hooks. `ops/image/build/tc-image-refresh.sh` installs the six scripts from the kit and rewrites every `${TC_NAME:-default}` (and `${TC_NAME-default}`) to its default, removes the one command hook (`TC_WRITE`) with its branch,. `TC_LOG` stays: it is the event-log argument that the scripts pass to each other, not a hook. A gate refuses the installation if any other `TC_` name is left in the six scripts.
- **How to change it:** the list of scripts is `FILES` at the top of `tc-image-refresh.sh`.
- **Consequences:** the measured event `tc-lib` of a stripped image differs from an unstripped one (shown in section 9.13); the rehearsals test the sources, and the stripped scripts are tested by running them on the real fleet.
- **Amendment, 27 October 2026:** the strip also drops the comment lines that describe a removed hook (`ops/image/build/tc-strip-hooks.py`, used by `tc-image-refresh.sh`), so that no description of a hook is left in an installed script. The code of the strip was moved out of the refresh script into its own file; it is byte for byte the same logic.

## ADR-076: The mentor's review is divided: R7 is the teammate's and R6 is deferred; our own nonce work is removed

- **Date:** 26 October 2026. **Status:** accepted (the mentor's decision, relayed by the user).
- **Supersedes:** the plan of 22 October, in which R7 (the consumer's nonce in the binding text, and read-only access for the teammate) and R6 (scale and benchmarks) were ours to do next.
- **Context:** the teammate's receipts change (PR 1) issues no nonce, so her receipts carry `nonce: null`; freshness rests on the signed time readings.
- **Decision:** R7 is the teammate's. We had built a first version of the nonce on our side (kit `r3l`); it is removed from our tree and was never committed, so there is no nonce code in the repository. R6 is deferred. Step R3 is done without both. The receipts of the teammate are verified independently by us (section 9.12), which does not replace her own verifiers.
- **How to change it:** nothing in the code depends on it. R7 is a change of the binding text that the fleet scripts build and of the verifier; nothing of it is in the repository yet.
- **Consequences:** the plan rows R6 and R7 ([milestone-plan.md](milestone-plan.md) section 11) say so.

## ADR-077: The commit is part of the measured state (the first event, `source`), and the verifier is pinned to it (rule E9)

- **Date:** 27 October 2026. **Status:** accepted: shown on the real cluster on image `tc-img-r4-1` ([run-comparison.md](run-comparison.md) section 9.14). It implements the first and the last part of the mentor's decision 4 (the image is built from `git archive` of a named commit, the commit is in the measured state, and the verifier accepts only the commit pinned for the run).
- **Supersedes:** nothing. It narrows limitations row 118.
- **Context:** until now nothing tied an image to a source tree: an image built from an unnamed working copy measured the same way as one built from a named commit, and the reference file only recorded what two machines had reported.
- **Decision:** (1) the source of a build is the `git archive` of a named commit; `ops/image/test/r4-archive.py` reads the commit id from the archive's own header and refuses an archive whose header names another commit than the one expected (a prefix of 9 characters is accepted); (2) the bake writes `/etc/tc/source.txt` with one line, `commit <id>`, and stops when no commit file is shipped (`ALLOW_NO_COMMIT=1` records `commit none` for a development build, with a warning); (3) `source` is the first event of the measured lists, so the lists have 15 events (F1) and 16 events (F4) and the commit extends RTMR3; (4) `f1-fleet.py enforce OUT REFERENCE COMMIT` takes the pin (rule E9): reference values that name a commit are refused without the pin and with another commit; a pin for reference values that name no commit is refused; the `source` event of the reference must be the SHA-384 of the line `commit <id>`; `commit none` is never a reference; a node built from another commit is refused by name; (5) `f1-fleet.py reference` records the commit only when the nodes really measured it (`TC_REF_COMMIT`, which `f1-drive.sh` sets from `PIN_COMMIT`).
- **How to change it:** the pin is the third argument of `enforce` (`PIN_COMMIT` for the stage `enforce` of `f1-drive.sh`); the lists of events are `ops/image/rootfs/etc/tc/measured-paths-f1.txt` and `measured-paths-f4.txt`.
- **Consequences:** limitations rows 186, 187 and 192; security row 32. The image of section 9.14 names the base commit `9b45b91af` while it was built with the R4 kit, so the reference of the shipped state must be made from builds of the final commit (row 187).

## ADR-078: A build is made reproducible by removing build-time data that two real builds were seen to differ in, never by hiding a difference

- **Date:** 27 October 2026. **Status:** accepted: two builds of one commit (the first experiment from scratch; the later rounds re-ran every stage after the preparation on the same two builders, which were made from one pinned base image) now give the same 15 measured events, the same 601 package versions, the same kernels and GRUB configuration and the same initramfs (section 9.14). It implements the "deterministic jar" part of the mentor's decision 4 and part of "deterministic root filesystem".
- **Supersedes:** ADR-009 in part: ADR-009 decided on 21 October 2026 that the nodes of a fleet share one copy of the JDK's start-up cache `classes.jsa`; the file is now removed from the image.
- **Context:** the first experiment built commit `9b45b91af` twice from scratch and compared everything: 12 of 15 events were equal. The three that differed held build-time data: the JDK's class-data cache `classes.jsa` (11,919,360 bytes, made when the JDK is installed); the job jar (a build stamp in the `pom.properties` of the language-detection library, and the time in the zip headers of 1,369 entries); and `tc-conf`, which only recorded the job's hash. After those were fixed, a second experiment left one difference, the sealed initramfs: of its 539 entries three differed, all written by hooks of other packages: `.random-seed` (the `overlayroot` hook copies up to 4 KB of the build machine's `/dev/random` into it) and the date line in `etc/mdadm/mdadm.conf` and `mdadm.conf.tmp` (`mkconf` writes the current time).
- **Decision:** (1) `ops/image/build/tc-image-jdkcache.sh` checks that the JVM starts with `-Xshare:off` and then removes `classes.jsa`; (2) `tc-job-normalize.py` rewrites the job and its nested jars with one zip time (1 January 1980), no extra fields and no date line in the `pom.properties` of unsigned jars (58 lines), never changes the content of a signed jar (5), keeps order, permissions and compression, and checks its own result and that a second run changes nothing before it writes; (3) `tc-initrd-normalize.py` patches the three entries in place with the same lengths (the seed becomes zeros, the time in the two mdadm comments becomes the time of `SOURCE_DATE_EPOCH`), compresses with the same `gzip -n` as `mkinitramfs`, checks that no other byte changed, and runs in `tc-image-sealbake.sh` after `mkinitramfs` and before the gates; (4) the method: a difference is read from two real builds (jar entries, cpio entries) before any fix, and each fix is tested on the real files before a rebuild.
- **How to change it:** each tool has its rules at the top of the file; a new rule is one line and one rehearsal check, and the tool refuses any change that the rule does not allow.
- **Consequences:** limitations rows 188 to 191; mistakes 183 to 187; rules 73 to 77. The seed in the initramfs is public and measured, so it gave no secrecy: the keys of the scratch disk come from the kernel's own random number generator.
- **Amendment, 28 October 2026:** a fourth build-time datum was found by comparing builds of two different days: the day on which the JDK's certificate store was generated reached the collection policy, and so `tc-conf` (ADR-080).

## ADR-079: The reference values are generated from independent builds and merged with a real run; the platform part stays the real run's

- **Date:** 27 October 2026. **Status:** accepted: shown on the real cluster on image `tc-img-r4-1` (section 9.14). It implements the middle of the mentor's decision 4 (reference values from CI).
- **Supersedes:** nothing. It narrows limitations row 118.
- **Context:** MRTD and RTMR0 to RTMR2 are measured by the platform and by the sealed disk, and a build on a builder cannot produce them; the hash of the sealed root is not reproducible (limitations row 186). The stable events of RTMR3 can be produced by a build.
- **Decision:** `ops/image/test/r4-reference.py` makes the reference of a commit from the ground truth of at least two builds (`events.tsv` and `source.txt`, written by `r4-manifest.sh`) and refuses unless they agree on every event, in the same order, and each recorded exactly `commit <id>`; with `--platform` (the reference of a real fleet run) it takes MRTD and RTMR0 to RTMR2 from the real run and refuses unless every stable event and the event order equal what the real machines measured. `r4-accept.sh` runs this and the pinned `enforce` on the quotes of a real fleet, and proves that the verifier refuses a wrong pin and a missing pin on the same quotes.
- **How to change it:** the number of builds is the number of `--build` arguments (at least two; `--allow-single` is for development only and the result says that it is incomplete).
- **Consequences:** limitations rows 186 to 189; the final reference must be made from builds of the final commit (row 187), and a rebuild by the teammate is still open (row 188).

## ADR-080: The collection policy must not contain the day of the build (its file hash is taken over the keytool text without the Creation date lines)

- **Date:** 28 October 2026. **Status:** accepted: shown on the real cluster on commit `43f6fd386` ([run-comparison.md](run-comparison.md) section 9.15).
- **Supersedes:** nothing. It adds a fourth build-time datum to ADR-078.
- **Context:** the second pair of builds of 27 October (commit `68961df9e`) made the policy `e623c150…`, the first pair `1ba5c732…`, with the same 120 certificates. `keytool -list -rfc` prints a `Creation date` line for every certificate: the day on which the JDK's store was generated on that machine (26 October on the old builders, 27 October on the new ones). The hash of the whole text was `cfa67d60…` against `7e89bc58…`; without the date lines it was `757d0a8d…` on both. The policy is in `/etc/tc`, so the day reached the event `tc-conf` and the reference values. Two builds of one day cannot show this; it appeared because the two pairs were made on different days.
- **Decision:** `tc-policy.py` hashes the keytool text without the lines `Creation date: …` and nothing else (the aliases, the entry types and the certificates stay in the hash); the hash of the anchor set did not change. The rehearsal `r4g-rehearse.sh` makes the same store on two days and shows the same policy, shows that another certificate, alias or entry type still changes it, and has a control that fails for the old behavior. On the real builders, the fixed script made the same policy `bd4a62bb…` for the two stores of 26 and 27 October.
- **How to change it:** the line of `tc-policy.py` that builds `text`; the teammate's `make_policy.py` must drop the same lines for her policy and ours to agree on one machine.
- **Update, 28 October 2026:** in the comparisons between pairs of builds `tc-conf` also changed because `job-versions.txt` names the source archive by file name and hash (limitations row 203); the day-dependence of the policy is proven separately (the same 120 certificates, and the hash without the date lines equal on two stores of different days).
- **Consequences:** limitations rows 194 and 195; mistake 189; rule 79. The reference values of image `tc-img-r4-1`, made before the fix, hold a `tc-conf` that depends on the day; the reference of commit `43f6fd386` is the one to use.

## ADR-081: The sealed root is not required to be reproducible bit for bit, its contents are (a default taken on 28 October 2026, for the mentor to confirm or change)

- **Date:** 28 October 2026. **Status:** accepted as a default that we took, as the mentor's note asks for decisions that an experienced researcher would take and that can be changed easily; whatever the mentor decides supersedes it.
- **Supersedes:** nothing. It settles the open question of limitations row 186.
- **Context:** the mentor's decision 4 asks for "a deterministic root filesystem and jar". The jar is done (ADR-078). Two sealings of builds of one commit give different disks (file system times, UUIDs, hash seed): the root hash and RTMR2 were `a2b4de40…` and `daa83af9…` on `tc-img-seal-5`, `8c36e94d…` and `c8066c42…` on `tc-img-r4-1`, `8888150c…` and `238055e3…` on `tc-img-fin2-1`.
- **Decision:** what must be reproducible is the content of the image: the 15 measured events, the initramfs, the kernels and the package versions, which are identical in every build (sections 9.14 and 9.15). The root hash and RTMR2 are taken from the real run of the sealed image: the reference merges them with the events that independent builds recomputed (`r4-reference.py --platform`, ADR-079), and every node of a fleet must show the same.
- **How to change it:** if the mentor wants the disk bit for bit, a new step has to make the file-system image deterministic (times, UUIDs, hash seed, directory order) and seal again; no other decision changes and no code is needed now.
- **Update, 28 October 2026:** in her review the mentor said that she took the sealed root hash to give an identical disk already, and asked why identical disks would be a new step. She also said that RTMR2 and RTMR3 must appear in the final work file and match the first verification, that machine-specific measurements may differ, and that the OS and the image must be identical. The explanation (to be sent): the hash identifies one sealed disk, and four sealings of builds of the same content gave four different root hashes (`a2b4de40…`, `8c36e94d…`, `8888150c…`, `a6881d07…`) because the file system is created with times and IDs that change; RTMR2 holds the hash. Her answer is still to come; this default stands until then, and it is no longer certain that it is what she wants.
- **Consequences:** limitations row 186 is decided by default; the plan and the session page no longer list the question as waiting for us. This is our default, not a statement that the mentor agrees.

## ADR-082: Nothing reaches GitHub before the whole run on the real cluster has passed: a local commit, one command on the cluster, a push that needs the cluster's commit id

- **Date:** 28 October 2026. **Status:** accepted: used for commits `43f6fd386` and `1c8a2cc19`. It states the standing rule of the project (only code that ran on the real cluster, in exactly those bytes, is committed) as a procedure.
- **Supersedes:** nothing.
- **Context:** an image records the commit that built it, so a commit has to exist before the run, and on 27 October I proposed to commit the policy fix before it had run in the pipeline (mistake 190).
- **Decision:** (1) a LOCAL commit on the laptop, with the source archive and the commit id (`r4-prepare.ps1`); (2) one command in Cloud Shell runs prepare, both builds, the comparison with automatic gates, the sealing, the boot check, the fleet, the verification and the cleanup, stops at the first failure and can be run again (`ops/r4-final-kit/r4-final.sh`); (3) `r4-push.ps1` pushes only when the commit id that Cloud Shell printed after `R4-FINAL-PASS` is typed and equals the local commit. If anything fails, `git reset --hard` discards the local commit and GitHub has never seen it.
- **How to change it:** the stages and their success lines are the table at the end of `r4-final.sh`; the push guard is the typed id. The two PowerShell scripts are not in the repository because they hold the hashes of one package.
- **Amendment, 28 October 2026:** the procedure was used twice (the policy fix and the package pin) and changed in four ways: the commit id travels in the command (`EXPECT=<id>`), the archive is named after its commit, every kit has its own run folder and refuses a PASS without a recorded commit, and `--until <stage>` runs a kit up to a stage and stops with its report. The second kit (`r4-pin-kit5.zip`, SHA-256 `b0d7d4addf1fa1ca…`) is kept outside the repository until the step R4.7 has run, because it has two known defects (limitations rows 200 and 204); the fixed kit is then committed as `ops/r4-pin-kit/`.
- **Consequences:** mistakes 190 and 191 (and 195 to 199 for the second kit); rules 80 and 81 (and 85 to 89); limitations row 196. The kit ran on the real cluster in exactly the committed bytes, but the zone fallback of its boot stage ran only against a stub.

## ADR-083: The initramfs stays inside the sealed root (a default taken on 28 October 2026, for the mentor to confirm or change)

- **Date:** 28 October 2026. **Status:** accepted as a default that we took; whatever the mentor decides supersedes it.
- **Supersedes:** nothing. It settles the open question that ADR-074 and limitations row 180 left to the mentor.
- **Context:** the measured initramfs lives inside the sealed root, so a change of it needs a new seal and a new image. Putting it on the EFI partition would avoid that, at the price of one more measured file.
- **Decision:** it stays inside the sealed root. It has been the same bytes (`82da7978…`) in every build of 26 to 28 October, and a new seal takes about 7 minutes (the stage `seal-disk` of 28 October).
- **How to change it:** move the file to the EFI partition, add it to the measured list (the reference gets a 16th event) and measure it; this is a new step with its own run.
- **Update, 28 October 2026:** the mentor confirmed the default in her review (any change needs a new seal anyway).
- **Consequences:** limitations row 180 is decided by default and confirmed.

## ADR-084: Rebuilds must match over a short horizon, and the package versions are recorded; a longer horizon would use a dated copy of the Ubuntu archive (a default taken on 28 October 2026)

- **Date:** 28 October 2026. **Status:** superseded by ADR-086 on 28 October 2026: the mentor decided that package archive pinning (a monthly horizon) is needed and takes the new step, and not this default.
- **Supersedes:** nothing. It settles the design part of limitations row 189.
- **Context:** the 601 package versions of two builds are equal because the builds ran on the same day; Ubuntu keeps updating packages, so a rebuild weeks later can differ without any change of our code. Four ways exist: record the versions (the list is in the evidence and the comparison names any difference); install exactly the recorded versions (fragile: Ubuntu drops superseded versions from its package lists); build from a dated copy of the Ubuntu archive (Canonical's snapshot service, not yet tried from our builders); keep our own copies of the package files.
- **Decision:** the horizon is short. The reference records all package versions, `r4-diff.py` reports a difference by name and does not hide it, and the base image name is a build input. A copy of the base image in our own project (a few cents a month, not made yet) would remove the risk that Google withdraws it.
- **How to change it:** for a horizon of months, build from a dated copy of the Ubuntu archive with the date written in the repository, and store the SHA-512 of the Hadoop tarball in the repository; this is a new step (R4.6) that must run on a new pair of builders before it is committed.
- **Consequences:** limitations row 189 is decided by default; its two other parts (our own copy of the base image, the SHA-512 in the repository) stay open.

## ADR-085: The retention lock of the evidence bucket stays off until a retention period is named (a default taken on 28 October 2026)

- **Date:** 28 October 2026. **Status:** accepted as a default that we took.
- **Supersedes:** nothing. It settles the trigger of limitations row 176 ("the final evidence run").
- **Context:** the lock cannot be undone, and the evidence runs of step R4 are final but the mentor has not named a retention period.
- **Decision:** the bucket stays unlocked, and the master's account is refused overwrite and delete in any case (shown on 23 October); the lock is applied when a period is named.
- **How to change it:** one command on the bucket, with the period in days; it cannot be reversed.
- **Update, 28 October 2026:** the mentor did not understand the question in her review. It needs a plainer explanation (the lock makes the bucket read-only for a number of days and cannot be undone) or it is dropped; the default stands.
- **Consequences:** limitations row 176 stays open, with the default noted.

## ADR-086: The packages are installed from a dated copy of the Ubuntu archive (the mentor's decision of 28 October 2026, built as step R4.6 and verified on commit `1c8a2cc19`)

- **Date:** 28 October 2026. **Status:** accepted: decided by the mentor, built and verified on the real cluster ([run-comparison.md](run-comparison.md) section 9.16).
- **Supersedes:** ADR-084 (the short-horizon default).
- **Context:** the package versions of builds are equal only while the live archive does not change; the mentor asked on 28 October for a monthly horizon and said that this is the new step, not the default. Canonical's snapshot service serves the archive as it was at a given time.
- **Decision:** the date is one line, `ops/image/build/apt-snapshot.txt` (`20261027T000000Z`); the stage `aptpin` (`tc-image-aptpin.sh`) points apt at `https://snapshot.ubuntu.com/ubuntu/<date>` for jammy, jammy-updates and jammy-security, and runs before `tc-image-prep.sh` because the preparation installs `wireguard-tools` (the measured event `wg`). It refuses a missing, malformed, impossible or future date, a machine that is not Ubuntu 22.04, a failing update, and package lists that do not come from the dated copy. The proof is made on fresh builders, because machines that already hold newer packages would not show the pin; the Hadoop tarball is copied inside the network from a builder that was not cleaned.
- **Result on the real cluster (commit `1c8a2cc19`):** `APTPIN-OK snapshot=20261027T000000Z` on both fresh builders (JDK `11.0.32.1+1-1ubuntu1~22.04`); the two builds are identical in all 15 events and in the 601 package versions, and the versions equal those of the last pair's build of the day before; the sealed fleet, the receipts, the export and the pinned acceptance pass. **Correction, 28 October 2026:** the build stage of the kit had the archive name written in it, so the file `src-pin.tgz` that was still in the home folder (the archive of the earlier local commit `ec581508a`, SHA-256 `1dad36a7…`) was shipped to the builders and not the archive of `1c8a2cc19`; the two archives differ only in a test file (`f03a-rehearse.sh`), so the Nutch source, the job and the image content are the same, but `job-versions.txt` (part of `tc-conf`) names the old archive (limitations rows 203 and 204).
- **How to change it:** change the one line of `apt-snapshot.txt` and run the kit again; the packages, the events that hold them and the reference change with it.
- **Open parts:** the kernel packages are still downloaded from the live archive pool (SHA-256 checked, limitations row 197), the SHA-512 of the Hadoop tarball is not stored in the repository, our own copy of the base image is not made (row 189), and the date was chosen by us (row 198).
- **Consequences:** limitations rows 189 (main part closed) and 197 to 204; mistakes 195 to 201; rules 85 to 91.
