# 1K URL test run, first run: analysis of the run `Test_Run_1K_URL_2026_11_09_Run_1` (commit `350c7c09b30f`)

Generated 2026-11-10 07:00 UTC by `run_analysis.py`, read-only, from `/home/rishabsdp17/evidence-k1a-f`. Every number says where it comes from (last section). This is **one run**: no median, no range, and the live web changes from day to day.

## 1. What was run

| Item | Value |
|---|---|
| Commit under test | `350c7c09b30f1a20eb50027578d95c2fba808449` |
| Fleet | 11 VMs (1 master + 10 worker(s)), each `c3-standard-4` = 4 vCPUs and 16 GB RAM, Intel TDX |
| Seeds | 908 URLs in `profile-seeds.txt` |
| Crawl profile | rounds 1, fetch tasks 10, tasks 10, threads per task 50, fetch time limit 30 min, fetch list size 10000 (cap per task = size / tasks = 1000 URLs) |
| When (UTC) | crawl 2026-11-09T13:48:16 to 13:58:36; export done 14:03:25 |

## 2. Why and how it was measured

- **Why:** to find out, on our own branch as pushed, what a crawl of 908 seeds in 1 round(s) does on 11 TDX VM(s): how many pages are fetched and authenticated, where the time and the resources go, and whether the whole verifier accepts the export.
- **Clocks (they differ on purpose):** the *segment name* is the time of a round's generate step; the *master's log lines* mark the start and end of the crawl script and of the export; the *signed window and each task's signed start and end* come from a Roughtime server, not from the crawler's clock; *Cloud Monitoring* gives CPU and network of each VM **from the host side**, in 60 s steps; the *fetch dates* (WARC-Date) are the crawler's own unsigned clock.
- **Not measured:** per-job times of the Hadoop jobs (the sealed image has no YARN access), memory, disk I/O, the cost of builds and verification, and any plain crawl without custody on this fleet.

## 3. What the crawl produced

### 3.1 Rounds

| Round | Starts (UTC) | Takes | Scheduled | Outcomes | Receipts | Statuses |
|---|---|---|---|---|---|---|
| 1 | 13:48:16 | 620 s = 10.3 min | 908 | 908 | 666 | ACCEPTED 666, HTTP_STATUS 16, NOT_ATTEMPTED 7, NOT_FETCHED 86, NOT_HTTPS 110, TRUNCATED 23 |

A round takes the time from its segment (its generate step) to the next segment, and the last one to the `crawl done` marker, so it includes the jobs that follow the fetching.

### 3.2 Outcomes

| Class of outcome | Count | Share of 908 outcomes |
|---|---|---|
| ACCEPTED: fetched, with a receipt | 666 | 73.3 % |
| NOT_HTTPS: not https | 110 | 12.1 % |
| TRUNCATED: content reached http.content.limit; possibly truncated | 23 | 2.5 % |
| NOT_FETCHED: fetch_retry exception(n), java.net.SocketTimeoutException: c | 11 | 1.2 % |
| HTTP_STATUS 301 (a redirect or an error status, no page stored) | 8 | 0.9 % |
| HTTP_STATUS 302 (a redirect or an error status, no page stored) | 7 | 0.8 % |
| NOT_ATTEMPTED: task timeout | 7 | 0.8 % |
| NOT_FETCHED: fetch_retry exception(n), java.net.ConnectException: Failed  | 3 | 0.3 % |
| NOT_FETCHED: fetch_retry exception(n), java.net.UnknownHostException: www | 3 | 0.3 % |
| NOT_FETCHED: fetch_retry exception(n), java.net.SocketTimeoutException: t | 3 | 0.3 % |
| NOT_FETCHED: fetch_retry exception(n), javax.net.ssl.SSLException: Receiv | 2 | 0.2 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.dgv | 2 | 0.2 % |
| NOT_FETCHED: fetch_gone robots_denied(n), | 2 | 0.2 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=429, url=https://rotom.f | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://consult | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=http://toksyczn | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=http://www.hnfe | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://www.familien-werkstatt.de/le | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=202, url=https://www.gal | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=500, url=https://g-inpro | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=500, url=https://mamasop | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://m.inqaahe.com/sports-news/a1 | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), java.net.UnknownHostException: epi | 1 | 0.1 % |
| HTTP_STATUS 308 (a redirect or an error status, no page stored) | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://plazaro | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://www.honch.co/client-resource | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://ausserr | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://nothing-is-3d.com/article17/ | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.opp | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://biodent | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone gone(n), Http: 410 url=https://www.otuzsekiz.com. | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://www.fresnotruckline.com/cont | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://balilux | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://spectru | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://winwith | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://www.alternative-mobility.eu/ | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=206, url=http://www.jiar | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.bir | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://avology | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.kam | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=http://www.serb | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://grupovi | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://www.tyrell.kr/ | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://live.ca | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone gone(n), https://fa.hiconpopdisplays.com/ | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://avolona | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://inclue. | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://naturallyinformed.net/2020-s | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.tps | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://www.epdplastic.com/recycle-p | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://stylowy | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.tow | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://www.martin-arquitectos.com/c | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=503, url=https://www.swi | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=429, url=https://www.bin | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://acapulc | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://radikaluzem.com/ahsen-cylani | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=406, url=http://finalbac | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=206, url=http://4301119. | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://prediks | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), java.net.UnknownHostException: fro | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://portal- | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), java.net.UnknownHostException: san | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://program | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), java.net.UnknownHostException: lae | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://bisontr | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://blackwingzlimo.com/point-to- | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://www.bhouse.com.tr/blog/ | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://statist | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.lig | 1 | 0.1 % |
| NOT_FETCHED: fetch_gone notfound(n), https://amazingpakistanis.com/amp/ | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://noisype | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), Http code=403, url=https://www.hbc | 1 | 0.1 % |
| NOT_FETCHED: fetch_retry exception(n), java.net.UnknownHostException: sko | 1 | 0.1 % |

