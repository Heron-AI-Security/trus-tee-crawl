# ops/perf: analysis of a finished run, and the check that the documents are current

These tools only read. They read the evidence folder of a run (and Google Cloud Monitoring, best effort) and write result files next to the evidence. None of them changes a run, an image or the repository.

| File | What it does |
|---|---|
| `run_analysis.py` | The report of one run: what was run, rounds, outcomes (a table per seed for small runs), time with the critical path of each round, each fetch task, host side CPU and network per VM, cost, idle time, the export model, verification, findings. Writes `NAME_analysis.md` and `NAME_summary.json` |
| `run_task_times.py` | The signed start and end of each fetch task, when its pages were fetched, the dead tail at its end, and the URLs that ended as NOT_ATTEMPTED |
| `run_network_phases.py` | Network and CPU of the master and of the workers per minute and per phase (one phase per round and job group) |
| `docs_currency_check.py` | Are the documents up to date: commits named, the numbered registers continuous and equal to the counts in session-start, no finished step called planned, every run folder complete, every named path real |
| `step_status.tsv` | The status of every step and run in one place; update it in the same commit as the documents |

## Use

```
python3 run_analysis.py EVIDENCE_DIR --run-name Test_Run_15_URL_2026_11_07_Run_2 --title "15-URL test run, second run"
python3 run_network_phases.py EVIDENCE_DIR > EVIDENCE_DIR/Test_Run_15_URL_2026_11_07_Run_2_network_phases.txt
python3 run_task_times.py EVIDENCE_DIR --tools ops/attested > EVIDENCE_DIR/Test_Run_15_URL_2026_11_07_Run_2_task_times.txt
python3 ops/perf/docs_currency_check.py --since COMMIT
```

The analysis needs the kit folder, the run folder and the verifier workspace of the run (`~/LABEL-kit`, `~/LABEL-run`, `~/LABEL-p56` by default; options `--kit`, `--run-dir`, `--p56`). Cloud Monitoring keeps the metrics of deleted VMs only for its retention time.

## Naming

A run name starts with a letter and holds letters, digits and underscores: `Test_Run_15_URL_2026_11_07_Run_2` (what, size, date as `YYYY_MM_DD`, run number). Result files carry the run name and are lower case after it: `NAME_analysis.md`, `NAME_summary.json`, `NAME_network_phases.txt`, `NAME_task_times.txt`. Scripts and JSON keys are `lower_snake_case`. Run folders in `docs/perf` are named after the run.

## What is not measured

Per-job times of the Hadoop jobs (the sealed image gives no access to YARN), memory, disk I/O, per-request latency, the cost of builds and verification, and any plain crawl without custody on the same fleet. Cost uses the list price of the VM (0.2016 USD per VM-hour), without the TDX surcharge, disks, egress or idle VMs outside the crawl window.
