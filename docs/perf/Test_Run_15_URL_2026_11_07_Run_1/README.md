# 15-URL test run, first run (`Test_Run_15_URL_2026_11_07_Run_1`)

**State: finished and verified, but incomplete as a test of 15 sites and partial as a record.** All ten checks of `ops/verify-export.py` pass and all 14 receipts are authenticated, so the chain from the image to the ten checks works on 11 TDX machines. It is incomplete for three reasons, in this order of importance: (1) **four of the 15 seeds were never scheduled** (seeds 2, 3, 6 and 10 of the list), because of a mistake in my profile, so it did not test 15 sites; (2) **the kit did not run to its end**: the driver fetched before the export's `DONE` object existed, the fleet stage stopped, and the run was finished by hand (the stage table of the kit, [../15-url-crawl.md](../15-url-crawl.md) section 4.1, shows the fleet stage as stopped and finished by hand, the verifier stage as stopped, and the stage `clean` as not run, with the VMs deleted by hand); (3) **its analysis is partial**: the master's log was not collected while the run went on, so the crawl start and the cluster markers are lost (section 5). The second run ([../Test_Run_15_URL_2026_11_07_Run_2/README.md](../Test_Run_15_URL_2026_11_07_Run_2/README.md)) corrected (1) and (2) and is the complete one. Written on 9 November 2026 from the files of this folder.

## 1. What was run

| Item | Value |
|---|---|
| Label | `e15a`; the evidence archive `evidence-e15a-partial.tar.gz` was made by hand because the kit stopped |
| Repository state | `8c7a6e554`, nothing of `main` merged; the test commit `95553d8d7` is local, has the subject `TEST ONLY` and was never pushed |
| Fleet | 11 VMs (1 master and 10 workers), `c3-standard-4`, Intel TDX |
| When | 7 November 2026, from 13:07 UTC; the crawl from 14:02:37 to 14:13:37 UTC; the export was done at 14:23:31 UTC |
| Profile | `ROUNDS=2`, `NUM_FETCHERS=10`, `NUM_TASKS=10`, `NUM_THREADS=2`, `TIME_LIMIT_FETCH=10`, `MIN_FETCHED=6`, **`SIZE_FETCHLIST=15`** (the mistake), 15 seeds |

## 2. Results

| Measure | Value |
|---|---|
| Scheduled per round | 8 in round 1 and 10 in round 2 (18 in all, not 15 + the links) |
| Outcomes (signed) | 18: ACCEPTED 14, NOT_FETCHED 2, HTTP_STATUS 1, NOT_HTTPS 1; **4 seeds have no outcome** |
| Receipts | 14, all authenticated |
| The ten checks | all pass |
| Export | 257 files, 1.1 MB |
| Crawl (first segment to the done marker) | 660 s = 11.0 min; the export 594 s = 9.9 min |
| Workers' CPU, mean | 20.8 % of 4 vCPUs |

### 2.1 The critical path of each round