| Headline | Value |
|---|---|
| Scheduled per round / outcomes in all rounds / seeds without an outcome | 908 / 908 / **0** |
| Pages fetched, as counted by the crawl database | 778 |
| Receipts (ACCEPTED with a receipt) | 666 (73.3 % of the 908 outcomes) |
| Receipts authenticated by the signed-time check | 653 of 666; **13 not authenticated** |
| Outcomes by status | ACCEPTED 666, NOT_FETCHED 86, HTTP_STATUS 16, NOT_HTTPS 110, TRUNCATED 23, NOT_ATTEMPTED 7 |
| Fetch tasks that wrote outcomes (all rounds); outcomes per task (smallest, median, largest) | 10; 79, 91, 102 |
| Size of the export | 29.7 MB in 134 files (WARC files 28.4 MB) |
| WARC bytes per receipt | 43 kB |

## 4. Time

| Measure | Value |
|---|---|
| Cluster wait (crawl driver start to HDFS ready) | 93 s = 1.6 min |
| Nutch crawl script (seeds in HDFS to done) | 693 s = 11.6 min |
| First segment to the done marker | 620 s = 10.3 min |
| The whole crawl driver (start to done) | 796 s = 13.3 min |
| **Signed fetch window** (first task start to last task end, all rounds, time server's clock) | 314 s = 5.2 min, from 20 readings of 10 tasks |
| Export (crawl done to export done) | 289 s = 4.8 min |
| Pages fetched per second of signed window | 2.478 pages/s for the whole fleet (the window may contain idle time: see section 5) |

**4.1 Critical path of each round** (the three parts add up to the round time; the middle part is the SIGNED window of that round's fetch tasks):

| Round | Generate and fetch start-up (segment to first task start) | Fetch tasks (first start to last end, signed) | Later jobs (last task end to next segment or done) | Round |
|---|---|---|---|---|
| 1 | 49 s = 0.8 min (8 %) | 314 s = 5.2 min (51 %) | 257 s = 4.3 min (41 %) | 620 s = 10.3 min |

Stages of the kit (minutes): prepare 6, build 16, compare 0, seal-prep 1, seal-disk 7, seal-image 4, seal-disk-b 7, seal-image-b 5, fleet 35, verify 0, p4 23, verify-export 3, clean 0. Sum of the stages: 107 min.

## 5. Each fetch task: signed time and dead tail

```
task             start       end signed s   URLs  pages   N/A | 1st fetch last fetch  dead tail
                 (UTC)     (UTC)                              | after start after start end - last
m_000003_0    13:49:07  13:49:26       19     95     74     0 |      +4 s     +17 s        2 s
m_000005_0    13:49:07  13:49:31       24     91     61     0 |      +3 s      +8 s       16 s
m_000009_0    13:49:07  13:49:31       24     79     58     0 |      +3 s     +10 s       14 s
m_000007_0    13:49:07  13:49:32       25     88     62     0 |      +4 s      +9 s       16 s
m_000000_0    13:49:07  13:49:33       26    102     76     0 |      +4 s     +10 s       16 s
m_000004_0    13:49:07  13:49:33       26     88     68     0 |      +4 s     +20 s        6 s
m_000008_0    13:49:05  13:54:12      307     86     62     1 |      +4 s     +14 s      293 s
m_000002_0    13:49:07  13:54:13      306     96     63     1 |      +4 s      +9 s      297 s
m_000001_0    13:49:07  13:54:18      311     98     79     2 |      +3 s     +13 s      298 s
m_000006_0    13:49:07  13:54:19      312     85     63     3 |      +4 s     +12 s      300 s

tasks: 10 | signed task time: smallest 19 s, median 26 s, largest 312 s | tasks of 290 s or more: 4
dead tail (end of the task minus its last fetched page): smallest 2 s, median 16 s, largest 300 s; tasks with a tail of 200 s or more: 4
fleet signed window: 13:49:05 .. 13:54:19 (314 s)
NOT_ATTEMPTED: 7 URLs, in tasks: m_000001_0 x2, m_000002_0 x1, m_000006_0 x3, m_000008_0 x1
   m_000001_0   http://www.erp28.com/en/blog/2024/10/30/vinci-acquires-fm-conway-limited-in-the-united-kingdom/ (task timeout)
   m_000001_0   http://www.syouter.com/html/6.html (task timeout)
   m_000002_0   https://arcadia-intellicad.pl/1459-2/ (task timeout)
   m_000006_0   http://mts-syj.net/ (task timeout)
   m_000006_0   https://cateringsanchez.com/finca-el-algarrobo/ (task timeout)
   m_000006_0   https://pleubian.over-blog.com/2025/08/samedi-02-aout-2025.html (task timeout)
   m_000008_0   http://www.hiconex.com/book.html (task timeout)
note: the start and end are SIGNED (time server); the fetch dates are the crawler's own clock (second resolution), good enough for a distribution but not evidence.
```

Straggler view: the largest task took 312 s and the median task 26 s (ratio 12.0). A fetch job lasts as long as its slowest task, so the signed window of a round is set by one task, not by the number of pages.

## 6. Fleet resources (host side, Cloud Monitoring)

**Window: crawl (first segment to done)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 7.9 | 16.1 | 190 | 20.3 | 1208.7 |
| tc-f1-w | 11.1 | 33.2 | 266 | 1368.5 | 1353.1 |
| tc-f1-w10 | 12.3 | 33.5 | 294 | 1383.8 | 933.5 |
| tc-f1-w2 | 11.6 | 34.2 | 279 | 1388.9 | 1237.2 |
| tc-f1-w3 | 12.4 | 29.0 | 298 | 1273.2 | 1258.2 |
| tc-f1-w4 | 13.2 | 27.7 | 317 | 1549.4 | 1238.3 |
| tc-f1-w5 | 8.0 | 18.2 | 192 | 1311.0 | 1139.8 |
| tc-f1-w6 | 11.6 | 25.7 | 279 | 1326.1 | 967.3 |
| tc-f1-w7 | 12.6 | 28.5 | 304 | 1262.6 | 1969.5 |
| tc-f1-w8 | 14.8 | 37.6 | 356 | 1644.1 | 1534.8 |
| tc-f1-w9 | 12.3 | 31.0 | 295 | 1554.5 | 1203.0 |
| **all 11 VMs** | | | **3071** | **14082.3** | **14043.5** |

- Workers: CPU mean 12.0 % (smallest 8.0, largest 14.8), on average 0.48 of 4 vCPUs.
- Per fetched page: 3.95 vCPU-seconds and 18.1 MB sent over the fleet network (web content in the WARC files: 0.036 MB per page); the network volume is far above the web content, so most of it is Hadoop's own traffic (not decomposed).
- Cost of the crawl window at the list price of 0.2016 USD per VM-hour: 11 VMs x 0.172 h = 1.89 VM-hours = **0.38 USD** (no TDX surcharge, disks, egress, idle time, builds or verification).

**Window: export (crawl done to export done)**

| VM | CPU mean (%) | CPU max (%) | vCPU-seconds | MB received | MB sent |
|---|---|---|---|---|---|
| tc-f1-m | 50.4 | 56.0 | 605 | 38.1 | 139.1 |
| tc-f1-w | 1.6 | 5.5 | 19 | 68.7 | 71.5 |
| tc-f1-w10 | 0.6 | 1.8 | 7 | 166.1 | 170.2 |
| tc-f1-w2 | 0.6 | 1.7 | 7 | 134.1 | 73.0 |
| tc-f1-w3 | 4.1 | 19.2 | 49 | 258.7 | 137.1 |
| tc-f1-w4 | 1.6 | 6.6 | 19 | 173.7 | 324.6 |
| tc-f1-w5 | 2.0 | 7.7 | 24 | 182.9 | 124.4 |
| tc-f1-w6 | 1.7 | 7.4 | 21 | 95.2 | 7.3 |
| tc-f1-w7 | 2.0 | 7.8 | 23 | 171.6 | 351.9 |
| tc-f1-w8 | 2.9 | 13.3 | 35 | 101.1 | 4.9 |
| tc-f1-w9 | 1.2 | 4.4 | 14 | 49.1 | 57.3 |
| **all 11 VMs** | | | **824** | **1439.2** | **1461.3** |

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
| Driver start to first segment (cluster wait, inject, generate) | 176 | 0.538 | 0.108 | 16.2 % |
| Round 1: generate and fetch start-up | 49 | 0.150 | 0.030 | 4.5 % |
| Round 1: fetch tasks (signed window) | 314 | 0.959 | 0.193 | 28.9 % |
| Round 1: later jobs | 257 | 0.785 | 0.158 | 23.7 % |
| Export (crawl done to export done) | 289 | 0.883 | 0.178 | 26.6 % |
| **Total (driver start to export done)** | **1085** | **3.315** | **0.67** | |

- **Cost per 1,000 pages fetched** (crawl window, first segment to done): 0.49 USD (778 pages in 0.38 USD); per 1,000 receipts: 0.57 USD.
- Including the cluster wait and inject (driver start to done): 0.63 USD per 1,000 pages.
- **Idle time:** 4 of the 10 minutes of the crawl window had a worker CPU mean below 5 %; those 4 minutes cost 0.15 USD (39 % of the crawl window's 0.38 USD).
- The fleet stage of the kit (boot to the end of the fetch of the export) took 35 min: 11 VMs x 35 min = 6.42 VM-hours = 1.29 USD.

## 9. Export and scaling model

- **Manifest phase** (crawl done to the export manifest): 266 s for 133 files = **2.00 s per file**; the export holds 29.7 MB, so 9.0 s per MB.
- **Upload** (manifest to export done): 23 s for 136 objects = 0.17 s per object.
- During the export the master's CPU mean was 50.4 % of 4 vCPUs and the workers' 1.8 %: the export runs on the master alone.
- **Model, from this run:** export time is about 2.2 s x the number of files, whatever their size. At this rate 1,000 files take about 36 min. Check the model against another run before relying on it.

## 10. Findings (rules applied automatically)

- Every seed has an outcome (0 seeds without an outcome).
- **13 of 666 receipts are not authenticated** by the signed-time check.
- 7 URLs were NOT_ATTEMPTED (reason in the outcome: task timeout).
- **4 fetch task(s) idled for 200 s or more after their last page** (dead tail, section 5). With NOT_ATTEMPTED URLs this fits the fetcher's 300 s idle abort after a deferral; one explanation is a host whose robots.txt fails with a 5xx (deferred for 300 s by default). Check the hosts of the NOT_ATTEMPTED URLs.
- 23 pages were TRUNCATED at the content limit.
- **Straggler:** the slowest fetch task took 312 s against a median of 26 s: one task sets the length of a fetch job.
- Export: 2.00 s per file for 133 files (the manifest phase alone took 266 s).
- 4 idle minute(s) in the crawl window cost 0.15 USD.
- 110 seeds or links ended as NOT_HTTPS: no receipt is possible for them.
- The workers were mostly idle: mean CPU 12.0 % of 4 vCPUs.
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
| Stage minutes | `/home/rishabsdp17/k1a-run/timings.txt` |
| Verification checks | `/home/rishabsdp17/k1a-p56/verify-export.txt` |
