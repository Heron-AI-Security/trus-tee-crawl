# Performance and scale results (`docs/perf`)

This folder keeps the measurements of the crawl: how long it takes, where the time goes, and what a test on many machines shows and does not show. It is the counterpart of the performance results that teammate S wrote on 27 October 2026 (the document *Training Custody Performance Results -1*, which is not in this repository): hers measures plain CCBot on one or two workers; ours measures our own sealed image on a fleet of eleven machines, with every check of the verifier running after the crawl.

**Status check, 7 November 2026.** One document so far: [15-url-crawl.md](15-url-crawl.md), the crawl of 15 sites on 1 master and 10 workers (two runs on 7 November 2026). The runs of about 1,000 URLs asked for by the mentor's review of 1 November 2026 are **not run yet**; they wait for the seed list and the crawl settings of teammate S and for the mentor's answer on how the 1,000 URLs enter the commit ([end-to-end-testing.md](../end-to-end-testing.md); limitations row 236). The mentor's plan has two parts, each with a 15-URL and a 1,000-URL run: part 1 on the repository as pushed (commit `8c7a6e554`, nothing of `main` merged), part 2 after the merge of `main`; this folder holds part 1 so far.

## How these documents are written

- **Times are UTC.** Tools on the operator's laptop print India Standard Time (UTC+5:30); it is converted where cited.
- **One question per heading, and the answer first.** Each document opens with a table of questions, results and what they mean, then the numbers, then what we would and would not claim.
- **Every number says where it comes from.** The sources are listed in the table below, with the command that gives the number again.
- **A number that was not captured is named as such** and not estimated.

| What is measured | Where the number comes from | How to read it again |
|---|---|---|
| The time of each stage of a kit run (prepare, build, seal, fleet, comparison, verification) | `timings.txt` of the kit, printed in its `REPORT` block | `cat ~/e15r2-run/logs/*.log`, `~/e15r2-run/timings.txt` in Cloud Shell |
| The start of each crawl round | the **name of the segment**: it is the time of the `generate` step of that round | `ls export/tc/crawl/segments/` in the evidence |
| The end of the crawl, and of the export | the lines `tc-crawl: done:` and `tc-export: done:` of the master, with their own timestamps | the master's console (it keeps only the last 1 MiB), or `master-log-lines.txt` that the kit of the second run collects during the run |
| The time of the fetching, from an independent clock | the signed Roughtime readings of each fetch task (a start and an end reading), checked by step 10 of `ops/verify-export.py` | `python3 ops/attested/verify_time_export.py EXPORT_DIR` prints the signed window (`EXPORT_DIR` is the `export` folder of the evidence) (`EXPORT_DIR` is the `export` folder of the evidence) (`EXPORT_DIR` is the `export` folder of the evidence) |
| What happened to each URL | the signed outcome records of each task (`outcomes-*.jsonl`) | `python3 ops/kits/e15r2-kit/e15-report.py EXPORT_DIR SEEDS_FILE [MASTER_LOG_LINES]` (`EXPORT_DIR` is the `export` folder of the evidence) (`EXPORT_DIR` is the `export` folder of the evidence) (`EXPORT_DIR` is the `export` folder of the evidence) |

## Documents

| File | What it answers |
|---|---|
| [15-url-crawl.md](15-url-crawl.md) | Who ran what, when, where, why and how for the crawl of 15 sites on 11 machines; how long each part took; which seeds gave what; what the first run found and the second run confirmed; how it compares with teammate S's 1,000-URL results |

## What is not here yet

The 1,000-URL runs; the same crawl after the merge of `main` (part 2); repeats of the same run (every number in this folder is one run; the earlier crawls of 8 pages on 2 nodes took about 13 and 15 minutes); and the comparison with a plain, receipt-free crawl on the same fleet.

## Where the evidence is

The evidence bundles are in the Cloud Shell home and in the laptop's `tdx-evidence` folder, never in the repository; each document names its bundles with their SHA-256 ([15-url-crawl.md](15-url-crawl.md) section 9). The kit that produced the second run is in the repository as `ops/kits/e15r2-kit/`, and the profile that it used is `ops/image/test/e2e/params-11nodes.env` next to the original `params.env`.
