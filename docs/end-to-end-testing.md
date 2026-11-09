# The end to end test of the crawl on 15 sites

**Status check, 7 November 2026.** The test **ran twice on 7 November 2026**, on 1 master and 10 workers, on the repository as pushed (commit `8c7a6e554`, nothing of `main` merged: part 1 of the mentor's two-part plan). The first run (`e15a`) passed all ten checks of the verifier but did not test all 15 seeds, because the size of the fetch list in my profile was too small for 10 fetch tasks; the second run (`e15r2`) scheduled all 15 and the kit ran from the first stage to the last with no manual step. 11 of the 15 seeds gave what was expected; the crawl took 14.9 minutes from the first segment to the end. The numbers, the seed table and the findings are in [perf/15-url-crawl.md](perf/15-url-crawl.md); the profile for 11 nodes is below. The default image was **not** changed. The runs of about 1,000 URLs are not run yet.

**Status check, 4 November 2026.** On that day the test had **not run yet**. It was prepared on 29 October, it reached the two-build comparison, and that comparison found a real fault in the build (the Public Suffix List, [run-comparison.md](run-comparison.md) section 9.18), which is fixed. The crawl itself is postponed behind the mentor's six-step plan of 28 October US time (steps P1 and P2 are done on 29 October; P3 is next; ADR-090). The default image is **not** changed by this test. Reviewed on 30 October 2026: still not run; steps P1, P2 and P6 of the mentor's plan are done and the test waits behind P3 ([run-comparison.md](run-comparison.md) section 9.19). After step P3.1: still not run; the test waits behind step P3 (P3.1 is done; P3.2 and P3.3 are planned) and the rest of the mentor's plan ([mentor-plan-report.md](mentor-plan-report.md)). After step P3.2 (30 October 2026) it was reviewed again: still not run; step P3.2 is done, and the test waits behind step P3.3 and the rest of the plan ([mentor-plan-report.md](mentor-plan-report.md)). After step P4 (4 November 2026) it was reviewed again: still not run; steps P3.2 and P4 are done and P3.3 was dropped, and the mentor's review of 1 November 2026 asks for a different end-to-end run, of about 1,000 URLs from the tip of `main` with the verifier run from a clean checkout ([milestone-plan.md](milestone-plan.md) section 13); the test of this page waits behind that.

**Update, 9 November 2026.** The test has a second profile, for about 1,000 URLs, and it ran once (9 November 2026, 908 seeds on 11 machines); that run is **incomplete** (nine of ten checks pass; check 8 waits for the mentor, ADR-106). The two 15-URL runs were analysed again with new tools: the first run passes all ten checks but did not test 15 sites, and the second is complete. The folders of the three runs are in [perf/README.md](perf/README.md).

## Why this test exists

The mentor asked for our own code to be run end to end on about 10 URLs, to find bugs. We use 15 sites, each on its own host, each of a different kind, so that different paths of the crawler are exercised: HTML in other languages, plain text, a PDF, an RSS feed, a page that needs scripts, a crawl delay, and four deliberate refusals (three sites that robots.txt closes to our agent and one that answers 403).

## The 15 seeds

The probe was a read-only check from Cloud Shell on 29 October 2026 with our real agent name, `training-custody-test-bot`. It shows what the crawler meets: the HTTP status, the type, the size, and what robots.txt says for our agent. Every seed passes the crawl's own seed rule (plain `http(s)` addresses only).

| # | Field and kind | Seed | What it tests | Probe of 29 October 2026 |
|---|---|---|---|---|
| 1 | News, text only | `https://text.npr.org/` | many links, plain HTML | 200 html, 5,974 bytes; **robots closes it to us** |
| 2 | Reference, Japanese | `https://ja.wikipedia.org/wiki/Main_Page` | multibyte UTF-8, many links | 200 html, 162,241 bytes; open |
| 3 | Blog | `https://www.schneier.com/` | classic blog HTML | 200 html, 71,075 bytes; open |
| 4 | Code hosting | `https://github.com/apache/nutch` | a script-heavy page, possible 429 | 200 html, 355,670 bytes; open |
| 5 | Forum | `https://news.ycombinator.com/` | a robots crawl delay of 30 seconds against the fetch time limit | 200 html, 34,999 bytes; open, delay 30 |
| 6 | Social media | `https://www.reddit.com/r/programming/` | the refusal path (no page, no crash) | 403; **robots closes it to us** |
| 7 | Literature, large text | `https://www.gutenberg.org/cache/epub/1342/pg1342.txt` | a large non-HTML file, size limit | 200 plain text, 772,386 bytes; open |
| 8 | Technology, PDF | `https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf` | the binary and PDF path | 200 pdf, 13,264 bytes; open |
| 9 | Science and government, feed | `https://www.nasa.gov/feed/` | an XML feed | 200 rss, 274,439 bytes; open |
| 10 | Streaming and media | `https://archive.org/details/prelinger` | a script-driven page with little text | 200 html, 2,033 bytes; open |
| 11 | Education | `https://ocw.mit.edu/` | a large HTML page | 200 html, 892,987 bytes; open |
| 12 | Health | `https://www.who.int/news` | the refusal path | 200 html, 219,161 bytes; **robots closes it to us** |
| 13 | Shopping | `https://webscraper.io/test-sites/e-commerce/static` | a product listing | 200 html, 30,184 bytes; open |
| 14 | News, bot protected | `https://www.nytimes.com/` | a refusal that robots.txt does not announce | 403; robots allows us |
| 15 | News, India | `https://timesofindia.indiatimes.com/` | a very large, script-heavy page | 200 html, more than 1 MB; open |

The expected outcome of the test, which the report script checks per seed: seeds 1, 6 and 12 give no page (refused by robots.txt), seed 14 gives a recorded 403, and the other eleven give a fetched page with a receipt. The live sites change from day to day, so a different outcome on another day is a finding to read, not necessarily a bug.

## The test profile

The test uses its own seeds and parameters and leaves the defaults alone: `ops/image/test/e2e/seeds.txt` (the 15 seeds) and `ops/image/test/e2e/params.env`. The parameters differ from the defaults in three values: `ROUNDS=2` (it was 3), `SIZE_FETCHLIST=15` (it was 4, so that round 1 can take all 15 seeds and round 2 up to 15 links they lead to) and `MIN_FETCHED=6` (it was 2, because four seeds are expected to give no page). Everything else is unchanged, including the agent name. With one fetch task this is right; with 10 fetch tasks the same value gives only 1 URL per task (see the profile for 11 nodes below).

## How to run it

1. On the laptop, put the two profile files over the files of the same name in `ops/image/rootfs/etc/tc/crawl/` and make one local commit with the archive of it (the commit is for the test only and is discarded afterwards; it must never be pushed).
2. In Cloud Shell, run the end to end kit on that commit: the rehearsals run the crawler's code against the committed defaults, the real crawl driver checks the profile, two builds are made and compared, the image is sealed, the fleet runs the crawl, and the report prints one line per seed with what was expected, what happened, and `OK` or `CHECK`.
3. Read every `CHECK` line, fix real bugs as separate commits that are pushed only after a cluster pass, and discard the test commit.

The kit (`e2e-test-kit`) ran on 29 October up to the two-build comparison; it is committed under `ops/kits/` after its first complete run, as every kit is.

## What happened so far

| Date | Result |
|---|---|
| 29 October 2026 | the profile and the kit were prepared; the local test commit `5db916fd1` was made; the crawler rehearsal `f03c` failed because it pins the committed parameters (the kit now runs it on a copy with the committed defaults, mistake 205) |
| 29 October 2026 | the first complete try built both images and stopped at the two-build comparison: `nutch-deploy` and `tc-conf` differed because of the Public Suffix List (limitations row 208); the cause was found and fixed in step R4.9 (commit `5ae1aa386`); the test commit was discarded |
| 7 November 2026 | the first run `e15a` on 1 master and 10 workers (local test commit `95553d8d7`, never pushed): the crawl and all ten checks passed; only 8 URLs were scheduled in round 1 and seeds 2, 3, 6 and 10 never were (the size of the fetch list); the kit stopped at the export (a race) and at one rehearsal case, and both were finished by hand |
| 7 November 2026 | the second run `e15r2` (local test commit `619eb3d94`, `SIZE_FETCHLIST=150`): the kit ran from the first stage to the last in 105 minutes; all 15 seeds scheduled; 11 of 15 as expected; all ten checks pass ([perf/15-url-crawl.md](perf/15-url-crawl.md); limitations row 211 is updated) |
| 9 November 2026 | the first run of about 1,000 URLs `k1a` (local test commit `350c7c09b` on `947b47896`, never pushed; 908 seeds; 11 machines): the two builds are identical, the fleet crawled 908 URLs with 908 signed outcomes and 666 receipts, and nine of the ten checks pass; check 8 fails because 13 receipts record a source whose certificate does not validate; the kit stopped there, so the eight tamper cases and the cleanup were not run ([perf/Test_Run_1K_URL_2026_11_09_Run_1](perf/Test_Run_1K_URL_2026_11_09_Run_1/README.md); ADR-106) |

## The profile for 11 nodes

The fleet of 1 master and 10 workers needs its own variant, `ops/image/test/e2e/params-11nodes.env`, next to `params.env` (the seeds are the same). It differs from `params.env` in three values: `NUM_FETCHERS=10` and `NUM_TASKS=10`, so that the 15 seeds, each on its own host, are spread over 10 fetch tasks, and `SIZE_FETCHLIST=150`. **The last one is the point.** Nutch divides the size of the fetch list by the number of tasks (`limit = topN / numReduceTasks` in `Generator.java`), so `SIZE_FETCHLIST=15` with 10 tasks allows 1 URL per task and 10 per round: the first run scheduled 8 and then 10 URLs and never scheduled four of the seeds. The rule for any profile with N tasks is `SIZE_FETCHLIST` of at least N times the URLs that one task may take; the crawl driver does not check it (limitations row 237). The kit `ops/kits/e15r2-kit/` pins this profile, runs its rehearsals on a copy with the default profile (they pin the defaults, mistake 205), waits for the `DONE` object of the export and collects the master's log lines during the run.

## The profile for 908 seeds (9 November 2026)

The run of about 1,000 URLs uses a third variant of the profile in a local test commit (`350c7c09b`, subject `TEST ONLY`, never pushed), which changes three files: the crawl profile, the seed list and the wait of `f1-check.sh`. The values: `ROUNDS=1`, `NUM_FETCHERS=10`, `NUM_TASKS=10`, `NUM_THREADS=50`, `TIME_LIMIT_FETCH=30`, `MIN_FETCHED=500`, `SIZE_FETCHLIST=10000` (1,000 URLs per task, so that no seed is cut by the division of Nutch), 2,048 MB per container. The list has 1,000 distinct URLs, and the seed rule of `tc-crawl.sh` refuses the 92 that carry `?`, `=`, `%` or `&`, so the run has **908 seeds** (limitations row 247). The wait of the test script is now `TIME_LIMIT_FETCH` x 60 + 1,500 s (row 248). Details and results: [perf/Test_Run_1K_URL_2026_11_09_Run_1](perf/Test_Run_1K_URL_2026_11_09_Run_1/README.md).

## What this test does not show

It does not show reproducibility: the pages of live sites are not part of what is measured, and a different day gives different pages. It shows that the crawler handles different kinds of sites, refusals and large files without crashing and writes a receipt for every page it keeps.
