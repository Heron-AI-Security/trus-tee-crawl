# The end to end test of the crawl on 15 sites

**Status check, 29 October 2026.** The test has **not run yet**. It was prepared on 29 October, it reached the two-build comparison, and that comparison found a real fault in the build (the Public Suffix List, [run-comparison.md](run-comparison.md) section 9.18), which is fixed. The crawl itself is postponed behind the mentor's six-step plan of 28 October US time (steps 1 to 3 first; ADR-090). The default image is **not** changed by this test.

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

The test uses its own seeds and parameters and leaves the defaults alone: `ops/image/test/e2e/seeds.txt` (the 15 seeds) and `ops/image/test/e2e/params.env`. The parameters differ from the defaults in three values: `ROUNDS=2` (it was 3), `SIZE_FETCHLIST=15` (it was 4, so that round 1 can take all 15 seeds and round 2 up to 15 links they lead to) and `MIN_FETCHED=6` (it was 2, because four seeds are expected to give no page). Everything else is unchanged, including the agent name.

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
| later | the crawl on the 15 sites: not run yet (limitations row 211) |

## What this test does not show

It does not show reproducibility: the pages of live sites are not part of what is measured, and a different day gives different pages. It shows that the crawler handles different kinds of sites, refusals and large files without crashing and writes a receipt for every page it keeps.
