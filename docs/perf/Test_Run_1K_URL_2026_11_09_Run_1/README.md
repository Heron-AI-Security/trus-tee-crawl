# 1K-URL test run, first run (`Test_Run_1K_URL_2026_11_09_Run_1`)

**State: incomplete.** The crawl and the export are complete and nine of the ten checks of the verifier pass, but the run does not pass as a whole. Four things are missing, and the first one needs the mentor's decision: (1) **check [8] fails**: 653 of the 666 receipts are authenticated, because 13 sources have a certificate that does not validate, and the check demands that every receipt be authenticated, a policy that the crawler's default does not follow (section 4); (2) **the table of the mentor's eight tamper cases was not produced**, because the kit stops at the first failed check; (3) **the stage `clean` did not run**, so the 11 VMs stayed up until they were stopped by hand on 9 November 2026 (stopped, not deleted); (4) **the question to the mentor is open**: it was sent on 9 November 2026 and it decides whether this run is finished by re-checking the same evidence or by a new run (section 6). Written on 9 November 2026 from the files of this folder.

## 1. What was run

| Item | Value |
|---|---|
| Label | `k1a`; the kit `k1a-kit` (kept in the `inputs` folder of the run's evidence on the laptop, `tdx-evidence/k1a/inputs`) is not yet committed: kits are committed after a complete run |
| Repository state | `947b47896` (the pushed head of `feat/tee-hadoop-cluster`, nothing of `main` merged: part 1 of the mentor's two-part plan); the test commit `350c7c09b` is local, has the subject `TEST ONLY` and was never pushed; it changes three files: the crawl profile, the seed list and the wait in `f1-check.sh` |
| Fleet | 11 VMs (1 master and 10 workers), `c3-standard-4`, Intel TDX (the mentor decided in a meeting that every run uses 11 VMs: ADR-103) |
| When | 9 November 2026; the crawl from 13:48:16 to 13:58:36 UTC |
| Profile | `ROUNDS=1`, `NUM_FETCHERS=10`, `NUM_TASKS=10`, `NUM_THREADS=50`, `TIME_LIMIT_FETCH=30`, `MIN_FETCHED=500`, `SIZE_FETCHLIST=10000` (1,000 per task), agent `training-custody-test-bot`, memory 2,048 MB per container |
| Seeds | **908**, not 1,000: the list has 1,000 distinct URLs, and the seed rule of `tc-crawl.sh` (only `^https?://[A-Za-z0-9./:_-]+$`) refuses the 92 that carry `?`, `=`, `%` or `&` (66, 63, 31 and 21 of them; some carry several). A change of the seed rule is a separate product decision; the refused URLs are in the kit (`seeds-refused-92.txt`) |
| Why | the mentor's acceptance run: build and seal, publish the reference, bring up the fleet, crawl about 1,000 URLs with receipts, run the whole verifier, and reject eight tamper cases ([../../milestone-plan.md](../../milestone-plan.md) section 13) |

## 2. What succeeded

| Stage or check | Result |
|---|---|
| Two builds of the commit and their comparison (step P4) | identical: `TREE-DIFF-IDENTICAL files=64612 dirs=8390 symlinks=5197`; `P4-ACCEPT-OK` |
| The fleet | enforcement `ENFORCE-OK` on all 11 nodes; `REFERENCE-OK`; the 11 digests are equal (`FLEET-DIGEST-EQUAL`) |
| The crawl | 1 round; 908 URLs scheduled, **908 outcomes, 0 seeds without an outcome**; 778 pages fetched as the crawl database counts them; 666 receipts |
| The export | complete: 133 files and 136 objects, 29.7 MB |
| The verifier | checks 1 to 7, 9 and 10 pass; **check 8 fails** |
| Kit minutes | prepare 6, build 16, compare 0, seal-prep 1, seal-disk 7, seal-image 4, seal-disk-b 7, seal-image-b 5, fleet 35, verify 0, p4 23 (104 minutes up to the verifier) |

### 2.1 The outcomes

| Outcome | Count | Share of 908 |
|---|---|---|
| ACCEPTED (a page with a receipt) | 666 | 73.3 % |
| NOT_HTTPS (a plain `http` URL: no receipt is possible) | 110 | 12.1 % |
| NOT_FETCHED (DNS failure, HTTP 403 and other errors, 404, robots.txt) | 86 | 9.5 % |
| TRUNCATED (reached the 1 MiB content limit) | 23 | 2.5 % |
| HTTP_STATUS (a redirect: not followed in the round) | 16 | 1.8 % |
| NOT_ATTEMPTED (dropped from a queue at the task timeout) | 7 | 0.8 % |

## 3. The critical path and the time

**Critical path of each round** (the three parts add up to the round time; the middle part is the SIGNED window of that round's fetch tasks):

| Round | Generate and fetch start-up (segment to first task start) | Fetch tasks (first start to last end, signed) | Later jobs (last task end to next segment or done) | Round |
|---|---|---|---|---|
| 1 | 49 s = 0.8 min (8 %) | 314 s = 5.2 min (51 %) | 257 s = 4.3 min (41 %) | 620 s = 10.3 min |

The fetch tasks of the round took 314 s, but **6 of the 10 tasks took 19 to 26 s**: the other four sat idle for about 300 s after their last page (section 5). So the fetching itself was over about 27 s after it began, and my first reading of this run ("fetching is 45 % of the crawl") was wrong (mistake 250).

### 3.1 Each fetch task

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
```

### 3.2 Cost, idle time and the export

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

- **Manifest phase** (crawl done to the export manifest): 266 s for 133 files = **2.00 s per file**; the export holds 29.7 MB, so 9.0 s per MB.
- **Upload** (manifest to export done): 23 s for 136 objects = 0.17 s per object.
- During the export the master's CPU mean was 50.4 % of 4 vCPUs and the workers' 1.8 %: the export runs on the master alone.
- **Model, from this run:** export time is about 2.2 s x the number of files, whatever their size. At this rate 1,000 files take about 36 min. Check the model against another run before relying on it.

### 3.3 Network and CPU per phase

```
per phase (whole fleet = master + all workers; MB = megabytes; vCPU-s = utilization x 4 vCPUs x 60 s; worker CPU = mean over workers and minutes):
phase                                                           length  min.      MB in     MB out   share    vCPU-s  w cpu %
before the crawl driver (4 min)                                  240 s     4        0.1        0.0               401      4.2
driver start to HDFS ready                                        93 s     1        0.2        0.2   0.0 %       154      4.1
HDFS ready to seeds in HDFS                                       10 s     1      484.9      465.5   2.8 %       205      5.5
seeds in HDFS to first segment (inject, generate)                 73 s     1     2566.9     2561.8  15.0 %       371     13.6
round 1 fetch job (segment to end of signed window)              363 s     6     3795.5     3793.8  22.2 %      1101      7.3
round 1 later jobs (to crawl done)                               257 s     4    10286.8    10249.7  60.0 %      1970     19.1
crawl done to export manifest                                    266 s     5     1439.2     1461.3               824      1.8
export manifest to export done (upload)                           23 s     0        0.0        0.0                 0      0.0
total over the phases shown                                                     18573.6    18532.3
share = MB received in the phase / MB received from the driver start to crawl done (the phases before the driver and after the crawl are not counted in it).
```

Counted from the first segment to the end of the crawl (14.1 GB received), 73 % (10.3 GB) fall in the jobs after the fetching; the share column of the table counts from the driver start (17.1 GB), where the same jobs are 60 %. The web content is 28 MB, so the traffic is the fleet's own. In every busy minute (250 MB or more) each worker received about 255 to 315 MB. The cause is not known (limitations row 246).

## 4. Why check 8 fails: a policy, not an integrity failure

Every integrity part of check 8 passes for all 666 receipts: each receipt is in the signed receipts files and in the WARC record byte for byte, its hashes and its payload are right, its TLS facts are complete. What fails is one sentence that I wrote into the check (`ops/image/test/r3-receipt-verify.py`, line 65): that **every** receipt must be authenticated, with a valid chain and a hostname match, and that the validity dates of every certificate enclose the fetch time. The crawler does not follow that rule: certificate checking is off by design (ADR-002, provisional) and `tc.receipts.require.authenticated` is false by default, so a page from a site with a bad certificate is accepted and its receipt says `authenticated: false`, honestly. In the earlier small runs all sites had valid certificates, so the check never met this case.

| Reason (from the receipts' own validation fields) | Receipts |
|---|---|
| Chain **expired** (a certificate of the chain ended before the fetch), hostname matches | 9 |
| Chain expired **and** hostname mismatch | 1 |
| Chain valid, hostname **not in the certificate** | 2 |
| Chain from an **untrusted** issuer | 1 |
| **Total not authenticated** | **13** (2.0 % of the 666 receipts, 1.4 % of the 908 seeds) |

The 10 receipts with an expired chain are exactly the 10 receipts that fail the dates part (656 of 666): the second failing line is a consequence of the first. The 13 sites are listed in `unauthenticated-13.txt`; the failed check is in the verification table below.

| Check | Result | What it checks |
|---|---|---|
| [1] | **PASS** | the reference is the published reference of the commit (part A of ops/verify-reference.sh) |
| [2] | **PASS** | the quotes of every node equal the reference (rules E1 to E7, and E9 when a commit is given) |
| [3] | **PASS** | TD attributes: the debug bit is off in every quote (P5.4) |
| [4] | **PASS** | the export is what quote C says (rule E8) |
| [5] | **PASS** | every record and folder identity of the export is signed by a key of the fleet (P5.2) |
| [6] | **PASS** | the Intel signature chain of every quote (E0, P5.3) |
| [7] | **PASS** | the MRTD is in Google's signed launch endorsement (P5.5) |
| [8] | **FAIL** | the receipts: every receipt in the WARCs is in the signed receipts files, and each describes its response (P5.6, part A) |
| [9] | **PASS** | every URL of the fetch list has exactly one outcome, and no outcome is for an unscheduled URL (P5.6, part B) |
| [10] | **PASS** | the signed Roughtime time of the run, and the certificates against it (P5.7) |

Detail of the failed check [8]:

```
[8] FAIL        the receipts: every receipt in the WARCs is in the signed receipts files, and each describes its response (P5.6, part A)
      FAIL: authenticated is true in the receipt and the outcome, with a valid chain and a hostname match  653 of 666
      FAIL: the validity dates of every certificate of the chain enclose the fetch time  656 of 666

```

## 5. The idle tail: 4 of the 10 tasks waited about 300 s

Four tasks (`m_000001`, `m_000002`, `m_000006`, `m_000008`) took 306 to 312 s, while their last page had arrived 9 to 14 s after their start: a **dead tail of 293 to 300 s**. These four tasks hold all 7 `NOT_ATTEMPTED` outcomes (1, 1, 2 and 3), with the reason `task timeout`. The hosts of the seven URLs, and what their `robots.txt` answered when it was fetched from Cloud Shell on 9 November, a few hours after the crawl (`robots.txt` in this folder):

```
www.erp28.com               http=503 size=51B 
www.syouter.com             http=520 size=16B 
arcadia-intellicad.pl       http=500 size=2882B 
mts-syj.net                 http=503 size=51B 
cateringsanchez.com         http=500 size=1393B 
pleubian.over-blog.com      http=000 size=0B 
www.hiconex.com             http=503 size=51B
```

None of the seven hosts has a second URL in the seeds (`samehost.txt`), so no URL waited behind another URL of its host:

```
NOT_ATTEMPTED outcomes: 7
m_000001_0  http://www.erp28.com/en/blog/2024/10/30/vinci-acquires-fm-conway-limited-in-the-united-kin
   same host in the seeds: 0 other URL(s)
m_000001_0  http://www.syouter.com/html/6.html
   same host in the seeds: 0 other URL(s)
m_000002_0  https://arcadia-intellicad.pl/1459-2/
   same host in the seeds: 0 other URL(s)
m_000006_0  http://mts-syj.net/
   same host in the seeds: 0 other URL(s)
m_000006_0  https://cateringsanchez.com/finca-el-algarrobo/
   same host in the seeds: 0 other URL(s)
m_000006_0  https://pleubian.over-blog.com/2025/08/samedi-02-aout-2025.html
   same host in the seeds: 0 other URL(s)
m_000008_0  http://www.hiconex.com/book.html
   same host in the seeds: 0 other URL(s)
```

**The explanation, with its confidence.** In our fork, a host whose `robots.txt` fails with a server error is deferred: the URL goes back to its queue and the queue is delayed by `http.robots.503.defer.visits.delay`, default 300,000 ms (5 minutes), with 3 retries (`http.robots.503.defer.visits`, default true: `FetcherThread.java`). The fetcher stops a task when no new request has started for `mapreduce.task.timeout` (10 minutes) divided by `fetcher.threads.timeout.divisor` (2), that is 300 s, and then empties its queues with the reason `task timeout` (`Fetcher.java`, `FetchItemQueues.java`): those URLs are the `NOT_ATTEMPTED` ones. The tail of 293 to 300 s equals that limit; all seven hosts answer their `robots.txt` with a server error or not at all; none has a `Crawl-delay`. **This is very likely the cause, but it is not proven**: the `robots.txt` answers were read hours later from another address, and the fetcher's own counters are not available in the sealed image. It is stock Nutch behaviour (politeness towards a host that cannot say what it allows), not a bug of ours. It costs about five minutes of a ten-minute crawl whenever one task holds such a host (limitations row 243). Any change (a shorter deferral, or none) changes measured configuration and belongs in a separate experiment after the acceptance run.

## 6. The question to the mentor, and what remains

The question sent on 9 November 2026 (one point):

> In the 1K run on 11 VMs (908 seeds) 9 of the 10 verifier checks pass and the two builds are identical, but check 8 fails on policy: 13 of the 666 receipts (2.0 %) record a source whose TLS certificate did not validate (10 expired, 3 hostname mismatches with one also expired, 1 untrusted chain). The crawler records them honestly as `authenticated=false` (its default `tc.receipts.require.authenticated=false`, ADR-002 provisional), while our receipt check demands that every receipt be authenticated. Should the crawler keep recording such pages and the verifier only check that no receipt lies about its authentication (report the unauthenticated count, strict mode optional), or should the crawler refuse invalid certificates, which drops about 1.4 % of the seeds and means repeating the 1K run?

| If the answer is | What is done | Cost |
|---|---|---|
| **Keep recording** (option 1) | the check is split: it passes when every receipt tells the truth, reports the count of unauthenticated receipts, and fails them only with a strict switch; rehearsal cases prove that a receipt that claims authentication without the evidence still fails; then only the stages `verify-export` and `clean` run again on this evidence, the eight-case table and the final report are made, and the fix is committed after it has run for real | minutes; no VM |
| **Refuse invalid certificates** (option 2) | `tc.receipts.require.authenticated=true` in the job's configuration: the image changes, so the whole run is repeated on a new image (the stopped VMs must be deleted first) | about two hours and about 1.3 USD for the fleet stage |

In both cases the wait fix of `f1-check.sh` (the test waited at most 1,800 s whatever `TIME_LIMIT_FETCH` said; limitations row 248) is pushed as a commit of its own after a pass, and the kit of this run is committed after a complete run (guide rule 120). This ADR is open: ADR-106.

## 7. Problems met, and what was done

| Problem | What was done | Where |
|---|---|---|
| Check 8 fails on 13 unauthenticated receipts | the question above; the integrity part passes | limitations row 242; ADR-106 |
| 4 of 10 tasks idle for about 300 s; 7 URLs `NOT_ATTEMPTED` | explained (very likely, not proven); no change | limitations row 243 |
| The test waited at most 1,800 s for the crawl whatever the time limit | the wait is `TIME_LIMIT_FETCH` x 60 + 1,500 s, at least 1,800 s (test commit only; pushed after a pass) | limitations row 248 |
| 92 of the 1,000 URLs are refused by the seed rule | the run uses the 908 accepted ones | limitations row 247 |
| The export takes about 2 s per file on the master alone | recorded; nothing changed | limitations row 245 |
| I read the 314 s fleet window as the time of fetching | corrected: per-round and per-task views | mistake 250 |

## 8. Files

| File | What it is |
|---|---|
| `README.md` | this document |
| `Test_Run_1K_URL_2026_11_09_Run_1_analysis.md` | the analysis report of the run (`ops/perf/run_analysis.py`) |
| `Test_Run_1K_URL_2026_11_09_Run_1_summary.json` | the same numbers as data, with keys in lower_snake_case |
| `Test_Run_1K_URL_2026_11_09_Run_1_network_phases.txt` | network and CPU of the master and the workers per minute and per phase (`ops/perf/run_network_phases.py`) |
| `Test_Run_1K_URL_2026_11_09_Run_1_task_times.txt` | the signed start and end of each fetch task and its dead tail (`ops/perf/run_task_times.py`) |
| `time-check.txt` | the check of the signed time readings (`ops/attested/verify_time_export.py`) |
| `samehost.txt` | the seven `NOT_ATTEMPTED` URLs and the other URLs of their hosts in the seeds (none) |
| `robots.txt` | what the `robots.txt` of the seven hosts answered on 9 November 2026 (read from Cloud Shell, hours after the crawl) |
| `unauthenticated-13.txt` | the 13 receipts whose source was not authenticated, with the reason of each |

## 9. How to make the analysis again

```
python3 run_analysis.py ~/evidence-k1a-f --run-name Test_Run_1K_URL_2026_11_09_Run_1 --title "..."
python3 run_network_phases.py ~/evidence-k1a-f > ~/evidence-k1a-f/Test_Run_1K_URL_2026_11_09_Run_1_network_phases.txt
python3 run_task_times.py ~/evidence-k1a-f --tools ops/attested > ~/evidence-k1a-f/Test_Run_1K_URL_2026_11_09_Run_1_task_times.txt
```
The scripts are in [`ops/perf/`](../../../ops/perf/README.md); they read the evidence folder of the run and Google Cloud Monitoring (best effort) and change nothing.
