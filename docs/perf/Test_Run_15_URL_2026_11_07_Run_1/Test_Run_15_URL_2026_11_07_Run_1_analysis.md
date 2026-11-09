# 15-URL test run, first run: analysis of the run `Test_Run_15_URL_2026_11_07_Run_1` (commit `95553d8d7a36`)

Generated 2026-11-09 18:20 UTC by `run_analysis.py`, read-only, from `/home/rishabsdp17/evidence-e15a-f`. Every number says where it comes from (last section). This is **one run**: no median, no range, and the live web changes from day to day.

## 1. What was run

| Item | Value |
|---|---|
| Commit under test | `95553d8d7a362e7a63c4c22f4f7d5706b2ae5eed` |
| Fleet | 11 VMs (1 master + 10 worker(s)), each `c3-standard-4` = 4 vCPUs and 16 GB RAM, Intel TDX |
| Seeds | 15 URLs in `profile-seeds.txt` |
| Crawl profile | rounds 2, fetch tasks 10, tasks 10, threads per task 2, fetch time limit 10 min, fetch list size 15 (cap per task = size / tasks = 1 URLs) |
| When (UTC) | crawl 2026-11-07T14:02:37 to 14:13:37; export done 14:23:31 |

## 2. Why and how it was measured

- **Why:** to find out, on our own branch as pushed, what a crawl of 15 seeds in 2 round(s) does on 11 TDX VM(s): how many pages are fetched and authenticated, where the time and the resources go, and whether the whole verifier accepts the export.
- **Clocks (they differ on purpose):** the *segment name* is the time of a round's generate step; the *master's log lines* mark the start and end of the crawl script and of the export; the *signed window and each task's signed start and end* come from a Roughtime server, not from the crawler's clock; *Cloud Monitoring* gives CPU and network of each VM **from the host side**, in 60 s steps; the *fetch dates* (WARC-Date) are the crawler's own unsigned clock.
- **Not measured:** per-job times of the Hadoop jobs (the sealed image has no YARN access), memory, disk I/O, the cost of builds and verification, and any plain crawl without custody on this fleet.

## 3. What the crawl produced

### 3.1 Rounds

| Round | Starts (UTC) | Takes | Scheduled | Outcomes | Receipts | Statuses |
|---|---|---|---|---|---|---|
| 1 | 14:02:37 | 271 s = 4.5 min | 8 | 8 | 6 | ACCEPTED 6, HTTP_STATUS 1, NOT_FETCHED 1 |
| 2 | 14:07:08 | 389 s = 6.5 min | 10 | 10 | 8 | ACCEPTED 8, NOT_FETCHED 1, NOT_HTTPS 1 |

A round takes the time from its segment (its generate step) to the next segment, and the last one to the `crawl done` marker, so it includes the jobs that follow the fetching.

### 3.2 Outcomes

| Class of outcome | Count | Share of 18 outcomes |
|---|---|---|
| ACCEPTED: fetched, with a receipt | 14 | 77.8 % |
| HTTP_STATUS 301 (a redirect or an error status, no page stored) | 1 | 5.6 % |
| NOT_FETCHED: fetch_gone robots_denied(n), | 1 | 5.6 % |
| NOT_HTTPS: not https | 1 | 5.6 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.nyt | 1 | 5.6 % |

| Headline | Value |
|---|---|
| Scheduled per round / outcomes in all rounds / seeds without an outcome | 8, 10 / 18 / **4** |
| Pages fetched, as counted by the crawl database | 14 |
| Receipts (ACCEPTED with a receipt) | 14 (77.8 % of the 18 outcomes) |
| Receipts authenticated by the signed-time check | 14 of 14; **0 not authenticated** |
| Outcomes by status | ACCEPTED 14, NOT_FETCHED 2, HTTP_STATUS 1, NOT_HTTPS 1 |
| Fetch tasks that wrote outcomes (all rounds); outcomes per task (smallest, median, largest) | 12; 1, 1, 3 |
| Size of the export | 1.1 MB in 258 files (WARC files 1.0 MB) |
| WARC bytes per receipt | 70 kB |

