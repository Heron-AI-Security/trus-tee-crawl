# Benchmark layers (branch `bench/layer-flag`)

For the performance study, the fleet image of this branch can leave out custody layers, so that the cost of each layer can be measured. It is a
**benchmark image only**: the custody image is built from `1m-run` (and `main`) without this switch, and an export is never made by a benchmark run.

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

## How the switch works

- `tc-fleet.sh` reads `tc-bench-layers` once, early in the boot, and keeps it in `/run/tc/bench-layers`. Any other value stops the node.
- Unset or `fleet-wireguard-signing`: nothing changes. No event, the same rendered Hadoop configuration, the same network steps as without the switch.
- `fleet` or `fleet-wireguard`: the setting is extended into RTMR3 as the event `bench-layers` **before** the node's announcement, so every quote and
  every export names it, and mutual attestation refuses a fleet whose nodes differ. `tc-export.sh` makes no export and publishes `tc/export-skipped`.
- `ops/image/test/f1-drive.sh` sets it at VM creation from `BENCH_LAYERS` (and `BENCH_LAYERS_<vm>` for one node).
- Tested by `ops/image/test/bench-flag-rehearse.sh` (with the unchanged `tc-fleet.sh` of `main` as the reference) and the existing `f1-rehearse.sh`.

## Reading the results

- **The costs are order-dependent marginal costs.** Each step's cost is measured on top of the steps before it, in this order. Layers interact (with
  WireGuard on, the signing wrapper's HDFS traffic is also encrypted), so a layer's cost in another order, or alone, can differ. The steps add up to
  the total cost of step 6 against step 1 by construction; they are not standalone costs of each mechanism.
- Steps 1 to 3 and steps 4 to 6 run on different machinery (benchmark cluster vs sealed fleet), so step 4 also contains the sealed fleet's own start-up.
- The encrypted scratch disk, attestation and the sealed root are inside step 4 and are not separated; their share is read from the per-process and
  kernel-thread CPU of the profiled runs, and attestation's start-up cost from the fleet-formation timings.
