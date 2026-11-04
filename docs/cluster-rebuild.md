# Rebuilding the cluster after a wipe

**Status check, 4 November 2026.** The image is built from a dated copy of the Ubuntu archive (`ops/image/build/apt-snapshot.txt`, step R4.6), and a rebuild uses a one-command kit (the first, `ops/kits/r4-final-kit/`, is in the repository; the kit of step R4.7, `ops/kits/r4-r47-kit/`, is in it too: it ran on 28 October 2026 for commit `41033a7e0`, and the kit of step R4.9 is `ops/kits/psl-fix-kit/` (it ran on 29 October for commit `5ae1aa386`), and the kit of steps P2 and P6 is `ops/kits/rel-fix-kit/` (it ran on 29 October for commit `16bafb3b1`)): its inputs are the archive made by `git archive` of the commit, the commit id in the command (`EXPECT=<id>`), and a builder that was not cleaned and still holds the Hadoop tarball. Evidence bundles are kept outside the repository (the laptop folder `tdx-evidence`, extracted into `extracted\<bundle name>`, with a second copy on another drive). Reviewed on 30 October 2026: after a rebuild the image is checked by a dummy run, its boot events are tabulated and the release is made (steps P1, P2 and P6; section 8 below). After step P3.1: section 9 says how the CI identity is made again. After step P3.2 (30 October 2026) it was reviewed again: section 9 now also says how the reference of an image is published by a tag. After step P4 (4 November 2026) it was reviewed again: the sealing now includes the cleanup of gate 6b (section 10), and section 10 says how two builds of one commit are compared; the kit of that run is not in the repository yet.

When a teammate or the mentor uses the lab machines, **our progress and the files we stored on the two TDX VMs are wiped; the VMs themselves stay.** Cloud Shell's `/tmp` is lost whenever Cloud Shell is reset. This page says what survives, what to do **before** that happens, and how to get back to a working cluster **after** it. It describes the rebuild kit in `ops/rebuild/`.

**Status of the kit (read this first).** The specification was checked against the working cluster (`check-existing.sh` on each node; the output is kept in the evidence bundle `evidence-rebuild-kit-check`), and each script was tested in a sandbox with stand-ins (fake Hadoop, fake `gcloud`). **The install actions have not yet run on fresh VMs.** The first real rebuild is the real test; expect to fix small things then, and add them here.

**Checked on 17 October 2026.** No real rebuild on fresh VMs has been recorded since the kit was written on 13 October, so the statement above still holds. Since then the cluster has gained the work of Milestone 5, which the kit does not cover (section 4).

**Note (19 October 2026).** Under the fixed-fleet plan `ops/rebuild/` becomes the image build (steps F0.3 and F5 of [milestone-plan.md](milestone-plan.md) section 10); this runbook describes the current kit until then.

**Checked on 27 October 2026.** No real rebuild on fresh VMs with this kit is recorded in these documents, so the statement above still holds. Every evidence run since 19 October 2026 used the image pipeline of `ops/image/` (a builder, an image, a fleet made from it) and not this kit; `ops/rebuild/` becomes the image build at step F5, which is next ([milestone-plan.md](milestone-plan.md) section 11).

## 1. The idea

Think of a shared rented kitchen that is cleaned after every guest. You cannot leave anything in it. You keep your recipes in your own cupboard, your notes at home, and you carry a checklist so that you can set the kitchen up again quickly.

| Place | Survives a wipe? | What is kept there |
|---|---|---|
| GitHub (`Heron-AI-Security/nutch-private`, a private repository since 19 October 2026; branch `feat/tee-hadoop-cluster`) | yes | code, scripts, tools, documents, the rebuild kit |
| The user's laptop (`tdx-evidence`) | yes | evidence bundles, the VM-state bundle, the job files |
| Our files and progress on the VMs, Cloud Shell's `/tmp`, an assistant's sandbox | **no** | nothing that exists only there |

## 2. Before a wipe (end of every session)

1. In Cloud Shell, from a clone of the repository: `bash ops/rebuild/end-of-session.sh`. It collects the state of both VMs (configuration, firewall rules, WireGuard setup **without private keys**, package lists, the HDFS contents), bundles it, scans the bundle for secrets (every count must be 0) and prints its SHA-256.
2. Download `evidence-vm-state-<date>.tar.gz` to the laptop and compare its SHA-256 with the printed value.
3. Download any evidence bundle made during the session, and the job file if a new one was built (see section 6).
4. Keep a second copy of the whole evidence folder on another drive or in cloud storage.
5. Commit what was tested, in the usual gated way (code and documents in separate commits).

## 3. After a wipe (back to a working cluster)

You need a Cloud Shell with access to the project `training-custody` (`gcloud config set project training-custody`) and `sudo` on the VMs.

**The usual case: the VMs are still there.** The stages look before they act, so they only do what is missing:

