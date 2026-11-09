# 15-URL test run, second run: analysis of the run `Test_Run_15_URL_2026_11_07_Run_2` (commit `619eb3d94d64`)

Generated 2026-11-09 16:13 UTC by `run_analysis.py`, read-only, from `/home/rishabsdp17/evidence-e15r2-f`. Every number says where it comes from (last section). This is **one run**: no median, no range, and the live web changes from day to day.

## 1. What was run

| Item | Value |
|---|---|
| Commit under test | `619eb3d94d647e27c6f79f334540967bde003f80` |
| Fleet | 11 VMs (1 master + 10 worker(s)), each `c3-standard-4` = 4 vCPUs and 16 GB RAM, Intel TDX |
| Seeds | 15 URLs in `profile-seeds.txt` |
| Crawl profile | rounds 2, fetch tasks 10, tasks 10, threads per task 2, fetch time limit 10 min, fetch list size 150 (cap per task = size / tasks = 15 URLs) |
| When (UTC) | crawl 2026-11-07T16:51:54 to 17:06:48; export done 17:16:20 |

## 2. Why and how it was measured

- **Why:** to find out, on our own branch as pushed, what a crawl of 15 seeds in 2 round(s) does on 11 TDX VM(s): how many pages are fetched and authenticated, where the time and the resources go, and whether the whole verifier accepts the export.
- **Clocks (they differ on purpose):** the *segment name* is the time of a round's generate step; the *master's log lines* mark the start and end of the crawl script and of the export; the *signed window and each task's signed start and end* come from a Roughtime server, not from the crawler's clock; *Cloud Monitoring* gives CPU and network of each VM **from the host side**, in 60 s steps; the *fetch dates* (WARC-Date) are the crawler's own unsigned clock.
- **Not measured:** per-job times of the Hadoop jobs (the sealed image has no YARN access), memory, disk I/O, the cost of builds and verification, and any plain crawl without custody on this fleet.

## 3. What the crawl produced

### 3.1 Rounds

| Round | Starts (UTC) | Takes | Scheduled | Outcomes | Receipts | Statuses |
|---|---|---|---|---|---|---|
| 1 | 16:51:54 | 272 s = 4.5 min | 15 | 15 | 10 | ACCEPTED 10, HTTP_STATUS 1, NOT_FETCHED 4 |
| 2 | 16:56:26 | 622 s = 10.4 min | 134 | 134 | 107 | ACCEPTED 107, HTTP_STATUS 9, NOT_FETCHED 15, NOT_HTTPS 2, TRUNCATED 1 |

A round takes the time from its segment (its generate step) to the next segment, and the last one to the `crawl done` marker, so it includes the jobs that follow the fetching.

### 3.2 Outcomes

| Class of outcome | Count | Share of 149 outcomes |
|---|---|---|
| ACCEPTED: fetched, with a receipt | 117 | 78.5 % |
| NOT_FETCHED: fetch_gone robots_denied(n), | 8 | 5.4 % |
| HTTP_STATUS 301 (a redirect or an error status, no page stored) | 8 | 5.4 % |
| HTTP_STATUS 302 (a redirect or an error status, no page stored) | 2 | 1.3 % |
| NOT_HTTPS: not https | 2 | 1.3 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.nyt | 1 | 0.7 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.sch | 1 | 0.7 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.mul | 1 | 0.7 % |
| NOT_FETCHED: fetch_gone notfound(n), https://fonts.googleapis.com/ | 1 | 0.7 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://mattlak | 1 | 0.7 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=460, url=https://apollo. | 1 | 0.7 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=402, url=https://www.wis | 1 | 0.7 % |
| NOT_FETCHED: fetch_gone notfound(n), https://github.githubassets.com/ | 1 | 0.7 % |
| NOT_FETCHED: fetch_gone notfound(n), https://use.fontawesome.com/ | 1 | 0.7 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://blog.ad | 1 | 0.7 % |
| TRUNCATED: content reached http.content.limit; possibly truncated | 1 | 0.7 % |
| NOT_FETCHED: fetch_gone notfound(n), https://fonts.gstatic.com/ | 1 | 0.7 % |

