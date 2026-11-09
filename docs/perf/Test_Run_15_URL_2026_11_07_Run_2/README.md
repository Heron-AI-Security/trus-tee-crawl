# 15-URL test run, second run (`Test_Run_15_URL_2026_11_07_Run_2`)

**State: complete.** All ten checks of `ops/verify-export.py` pass, every one of the 15 seeds has a signed outcome (0 seeds without an outcome), all 117 receipts are authenticated, and the kit ran from its first stage to its last with no manual step (105 minutes). This is the run on which the mentor's 15-URL test stands. It was written on 9 November 2026 from the analysis files of this folder; the older document [../15-url-crawl.md](../15-url-crawl.md) tells the story of both 15-URL runs and has been corrected from these files.

## 1. What was run

| Item | Value |
|---|---|
| Label and kit | `e15r2`; the kit is `ops/kits/e15r2-kit/` (committed as `24a1ba8f6`) |
| Repository state | `8c7a6e554`, nothing of `main` merged (part 1 of the mentor's two-part plan); the test commit `619eb3d94` is local, has the subject `TEST ONLY`, replaces only the two files of the crawl profile, and was never pushed |
| Fleet | 11 VMs (1 master and 10 workers), `c3-standard-4` (4 vCPUs, 16 GB), Intel TDX |
| When | 7 November 2026, 15:58 to 17:42 UTC (the whole kit); the crawl from 16:51:54 to 17:06:48 UTC |
| Profile | `ROUNDS=2`, `NUM_FETCHERS=10`, `NUM_TASKS=10`, `NUM_THREADS=2`, `TIME_LIMIT_FETCH=10`, `MIN_FETCHED=6`, `SIZE_FETCHLIST=150`, 15 seeds, agent `training-custody-test-bot` |
| Why | to run our own code end to end on 15 sites of different kinds, to time the crawl, and to test the fleet at 11 nodes (before: 2 nodes) |

## 2. Results

| Measure | Value |
|---|---|
| Outcomes (signed) | 149: ACCEPTED 117, NOT_FETCHED 19, HTTP_STATUS 10, NOT_HTTPS 2, TRUNCATED 1 |
| Scheduled per round | 15 in round 1, 134 in round 2 |
| Receipts | 117, all authenticated |
| Export | 257 files, 5.8 MB (WARC files 5.5 MB; 47 kB per receipt) |
| The ten checks | all pass |
| Crawl (first segment to the done marker) | 894 s = 14.9 min; the whole crawl driver 1,056 s = 17.6 min; the export 572 s = 9.5 min |
| Workers' CPU, mean | 16.2 % of 4 vCPUs |

### 2.1 The critical path of each round

**Critical path of each round** (the three parts add up to the round time; the middle part is the SIGNED window of that round's fetch tasks):

| Round | Generate and fetch start-up (segment to first task start) | Fetch tasks (first start to last end, signed) | Later jobs (last task end to next segment or done) | Round |
|---|---|---|---|---|
| 1 | 42 s = 0.7 min (15 %) | 6 s = 0.1 min (2 %) | 224 s = 3.7 min (82 %) | 272 s = 4.5 min |
| 2 | 47 s = 0.8 min (8 %) | 248 s = 4.1 min (40 %) | 327 s = 5.5 min (53 %) | 622 s = 10.4 min |

## 3. Why it succeeded

- **The chain holds at 11 nodes.** The steps from the image to the ten checks had only run on 2 nodes and 3 fetch tasks; here there were 20 fetch tasks in two rounds, 11 quotes and 257 files in the export, and nothing in the chain had to change.
- **The mistake of the first run is gone.** The fetch list size is 150, so each of the 10 tasks may take 15 URLs: all 15 seeds were scheduled in round 1 and 134 more URLs in round 2. The first run had 15, which is 1 URL per task ([../15-url-crawl.md](../15-url-crawl.md) section 6).
- **The kit no longer races the export.** It waits for the export's `DONE` object (it waited 20 s) and collects the master's log every 45 seconds, so the crawl could be timed from its start.

## 4. What the analysis shows

- **The second round is longer because of one slow task, not because of the number of URLs.** Round 2 took 622 s against 272 s for round 1. Its fetch tasks took 248 s against 6 s, and its later jobs 327 s against 224 s. The longest task, `m_000005_0`, took 245 s for 15 URLs (its last page arrived 243 s after its start) while the median task took 4 s, and 12 of the 20 tasks took 3 to 5 s. A fetch job lasts as long as its slowest task. The first 15-URL run had only 10 URLs in round 2 and its later jobs took 337 s, against 327 s here: the later jobs do not depend on the number of URLs.
- **The fleet was idle for part of the crawl.** 3 of the 15 minutes of the crawl window had a worker CPU mean below 5 %, while the slow task finished; those 3 minutes cost 0.11 USD, 20 % of the crawl window's 0.55 USD.
- **The export is slow and runs on the master alone.** The manifest phase took 532 s for 257 files (2.07 s per file) while the master's CPU was at 51 % and the workers' at 1 %; the upload took 40 s for 260 objects. The export is as long as the crawl.
- **Network.** 31.6 GB were received over the crawl window for 5.5 MB of web content in the WARC files, and in every busy minute each worker received about 260 to 320 MB, in both rounds. The web content is a tiny part: most of the traffic is the fleet's own (Hadoop jobs). It is not decomposed (limitations row 246).

### 4.1 Each fetch task

```
task             start       end signed s   URLs  pages   N/A | 1st fetch last fetch  dead tail
                 (UTC)     (UTC)                              | after start after start end - last
m_000006_0    16:52:36  16:52:40        4      1      1     0 |      +3 s      +3 s        1 s
m_000007_0    16:52:38  16:52:41        3      1      0     0 |         -         -          -
m_000008_0    16:52:38  16:52:41        3      0      0     0 |         -         -          -
m_000009_0    16:52:38  16:52:41        3      0      0     0 |         -         -          -
m_000000_0    16:52:37  16:52:42        5      3      2     0 |      +3 s      +3 s        2 s
m_000001_0    16:52:38  16:52:42        4      3      3     0 |      +2 s      +2 s        2 s
m_000002_0    16:52:38  16:52:42        4      2      1     0 |      +2 s      +2 s        2 s
m_000003_0    16:52:38  16:52:42        4      2      1     0 |      +2 s      +2 s        2 s
m_000004_0    16:52:38  16:52:42        4      2      1     0 |      +2 s      +2 s        2 s
m_000005_0    16:52:38  16:52:42        4      1      1     0 |      +2 s      +2 s        2 s
m_000009_0    16:57:15  16:57:18        3      2      1     0 |      +2 s      +2 s        1 s
m_000008_0    16:57:16  16:57:20        4      3      3     0 |      +2 s      +2 s        2 s
m_000007_0    16:57:15  16:57:21        6      5      3     0 |      +2 s      +3 s        3 s
m_000004_0    16:57:16  16:57:31       15     14     12     0 |      +2 s     +14 s        1 s
m_000003_0    16:57:15  16:57:55       40     12     10     0 |      +3 s     +38 s        2 s
m_000006_0    16:57:15  16:58:04       49     13      7     0 |      +2 s     +48 s        1 s
m_000002_0    16:57:13  16:58:15       62     18     15     0 |      +3 s     +60 s        2 s
m_000000_0    16:57:15  16:58:16       61     26     20     0 |      +3 s     +60 s        1 s
m_000001_0    16:57:15  16:58:23       68     26     24     0 |      +2 s     +65 s        3 s
m_000005_0    16:57:16  17:01:21      245     15     12     0 |      +2 s    +243 s        2 s

tasks: 20 | signed task time: smallest 3 s, median 4 s, largest 245 s | tasks of 290 s or more: 0
dead tail (end of the task minus its last fetched page): smallest 1 s, median 2 s, largest 3 s; tasks with a tail of 200 s or more: 0
fleet signed window: 16:52:36 .. 17:01:21 (525 s)
NOT_ATTEMPTED: 0 URLs
```

### 4.2 Cost (list price, the fleet only)

| Phase | Seconds | VM-hours | USD | Share |
|---|---|---|---|---|
| Driver start to first segment (cluster wait, inject, generate) | 162 | 0.495 | 0.100 | 10.0 % |
| Round 1: generate and fetch start-up | 42 | 0.128 | 0.026 | 2.6 % |
| Round 1: fetch tasks (signed window) | 6 | 0.018 | 0.004 | 0.4 % |
| Round 1: later jobs | 224 | 0.684 | 0.138 | 13.8 % |
| Round 2: generate and fetch start-up | 47 | 0.144 | 0.029 | 2.9 % |
| Round 2: fetch tasks (signed window) | 248 | 0.758 | 0.153 | 15.2 % |
| Round 2: later jobs | 327 | 0.999 | 0.201 | 20.1 % |
| Export (crawl done to export done) | 572 | 1.748 | 0.352 | 35.1 % |
| **Total (driver start to export done)** | **1628** | **4.974** | **1.00** | |

- **Cost per 1,000 pages fetched** (crawl window, first segment to done): 4.71 USD (117 pages in 0.55 USD); per 1,000 receipts: 4.71 USD.
- Including the cluster wait and inject (driver start to done): 5.56 USD per 1,000 pages.
- **Idle time:** 3 of the 15 minutes of the crawl window had a worker CPU mean below 5 %; those 3 minutes cost 0.11 USD (20 % of the crawl window's 0.55 USD).
- The fleet stage of the kit (boot to the end of the fetch of the export) took 32 min: 11 VMs x 32 min = 5.87 VM-hours = 1.18 USD.

### 4.3 The export and what it scales with

- **Manifest phase** (crawl done to the export manifest): 532 s for 257 files = **2.07 s per file**; the export holds 5.8 MB, so 91.9 s per MB.
- **Upload** (manifest to export done): 40 s for 260 objects = 0.15 s per object.
- During the export the master's CPU mean was 51.5 % of 4 vCPUs and the workers' 1.2 %: the export runs on the master alone.
- **Model, from this run:** export time is about 2.2 s x the number of files, whatever their size. At this rate 1,000 files take about 37 min. Check the model against another run before relying on it.

### 4.4 Network and CPU per phase

```
per phase (whole fleet = master + all workers; MB = megabytes; vCPU-s = utilization x 4 vCPUs x 60 s; worker CPU = mean over workers and minutes):
phase                                                           length  min.      MB in     MB out   share    vCPU-s  w cpu %
before the crawl driver (4 min)                                  240 s     4        0.2        0.1               918      8.7
driver start to HDFS ready                                        85 s     1        0.3        0.3   0.0 %       174      4.4
HDFS ready to seeds in HDFS                                        9 s     0        0.0        0.0   0.0 %         0      0.0
seeds in HDFS to first segment (inject, generate)                 68 s     1     1221.3     1210.6   3.7 %       236      6.8
round 1 fetch job (segment to end of signed window)               48 s     1     3108.3     2960.5   9.5 %       522     20.5
round 1 later jobs (to next segment)                             224 s     4    11288.9    11403.9  34.4 %      2292     22.5
round 2 fetch job (segment to end of signed window)              295 s     5     4289.0     4350.6  13.1 %       999      7.7
round 2 later jobs (to crawl done)                               327 s     5    12907.1    13044.3  39.3 %      2418     18.9
crawl done to export manifest                                    532 s     9     1747.9     1580.3              1418      1.3
export manifest to export done (upload)                           40 s     1        1.3        2.3               107      0.3
total over the phases shown                                                     34564.3    34552.8
share = MB received in the phase / MB received from the driver start to crawl done (the phases before the driver and after the crawl are not counted in it).
```

## 5. Problems met, and what was done

| Problem | What was done | Where |
|---|---|---|
| The first 15-URL run scheduled only 8 and 10 URLs (a cap per task) | the profile of this run has `SIZE_FETCHLIST=150` | limitations row 237, mistake 243 |
| The driver fetched before the export's `DONE` object existed (first run) | the kit waits for `DONE` | row 238, mistake 244 |
| One slow task sets the length of a fetch job (this run: 245 s against a median of 4 s), and the fleet idles meanwhile | nothing was changed: it is how a fetch job behaves; the analysis now reports it | limitations row 244 |
| My earlier text called the fleet-level signed window "the fetching" and said that 134 URLs add four minutes | corrected in [../15-url-crawl.md](../15-url-crawl.md) | mistakes 250 and 251 |

## 6. Files

| File | What it is |
|---|---|
| `README.md` | this document |
| `Test_Run_15_URL_2026_11_07_Run_2_analysis.md` | the analysis report of the run (`ops/perf/run_analysis.py`) |
| `Test_Run_15_URL_2026_11_07_Run_2_summary.json` | the same numbers as data, with keys in lower_snake_case |
| `Test_Run_15_URL_2026_11_07_Run_2_network_phases.txt` | network and CPU of the master and the workers per minute and per phase (`ops/perf/run_network_phases.py`) |
| `Test_Run_15_URL_2026_11_07_Run_2_task_times.txt` | the signed start and end of each fetch task and its dead tail (`ops/perf/run_task_times.py`) |
| `time-check.txt` | the check of the signed time readings (`ops/attested/verify_time_export.py`) |

## 7. How to make the analysis again

```
python3 run_analysis.py ~/evidence-e15r2-f --run-name Test_Run_15_URL_2026_11_07_Run_2 --title "..."
python3 run_network_phases.py ~/evidence-e15r2-f > ~/evidence-e15r2-f/Test_Run_15_URL_2026_11_07_Run_2_network_phases.txt
python3 run_task_times.py ~/evidence-e15r2-f --tools ops/attested > ~/evidence-e15r2-f/Test_Run_15_URL_2026_11_07_Run_2_task_times.txt
```
The scripts are in [`ops/perf/`](../../../ops/perf/README.md); they read the evidence folder of the run and Google Cloud Monitoring (best effort) and change nothing.

## 8. What this run does not show

It is **one** run: the timings do not repeat exactly and the live sites change. There is no plain crawl on the same fleet, so nothing here says what TDX or the custody layer costs per page, and the fleet size was not varied, so nothing says how the crawl scales with the number of workers. The cost is the list price of the VMs for the crawl window only (no TDX surcharge, disks, egress, builders or verification).