### 3.3 Each seed

| # | Seed | Round-1 outcome | Task |
|---|---|---|---|
| 1 | `https://text.npr.org/` | NOT_FETCHED: fetch_gone robots_denied(n), | m_000001_0 |
| 2 | `https://ja.wikipedia.org/wiki/Main_Page` | **no outcome** | - |
| 3 | `https://www.schneier.com/` | **no outcome** | - |
| 4 | `https://github.com/apache/nutch` | ACCEPTED: fetched, with a receipt | m_000000_0 |
| 5 | `https://news.ycombinator.com/` | ACCEPTED: fetched, with a receipt | m_000001_0 |
| 6 | `https://www.reddit.com/r/programming/` | **no outcome** | - |
| 7 | `https://www.gutenberg.org/cache/epub/1342/pg1342.txt` | ACCEPTED: fetched, with a receipt | m_000002_0 |
| 8 | `https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pd` | ACCEPTED: fetched, with a receipt | m_000001_0 |
| 9 | `https://www.nasa.gov/feed/` | ACCEPTED: fetched, with a receipt | m_000003_0 |
| 10 | `https://archive.org/details/prelinger` | **no outcome** | - |
| 11 | `https://ocw.mit.edu/` | ACCEPTED: fetched, with a receipt | m_000005_0 |
| 12 | `https://www.who.int/news` | ACCEPTED: fetched, with a receipt | m_000004_0 |
| 13 | `https://webscraper.io/test-sites/e-commerce/static` | ACCEPTED: fetched, with a receipt | m_000004_0 |
| 14 | `https://www.nytimes.com/` | NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.nyt | m_000002_0 |
| 15 | `https://timesofindia.indiatimes.com/` | HTTP_STATUS 301 (a redirect or an error status, no page stored) | m_000000_0 |

## 4. Time