```bash
gh auth login   # once: the repository is private
gh repo clone Heron-AI-Security/nutch-private nutch -- --branch feat/tee-hadoop-cluster && cd nutch
bash ops/rebuild/rebuild-cluster.sh ship base hadoop mesh build wrapper suite
```

If the VMs themselves are gone, run `bash ops/rebuild/rebuild-cluster.sh` with no stage names: it starts with `provision`.

What "looking first" means: `base` skips what is installed and **leaves Hadoop settings alone if they differ** from the specification (set `REBUILD_FORCE_CONF=1` to rewrite them); `hadoop` refuses to format a NameNode that still holds a file system, and `start` skips a daemon that already runs; `mesh` **skips itself when the mesh is already up** and stops with a message when it is only half there.

The stages, in order. Each one stops with a message at the first failure, and a stage that succeeded can be run again.

| Stage | What it does | Script |
|---|---|---|
| `provision` | creates `tdx-lab` and `tdx-lab-worker` if they do not exist: `c3-standard-4`, TDX, Ubuntu 22.04, a 50 GB boot disk, internal addresses `10.128.0.2` and `10.128.0.5` | `rebuild-cluster.sh` |
| `ship` | copies the repository's `ops/` folder to both VMs | `rebuild-cluster.sh` |
| `base` | packages, host names, Hadoop 3.4.3 (its SHA-512 checked against Apache's file), the four settings files, data folders | `node-base.sh` |
| `hadoop` | formats the NameNode (refuses if one exists), starts the daemons in the lab's order, waits for the cluster, creates `/user/<you>`, runs Hadoop's Pi example | `node-hadoop.sh` |
| `mesh` | the WireGuard mesh, Hadoop moved onto it, the host firewall (it undoes itself after 150 seconds unless confirmed), the names | the scripts in `ops/mesh` |
| `build` | builds `crawler-commons` and `language-detection-cld2` at the commits of the lab cluster, then the crawler job with `ant runtime` | `node-wrapper.sh` |
| `wrapper` | builds the wrapper's library jar from the job, installs it on both nodes, switches both to the wrapped configuration | `node-wrapper.sh` |
| `suite` | the smoke tests against the real HDFS and the contract tests, with a pass table at the end | `node-suite.sh` |

Expected time, not measured: about 40 minutes in all, most of it in `base` (a 491 MB download), `build` (a cold build is long) and `suite`. Cloud Shell can go to sleep when it sits idle, so stay with it, or run the stages one by one.

A result you can trust ends with `SUITE-OK` and a table. Run `bash ops/rebuild/rebuild-cluster.sh --dry-run <stages>` to see the commands without running them.

## 4. What the kit does not do yet

- **The measurement stage** (the 6.17 kernel, the one-time boot, measuring the stack into RTMR3, the quote). It was done by hand in Milestone 1 and is written down in `milestone-1-code-measurement.md` and in `attest/measure/` and `ops/worker-kernel-prep.sh`. A fresh VM boots a fresh measurement: the old quotes stay valid as evidence of the old image.
- **Which parts of the machines disappear** (only the home folder, or also installed packages, system settings and HDFS data) is not known. Because every stage looks first, the kit works in either case, and the first real rebuild will show which case this is.
- **Restoring the old HDFS contents.** The export is in the VM-state bundle (`hdfs/user-home`). Uploading it through the wrapper would give every file a new record; it is rarely needed.
- **The signing key, the key list, the reference file, the admission of keys and the mesh doorman** (steps 5.1.3 to 5.2.2 of `milestone-plan.md`, built and run on the cluster on 16 and 17 October 2026) are not part of the rebuild stages. They run in windows with the kits in `ops/kits/` (`m513-window`, `m521-window`, `m522-window`), and the signing keys are made at each boot and stored nowhere, so after a rebuild they have to be made again.
- Where the VMs get an internal address other than `10.128.0.2` and `10.128.0.5`, the existing mesh scripts need those addresses changed (they have them written in).

## 5. Checking the specification against a working cluster

On a node that works (read-only): `bash ops/rebuild/check-existing.sh master` (or `worker`). It compares the versions, the packages the kit installs, the host names and the four settings files with the kit's specification and prints `EXISTING-MATCHES-KIT` or each difference. A difference means the kit is wrong or incomplete.

## 6. Job files

The baseline job (the one whose SHA-384 starts `f993fd407ab5`, the value of the Milestone 1 quote) is kept as a full file; the other jobs are tiny `zstd` patches against it. The manifest in the job-patches evidence bundle (`MANIFEST.txt`) lists every fingerprint and the rebuild command:

```bash
zstd -d --long=28 --memory=2048MB --patch-from=job-bbd30ad9-baseline.job run9.patch.zst -o job-run9.job
```

then check that `sha256sum job-run9.job` equals the value in the manifest. A job built again from git has the same content but not the same bytes: only the baseline's exact bytes are tied to a quote.

## 7. When something goes wrong

| Message or symptom | Likely cause and what to do |
|---|---|
| `could not create tdx-lab (is 10.128.0.2 free, and is TDX available in the zone?)` | the old VM still holds the address, or the zone has no TDX capacity; delete the old VM or change `ZONE` |
| `passwordless sudo is needed` | the user on the VM has no passwordless `sudo`; the VMs made by `provision` have it |
| `less than 5 GB free` | the boot disk is too small; create the VM with `--boot-disk-size=50GB` |
| `the SHA-512 of the Hadoop download does not match` | a bad download; the file was removed, run the stage again |
| `CLUSTER-UP` never appears | check `~/hadoop/logs` on the node and that `hadoop-worker` resolves on both nodes (host names matter: the worker must register under that name) |
| `the mesh is half there` | `wg0` exists on one node only, or the nodes cannot reach each other; follow the message, then run the stage again |
| the mesh stage fails | the firewall undoes itself after 150 seconds; log in again and look at `sudo iptables -S` and `sudo wg show` |
| the build fails in `deps` | a snapshot library could not be fetched or built; read `~/.rebuild/mvn-<name>.log` on the master |
| `NameNode folder already holds a file system` | HDFS already exists on this VM; that is correct if you are re-running; remove `~/hadoop-data/namenode/current` only if you mean to erase HDFS |

## 8. Checking an image after a rebuild (steps P1, P2 and P6)

After a rebuild the image is checked in three ways, each by one command in Cloud Shell (they were run for the image `tc-img-rel-1`; [run-comparison.md](run-comparison.md) section 9.19):

1. **The dummy run.** `bash ops/reference-run.sh IMAGE RUNDIR` makes one TDX VM from the image exactly like a fleet node but without a fleet list, saves its quote, its RTMR3 log, its settings and its boot event log, and deletes the VM. `python3 ops/reference-compare.py RUNDIR REFERENCE.json` compares whole MRTD and RTMR0 to RTMR2 values and the stable RTMR3 events with the reference, and requires the debug bit to be off.
2. **The boot event table.** `python3 ops/ccel-table.py RUNDIR --markdown FILE --full` replays RTMR0 to RTMR2 against the quote and writes the tables of every RTMR1 and RTMR2 event ([boot-events.md](boot-events.md)).
3. **The release.** `python3 ops/make-release.py --commit COMMIT --image IMAGE --root-hash ROOTHASH --run RUNDIR --reference REFERENCE.json --out DIR --apply-labels` makes five checks, writes `release.json` and labels the image.

The dummy run creates one TDX VM, so it needs a free zone and CPU quota; the blocks that run it wait out a stockout. The builders of an image run are left stopped by the kit and hold disk quota until they are deleted.

## 9. The CI of the project (step P3.1)

If the CI identity must be made again, for example in a new project, edit `ops/ci/ci.env`, check your rights and the plan with `DRY=1 bash ops/ci/setup-gcp.sh`, and run `bash ops/ci/setup-gcp.sh`; it prints the three GitHub repository variables to set. A run of the check is started by pushing a tag that starts with `ci-smoke-` on the commit to check, after making sure that GitHub Actions are on; the run is named `ci-smoke`. Remove the two temporary roles of the account that ran the setup afterwards. The full steps, the settings and the reasoning are in [ci-publishing.md](ci-publishing.md).

To publish the reference of an image, push a tag `publish-ref-<commit>` on a commit that contains the workflow `ci-publish.yml`, after making sure that GitHub Actions are on; the workflow makes two dummy runs of the sealed image of that commit and creates a GitHub release with eleven files ([ci-publishing.md](ci-publishing.md) section 9). The same script runs by hand: `COMMIT=<commit> bash ops/ci/publish-ref.sh OUTDIR`.

## 10. Comparing two builds of one commit (step P4)

To show that an image is the product of a commit, build it twice from a `git archive` of the commit (two builders at the same time, as the kit of 4 November 2026 did), seal both (the sealing runs the cleanup of gate 6b, `ops/image/build/tc-image-normalize.sh`, unless `--no-normalize` is given), and compare them:

1. a quick test that the helper VM boots with the two disks: `bash ops/tree-diff.sh probe IMAGE_A IMAGE_B --work DIR` (about 3 minutes; it ends `TREE-PROBE-OK`);
2. publish the reference of image A (section 9: a tag `publish-ref-<commit>`, or by hand `COMMIT=<commit> bash ops/ci/publish-ref.sh OUTDIR`);
3. the whole verdict: `bash ops/verify-reference.sh <full commit id> --published OUTDIR/publish --published-image IMAGE_A --own-image IMAGE_B --work DIR`; it ends `VERIFY-REFERENCE-OK … trees=identical image-run=exact` (16 to 28 minutes);
4. if it fails, `DIR/trees/differences.tsv` lists every difference with its kind, path and detail; [tree-comparison.md](tree-comparison.md) section 5 explains the ones that we met, and section 6 what to do when the helper VM does not answer (its console is printed and saved).

A long run is started detached (`setsid nohup … &`) and read with `tail -f` (guide rule 118). The kit that ran (`cl2-kit`) is not in the repository yet (limitations row 230).
