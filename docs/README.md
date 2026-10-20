# CCBot on Hadoop inside Intel TDX Confidential VMs: documentation

This folder documents a two-run experiment: run Common Crawl's Nutch fork ("CCBot") on a
two-node Hadoop cluster whose nodes are Intel TDX Confidential VMs on Google Cloud, crawl at most
10 URLs, collect the WARC output, and bind a manifest of each run to hardware attestation quotes.

Everything here was written from terminal output captured during the work (2 and 3 October 2026).
Times are UTC. Timestamps printed by tools on the operator's laptop use India Standard Time (UTC+5:30) and are
converted where cited. Where something was not observed, the text says so.

**Update, 17 October 2026.** On 7 October the work moved from this two-run pilot to a plan of Milestones 0 to 6. Milestones 0 to 4 are closed (Milestone 4 on 14 October) and Milestone 5 is in progress: steps 5.1.1 to 5.2.2 are done and step 5.3 is open. The newest state is on [session-start.md](session-start.md), the plan is [milestone-plan.md](milestone-plan.md), and the milestone reports and the decision log are listed below. Runs 14 and 15, the first crawls with signing on, are in [run-comparison.md](run-comparison.md) section 9.8. **The plan from 19 October 2026 is the mentor's fixed fleet** ([next-steps-fixed-fleet.md](next-steps-fixed-fleet.md)): steps F0 to F5 in [milestone-plan.md](milestone-plan.md) section 10, which keep the older steps as history and name what each new step replaces.

## Documents

| File | What it answers |
|---|---|
| [session-start.md](session-start.md) | Where we are and how to continue: the state in one page, where everything is, and the working rules (read this first in a new session) |
| [cluster-configuration.md](cluster-configuration.md) | How the VMs, network, Hadoop and the crawl were configured, and why two VMs; sections 9 to 27 record each later change and window in date order |
| [cluster-rebuild.md](cluster-rebuild.md) | Getting back to a working cluster after the lab machines were wiped (the rebuild kit in `ops/rebuild/`) |
| [run-1-pilot.md](run-1-pilot.md) | Run 1: hand-typed commands, full timeline, results and evidence |
| [run-2-scripted.md](run-2-scripted.md) | Run 2: the same crawl driven by the committed scripts |
| [run-comparison.md](run-comparison.md) | What was identical, what differed, and what that does and does not show, for runs 1 to 15 |
| [quote-verification.md](quote-verification.md) | Signature checks, measurement registers and tamper tests on the four quotes |
| [limitations-and-trust.md](limitations-and-trust.md) | Updated limitations and challenges table, ranked trust issues, better-TEE comparison, next experiments |
| [guide-first-principles.md](guide-first-principles.md) | Beginner's master guide to the two-run pilot (runs 1 and 2): every concept from first principles, and every step from first login to last commit; the later work is explained in plain words at the top of each milestone report |
| [guide-pitfalls-and-lessons.md](guide-pitfalls-and-lessons.md) | Mistakes made, corrections, decisions taken, and a checklist for repeating the work |
| [milestone-plan.md](milestone-plan.md) | The plan: Milestones 0 to 6, steps and status, dependencies, teammate S's work, timeline |
| [milestone-0-clean-baseline.md](milestone-0-clean-baseline.md) | Milestone 0: the clean baseline with CCBot's real HTTP client (run 3) |
| [milestone-1-code-measurement.md](milestone-1-code-measurement.md) | Milestone 1: measuring the code that runs into the hardware quote |
| [milestone-2-wireguard-mesh.md](milestone-2-wireguard-mesh.md) | Milestone 2: the WireGuard mesh and a closed ordinary network |
| [milestone-3-hdfs-wrapper.md](milestone-3-hdfs-wrapper.md) | Milestone 3: the `hdfs://` wrapper and the storage audit |
| [milestone-4-storage-integrity.md](milestone-4-storage-integrity.md) | Milestone 4: storage integrity (hashing, records, verified reads, contract tests, the fail-open fixes and the first timing pair); closed on 14 October 2026 |
| [milestone-5-signed-records.md](milestone-5-signed-records.md) | Milestone 5: signed records, the real per-VM key, the admission of keys and of mesh nodes by their quote (steps 5.1.1 to 5.2.2 done; the rest replaced on 18 October 2026 by the fixed fleet, steps F0 to F5) |
| [decisions.md](decisions.md) | The decision log, with the mentor's decisions |
| [handoff-attested-hadoop-cluster.md](handoff-attested-hadoop-cluster.md) | The mentor's handoff, with the corrections of 7 October and dated status updates |
| [next-steps-fixed-fleet.md](next-steps-fixed-fleet.md) | **The current handoff:** the mentor's note of 18 October 2026, kept verbatim: the fixed fleet, the locked image, the smaller trusted code, and the steps 0 to 5 (F0 to F5 in our documents) |
| [next-steps-storage-signing.md](next-steps-storage-signing.md) | The mentor's note of 10 October: the decisions after step 4.6 and the steps A1 to C4 (with a status note of 17 October) |