| Measure | Value |
|---|---|
| First segment to the done marker | 660 s = 11.0 min |
| **Signed fetch window** (first task start to last task end, all rounds, time server's clock) | 280 s = 4.7 min, from 40 readings of 20 tasks |
| Export (crawl done to export done) | 594 s = 9.9 min |
| Pages fetched per second of signed window | 0.050 pages/s for the whole fleet (the window may contain idle time: see section 5) |

**4.1 Critical path of each round** (the three parts add up to the round time; the middle part is the SIGNED window of that round's fetch tasks):

| Round | Generate and fetch start-up (segment to first task start) | Fetch tasks (first start to last end, signed) | Later jobs (last task end to next segment or done) | Round |
|---|---|---|---|---|
| 1 | 43 s = 0.7 min (16 %) | 6 s = 0.1 min (2 %) | 222 s = 3.7 min (82 %) | 271 s = 4.5 min |
| 2 | 46 s = 0.8 min (12 %) | 6 s = 0.1 min (2 %) | 337 s = 5.6 min (87 %) | 389 s = 6.5 min |

Stages of the kit (minutes): prepare 6, build 16, compare 0, seal-prep 1, seal-disk 7, seal-image 5, seal-disk-b 7, seal-image-b 4, verify 0, p4 23. Sum of the stages: 69 min.

## 5. Each fetch task: signed time and dead tail

```
task             start       end signed s   URLs  pages   N/A | 1st fetch last fetch  dead tail
                 (UTC)     (UTC)                              | after start after start end - last
m_000003_0    14:03:20  14:03:24        4      1      1     0 |      +3 s      +3 s        1 s
m_000004_0    14:03:22  14:03:25        3      1      1     0 |      +2 s      +2 s        1 s
m_000005_0    14:03:22  14:03:25        3      1      1     0 |      +2 s      +2 s        1 s
m_000006_0    14:03:22  14:03:25        3      0      0     0 |         -         -          -
m_000007_0    14:03:22  14:03:25        3      0      0     0 |         -         -          -
m_000008_0    14:03:22  14:03:25        3      0      0     0 |         -         -          -
m_000009_0    14:03:22  14:03:25        3      0      0     0 |         -         -          -
m_000000_0    14:03:22  14:03:26        4      2      1     0 |      +3 s      +3 s        1 s
m_000001_0    14:03:22  14:03:26        4      2      1     0 |      +2 s      +2 s        2 s
m_000002_0    14:03:22  14:03:26        4      1      1     0 |      +2 s      +2 s        2 s
m_000000_0    14:07:54  14:07:58        4      3      3     0 |      +2 s      +3 s        1 s
m_000001_0    14:07:55  14:07:59        4      2      2     0 |      +3 s      +3 s        1 s
m_000002_0    14:07:55  14:07:59        4      2      0     0 |         -         -          -
m_000004_0    14:07:56  14:07:59        3      1      1     0 |      +2 s      +2 s        1 s
m_000005_0    14:07:55  14:07:59        4      1      1     0 |      +3 s      +3 s        1 s
m_000006_0    14:07:56  14:07:59        3      0      0     0 |         -         -          -
m_000007_0    14:07:55  14:07:59        4      0      0     0 |         -         -          -
m_000008_0    14:07:55  14:07:59        4      0      0     0 |         -         -          -
m_000009_0    14:07:55  14:07:59        4      0      0     0 |         -         -          -
m_000003_0    14:07:56  14:08:00        4      1      1     0 |      +2 s      +2 s        2 s

tasks: 20 | signed task time: smallest 3 s, median 4 s, largest 4 s | tasks of 290 s or more: 0
dead tail (end of the task minus its last fetched page): smallest 1 s, median 1 s, largest 2 s; tasks with a tail of 200 s or more: 0
fleet signed window: 14:03:20 .. 14:08:00 (280 s)
NOT_ATTEMPTED: 0 URLs
note: the start and end are SIGNED (time server); the fetch dates are the crawler's own clock (second resolution), good enough for a distribution but not evidence.
```

Straggler view: the largest task took 4 s and the median task 4 s (ratio 1.0). A fetch job lasts as long as its slowest task, so the signed window of a round is set by one task, not by the number of pages.

## 6. Fleet resources (host side, Cloud Monitoring)

**Window: crawl (first segment to done)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 15.0 | 20.7 | 397 | 39.6 | 2873.6 |
| tc-f1-w | 18.5 | 40.4 | 490 | 2829.0 | 2361.3 |
| tc-f1-w10 | 24.0 | 46.3 | 635 | 3019.5 | 2718.8 |
| tc-f1-w2 | 18.2 | 24.1 | 480 | 3178.9 | 3172.9 |
| tc-f1-w3 | 19.0 | 31.0 | 501 | 2995.9 | 3435.9 |
| tc-f1-w4 | 21.3 | 38.4 | 562 | 3177.1 | 3020.1 |
| tc-f1-w5 | 21.1 | 29.8 | 557 | 3174.4 | 2584.5 |
| tc-f1-w6 | 20.7 | 29.2 | 547 | 3012.4 | 3119.8 |
| tc-f1-w7 | 22.0 | 37.4 | 580 | 3439.4 | 2747.0 |
| tc-f1-w8 | 22.9 | 38.7 | 605 | 3175.3 | 2328.1 |
| tc-f1-w9 | 20.6 | 37.9 | 543 | 3129.6 | 2833.5 |
| **all 11 VMs** | | | **5897** | **31171.1** | **31195.5** |

- Workers: CPU mean 20.8 % (smallest 18.2, largest 24.0), on average 0.83 of 4 vCPUs.
- Per fetched page: 421.23 vCPU-seconds and 2228.2 MB sent over the fleet network (web content in the WARC files: 0.070 MB per page); the network volume is far above the web content, so most of it is Hadoop's own traffic (not decomposed).
- Cost of the crawl window at the list price of 0.2016 USD per VM-hour: 11 VMs x 0.183 h = 2.02 VM-hours = **0.41 USD** (no TDX surcharge, disks, egress, idle time, builds or verification).

**Window: round 1 (segment 140237 to next segment)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 14.8 | 20.2 | 177 | 18.0 | 1282.9 |
| tc-f1-w | 24.9 | 40.4 | 298 | 1357.6 | 1349.9 |
| tc-f1-w10 | 27.5 | 46.3 | 330 | 1361.8 | 1503.7 |
| tc-f1-w2 | 21.7 | 24.1 | 260 | 1514.7 | 1365.2 |
| tc-f1-w3 | 20.0 | 25.6 | 240 | 1442.8 | 1443.5 |
| tc-f1-w4 | 18.9 | 30.4 | 227 | 1426.9 | 1292.6 |
| tc-f1-w5 | 24.3 | 29.8 | 291 | 1561.2 | 975.2 |
| tc-f1-w6 | 22.5 | 29.2 | 270 | 1516.0 | 1495.8 |
| tc-f1-w7 | 20.5 | 25.2 | 246 | 1476.4 | 1144.8 |
| tc-f1-w8 | 18.7 | 22.5 | 225 | 1437.0 | 1060.4 |
| tc-f1-w9 | 20.5 | 25.1 | 246 | 1470.2 | 1321.7 |
| **all 11 VMs** | | | **2811** | **14582.5** | **14235.8** |

**Window: round 2 (segment 140708 to done)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 15.3 | 20.7 | 220 | 21.6 | 1590.7 |
| tc-f1-w | 13.3 | 22.3 | 191 | 1471.4 | 1011.5 |
| tc-f1-w10 | 21.2 | 30.6 | 305 | 1657.7 | 1215.1 |
| tc-f1-w2 | 15.2 | 21.6 | 219 | 1664.2 | 1807.7 |
| tc-f1-w3 | 18.2 | 31.0 | 261 | 1553.1 | 1992.5 |
| tc-f1-w4 | 23.3 | 38.4 | 335 | 1750.2 | 1727.5 |
| tc-f1-w5 | 18.5 | 24.1 | 266 | 1613.2 | 1609.2 |
| tc-f1-w6 | 19.2 | 26.3 | 277 | 1496.5 | 1624.0 |
| tc-f1-w7 | 23.2 | 37.4 | 334 | 1963.1 | 1602.2 |
| tc-f1-w8 | 26.4 | 38.7 | 381 | 1738.3 | 1267.7 |
| tc-f1-w9 | 20.7 | 37.9 | 297 | 1659.4 | 1511.7 |
| **all 11 VMs** | | | **3087** | **16588.6** | **16959.6** |

**Window: export (crawl done to export done)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 52.7 | 56.1 | 1264 | 7.9 | 86.1 |
| tc-f1-w | 1.2 | 7.2 | 28 | 114.3 | 2.9 |
| tc-f1-w10 | 1.6 | 13.3 | 39 | 150.8 | 150.0 |
| tc-f1-w2 | 1.1 | 8.8 | 28 | 149.1 | 148.8 |
| tc-f1-w3 | 0.5 | 1.9 | 12 | 61.4 | 62.9 |
| tc-f1-w4 | 1.9 | 14.0 | 47 | 201.3 | 136.9 |
| tc-f1-w5 | 0.4 | 1.3 | 11 | 98.2 | 98.9 |
| tc-f1-w6 | 1.3 | 10.3 | 32 | 132.9 | 2.4 |
| tc-f1-w7 | 0.7 | 3.9 | 16 | 106.7 | 140.9 |
| tc-f1-w8 | 0.4 | 1.3 | 10 | 79.8 | 105.2 |
| tc-f1-w9 | 0.4 | 1.6 | 10 | 113.0 | 113.2 |
| **all 11 VMs** | | | **1497** | **1215.4** | **1048.2** |

*Method: utilization is the mean over each 60 s step times 4 vCPUs times 60 s; the window edges are rounded to whole minutes, so vCPU-seconds are good to about one minute of one VM.*

## 7. Verification

| Check | Result | What it checks |
|---|---|---|
| [1] | **PASS** | the reference is the published reference of the commit (part A of ops/verify-reference.sh) |
| [2] | **PASS** | the quotes of every node equal the reference (rules E1 to E7, and E9 when a commit is given) |
| [3] | **PASS** | TD attributes: the debug bit is off in every quote (P5.4) |
| [4] | **PASS** | the export is what quote C says (rule E8) |
| [5] | **PASS** | every record and folder identity of the export is signed by a key of the fleet (P5.2) |
| [6] | **PASS** | the Intel signature chain of every quote (E0, P5.3) |
| [7] | **PASS** | the MRTD is in Google's signed launch endorsement (P5.5) |
| [8] | **PASS** | the receipts: every receipt in the WARCs is in the signed receipts files, and each describes its response (P5.6, part A) |
| [9] | **PASS** | every URL of the fetch list has exactly one outcome, and no outcome is for an unscheduled URL (P5.6, part B) |
| [10] | **PASS** | the signed Roughtime time of the run, and the certificates against it (P5.7) |

## 8. Cost (list price 0.2016 USD per VM-hour; the fleet of 11 VMs only: no TDX surcharge, disks, egress, builders or verification)

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

## 9. Export and scaling model

- **Manifest phase** (crawl done to the export manifest): 553 s for 257 files = **2.15 s per file**; the export holds 1.1 MB, so 505.0 s per MB.
- **Upload** (manifest to export done): 41 s for 260 objects = 0.16 s per object.
- During the export the master's CPU mean was 52.7 % of 4 vCPUs and the workers' 1.0 %: the export runs on the master alone.
- **Model, from this run:** export time is about 2.3 s x the number of files, whatever their size. At this rate 1,000 files take about 38 min. Check the model against another run before relying on it.

## 10. Findings (rules applied automatically)

- **4 seeds have no outcome**: first https://ja.wikipedia.org/wiki/Main_Page
- Export: 2.15 s per file for 257 files (the manifest phase alone took 553 s).
- 1 seeds or links ended as NOT_HTTPS: no receipt is possible for them.
- Round times: round 1 271 s = 4.5 min, round 2 389 s = 6.5 min.
- The workers were mostly idle: mean CPU 20.8 % of 4 vCPUs.
- All 10 verification checks pass.

## 11. Where each number comes from

| Number | Source |
|---|---|
| Outcomes, receipts, per round, per seed | signed outcome records `tc/crawl/segments/*/tc_receipts/outcomes-*.jsonl` and `fetchlist.txt` |
| Round start | name of the segment folder |
| Crawl start, end, export end | `master-log-lines.txt` (master log lines collected during the run) |
| Signed window, readings, authenticated receipts | `time-check.txt` (`verify_time_export.py`) |
| Each task's signed start and end, fetch dates, critical path per round | `run_task_times.py` and the signed readings (WARC-Date is the crawler's clock) |
| Cost, idle minutes | VM-seconds of each phase x the list price; idle = minutes of the crawl window with a worker CPU mean below 5 % (Cloud Monitoring) |
| Export model | master log lines `tc-export: manifest: N files` and `uploaded M objects` |
| CPU and network per VM | Cloud Monitoring `instance/cpu/utilization`, `network/received_bytes_count`, `network/sent_bytes_count` |
| Stage minutes | `/home/rishabsdp17/e15a-run/timings.txt` |
| Verification checks | `/home/rishabsdp17/e15a-p56/verify-export.txt` |
