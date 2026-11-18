# Benchmark settings of the one image

For the performance study, ONE sealed fleet image serves every benchmark setting: which custody layers are on, how many seeds are crawled, and how
many fetch tasks and threads run. The settings are chosen at VM creation, through instance metadata, and the image is the same for all of them.
It is a **benchmark image only**: the custody image is built WITHOUT this switch, and a benchmark run never makes an export.

Each statement below names the file that proves it (paths from the repository root).

## The configurations

The study has six cumulative configurations. Each adds one layer to the previous one; the first three run on plain benchmark clusters
(`bench/setup.sh` in Heron-AI-Security/training-custody), the last three on the fleet image of this branch, selected with the instance metadata
`tc-bench-layers`.

| Step | Configuration | What is on | How it runs |
|---|---|---|---|
| 1 | Plain crawler, plain VMs | Common Crawl's Nutch; no TDX, no receipts | benchmark cluster, `c3-standard-4` without TDX |
| 2 | **TDX-only baseline** | step 1 on Intel TDX confidential VMs; no fleet, no receipts, no sealed image | benchmark cluster, `c3-standard-4` with TDX |
| 3 | + receipts | step 2 + source receipts (receipt build, WARC files with receipts) | benchmark cluster |
| 4 | `fleet` | the sealed fleet: TDX VMs, the sealed and measured image (dm-verity), the encrypted and integrity-checked scratch disk, attestation and mutual attestation, the crawl **with source receipts**; **no** WireGuard (Hadoop on the VPC addresses, the host firewall open to the other fleet nodes only) and **no** signing wrapper | fleet, `tc-bench-layers=fleet` |
| 5 | `fleet-wireguard` | `fleet` + the WireGuard mesh | fleet, `tc-bench-layers=fleet-wireguard` |
| 6 | `fleet-wireguard-signing` | `fleet-wireguard` + the signing wrapper (sign on write, verify on read): **every layer** | fleet, metadata unset or `fleet-wireguard-signing` |

Step 6 is the configuration whose security guarantees the paper claims; every other configuration is a measurement point only.
The step-2 TDX-only baseline is a benchmark cluster, not a fleet setting: there is no fleet configuration without receipts.
Proof for steps 4 to 6: the comment block and the `WG`/`SIGN` line of `ops/image/rootfs/usr/local/lib/tc/tc-fleet.sh`.
Steps 1 to 3 are taken from the earlier text of this document and were not checked in this repository (they run on benchmark clusters set up from another repository).

## The isolated configurations

Besides the cumulative ladder, the study measures each switchable layer **on its own**, on the same fleet image. Each setting is the sealed fleet
(Intel TDX, dm-verity, attestation and mutual attestation) with at most one of the layers on. The last column is the scratch disk, which the
initramfs makes before the root is mounted:

| Setting (`tc-bench-layers`) | Receipts | WireGuard | Signing wrapper | Scratch disk |
|---|---|---|---|---|
| `all-off` | off | off | off | plain ext4 |
| `receipts-only` | on | off | off | plain ext4 |
| `wireguard-only` | off | on | off | plain ext4 |
| `signing-only` | off | off | on | plain ext4 |
| `encryption-only` | off | off | off | encrypted (dm-crypt and dm-integrity) |
| `fleet`, `fleet-wireguard`, `fleet-wireguard-signing`, unset | see the ladder | | | encrypted |

- Receipts are off for `all-off`, `wireguard-only`, `signing-only` and `encryption-only`: `tc-crawl.sh` drops `tc.receipts.enabled`, `tc.policy.file`
  and `tc.binding`, and the WARC files are still written by the same writer. Proof: the `case "$BL"` line in `ops/image/rootfs/usr/local/lib/tc/tc-crawl.sh`.
- `receipts-only` turns on the same layers as `fleet`, under its own name, so that the isolated runs are labelled as such.
- The scratch disk is **plain** (no dm-integrity, no dm-crypt) for `all-off`, `receipts-only`, `wireguard-only` and `signing-only`, and **encrypted** for every
  other value, for no value, and when the metadata server cannot be reached, so that a custody node without the switch is never plain. Proof:
  `ops/image/rootfs/etc/tc/initramfs-tools/scripts/local-top/tc-scratch-dev` (it reads `tc-bench-layers` itself, before the root is mounted, and leaves its choice in
  `/run/tc-scratch-mode`) and the `WANT=` line of `tc-fleet.sh`, which refuses a node whose disk does not match the setting.
- Because the disk of the first four settings is plain, the cost of the encrypted disk is the difference to `encryption-only`; for the cumulative steps 4 to 6 it is
  inside the sealed fleet's own start-up and is read from the per-process and kernel-thread CPU of the profiled runs.

## The size and the fetch concurrency

Two more metadata values choose the size of the run and the fetch concurrency, on the same image. Proof: `tc-fleet.sh` (reads and checks them),
`tc-crawl.sh` (applies them) and `ops/image/build/tc-image-crawl.sh` (bakes the lists).

| Metadata | Values | Effect |
|---|---|---|
| `tc-bench-size` | `1k`, `10k`, `100k`, `1m` | the crawl takes `/etc/tc/crawl/bench-seeds/SIZE.txt` instead of `seeds.txt`; `SIZE_FETCHLIST` is the number of seeds of the list and `MIN_FETCHED` is N / 10 |
| `tc-bench-fetch` | `TASKSxTHREADS`, for example `20x160` (1 to 100 tasks, 1 to 500 threads) | `NUM_FETCHERS` and `NUM_TASKS` become TASKS and `NUM_THREADS` becomes THREADS, instead of `params.env` |

