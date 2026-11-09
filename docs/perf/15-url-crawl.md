# The crawl of 15 sites on 11 machines: how long it takes and what it shows

The question was simple: **does our whole chain, from the image to the ten checks of the verifier, work on a fleet of 1 master and 10 workers, and how long does a small crawl take on it?** The answer is yes, and the crawl of 15 sites took **about 15 minutes** (round 1: 4.5 minutes, round 2: 10.4 minutes), of which the fetching itself is less than half. Most of a small crawl is the fixed cost of the Hadoop jobs, as teammate S's measurements of 1,000 URLs predict.

**Status check, 7 November 2026.** Two runs were made on 7 November 2026, both on the repository as pushed (commit `8c7a6e554`, nothing of `main` merged: part 1 of the mentor's two-part plan). The first run (`e15a`) finished the crawl and passed all ten checks, but it did **not** test 15 sites: four seeds were never scheduled, because of a mistake in my profile (section 6). The second run (`e15r2`) fixed that, scheduled all 15 seeds, and the kit ran from the first stage to the last without a manual step. The runs of about 1,000 URLs are **not run yet** (limitations row 236). Every number below is one run.

## 1. The questions answered

| Question | Answer |
|---|---|
| **Who** ran it? | The operator, from the laptop and from Cloud Shell, with the kit `e15r2-kit`. The mentor asked for the test (the review of 1 November 2026) and for the two parts (the repository as pushed, then after the merge of `main`). The 15 seeds are ours ([end-to-end-testing.md](../end-to-end-testing.md)); the comparison figures are teammate S's. |
| **What** was run? | The crawl of 15 sites, in 2 rounds, with 10 fetch tasks, on 1 master and 10 workers; then the export and the ten checks of `ops/verify-export.py`. Before it, two builds of the image were made, sealed and compared (step P4). |
| **When**? | 7 November 2026. The first run started at 13:07 UTC; the second ran from 15:58 to 17:42 UTC (105 minutes). |
| **Where**? | Google Cloud project `training-custody`, zone `us-central1-a`; 11 confidential VMs of type `c3-standard-4` with Intel TDX; the kit and the evidence in Cloud Shell, the evidence also on the laptop. |
| **Why**? | To find bugs by running our own code end to end on 15 sites of different kinds (the mentor's review), to time the crawl, and to test the fleet at 11 nodes for the first time (before: 2 nodes). |
| **How**? | A test profile (15 seeds, 2 rounds, 10 fetch tasks) is put over the default profile in a local commit that is never pushed; the kit builds the image twice, seals both, boots the fleet, crawls, exports and verifies ([end-to-end-testing.md](../end-to-end-testing.md); [mentor-plan-report.md](../mentor-plan-report.md) section 8.2). |
| **How long**? | Crawl: 14.9 minutes from the first segment to the end (17.6 minutes for the whole crawl driver); export: 9.5 minutes; the whole kit: 105 minutes (section 4). |

## 2. Quick read

| Question | Result | What it means |
|---|---|---|
| Does the whole chain work on 11 TDX machines? | Yes: 15 seeds scheduled in round 1, 134 more URLs in round 2, 149 signed outcomes, 117 pages fetched; **all ten checks pass** | The chain of steps R3 to R5 and P4 to P5 holds at 11 nodes and 20 fetch tasks, where it had only run on 2 nodes and 3 tasks |
| How long does the crawl take? | Round 1: 4.5 min; round 2: 10.4 min; first segment to the end: 14.9 min | Round 1 took the same time for 8 and for 15 URLs: a small crawl measures Hadoop's start-up |
| Where does the time go? | The signed fetching window of the first run was 280 s of a crawl that took 11.0 min; the export took 9.5 min | Fetching is under half of the crawl, and the export of 257 files is as long as the crawl |
| Did every seed behave as expected? | 11 of 15 | The four others are findings about the live web and one unexplained exception (section 5) |
| Did the first run teach anything? | Four things | The profile arithmetic, the export race, a flaw in one of my test cases, and the limit of the console log (section 6) |
| Is it comparable with teammate S's 1,000 URLs? | Only in what it shares: the fixed cost | Her runs: 1 round, 50 threads per worker, no custody layer; ours: 2 rounds, 2 threads per task, full custody (section 7) |

## 3. How the comparison was kept fair

Both runs used the same repository state (`8c7a6e554`), the same hardware, the same 15 seeds and the same profile except one value. The test commits (`95553d8d7` and `619eb3d94`) are local, carry the subject `TEST ONLY` and are never pushed; they replace only the two files of the crawl profile.

| Setting | Both runs |
|---|---|
| Fleet | 1 master and 10 workers, `c3-standard-4` (4 vCPU, 16 GB), Intel TDX, maintenance policy `TERMINATE`; the 11 machines were checked with `gcloud` (machine type, `TDX`) |
| Disks | a 30 GB boot disk and a 10 GB scratch disk per machine, both `pd-balanced` |
| Image | built twice from the same archive and sealed; the two builds hold identical files in both runs (the second run: `TREE-DIFF-IDENTICAL files=64612 dirs=8390 symlinks=5197 ignored=0 verity=checked`) |
| Profile | `ROUNDS=2`, `NUM_FETCHERS=10`, `NUM_TASKS=10`, `NUM_THREADS=2`, `TIME_LIMIT_FETCH=10`, `MIN_FETCHED=6`, the 15 seeds of `ops/image/test/e2e/seeds.txt`, agent name `training-custody-test-bot` |
| What differs | `SIZE_FETCHLIST`: 15 in the first run, 150 in the second; and the kit: the second run waits for the export's `DONE` object, uses the corrected rehearsal and collects the master's log during the run |
| Quota | 140 C3 vCPUs and 10,000 GB of SSD in the region; the 11 machines need 44 vCPUs and 440 GB |

## 4. How long it takes

### 4.1 The stages of the kit (minutes)

| Stage | Run `e15a` (11 nodes) | Run `e15r2` (11 nodes) |
|---|---|---|
| prepare | 6 | 6 |
| build (two builds, at the same time) | 16 | 16 |
| compare, seal-prep | 0, 1 | 0, 1 |
| seal and test image A, then B | 7, 5, 7, 4 | 7, 4, 7, 4 |
| **fleet (boot, mesh, crawl, export, fetch)** | stopped, finished by hand | **32** |
| verify | 0 | 0 |
| p4 (the two builds compared) | 23 | 23 |
| verify-export (ten checks and rehearsals) | stopped | 1 |
| clean | not run (VMs deleted by hand) | 1 |
| **Total of the kit** | not complete | **105** |

For comparison, the last kit run on 2 nodes (`fl3`, 6 November) took 117 minutes: prepare 6, build 39, the sealing of the two images 22, fleet 20, comparison 24 and the rest 6. The fleet stage is the one that depends on the number of machines: 20 minutes for 2 nodes and 32 for 11, of which the export is about 10. The build takes 16 minutes when the package download is quick; the 39 of `fl3` show that it is not always.

### 4.2 The rounds of the crawl

The name of a segment is the time of its `generate` step, so the start of each round can be read from the evidence without any VM.

| Run | Fleet | URLs per round | Round 1 starts | Round 1 takes | Round 2 takes | First segment to the end |
|---|---|---|---|---|---|---|
| `fl3` (6 November) | 2 nodes | 3 rounds, 8 pages | about 14:33 | about 5 min per round (my reading of the heartbeat times) | | about 15 min (the end was 14:48:51) |
| `e15a` | 11 nodes | 8, 10 | 14:02:37 | 4.5 min | 6.5 min | 11.0 min |
| `e15r2` | 11 nodes | **15, 134** | 16:51:54 | **4.5 min** | **10.4 min** | **14.9 min** |

"Takes" is the time to the next segment, and for the last round the time to the `crawl done` marker, so the last round includes the jobs that follow the fetching. Round 1 took 4.5 minutes in both runs on 11 nodes, for 8 URLs and for 15 URLs. Round 2 grew from 6.5 minutes (10 URLs) to 10.4 minutes (134 URLs): about 4 more minutes for 124 more pages.

### 4.3 The second run in detail (from the master's own log)

| Measure | Time |
|---|---|
| Cluster wait (the crawl driver starts, HDFS has its 10 DataNodes) | 85 s = 1.4 min |
| The Nutch crawl script (seeds in HDFS to `crawl done`, 17:06:48 UTC) | 962 s = 16.0 min |
| The whole crawl driver (start to `crawl done`) | 1,056 s = 17.6 min |
| The export (`crawl done` to the last upload) | 572 s = 9.5 min |
| The wait of the kit for the `DONE` object after the quote | 20 s |

### 4.4 What the numbers say

- **Fixed cost dominates.** Our two-round script took 962 s, which is about 481 s per round. Teammate S's fit for one round of 9 jobs is a fixed 470 s (1 worker) to 518 s (2 workers) plus 38 to 81 ms per page ([section 7](#7-how-it-compares-with-teammate-ss-results)). The two agree to within a few percent, which is consistent with the same Hadoop job sequence; it is not a proof, because the settings differ.
- **The fetching is a minority of the time.** In the first run the signed fetch window (the time server's clock, from the first fetch task's start to the last one's end) was 14:03:20 to 14:08:00, **280 s**, inside a crawl of 660 s from the first segment to the end: 42 percent. The signed window of the second run was not captured in the output that was kept; it can be read again from the evidence (`python3 ops/attested/verify_time_export.py`).
- **More tasks make a bigger export.** 3 tasks gave 57 files and an export that took 1 to 2 minutes; 20 tasks gave 257 files (260 objects). The export took 9.9 minutes in the first run (`tc-export.service` used 19 min 37 s of CPU) and 9.5 minutes in the second. It is now as long as the crawl.

## 5. What happened to each seed

The second run, from the signed outcome records (`ops/kits/e15r2-kit/e15-report.py`):

| # | Seed | Expected | What the outcomes say | Verdict |
|---|---|---|---|---|
| 1 | `text.npr.org` | no page (robots.txt) | `NOT_FETCHED`, `fetch_gone robots_denied(18)` | OK |
| 2 | `ja.wikipedia.org` | a page | `ACCEPTED` | OK |
| 3 | `schneier.com` | a page | `NOT_FETCHED`, `fetch_retry exception(16)` | CHECK |
| 4 | `github.com` | a page | `ACCEPTED` | OK |
| 5 | `news.ycombinator.com` | a page | `ACCEPTED` | OK |
| 6 | `reddit.com` | no page (robots.txt) | `NOT_FETCHED`, `fetch_gone robots_denied(18)` | OK |
| 7 | `gutenberg.org` | a page | `ACCEPTED` | OK |
| 8 | `w3.org` | a page | `ACCEPTED` | OK |
| 9 | `nasa.gov` | a page | `ACCEPTED` | OK |
| 10 | `archive.org` | a page | `ACCEPTED` | OK |
| 11 | `ocw.mit.edu` | a page | `ACCEPTED` | OK |
| 12 | `who.int` | no page (robots.txt) | `ACCEPTED` | CHECK |
| 13 | `webscraper.io` | a page | `ACCEPTED` | OK |
| 14 | `nytimes.com` | a recorded 403 | `NOT_FETCHED`, `fetch_retry exception(16)` | CHECK |
| 15 | `timesofindia.indiatimes.com` | a page | `HTTP_STATUS`, 301 (the redirect is not followed in that round) | CHECK |

149 outcomes in all: 15 for the seeds and 134 for the links that round 1 led to, of which 107 were fetched with a receipt; 20 tasks wrote outcomes. A refusal by robots.txt is **recorded as a signed outcome**, not silent. Of the four `CHECK` lines: seed 12 is the live web (the site no longer closes itself to our agent); seed 15 is a redirect; seeds 3 and 14 are one unexplained thing: a plain `curl` from Cloud Shell gets HTTP 200 from `schneier.com` (0.75 s) and a fast 403 from `nytimes.com` (0.10 s), while our crawler ended both with `exception(16)` and not with a status (limitations row 239). In the first run seeds 2, 3 and 10 had no outcome at all, because they were never scheduled (section 6).

## 6. What the first run found, and the second confirmed

| # | Finding | Cause | What changed | Row |
|---|---|---|---|---|
| 1 | Only 8 URLs in round 1 and 10 in round 2; seeds 2, 3, 6 and 10 never scheduled | Nutch divides the size of the fetch list by the number of fetch tasks (`limit = topN / numReduceTasks` in `Generator.java`): 15 divided by 10 tasks is 1 URL per task. My profile kept 15 when the tasks went from 1 to 10 | `SIZE_FETCHLIST=150`; round 1 then scheduled all 15 and round 2 scheduled 134 | 237; mistake 243 |
| 2 | The kit stopped: no `DONE` object in the bucket | The master publishes the quote of the export first and uploads the 260 objects afterwards (41 s); the fleet driver fetched at once | The kit waits for `DONE` (it waited 20 s in the second run); `f1-drive.sh` is unchanged | 238; mistake 244 |
| 3 | Case 24 of the entry rehearsal failed on a good verifier | It removed the first outcome of the first task, which was a redirect without a receipt, so step 8 correctly stayed quiet | It removes the first outcome that carries a receipt (commit `a33184ed0`) | mistake 245 |
| 4 | The crawl's start could not be timed for the first run | A VM keeps only the last 1 MiB of its console | The kit collects the master's lines every 45 s | 240 |

## 7. How it compares with teammate S's results

| Setting | Teammate S, 1,000 seeds | Ours, 15 sites, run `e15r2` |
|---|---|---|
| Machines | 1 master and 1 or 2 workers, `c3-standard-4` | 1 master and 10 workers, `c3-standard-4`, TDX |
| Fetch threads | 50 per worker | 2 per fetch task, 20 in all |
| Fetch tasks | one per worker | 10 |
| Rounds | 1 (9 jobs) | 2 (about 18 jobs) |
| Custody layer | none in the plain runs; full custody in her section 7 (our branch at `20267a68d`, 908 seeds, image `tc-img-perf1k-1`) | full: receipts, signed records, signed time, sealed image, mesh |
| Wall time | 574 s [572 to 578] (TDX, 1 worker) and 562 s [559 to 574] (plain, 2 workers); full custody 576 s [576 to 586], +11 s (+2.0%) over the receipts-only run | round 1: 272 s; the two-round script: 962 s |
| Fixed cost (her fit) | 470 s + 80.6 ms per page (1 worker); 518 s + 38.2 ms per page (2 workers); 85 to 93 percent of a 1K crawl is fixed | about 481 s per round |
| What is measured | first job start to the 9th job end | from the first segment, or from the seeds in HDFS, to the end marker |

The two sets of numbers share one thing, the fixed cost of the job sequence, and they differ in almost everything else (threads, tasks, rounds, what the clock starts and stops on). They are **not** a like-for-like comparison. Her 8 to 10 minutes for 1,000 URLs and our 4.5 minutes for the first round of 15 URLs say the same: a small crawl measures how long Hadoop takes to get through its jobs.

## 8. What we would and would not claim

**We would claim:** the chain from the image to the ten checks works on 11 TDX machines and 20 fetch tasks; round 1 takes about 4.5 minutes whether it fetches 8 or 15 URLs; 134 more URLs add about 4 minutes to round 2; the export of 257 files takes about 10 minutes; a robots.txt refusal is recorded as signed evidence.

**We would not claim:** that the crawl scales with the number of workers (no run compares fleets of different sizes on the same profile); anything about the cost of TDX or of the custody layer per page (there is no plain run on this fleet); that the timings repeat (each is one run, and the earlier crawls of 8 pages on 2 nodes took about 13 and 15 minutes); that the seeds behave like this tomorrow (live sites change); or that our numbers compare with teammate S's (section 7).

## 9. Evidence

| What | Where |
|---|---|
| Run `e15r2` (the second run) | `evidence-e15r2-final.tar.gz`, 13,615,062 bytes, SHA-256 `4f4c9f7f248bc8b87d761d69480ead0619a5b4ce5db681fa8daacb642f4132c8`; the kit and its inputs in `ops/kits/e15r2-kit/` and in the laptop folder `tdx-evidence\e15r2\inputs` (the source archive of the test commit `619eb3d94`, `src-e15r2-619eb3d94.tgz`) |
| Run `e15a` (the first run) | `evidence-e15a-partial.tar.gz`, 9,957,753 bytes, SHA-256 `1acd4f0ef2aeaec930bfe85d0848e74de8764410325f7933be9612106900dc06` (it was made by hand because the kit stopped); the source archive of `95553d8d7` |
| The master's console of the first run | `serial-tc-f1-m.txt` and the ten other files in the evidence (each cut by Google at 1 MiB) |
| The seed table and the timing section | `seed-report.txt` in the evidence of the second run |
| The commits that this folder rests on | `8c7a6e554` (the repository state), `a33184ed0` (the rehearsal fix); the commit of the documents of 7 November 2026 |

## 10. What comes next

1. The runs of about 1,000 URLs, in both parts: they need teammate S's seed list (908 live seeds) and settings, and the mentor's answer on how the 1,000 URLs enter the commit; with `NUM_FETCHERS=10` the fetch list size must be at least 1,000 (limitations row 237).
2. The same two runs after the merge of `main` (part 2), with the same profile and kit, so that a difference can only come from the merge.
3. Repeats of one run, built once and booted several times from the same image, to give a median and a range instead of one number.
4. The two open questions of this document: why two sites end as `exception(16)` (row 239), and the fetch window of the second run, which can be read from the evidence.
