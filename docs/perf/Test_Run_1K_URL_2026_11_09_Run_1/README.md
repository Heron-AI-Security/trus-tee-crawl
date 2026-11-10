# 1K-URL test run, first run (`Test_Run_1K_URL_2026_11_09_Run_1`)

**State: complete, as part 1 of the mentor's end-to-end verifier run (the repository as pushed).** The crawl of 908 seeds, the export, the two builds and their comparison, all **ten checks** of the verifier, the four rehearsals (entry, fetch list, records, endorsement) and the mentor's eight tamper cases (**7 refused in this run, 1 by reference**, 0 failed) pass, and the stage `clean` ran, so the 11 fleet VMs are deleted. It took **two verification attempts** on the same evidence: the first (9 November 2026) stopped at check 8, because the check demanded that every receipt be authenticated and 13 of 666 are not; the mentor decided on 10 November 2026 that the crawler keeps recording such pages (ADR-106), the check was changed to test honesty instead, and the second attempt (10 November) found one more fault, in the rehearsal of check 9 (it assumed two segments), which was fixed as well. What this run does **not** show is in section 9. Written on 10 November 2026 from the files of this folder.

## 1. What was run

| Item | Value |
|---|---|
| Label | `k1a`; the kit `k1a-kit` is committed as `ce8dd7489` (it ran as committed; the verifier changes below were put into its tree afterwards, as an overlay, for the stage `verify-export`) |
| Repository state | `947b47896` (the pushed head of `feat/tee-hadoop-cluster`, nothing of `main` merged: part 1 of the mentor's two-part plan); the test commit `350c7c09b` is local, has the subject `TEST ONLY` and was never pushed; it changes three files: the crawl profile, the seed list and the wait in `f1-check.sh` (that wait fix is pushed as `5ac40563a`) |
| Fleet | 11 VMs (1 master and 10 workers), `c3-standard-4`, Intel TDX (the mentor decided in a meeting that every run uses 11 VMs: ADR-103) |
| When | the crawl on 9 November 2026 from 13:48:16 to 13:58:36 UTC; the second verification attempt on 10 November 2026 (06:35 UTC) |
| Profile | `ROUNDS=1`, `NUM_FETCHERS=10`, `NUM_TASKS=10`, `NUM_THREADS=50`, `TIME_LIMIT_FETCH=30`, `MIN_FETCHED=500`, `SIZE_FETCHLIST=10000` (1,000 per task), agent `training-custody-test-bot`, memory 2,048 MB per container |
| Seeds | **908**, not 1,000: the list has 1,000 distinct URLs, and the seed rule of `tc-crawl.sh` (only `^https?://[A-Za-z0-9./:_-]+$`) refuses the 92 that carry `?`, `=`, `%` or `&` (66, 63, 31 and 21 of them; some carry several). A change of the seed rule is a separate product decision (limitations row 247) |
| Why | the mentor's acceptance run: build and seal, publish the reference, bring up the fleet, crawl about 1,000 URLs with receipts, run the whole verifier, and reject eight tamper cases ([../../milestone-plan.md](../../milestone-plan.md) section 13) |

## 2. What succeeded

| Stage or check | Result |
|---|---|
| Two builds of the commit and their comparison (step P4) | identical: `TREE-DIFF-IDENTICAL files=64612 dirs=8390 symlinks=5197`; `P4-ACCEPT-OK` |
| The fleet | `ENFORCE-OK` on all 11 nodes; `REFERENCE-OK`; the 11 digests are equal (`FLEET-DIGEST-EQUAL`) |
| The crawl | 1 round; 908 URLs scheduled, **908 outcomes, 0 seeds without an outcome**; 778 pages fetched as the crawl database counts them; 666 receipts |
| The export | complete: 133 files and 136 objects, 29.7 MB |
| The verifier | **all ten checks pass** (`VERIFY-EXPORT-OK`); `P56-VERIFY-OK ... ALL TEN steps PASS` |
| The four rehearsals | entry: 36 damages rejected at the step that belongs to each; fetch list: 22 cases; records: 24 damages; endorsement: 37 cases (10 controls, 27 damages rejected for the right reason) |
| The mentor's eight tamper cases | 7 refused in this run, 1 by reference, 0 not found, 0 failed (section 6) |
| The cleanup | the stage `clean` ran (`clean: 0 min`): the fleet is deleted and the final evidence archive is made |
| Kit minutes (`kit-timings.txt`) | prepare 6, build 16, compare 0, seal-prep 1, seal-disk 7, seal-image 4, seal-disk-b 7, seal-image-b 5, fleet 35, verify 0, p4 23, verify-export 3, clean 0 |

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

**Critical path of the round** (the three parts add up to the round time; the middle part is the SIGNED window of that round's fetch tasks):

| Round | Generate and fetch start-up (segment to first task start) | Fetch tasks (first start to last end, signed) | Later jobs (last task end to next segment or done) | Round |
|---|---|---|---|---|
| 1 | 49 s = 0.8 min (8 %) | 314 s = 5.2 min (51 %) | 257 s = 4.3 min (41 %) | 620 s = 10.3 min |

The fetch tasks of the round took 314 s, but **6 of the 10 tasks took 19 to 26 s**: the other four sat idle for about 300 s after their last page (section 7). So the fetching itself was over about 27 s after it began, and my first reading of this run ("fetching is 45 % of the crawl") was wrong (mistake 250).

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

Counted from the first segment to the end of the crawl (14.1 GB received), 73 % (10.3 GB) fall in the jobs after the fetching; the share column counts from the driver start (17.1 GB), where the same jobs are 60 %. The web content is 28 MB, so the traffic is the fleet's own. In every busy minute (250 MB or more) each worker received about 255 to 315 MB. The cause is not known (limitations row 246).

## 4. The TLS breakdown (`Test_Run_1K_URL_2026_11_09_Run_1_tls_breakdown.*`)

The mentor asked on 10 November 2026 for a breakdown of every TLS case of the crawl, for the paper. `ops/perf/run_tls_breakdown.py` (commit `67cc859d3`) puts every outcome in exactly one case, and the cases add up to the total. The URL's scheme comes first (plain `http` is "not HTTPS" whatever happened to it afterwards), then the receipt's own validation facts, then what the crawler reported when no page was stored.

| Case | Group | Count | Share of all outcomes |
|---|---|---|---|
| A. TLS authenticated (valid chain, hostname matches, dates enclose the fetch) | HTTPS page with a receipt | 653 | 71.9 % |
| B1. not authenticated: chain expired | HTTPS page with a receipt | 9 | 1.0 % |
| B2. not authenticated: chain expired and hostname mismatch | HTTPS page with a receipt | 1 | 0.1 % |
| B3. not authenticated: hostname not in the certificate (chain valid) | HTTPS page with a receipt | 2 | 0.2 % |
| B4. not authenticated: chain from an untrusted issuer | HTTPS page with a receipt | 1 | 0.1 % |
| C. plain HTTP URL: no TLS at all | Plain HTTP | 127 | 14.0 % |
| D. HTTPS: the TLS handshake failed | TLS failed | 2 | 0.2 % |
| E1. HTTPS: no connection (DNS failure, timeout, refused) | No TLS evidence recorded | 20 | 2.2 % |
| E2. HTTPS: the server answered with an error status (page not stored) | No TLS evidence recorded | 35 | 3.9 % |
| E4. HTTPS: page not found (404 or 410) | No TLS evidence recorded | 16 | 1.8 % |
| E5. HTTPS: redirect or another status (page not stored) | No TLS evidence recorded | 16 | 1.8 % |
| E6. HTTPS: page truncated at the content limit (no receipt) | No TLS evidence recorded | 23 | 2.5 % |
| E7. HTTPS: not attempted (dropped at the task timeout) | No TLS evidence recorded | 3 | 0.3 % |
| **Total** | | **908** | 100.0 % |

By group: HTTPS page with a receipt 666 (73.3 %); Plain HTTP 127 (14.0 %); TLS failed 2 (0.2 %); No TLS evidence recorded 113 (12.4 %).


**HTTPS pages with a receipt (666):**

| Case | Count | Share of the pages with a receipt |
|---|---|---|
| A. TLS authenticated (valid chain, hostname matches, dates enclose the fetch) | 653 | 98.0 % |
| B1. not authenticated: chain expired | 9 | 1.4 % |
| B2. not authenticated: chain expired and hostname mismatch | 1 | 0.2 % |
| B3. not authenticated: hostname not in the certificate (chain valid) | 2 | 0.3 % |
| B4. not authenticated: chain from an untrusted issuer | 1 | 0.2 % |

TLS protocol versions of those pages: TLSv1.3 613, TLSv1.2 53.

Cipher suites: TLS_AES_128_GCM_SHA256 454, TLS_AES_256_GCM_SHA384 158, TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384 24, TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256 19, TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256 3, TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256 2, TLS_ECDHE_RSA_WITH_AES_256_CBC_SHA 2, TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384 2, TLS_ECDHE_RSA_WITH_AES_128_CBC_SHA 1, TLS_CHACHA20_POLY1305_SHA256 1.

The files `Test_Run_1K_URL_2026_11_09_Run_1_tls_breakdown.md`, `.json` and `.csv` hold the same numbers, and the two SVG files are the pie charts (`_all_outcomes.svg` for all 908 outcomes, `_https_pages.svg` for the 666 pages with a receipt). Of the 666 HTTPS pages with a receipt, **653 (98.0 %) are authenticated and 13 (2.0 %) are not**: 9 with an expired chain, 2 with a hostname that is not in the certificate, 1 with an expired chain and a hostname mismatch, and 1 from an untrusted issuer; `unauthenticated-13.txt` lists them. An HTTPS fetch that ended in an error status or a redirect did complete a handshake, but the crawler records the certificate only for a page that it stores, so such a URL is "no TLS evidence recorded" (limitations row 251). These are the numbers of one run of one list.

## 5. Check 8: from a failure to the mentor's decision

**What failed (9 November, first attempt).** The kit's report of that day, quoted: `[8] FAIL the receipts ...` with the lines `FAIL: authenticated is true in the receipt and the outcome, with a valid chain and a hostname match 653 of 666` and `FAIL: the validity dates of every certificate of the chain enclose the fetch time 656 of 666`; the other nine checks passed. The full output of the receipt verifier of that attempt is `receipt-verify-first-run-check8-FAIL.txt`. The original `verify-export.txt` of the first attempt was overwritten when the kit's last stage recreated its workspace folder (limitations row 252); the first version is kept on the laptop (`tdx-evidence\k1a\k1a-p56\verify-export.txt`) and the first analysis too (`analysis-k1a.txt`), and neither is in this folder.

**Why: a policy, not an integrity failure.** Every integrity part of check 8 passed for all 666 receipts (each equals its WARC record and its signed record, its hashes and payload are right, its TLS facts are complete). What failed was one sentence that I had written into the check (`ops/image/test/r3-receipt-verify.py`): that every receipt must be authenticated. The crawler does not follow that rule: certificate checking is off by design (ADR-002) and `tc.receipts.require.authenticated` is false by default, so a page from a site with a bad certificate is accepted and its receipt says `authenticated: false`, honestly. In the earlier small runs all sites had valid certificates, so the check never met this case (mistake 258).

| Reason (from the receipts' own validation fields) | Receipts |
|---|---|
| Chain **expired**, hostname matches | 9 |
| Chain expired **and** hostname mismatch | 1 |
| Chain valid, hostname **not in the certificate** | 2 |
| Chain from an **untrusted** issuer | 1 |
| **Total not authenticated** | **13** (2.0 % of the 666 receipts, 1.4 % of the 908 seeds) |

**The decision (10 November 2026).** The question to the mentor (ADR-106) and her answer: the crawler should definitely keep recording such pages, and a breakdown of all the TLS cases should be generated and documented (expired, hostname mismatch, untrusted chain, plain HTTP, all the cases), as a pie chart for the paper, to show the value that the crawler adds. **What changed:** check 8 now tests that no receipt lies about its authentication (the flag equals the result of its own chain and hostname facts, the outcome says the same, an authenticated receipt has valid dates, and the labels agree), reports the count and the reasons of the unauthenticated ones, and fails them only with `TC_REQUIRE_AUTHENTICATED=1` (commit `de3c0d118`; tested with 6 honest receipts and 14 mutants, lying receipts that must still be refused); the breakdown tool is commit `67cc859d3`. On the real evidence the new check passes 666 of 666 and prints `info: 13 of 666 receipts record a source that was not authenticated: expired chain 9, hostname mismatch 2, expired chain + hostname mismatch 1, untrusted chain 1` (`receipt-verify-new.txt`; the same line is under check [8] in `verify-export.txt`).

## 6. The second attempt: the rehearsal of check 9, and the eight cases

With the new check 8 all ten checks passed, but the stage stopped again: the rehearsal of the fetch-list check (check 9) reported `1 case(s) went wrong`. The kit had kept only the last three lines of its output, so the case was invisible (mistake 257), and the rehearsal had to be run by hand to read it: case 7, "a segment without a fetch list while the others have one", assumes that the export has at least two segments (the 15-URL runs had two rounds); this run has **one**, so removing its fetch list left an export with no fetch list at all, and the verifier answered `NOT CHECKED`, as it does for the runs of before (mistake 256). It showed a real gap too: the verifier looked only for the fetch list file and not for its signed record, so a lone record without its fetch list was not a failure of check 9 (the export's digest check would still have refused it). Check 9 now fails when a signed fetch-list record is left without its fetch list, and the rehearsal has a case for it (22 cases; commit `de3c0d118`; limitations row 250). Reproduced first on a one-segment copy of a real export with the old code, then fixed and run on the real export (`fetchlist-rehearsal.txt`).

The mentor's eight cases, as the kit made them from the saved rehearsal outputs (`eight-cases.txt`):

```
the eight tamper cases of the mentor (each is refused by the verifier on a COPY of this run's evidence):
1. an image of another commit                       REFUSED    2 of 2 evidence lines: ok: a pin for another commit (123456789012...) is refused (E9)
2. one changed file in the image                    REFERENCE  shown by ops/image/test/tamper-test.sh on real disks (2 November 2026: 5 cases, 10 checks; docs/tree-comparison.md section 3); not repeated in a fleet run
3. a debug TD                                       REFUSED    3 of 3 evidence lines: ok:    1. the debug bit set in one quote A                                             -> exit 1
4. an MRTD that is not in Google's endorsement      REFUSED    1 of 1 evidence lines: ok:    5. the MRTD with one bit changed                                                      -> 
5. one changed byte in a WARC                       REFUSED    1 of 1 evidence lines: ok:    8. a changed byte in a WARC                                                     -> exit 1
6. one deleted record file                          REFUSED    1 of 1 evidence lines: ok:    9. a record file deleted                                                        -> exit 1
7. a receipt removed from the signed receipts file  REFUSED    1 of 1 evidence lines: ok:   17. a receipt removed from the signed receipts file                              -> exit 1
8. a fleet key without a matching quote             REFUSED    2 of 2 evidence lines: ok:   13. fleet.tsv replaced by one with the attacker's own valid signing keys         -> exit 1
EIGHT-CASES: 7 refused in this run, 1 by reference, 0 not found, 0 failed
```

Case 2 (one changed file in the image) was shown on real disks by `tamper-test.sh` on 2 November 2026 (5 cases, 10 checks; [../../tree-comparison.md](../../tree-comparison.md) section 3) and was **not repeated** on this run.

## 7. The idle tail: 4 of the 10 tasks waited about 300 s

Four tasks (`m_000001`, `m_000002`, `m_000006`, `m_000008`) took 306 to 312 s, while their last page had arrived 9 to 14 s after their start: a **dead tail of 293 to 300 s**. These four tasks hold all 7 `NOT_ATTEMPTED` outcomes (1, 1, 2 and 3), with the reason `task timeout`. The hosts of the seven URLs, and what their `robots.txt` answered when it was fetched from Cloud Shell on 9 November 2026, a few hours after the crawl (`robots.txt`):

```
www.erp28.com               http=503 size=51B 
www.syouter.com             http=520 size=16B 
arcadia-intellicad.pl       http=500 size=2882B 
mts-syj.net                 http=503 size=51B 
cateringsanchez.com         http=500 size=1393B 
pleubian.over-blog.com      http=000 size=0B 
www.hiconex.com             http=503 size=51B
```

None of the seven hosts has a second URL in the seeds (`samehost.txt`):

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

**The explanation, with its confidence.** In our fork, a host whose `robots.txt` fails with a server error is deferred: the URL goes back to its queue and the queue is delayed by `http.robots.503.defer.visits.delay`, default 300,000 ms (5 minutes), with 3 retries (`http.robots.503.defer.visits`, default true: `FetcherThread.java`). The fetcher stops a task when no new request has started for `mapreduce.task.timeout` (10 minutes) divided by `fetcher.threads.timeout.divisor` (2), that is 300 s, and then empties its queues with the reason `task timeout` (`Fetcher.java`, `FetchItemQueues.java`): those URLs are the `NOT_ATTEMPTED` ones. The tail of 293 to 300 s equals that limit; all seven hosts answer their `robots.txt` with a server error or not at all; none has a `Crawl-delay`. **This is very likely the cause, but it is not proven**: the answers were read hours later from another address, and the fetcher's own counters are not available in the sealed image. It is stock Nutch behaviour, not a bug of ours (limitations row 243). Any change (a shorter deferral, or none) changes measured configuration and belongs in a separate experiment.

## 8. Problems met, and what was done

| Problem | What was done | Where |
|---|---|---|
| Check 8 failed on 13 unauthenticated receipts: it demanded more than the crawler promises | the mentor decided (ADR-106); check 8 tests honesty, with mutants; the breakdown tool | limitations row 242, mistake 258, `de3c0d118`, `67cc859d3` |
| The rehearsal of check 9 assumed two segments, and the check did not see a removed fetch list when its record was left | the check and the rehearsal were corrected and tested on a one-segment export | limitations row 250, mistake 256, `de3c0d118` |
| The kit kept only the last three lines of a rehearsal, so the failing case was invisible | read by hand; the next kit prints the failed cases | mistake 257 |
| The kit's last stage deleted my copy of the first failing output | the first version is on the laptop; the next kit keeps first failing outputs | limitations row 252, mistake 260 |
| 4 of 10 tasks idle for about 300 s; 7 URLs `NOT_ATTEMPTED` | explained (very likely, not proven); no change | limitations row 243 |
| The test waited at most 1,800 s for the crawl whatever the time limit | the wait follows `TIME_LIMIT_FETCH` (commit `5ac40563a`) | limitations row 248 |
| 92 of the 1,000 URLs are refused by the seed rule | the run uses the 908 accepted ones | limitations row 247 |
| The export takes about 2 s per file on the master alone | recorded; nothing changed | limitations row 245 |
| I read the 314 s fleet window as the time of fetching | corrected: per-round and per-task views | mistake 250 |

## 9. What this run does not show

It is **one** run of **one** list, on the repository as pushed (part 1); part 2 (after the merge of `main`) is not made. The crawl was not repeated: the second verification attempt checked the same evidence with the corrected verifier. There is no plain crawl on the same fleet, so nothing here says what TDX or the custody layer costs per page. Of the eight tamper cases one is shown by reference. The TLS breakdown describes these 908 outcomes only.

## 10. Files

| File | What it is |
|---|---|
| `README.md` | this document |
| `Test_Run_1K_URL_2026_11_09_Run_1_analysis.md`, `Test_Run_1K_URL_2026_11_09_Run_1_summary.json` | the analysis report and the same numbers as data (made after the second attempt, so the verification section shows ten passes) |
| `Test_Run_1K_URL_2026_11_09_Run_1_network_phases.txt`, `Test_Run_1K_URL_2026_11_09_Run_1_task_times.txt` | network and CPU per phase; the signed start and end of each fetch task |
| `Test_Run_1K_URL_2026_11_09_Run_1_tls_breakdown.md`, `.json`, `.csv`, `_all_outcomes.svg`, `_https_pages.svg` | the TLS breakdown, its data and its two pie charts |
| `verify-export.txt` | the verifier's output of the second attempt: ten of ten pass |
| `eight-cases.txt`, `rehearsal-entry.txt`, `fetchlist-rehearsal.txt` | the eight tamper cases; the 36 damages of the entry rehearsal; the 22 cases of the fetch-list rehearsal |
| `receipt-verify-new.txt`, `receipt-verify-first-run-check8-FAIL.txt` | the receipt verifier on the 666 receipts, after and before the change of check 8 |
| `kit-timings.txt` | the minutes of each stage of the kit |
| `time-check.txt` | the check of the signed time readings |
| `samehost.txt`, `robots.txt` | the seven `NOT_ATTEMPTED` URLs and the other URLs of their hosts (none); the `robots.txt` answers of their hosts |
| `unauthenticated-13.txt` | the 13 receipts whose source was not authenticated, with the reason of each |

## 11. How to make the analysis again

```
python3 run_analysis.py ~/evidence-k1a-f --run-name Test_Run_1K_URL_2026_11_09_Run_1 --title "1K URL test run, first run"
python3 run_network_phases.py ~/evidence-k1a-f > ~/evidence-k1a-f/Test_Run_1K_URL_2026_11_09_Run_1_network_phases.txt
python3 run_task_times.py ~/evidence-k1a-f --tools ops/attested > ~/evidence-k1a-f/Test_Run_1K_URL_2026_11_09_Run_1_task_times.txt
python3 run_tls_breakdown.py ~/evidence-k1a-f --run-name Test_Run_1K_URL_2026_11_09_Run_1
```
The scripts are in [`ops/perf/`](../../../ops/perf/README.md); they read the evidence folder of the run and Google Cloud Monitoring (best effort) and change nothing.
