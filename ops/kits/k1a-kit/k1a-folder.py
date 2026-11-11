#!/usr/bin/env python3
"""k1a-folder.py EXPORT_DIR OUT_DIR key=value ...: writes the run folder of a crawl in the form of teammate S's docs/perf (summary.json and receipts.json) from the signed outcome records of the export.
Keys: run_id commit image date nodes machine seeds fetched script_s window_s notes.  Per-phase job times (her jobs.csv) are NOT written: the sealed image has no YARN access; the signed fetch window is given instead (fetch_window_signed_s).
Price: $0.2016 per VM hour (her figure for c3-standard-4, us-central1; no TDX surcharge, disks, idle time or builds)."""
import collections, glob, json, os, sys
def main(argv):
    if len(argv) < 2: print(__doc__.split("\n")[0]); return 2
    export, out = argv[0], argv[1]; kv = dict(a.split("=", 1) for a in argv[2:] if "=" in a)
    files = sorted(glob.glob(os.path.join(export, "tc", "crawl", "segments", "*", "tc_receipts", "outcomes-*.jsonl")))
    if not files: print("K1A-FOLDER-FAILED: no outcome files"); return 2
    outs = [json.loads(l) for f in files for l in open(f, encoding="utf-8") if l.strip()]
    st = collections.Counter(o.get("status", "?") for o in outs); urls = {o.get("source_url") for o in outs}
    seeds = int(kv.get("seeds", 0)); fetched = int(kv.get("fetched", 0)); wall = int(kv.get("script_s", 0)); nodes = int(kv.get("nodes", 11))
    seed_file = kv.get("seed_file"); missing = None
    if seed_file:
        import urllib.parse
        key = lambda u: ((urllib.parse.urlsplit(u.strip()).hostname or "").lower(), urllib.parse.urlsplit(u.strip()).path.rstrip("/") or "/")
        sk = [key(l) for l in open(seed_file, encoding="utf-8") if l.strip()]; ok = {key(u) for u in urls if u}; missing = sum(1 for k in sk if k not in ok)
    rec = {"receipts": sum(1 for o in outs if o.get("status") == "ACCEPTED" and o.get("receipt_sha256")), "outcomes": len(outs), "outcomes_by_status": dict(st), "distinct_urls_with_outcome": len(urls), "seed_urls_without_outcome": missing}
    vmh = round(nodes * wall / 3600.0, 3) if wall else None
    summ = {"run_id": kv.get("run_id"), "source_run": kv.get("run_id"), "date": kv.get("date"), "config": "custody", "commit": kv.get("commit"), "image": kv.get("image"), "nodes": nodes, "machine_type": kv.get("machine", "c3-standard-4 (Intel TDX)"),
            "seed_urls": seeds, "fetched": fetched, "rounds": 1, "crawl_wall_s": wall, "phase_wall_s": None, "fetch_window_signed_s": int(kv["window_s"]) if kv.get("window_s") else None, "yarn_cpu_s_9_jobs": None, "host_cpu": None, "receipts": rec["receipts"],
            "vm_hours_crawl": vmh, "cost_usd_crawl_list_price": round(vmh * 0.2016, 3) if vmh else None, "notes": kv.get("notes", "")}
    os.makedirs(out, exist_ok=True)
    json.dump(summ, open(os.path.join(out, "summary.json"), "w"), indent=1); json.dump(rec, open(os.path.join(out, "receipts.json"), "w"), indent=1)
    print("K1A-FOLDER-OK: %s (summary.json, receipts.json) | outcomes %d, receipts %d, seeds without outcome %s" % (out, len(outs), rec["receipts"], missing)); return 0
if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