| Headline | Value |
|---|---|
| Scheduled per round / outcomes in all rounds / seeds without an outcome | 15, 134 / 149 / **0** |
| Pages fetched, as counted by the crawl database | 117 |
| Receipts (ACCEPTED with a receipt) | 117 (78.5 % of the 149 outcomes) |
| Receipts authenticated by the signed-time check | 117 of 117; **0 not authenticated** |
| Outcomes by status | ACCEPTED 117, NOT_FETCHED 19, HTTP_STATUS 10, NOT_HTTPS 2, TRUNCATED 1 |
| Fetch tasks that wrote outcomes (all rounds); outcomes per task (smallest, median, largest) | 18; 1, 3, 26 |
| Size of the export | 5.8 MB in 258 files (WARC files 5.5 MB) |
| WARC bytes per receipt | 47 kB |

### 3.3 Each seed

| # | Seed | Round-1 outcome | Task |
|---|---|---|---|
| 1 | `https://text.npr.org/` | NOT_FETCHED: fetch_gone robots_denied(n), | m_000004_0 |
| 2 | `https://ja.wikipedia.org/wiki/Main_Page` | ACCEPTED: fetched, with a receipt | m_000001_0 |
| 3 | `https://www.schneier.com/` | NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.sch | m_000007_0 |
| 4 | `https://github.com/apache/nutch` | ACCEPTED: fetched, with a receipt | m_000001_0 |
| 5 | `https://news.ycombinator.com/` | ACCEPTED: fetched, with a receipt | m_000004_0 |
| 6 | `https://www.reddit.com/r/programming/` | NOT_FETCHED: fetch_gone robots_denied(n), | m_000002_0 |
| 7 | `https://www.gutenberg.org/cache/epub/1342/pg1342.txt` | ACCEPTED: fetched, with a receipt | m_000005_0 |
| 8 | `https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pd` | ACCEPTED: fetched, with a receipt | m_000000_0 |
| 9 | `https://www.nasa.gov/feed/` | ACCEPTED: fetched, with a receipt | m_000003_0 |
| 10 | `https://archive.org/details/prelinger` | ACCEPTED: fetched, with a receipt | m_000006_0 |
| 11 | `https://ocw.mit.edu/` | ACCEPTED: fetched, with a receipt | m_000000_0 |
| 12 | `https://www.who.int/news` | ACCEPTED: fetched, with a receipt | m_000001_0 |
| 13 | `https://webscraper.io/test-sites/e-commerce/static` | ACCEPTED: fetched, with a receipt | m_000002_0 |
| 14 | `https://www.nytimes.com/` | NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.nyt | m_000000_0 |
| 15 | `https://timesofindia.indiatimes.com/` | HTTP_STATUS 301 (a redirect or an error status, no page stored) | m_000003_0 |

## 4. Time

