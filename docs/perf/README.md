# Performance and scale results (`docs/perf`)

This folder keeps the measurements of the crawl: how long it takes, where the time goes, and what a test on many machines shows and does not show. It is the counterpart of the performance results that teammate S wrote on 27 October 2026 (the document *Training Custody Performance Results -1*, which is not in this repository): hers measures plain CCBot on one or two workers; ours measures our own sealed image on a fleet of eleven machines, with every check of the verifier running after the crawl.

**Status check, 7 November 2026.** One document so far: [15-url-crawl.md](15-url-crawl.md), the crawl of 15 sites on 1 master and 10 workers (two runs on 7 November 2026). The runs of about 1,000 URLs asked for by the mentor's review of 1 November 2026 are **not run yet**; they wait for the seed list and the crawl settings of teammate S and for the mentor's answer on how the 1,000 URLs enter the commit ([end-to-end-testing.md](../end-to-end-testing.md); limitations row 236). The mentor's plan has two parts, each with a 15-URL and a 1,000-URL run: part 1 on the repository as pushed (commit `8c7a6e554`, nothing of `main` merged), part 2 after the merge of `main`; this folder holds part 1 so far.

**Update, 9 November 2026.** The folder now holds one folder per run, named after the run, each with the analysis and the report of that run and a `README.md` that says whether the run is complete and why (section "The runs"). The analysis is made by the tools of `ops/perf/` (commit `df3ec7219`); the documents are checked for currency by `ops/perf/docs_currency_check.py`. The 15-URL document was corrected from the new analysis: the fleet-level signed window of a two-round run had been read as the time of fetching (mistake 250).

## How these documents are written

- **Times are UTC.** Tools on the operator's laptop print India Standard Time (UTC+5:30); it is converted where cited.
- **One question per heading, and the answer first.** Each document opens with a table of questions, results and what they mean, then the numbers, then what we would and would not claim.
- **Every number says where it comes from.** The sources are listed in the table below, with the command that gives the number again.
- **A number that was not captured is named as such** and not estimated.
- **Every run has a folder named after the run**, and its `README.md` opens with the state: **complete**, or **incomplete** with the reasons. A run is complete only when the whole kit ran, all ten checks pass and the analysis has no missing part.
- **Names are identifiers**: a run name starts with a letter and holds letters, digits and underscores, `Test_Run_15_URL_2026_11_07_Run_2` (what, size, date as `YYYY_MM_DD`, run number); its result files are `NAME_analysis.md`, `NAME_summary.json`, `NAME_network_phases.txt` and `NAME_task_times.txt`; the keys of the JSON are `lower_snake_case` (ADR-104).

| What is measured | Where the number comes from | How to read it again |
|---|---|---|
| The time of each stage of a kit run (prepare, build, seal, fleet, comparison, verification) | `timings.txt` of the kit, printed in its `REPORT` block | `cat ~/e15r2-run/logs/*.log`, `~/e15r2-run/timings.txt` in Cloud Shell |
| The start of each crawl round | the **name of the segment**: it is the time of the `generate` step of that round | `ls export/tc/crawl/segments/` in the evidence |
| The end of the crawl, and of the export | the lines `tc-crawl: done:` and `tc-export: done:` of the master, with their own timestamps | the master's console (it keeps only the last 1 MiB), or `master-log-lines.txt` that the kit of the second run collects during the run |
| The time of the fetching, from an independent clock | the signed Roughtime readings of each fetch task (a start and an end reading), checked by step 10 of `ops/verify-export.py` | `python3 ops/attested/verify_time_export.py EXPORT_DIR` prints the signed window (`EXPORT_DIR` is the `export` folder of the evidence) |
| What happened to each URL | the signed outcome records of each task (`outcomes-*.jsonl`) | `python3 ops/kits/e15r2-kit/e15-report.py EXPORT_DIR SEEDS_FILE [MASTER_LOG_LINES]` (`EXPORT_DIR` is the `export` folder of the evidence) |
| The critical path of each round (start-up, fetch tasks, later jobs), the cost, the idle minutes, the export model | the analysis of the run, `ops/perf/run_analysis.py`, from the evidence folder and Google Cloud Monitoring | `NAME_analysis.md` and `NAME_summary.json` in the run folder |
| The network and CPU of the master and the workers, per minute and per phase | Google Cloud Monitoring (host side, 60 s steps) with the phases taken from the evidence, `ops/perf/run_network_phases.py` | `NAME_network_phases.txt` in the run folder |
| The start, the end and the dead tail of each fetch task | the signed time readings and the WARC dates, `ops/perf/run_task_times.py` | `NAME_task_times.txt` in the run folder |

## Documents

| File | What it answers |
|---|---|
| [15-url-crawl.md](15-url-crawl.md) | Who ran what, when, where, why and how for the crawl of 15 sites on 11 machines; how long each part took (with the critical path of each round, section 4.5); which seeds gave what; what the first run found and the second run confirmed; how it compared with teammate S's 1,000-URL results on 7 November (preliminary) |
| [../../ops/perf/README.md](../../ops/perf/README.md) | The tools that make the analysis and check the documents, their use and the naming rules |

## The runs

| Run folder | State | In one line |
|---|---|---|
| [Test_Run_15_URL_2026_11_07_Run_1](Test_Run_15_URL_2026_11_07_Run_1/README.md) | verified, **incomplete** as a test and partial as a record | all ten checks pass, 14 receipts; four of the 15 seeds were never scheduled (a profile mistake); the kit stopped and the run was finished by hand; the master log was not collected, so the crawl start and the network view are missing |
| [Test_Run_15_URL_2026_11_07_Run_2](Test_Run_15_URL_2026_11_07_Run_2/README.md) | **complete** | all ten checks pass, 117 receipts, 0 seeds without an outcome; the kit ran with no manual step (105 min); the crawl took 14.9 min and the export 9.5 min; one slow task set the length of round 2 |
| [Test_Run_1K_URL_2026_11_09_Run_1](Test_Run_1K_URL_2026_11_09_Run_1/README.md) | **complete** | 908 seeds on 11 VMs, 908 outcomes, 666 receipts; all ten checks pass after two verification attempts (check 8 changed after the mentor's answer, ADR-106; check 9 and its rehearsal corrected); the eight cases: 7 refused, 1 by reference; the TLS breakdown with two pie charts; four tasks idled about 300 s |

## What is not here yet

The end of the first 1,000-URL run (it waits for the mentor's answer on the unauthenticated receipts, [limitations row 242](../limitations-and-trust.md)); the same crawl after the merge of `main` (part 2); repeats of the same run (every number in this folder is one run; the earlier crawls of 8 pages on 2 nodes took about 13 and 15 minutes); the comparison with a plain, receipt-free crawl on the same fleet; and the final comparison with teammate S's results, which the operator makes at the end from the summary files.

## Where the evidence is

The evidence bundles are in the Cloud Shell home and in the laptop's `tdx-evidence` folder, never in the repository; each document names its bundles with their SHA-256 ([15-url-crawl.md](15-url-crawl.md) section 9); the result files of each run (the analysis, the summary, the network phases and the task times) are in its run folder, byte for byte as the tools wrote them. The kit that produced the second run is in the repository as `ops/kits/e15r2-kit/`, and the profile that it used is `ops/image/test/e2e/params-11nodes.env` next to the original `params.env`.