## Repository map: what was added and why

Commit ids are abbreviated. `git log --stat --oneline` shows the full history.

| Path | Commit | Why it exists |
|---|---|---|
| `conf/nutch-site.xml` | `5635894b7` `feat(config)` | Nutch overrides: bot identity (`http.agent.name`), WARC output switched on, and the labels written into each WARC's `warcinfo` record. The repository's `.gitignore` ignores `conf/*.xml`, so it was added with `git add -f` |
| `attest/quote.sh` | `3560802e3` `feat(attest)` | Requests a TDX quote whose REPORTDATA field holds the SHA-512 of a file |
| `attest/verify-binding.sh` | `52a96263f` `feat(attest)` | Checks that a quote's REPORTDATA equals the SHA-512 of a file (prints MATCH or MISMATCH). It does **not** verify the quote's signature |
| `attest/make-manifest.sh` | `f30e694cc` `feat(attest)` | Writes a text inventory of one node: versions, config hashes, inputs, outputs |
| `ops/run-crawl.sh` | `4fec69478` `feat(ops)` | The capped cluster crawl command, kept as a script so run 2 used exactly the documented options |
| `seeds/seed.txt` | `4fec69478`, later corrected by a `fix(seeds)` commit | The two practice seed URLs. Lives outside `conf/` so it is not ignored |
| `attest/README.md` | `a7e758726` (empty by mistake), then `105efc288` | Explains the attestation workflow and its limits |
| `docs/run-1-pilot.md` | `2aadecd86` `docs(run-1)`, expanded later | Run 1 record |
| `docs/*` (this set) | later `docs` commits | Reports, comparison and lessons |
| `ops/mesh/` | `71dd0e9bd` `feat(ops)` | The WireGuard mesh and the Hadoop network scripts of Milestone 2 |
| `src/java/org/apache/nutch/attested/`, `ops/attested/` | `a033495de` `feat(attested)` | The `hdfs://` wrapper and its later layers (hashing and records, signing, folder identity files, the signing service, the key list and the admission of keys by their quote, the mesh doorman), and the tests, tools, checks and facts lists that go with them |
| `ops/kits/` | `93745032c` `feat(ops)` | One folder per step that ran on the cluster, exactly as it ran (build, test, window, capture and analysis kits; ADR-042) |
| `ops/rebuild/` | `c0ff414f2` `feat(ops)` | The rebuild kit and the VM-state collection script ([cluster-rebuild.md](cluster-rebuild.md)) |
| `ops/image/` | `f0b2c95be` `feat(image)` | The image build of the fixed fleet: the default 6.17 kernel, the boot-time RTMR3 measurement, the checks and the rehearsal (step F0; it takes over from `ops/rebuild/` at step F5); the software layer of step F0.3a: `139bfb81f` `feat(image)`; the job and the wrapper jar of step F0.3b: `ae0055d7b` `feat(image)`; the crawl that runs by itself of step F0.3c (the `feat(image)` commit just before its documents) |

The commit that both run-2 manifests record as `scripts_repo_commit` begins `441cb333c21b`. It is
presumably the `fix(seeds)` commit, but confirm with `git log`.