| Measure | Value |
|---|---|
| Cluster wait (crawl driver start to HDFS ready) | 85 s = 1.4 min |
| Nutch crawl script (seeds in HDFS to done) | 962 s = 16.0 min |
| First segment to the done marker | 894 s = 14.9 min |
| The whole crawl driver (start to done) | 1056 s = 17.6 min |
| **Signed fetch window** (first task start to last task end, all rounds, time server's clock) | 525 s = 8.8 min, from 40 readings of 20 tasks |
| Export (crawl done to export done) | 572 s = 9.5 min |
| Pages fetched per second of signed window | 0.223 pages/s for the whole fleet (the window may contain idle time: see section 5) |

**4.1 Critical path of each round** (the three parts add up to the round time; the middle part is the SIGNED window of that round's fetch tasks):

| Round | Generate and fetch start-up (segment to first task start) | Fetch tasks (first start to last end, signed) | Later jobs (last task end to next segment or done) | Round |
|---|---|---|---|---|
| 1 | 42 s = 0.7 min (15 %) | 6 s = 0.1 min (2 %) | 224 s = 3.7 min (82 %) | 272 s = 4.5 min |
| 2 | 47 s = 0.8 min (8 %) | 248 s = 4.1 min (40 %) | 327 s = 5.5 min (53 %) | 622 s = 10.4 min |

Stages of the kit (minutes): prepare 6, build 16, compare 0, seal-prep 1, seal-disk 7, seal-image 4, seal-disk-b 7, seal-image-b 4, fleet 32, verify 0, p4 23, verify-export 1, clean 1. Sum of the stages: 102 min.

## 5. Each fetch task: signed time and dead tail

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
note: the start and end are SIGNED (time server); the fetch dates are the crawler's own clock (second resolution), good enough for a distribution but not evidence.
```

Straggler view: the largest task took 245 s and the median task 4 s (ratio 61.2). A fetch job lasts as long as its slowest task, so the signed window of a round is set by one task, not by the number of pages.

## 6. Fleet resources (host side, Cloud Monitoring)

**Window: crawl (first segment to done)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 10.8 | 20.2 | 390 | 41.2 | 2986.4 |
| tc-f1-w | 15.7 | 34.4 | 566 | 3322.7 | 3166.9 |
| tc-f1-w10 | 17.8 | 30.5 | 639 | 2879.8 | 2335.4 |
| tc-f1-w2 | 18.2 | 30.1 | 655 | 3217.8 | 2146.2 |
| tc-f1-w3 | 18.1 | 33.9 | 653 | 3327.7 | 3027.8 |
| tc-f1-w4 | 17.2 | 39.1 | 620 | 3453.0 | 3298.5 |
| tc-f1-w5 | 17.1 | 26.9 | 617 | 2864.6 | 2537.3 |
| tc-f1-w6 | 16.5 | 34.4 | 593 | 3134.3 | 3463.9 |
| tc-f1-w7 | 13.8 | 25.1 | 497 | 3184.4 | 3042.0 |
| tc-f1-w8 | 13.5 | 28.7 | 486 | 3000.7 | 2731.2 |
| tc-f1-w9 | 14.3 | 25.5 | 514 | 3167.2 | 3023.7 |
| **all 11 VMs** | | | **6232** | **31593.4** | **31759.2** |

- Workers: CPU mean 16.2 % (smallest 13.5, largest 18.2), on average 0.65 of 4 vCPUs.
- Per fetched page: 53.26 vCPU-seconds and 271.4 MB sent over the fleet network (web content in the WARC files: 0.047 MB per page); the network volume is far above the web content, so most of it is Hadoop's own traffic (not decomposed).
- Cost of the crawl window at the list price of 0.2016 USD per VM-hour: 11 VMs x 0.248 h = 2.73 VM-hours = **0.55 USD** (no TDX surcharge, disks, egress, idle time, builds or verification).

**Window: round 1 (segment 165154 to next segment)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 13.6 | 16.8 | 163 | 18.3 | 1357.4 |
| tc-f1-w | 22.9 | 34.4 | 275 | 1650.0 | 926.3 |
| tc-f1-w10 | 25.4 | 30.5 | 304 | 1360.5 | 1052.8 |
| tc-f1-w2 | 24.6 | 27.5 | 296 | 1358.4 | 913.6 |
| tc-f1-w3 | 25.3 | 31.9 | 303 | 1517.0 | 1657.7 |
| tc-f1-w4 | 20.4 | 32.3 | 244 | 1512.1 | 1654.9 |
| tc-f1-w5 | 20.2 | 22.5 | 242 | 1211.9 | 1045.8 |
| tc-f1-w6 | 25.0 | 34.4 | 299 | 1464.5 | 1610.1 |
| tc-f1-w7 | 19.3 | 25.1 | 231 | 1579.6 | 1589.5 |
| tc-f1-w8 | 17.3 | 26.3 | 207 | 1366.3 | 1480.2 |
| tc-f1-w9 | 20.7 | 25.5 | 249 | 1358.6 | 1076.1 |
| **all 11 VMs** | | | **2814** | **14397.2** | **14364.4** |

**Window: round 2 (segment 165626 to done)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 9.5 | 20.2 | 228 | 23.0 | 1628.9 |
| tc-f1-w | 12.1 | 24.0 | 291 | 1672.7 | 2240.6 |
| tc-f1-w10 | 14.0 | 30.2 | 335 | 1519.3 | 1282.6 |
| tc-f1-w2 | 15.0 | 30.1 | 359 | 1859.4 | 1232.6 |
| tc-f1-w3 | 14.6 | 33.9 | 350 | 1810.7 | 1370.1 |
| tc-f1-w4 | 15.7 | 39.1 | 376 | 1940.9 | 1643.7 |
| tc-f1-w5 | 15.6 | 26.9 | 375 | 1652.7 | 1491.5 |
| tc-f1-w6 | 12.2 | 27.2 | 293 | 1669.7 | 1853.8 |
| tc-f1-w7 | 11.1 | 22.7 | 266 | 1604.8 | 1452.4 |
| tc-f1-w8 | 11.6 | 28.7 | 279 | 1634.4 | 1251.0 |
| tc-f1-w9 | 11.1 | 19.1 | 266 | 1808.6 | 1947.6 |
| **all 11 VMs** | | | **3418** | **17196.1** | **17394.8** |

**Window: export (crawl done to export done)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 51.5 | 55.9 | 1236 | 13.5 | 123.8 |
| tc-f1-w | 1.5 | 9.4 | 37 | 163.7 | 29.4 |
| tc-f1-w10 | 0.5 | 2.2 | 12 | 205.7 | 154.1 |
| tc-f1-w2 | 1.9 | 16.0 | 46 | 343.3 | 50.9 |
| tc-f1-w3 | 0.5 | 1.7 | 12 | 165.7 | 166.8 |
| tc-f1-w4 | 1.5 | 12.6 | 37 | 127.6 | 129.3 |
| tc-f1-w5 | 0.7 | 3.8 | 18 | 178.9 | 192.8 |
| tc-f1-w6 | 1.8 | 12.1 | 43 | 98.1 | 244.4 |
| tc-f1-w7 | 2.0 | 17.1 | 48 | 165.9 | 87.2 |
| tc-f1-w8 | 0.7 | 4.3 | 17 | 123.3 | 240.7 |
| tc-f1-w9 | 0.8 | 5.2 | 19 | 163.4 | 163.3 |
| **all 11 VMs** | | | **1525** | **1749.2** | **1582.6** |

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

## 9. Export and scaling model

- **Manifest phase** (crawl done to the export manifest): 532 s for 257 files = **2.07 s per file**; the export holds 5.8 MB, so 91.9 s per MB.
- **Upload** (manifest to export done): 40 s for 260 objects = 0.15 s per object.
- During the export the master's CPU mean was 51.5 % of 4 vCPUs and the workers' 1.2 %: the export runs on the master alone.
- **Model, from this run:** export time is about 2.2 s x the number of files, whatever their size. At this rate 1,000 files take about 37 min. Check the model against another run before relying on it.

## 10. Findings (rules applied automatically)

- Every seed has an outcome (0 seeds without an outcome).
- 1 pages were TRUNCATED at the content limit.
- **Straggler:** the slowest fetch task took 245 s against a median of 4 s: one task sets the length of a fetch job.
- Export: 2.07 s per file for 257 files (the manifest phase alone took 532 s).
- 3 idle minute(s) in the crawl window cost 0.11 USD.
- 2 seeds or links ended as NOT_HTTPS: no receipt is possible for them.
- Round times: round 1 272 s = 4.5 min, round 2 622 s = 10.4 min.
- The workers were mostly idle: mean CPU 16.2 % of 4 vCPUs.
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
| Stage minutes | `/home/rishabsdp17/e15r2-run/timings.txt` |
| Verification checks | `/home/rishabsdp17/e15r2-p56/verify-export.txt` |