**Critical path of each round** (the three parts add up to the round time; the middle part is the SIGNED window of that round's fetch tasks):

| Round | Generate and fetch start-up (segment to first task start) | Fetch tasks (first start to last end, signed) | Later jobs (last task end to next segment or done) | Round |
|---|---|---|---|---|
| 1 | 43 s = 0.7 min (16 %) | 6 s = 0.1 min (2 %) | 222 s = 3.7 min (82 %) | 271 s = 4.5 min |
| 2 | 46 s = 0.8 min (12 %) | 6 s = 0.1 min (2 %) | 337 s = 5.6 min (87 %) | 389 s = 6.5 min |

The fetch tasks took 6 s in each round: with 8 and 10 URLs there was nothing to wait for. The rest of each round is the Hadoop jobs around the fetching (start-up of 43 and 46 s, later jobs of 222 and 337 s).

## 3. Why it is not a complete test

- **Four seeds never entered the crawl.** Nutch divides the fetch list size by the number of fetch tasks (`limit = topN / numReduceTasks` in `Generator.java`): 15 divided by 10 tasks is 1 URL per task, so only 8 of the seeds were taken in round 1. The profile still had 15 when the tasks went from 1 to 10 (limitations row 237, mistake 243). The second run has 150.
- **The kit did not finish.** The master publishes the quote of the export first and uploads the 260 objects afterwards (41 s); the driver fetched at once and found no `DONE` object (limitations row 238, mistake 244). The kit now waits for `DONE`.

## 4. Why the verification passes anyway

The verifier checks what was crawled, not what should have been crawled: every URL of the fetch lists has exactly one signed outcome, every receipt is in the signed receipts files, and the quotes, the debug bit, the time and the reference all hold. A crawl of fewer seeds than intended is a profile mistake, not a custody failure, and the ten checks rightly say nothing about it.

## 5. Why the analysis is partial

The kit of this run did not collect the master's log lines while the run went on (the collection every 45 seconds was added in the kit of the second run), and a VM keeps only the last 1 MiB of its console, so the lines of the crawl start, the cluster and the seeds were lost (limitations rows 240 and 249). `master-log-lines.txt` in this folder is **derived**: it was made with `grep` from the console files that the evidence holds (`final-tc-f1-m.txt`, `export-tc-f1-m.txt`, `f1-check-tc-f1-m.txt`, `blockD-console.txt`, `serial-tc-f1-m.txt`), it says so in its first line, and the original files are unchanged. Only three markers survive: the crawl done, the export manifest and the export done. What follows from that:

| Part of the analysis | State |
|---|---|
| Verification, outcomes, receipts, rounds, the critical path, the task times | complete (they come from the signed evidence and the segment names) |
| Crawl window, the export, cost and host-side resources | complete, resting on the derived markers |
| Cluster wait, the time of the whole crawl driver, the cost row "driver start to first segment" | **not available** |
| Network and CPU per phase | **not available**: `NETPHASES-FAILED: missing in the evidence: ['start', 'hdfs', 'seeds']` (the file `Test_Run_15_URL_2026_11_07_Run_1_network_phases.txt` holds exactly that line) |

## 6. Cost and export

| Phase | Seconds | VM-hours | USD | Share |
|---|---|---|---|---|
| Round 1: generate and fetch start-up | 43 | 0.131 | 0.026 | 3.4 % |
| Round 1: fetch tasks (signed window) | 6 | 0.018 | 0.004 | 0.5 % |
| Round 1: later jobs | 222 | 0.678 | 0.137 | 17.7 % |
| Round 2: generate and fetch start-up | 46 | 0.141 | 0.028 | 3.7 % |
| Round 2: fetch tasks (signed window) | 6 | 0.018 | 0.004 | 0.5 % |
| Round 2: later jobs | 337 | 1.030 | 0.208 | 26.9 % |
| Export (crawl done to export done) | 594 | 1.815 | 0.366 | 47.4 % |
| **Total (driver start to export done)** | **1254** | **3.832** | **0.77** | |

- **Cost per 1,000 pages fetched** (crawl window, first segment to done): 29.04 USD (14 pages in 0.41 USD); per 1,000 receipts: 29.04 USD.
- **Idle time:** 0 of the 11 minutes of the crawl window had a worker CPU mean below 5 %; those 0 minutes cost 0.00 USD (0 % of the crawl window's 0.41 USD).

A cost per 1,000 pages is not meaningful for 14 pages (29 USD here: the fixed cost of the fleet divided by a very small number).

- **Manifest phase** (crawl done to the export manifest): 553 s for 257 files = **2.15 s per file**; the export holds 1.1 MB, so 505.0 s per MB.
- **Upload** (manifest to export done): 41 s for 260 objects = 0.16 s per object.
- During the export the master's CPU mean was 52.7 % of 4 vCPUs and the workers' 1.0 %: the export runs on the master alone.
- **Model, from this run:** export time is about 2.3 s x the number of files, whatever their size. At this rate 1,000 files take about 38 min. Check the model against another run before relying on it.

## 7. Problems met, and what was done

| Problem | What was done | Where |
|---|---|---|
| The fetch list size did not fit 10 tasks | `SIZE_FETCHLIST=150` in the second run | limitations row 237, mistake 243 |
| The driver fetched before `DONE` existed | the kit waits for `DONE` | row 238, mistake 244 |
| Case 24 of the entry rehearsal failed on a good verifier (it removed a redirect without a receipt) | it removes the first outcome that carries a receipt (`a33184ed0`) | mistake 245 |
| The console keeps only its last 1 MiB | the kit of the second run collects the master's lines every 45 seconds | limitations row 240 |
| The master log of this run was missing when the analysis tools were made | a derived, labelled file; the network view of this run stays unavailable | limitations row 249 |

## 8. Files

| File | What it is |
|---|---|
| `README.md` | this document |
| `Test_Run_15_URL_2026_11_07_Run_1_analysis.md` | the analysis report of the run (`ops/perf/run_analysis.py`) |
| `Test_Run_15_URL_2026_11_07_Run_1_summary.json` | the same numbers as data, with keys in lower_snake_case |
| `Test_Run_15_URL_2026_11_07_Run_1_network_phases.txt` | network and CPU of the master and the workers per minute and per phase (`ops/perf/run_network_phases.py`) |
| `Test_Run_15_URL_2026_11_07_Run_1_task_times.txt` | the signed start and end of each fetch task and its dead tail (`ops/perf/run_task_times.py`) |
| `time-check.txt` | the check of the signed time readings (`ops/attested/verify_time_export.py`) |
| `master-log-lines.txt` | **derived** and partial: the three markers that survive in the console files (see section 5); the line ends are normalized to LF here, the copy in the evidence has the console's CRLF |

## 9. How to make the analysis again

```
python3 run_analysis.py ~/evidence-e15a-f --run-name Test_Run_15_URL_2026_11_07_Run_1 --title "..."
python3 run_network_phases.py ~/evidence-e15a-f > ~/evidence-e15a-f/Test_Run_15_URL_2026_11_07_Run_1_network_phases.txt
python3 run_task_times.py ~/evidence-e15a-f --tools ops/attested > ~/evidence-e15a-f/Test_Run_15_URL_2026_11_07_Run_1_task_times.txt
```
The scripts are in [`ops/perf/`](../../../ops/perf/README.md); they read the evidence folder of the run and Google Cloud Monitoring (best effort) and change nothing.

For this run, first make `master-log-lines.txt` as described in section 5 (it is in this folder).