- The baked lists have ceil(N / 0.7) seeds before the fleet filter, made offline by `seeds/benchmark/tools/extend_seeds.py`. Their size and SHA-256 are in
  `seeds/benchmark/seeds-x07.meta.json`: `1k.txt` 1,307 lines, `10k.txt` 12,959, `100k.txt` 129,712, `1m.txt` 1,302,293 (the fleet lists of that file; the
  SHA-256 of each baked file equals the one of its `-fleet` entry).
- Without `tc-bench-size` the crawl takes the default seed list `ops/image/rootfs/etc/tc/crawl/seeds.txt` (911,385 lines; the repository has no other `seeds.txt` of the crawl) and the values of `ops/image/rootfs/etc/tc/crawl/params.env`: one round, 10 fetchers,
  10 tasks, 50 threads, `SIZE_FETCHLIST=1000000`, `MIN_FETCHED=100000`, fetch time limit 180 s, 2048 MB per map and reduce task (`-Xmx1536m`).
- `ops/image/test/f1-drive.sh` sets only `tc-bench-layers` (from `BENCH_LAYERS`, or `BENCH_LAYERS_<vm name with - as _>` for one node). It does not set
  `tc-bench-size` or `tc-bench-fetch`; they are put into the instance metadata by hand.

## How the switch works

- `tc-fleet.sh` reads `tc-bench-layers` once, early in the boot, and keeps it in `/run/tc/bench-layers`. Any other value than the eight settings above stops the node.
- Unset or `fleet-wireguard-signing`, with no size, no fetch value and an encrypted disk: nothing changes. No event, the same rendered Hadoop configuration, the same
  network steps as without the switch.
- Every other value of `tc-bench-layers` is extended into RTMR3 as the event `bench-layers` **before** the node's announcement, so every quote names it, and mutual
  attestation (the same measured events on every node) refuses a fleet whose nodes differ.
- When any benchmark value is set, or the disk is plain, the whole run setting (layers, scratch disk, size, SHA-256 of the seed list, fetch) is written to
  `/run/tc/bench-run` and extended into RTMR3 as the event `bench-run`, so a quote names the exact setting.
- `ops/image/rootfs/usr/local/lib/tc/tc-export.sh` makes **no export** for every setting except `fleet-wireguard-signing`, and publishes `tc/export-skipped`.
  A run whose log holds a `bench-layers` event is a benchmark, never a custody run.
- The seed lists are part of the sealed image, so dm-verity covers them, and when `tc-bench-size` is set the SHA-256 of the list in use is in the `bench-run` event (`seeds_sha256`).

## Reading the results

- **The costs are order-dependent marginal costs.** Each step's cost is measured on top of the steps before it, in this order. Layers interact (with
  WireGuard on, the signing wrapper's HDFS traffic is also encrypted), so a layer's cost in another order, or alone, can differ. The steps add up to
  the total cost of step 6 against step 1 by construction; they are not standalone costs of each mechanism.
- Steps 1 to 3 and steps 4 to 6 run on different machinery (benchmark cluster vs sealed fleet), so step 4 also contains the sealed fleet's own start-up.
- The encrypted scratch disk, attestation and the sealed root are inside step 4 and are not separated; their share is read from the per-process and
  kernel-thread CPU of the profiled runs, and attestation's start-up cost from the fleet-formation timings.

## Known gaps versus main

This branch is the benchmark branch. It was cut from `main` on 9 November 2026 and does not contain the later work of `main`. The figures below were measured on 18 November 2026 against `origin/main` at commit `bd339c8d2`:

- It is **66 commits behind** `main` (62 without merge commits). `git log --merges --first-parent origin/bench/single-image..origin/main` lists three pull requests, which hold
  62 commits in all: pull request 8 (branch `feat/tee-hadoop-cluster`, 33 commits), pull request 9 (branch `feat/image-lock-and-trim`, 17 commits) and pull request 10
  (branch `feat/snapshot-service-vendored-debs`, 12 commits). A merge of `main` into this branch has **4 text conflicts**: `ops/image/build/tc-image-crawl.sh`,
  `ops/image/rootfs/etc/tc/initramfs-tools/scripts/init-bottom/tc-scratch-bind`, `ops/image/rootfs/usr/local/lib/tc/tc-crawl.sh` and `ops/image/rootfs/usr/local/lib/tc/tc-fleet.sh`.
  Landing those commits changes files that are baked into the measured image (among the conflicted files `tc-fleet.sh`, `tc-crawl.sh` and `tc-scratch-bind`).
- **Packages:** an image build from this branch downloads its packages online. `ops/image/build/tc-image-aptpin.sh` points apt at `snapshot.ubuntu.com` with the date in
  `ops/image/build/apt-snapshot.txt` (20261027T000000Z), and `ops/image/build/tc-image-prep.sh` fetches two kernel packages from `archive.ubuntu.com` (checked against a SHA-256
  in the script). There is no `ops/image/debs` here, so the build is not offline and not reproducible the way the build of `main` is.
- **Kits:** the milestone kits and the three older one-command kits are in `ops/kits/archive/<name>`; only `ops/kits/r4-final-kit` stays directly under `ops/kits`.
  This archive layout is not on `main`, where the kits still sit directly under `ops/kits`.