The base of the branch is `3270a761e` ("Fetcher: do not set number of reduce tasks
programmatically"), the tip of the fork's `cc` branch when the work started. All work is on the
branch `feat/tee-hadoop-cluster` of the private repository `Heron-AI-Security/nutch-private`, which replaced the fork `Antisource/nutch` on 19 October 2026 (the fork is frozen at `ab26da172`, its last commit).

## Evidence (kept outside this repository)

| Location in Cloud Shell | Contents |
|---|---|
| `~/evidence/` | Run 1: manifests, quotes, WARC output, crawl log, HDFS listing |
| `~/evidence-run2/` | Run 2: manifests, quotes, WARC output, crawl log |
| `~/evidence-all.tar.gz` | Bundle of both folders, with its SHA-256 saved in `evidence-all.sha256` |
| `~/evidence-run2/measurements.txt`, `~/evidence-run2/tamper-test/` | Measurement values, and the manifest tamper-test log and tampered copy. Added after the first bundle was made |
| Laptop folder `tdx-evidence\tamper-test` (outside the repository) | The tampered quote and the `check` logs |
| Later evidence bundles (one per run, build, window or check) | Each milestone report names its bundles and their fingerprints in an "Evidence and commits" table (for Milestone 5: sections 3 to 9 of [milestone-5-signed-records.md](milestone-5-signed-records.md)); they are in the Cloud Shell home and in the laptop's `tdx-evidence` folder, never in the repository |

Full hash values live in the manifests. These documents quote only the first 12 hex characters
of a hash, because values retyped by hand were unreliable (see the pitfalls guide).

## Deliverable status

These rows are the deliverables of the two-run pilot (2 and 3 October 2026). The status of the milestones is in [milestone-plan.md](milestone-plan.md) and [session-start.md](session-start.md).

| Mentor deliverable | Status |
|---|---|
| Minimum number of VMs | Decided by the mentor: 2 (master and worker), both verified as TDX |
| Fork the CCBot repo and make CCBot/Hadoop work in a TEE | Done: fork `Antisource/nutch`, crawl ran on both TDX VMs, twice |
| Specify the VM configuration for Hadoop | [cluster-configuration.md](cluster-configuration.md) |
| Crawl 10 URLs and see the WARC output | Done twice: 8 pages + 2 redirect records = 10 fetch attempts each time |
| Update the limitations table, severe trust issue, better TEE for CCBot | Done: [limitations-and-trust.md](limitations-and-trust.md). Sources were gathered in a research pass and should be spot-checked before citing |
| Reference exercises: signature check, measurement comparison | Done: see [quote-verification.md](quote-verification.md) (four signatures verified, measurements compared, two tamper tests recorded). The measurements cannot be judged against a reference value |

## Glossary

| Term | Meaning |
|---|---|
| TEE | Trusted Execution Environment: hardware-isolated computation whose memory the host cannot read |
| Intel TDX, Trust Domain (TD) | Intel's confidential-VM technology. A TD is the protected VM |
| Confidential VM (CVM) | A whole VM run inside a TEE; on GCP, `confidentialInstanceType: TDX` |
| Quote | A signed statement from the CPU about a TD: its measurements plus 64 bytes of caller-chosen data |
| REPORTDATA | The 64-byte field of a quote the caller fills. Here: the SHA-512 of a manifest |
| MRTD, RTMR0-3 | Fingerprints of the TD's initial contents (MRTD), of the firmware and boot chain (RTMR0 to 2) and of the measured software stack (RTMR3). Since step 5.2.1 a quote's MRTD and RTMR0 to 2 are compared with an editable reference file, and RTMR3 is shown but not enforced |
| Window | A short, reserved period in which the cluster runs a stack that is not the measured one, for one step, and is then restored byte for byte (ADR-045) |
| Key bundle | A signing key's statement (its id and public key) together with a hardware quote whose REPORTDATA is the SHA-512 of that statement (ADR-047) |
| Reference file | An editable file of the register values (MRTD, RTMR0 to 2) that the quotes of our own machines show; a quote is admitted only if its registers match it (ADR-050) |
| Doorman | The check that lets a node join the mesh only if a fresh quote binds its WireGuard key and requested address to the machine (ADR-053 to ADR-055) |
| Manifest | A plain-text inventory of code versions, configuration hashes, inputs and outputs for one node |
| WARC | Web ARChive file format. Records here: `warcinfo`, `request`, `response`, `metadata` |
| Segment | The folder one crawl round writes (one per round) |
| HDFS, YARN | Hadoop's shared storage, and its job scheduler |
| tmux | A terminal that keeps commands running if the connection drops |

## Conventions

- Times are UTC. The VMs run in UTC, so their log, `ls` and `date` times are UTC; manifests use `date -u`.
  Tools run on the operator's laptop print India Standard Time (UTC+5:30); subtract 5 h 30 min.
- The VM clock is supplied by the host and is not proven by a quote.
- A hash comparison done by eye is not evidence. Comparisons in this work were done by the shell
  (`[ "$a" = "$b" ] && echo SAME`).
- Shell prompts identify the machine: `cloudshell`, `tdx-lab` (master), `tdx-lab-worker`, or the
  laptop's PowerShell.
