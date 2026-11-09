"""The 1M benchmark seed list from the CC-MAIN-2026-39 Parquet URL index (cc-index-table, subset=warc), with the sampling filters of bench/sample_seeds.py.
    python gen_1m.py PATHS.gz SEEDS-100K OUT_DIR
Phase 1 (resumable, checkpointed per file): for each of the 300 warc-subset files, ONE row group chosen by Random(SEED + file index); only the columns url,
url_host_name, fetch_status and content_mime_detected are read (HTTP range requests). Kept: status 200, detected text/html, not robots.txt, http(s), no space
or quote characters, at most 2 URLs per host (in index order). Phase 2: hosts of the existing 100K list are excluded; the remaining hosts are ranked by
SHA-256("SEED|host") and their URLs taken in that order until 900,000; those are shuffled with Random(SEED + 1) and appended to the existing 100K (unchanged),
so the existing 1K/10K/100K lists are the 1M list's prefixes. Writes seeds-1m.txt, the fleet-rule-filtered lists of every size, and seeds-1m.meta.json."""
import collections, gzip, hashlib, json, os, random, re, sys, time
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pyarrow.parquet as pq
from concurrent.futures import ThreadPoolExecutor
from rangefile import RangeFile
from urllib.parse import urlsplit
SEED, PER_HOST, NEW, CRAWL = 20261022, 2, 900_000, "CC-MAIN-2026-39"
BASE, RULE, COLS = "https://data.commoncrawl.org/", re.compile(r"^https?://[A-Za-z0-9./:_-]+$"), ["url", "url_host_name", "fetch_status", "content_mime_detected"]
paths_gz, old_path, out = sys.argv[1:4]; os.makedirs(os.path.join(out, "groups"), exist_ok=True)
paths = sorted(l.strip() for l in gzip.open(paths_gz, "rt") if "/subset=warc/" in l)

def one(i):
    ck = os.path.join(out, "groups", "%03d.json" % i)
    if os.path.exists(ck): return json.load(open(ck))
    f = RangeFile(BASE + paths[i]); pf = pq.ParquetFile(f); rg = random.Random(SEED + i).randrange(pf.metadata.num_row_groups)
    t = pf.read_row_group(rg, columns=COLS).to_pydict(); per, kept = collections.Counter(), []
    for u, h, st, mime in zip(t["url"], t["url_host_name"], t["fetch_status"], t["content_mime_detected"]):
        if st != 200 or mime != "text/html" or not u or u.endswith("/robots.txt"): continue
        if not u.startswith(("http://", "https://")) or any(c in u for c in " \t\"'<>"): continue
        h = (h or urlsplit(u).hostname or "").lower()
        if not h or per[h] >= PER_HOST: continue
        per[h] += 1; kept.append([h, u])
    rec = {"file": paths[i], "row_group": rg, "rows": len(t["url"]), "bytes": f.bytes, "candidates": kept}
    json.dump(rec, open(ck + ".tmp", "w")); os.replace(ck + ".tmp", ck); return rec

t0 = time.time(); done = 0; recs = [None] * len(paths)
with ThreadPoolExecutor(2) as ex:
    for i, rec in zip(range(len(paths)), ex.map(one, range(len(paths)))):
        recs[i] = rec; done += 1
        if done % 10 == 0 or done == len(paths): print("files %d/%d, %.0f MB, %d candidates, %.0f min" % (done, len(paths), sum(r["bytes"] for r in recs if r) / 1e6, sum(len(r["candidates"]) for r in recs if r), (time.time() - t0) / 60), flush=True)

old = [l.strip() for l in open(old_path) if l.strip()]
old_hosts = {(urlsplit(u).hostname or "").lower() for u in old}; old_set = set(old)
by_host = collections.defaultdict(list)
for r in recs:
    for h, u in r["candidates"]:
        if h in old_hosts or u in old_set: continue
        if len(by_host[h]) < PER_HOST and u not in by_host[h]: by_host[h].append(u)
rank = sorted(by_host, key=lambda h: hashlib.sha256(("%d|%s" % (SEED, h)).encode()).hexdigest())
new = []
for h in rank:
    for u in by_host[h]:
        if len(new) < NEW: new.append(u)
    if len(new) >= NEW: break
assert len(new) == NEW, "only %d new URLs available" % len(new)
random.Random(SEED + 1).shuffle(new)
full = old + new
meta = {"source": {"crawl": CRAWL, "index": "cc-index-table (Parquet), subset=warc", "manifest": "crawl-data/%s/cc-index-table.paths.gz" % CRAWL,
                   "manifest_sha256": hashlib.sha256(open(paths_gz, "rb").read()).hexdigest(), "files": len(paths),
                   "row_groups": [{"file": r["file"].rsplit("/", 1)[-1], "row_group": r["row_group"], "rows": r["rows"]} for r in recs],
                   "rows_read": sum(r["rows"] for r in recs), "bytes_downloaded": sum(r["bytes"] for r in recs)},
        "method": {"seed": SEED, "row_group_choice": "Random(seed + file index)", "filters": "fetch_status 200, content_mime_detected text/html, not /robots.txt, http(s), no space or quote characters",
                   "per_host_cap": PER_HOST, "host_ranking": "SHA-256('seed|host')", "new_url_shuffle": "Random(seed + 1)",
                   "prefix": "the existing seeds-100k.txt (bench/sample_seeds.py, CDX index of the same crawl), unchanged; its hosts are excluded from the new URLs"},
        "counts": {"candidates": sum(len(r["candidates"]) for r in recs), "candidate_hosts_after_exclusion": len(by_host), "new_urls": len(new)}, "lists": {}}
def write(name, lst):
    data = "".join(u + "\n" for u in lst).encode(); open(os.path.join(out, name), "wb").write(data)
    meta["lists"][name] = {"urls": len(lst), "hosts": len({(urlsplit(u).hostname or "").lower() for u in lst}), "sha256": hashlib.sha256(data).hexdigest()}
    print("%-24s %8d urls  sha256 %s" % (name, len(lst), meta["lists"][name]["sha256"]), flush=True)
write("seeds-1m.txt", full)
for n, name in ((1000, "1k"), (10000, "10k"), (100000, "100k"), (1_000_000, "1m")):
    write("seeds-%s.txt" % name, full[:n]); write("seeds-%s-fleet.txt" % name, [u for u in full[:n] if RULE.match(u)])
json.dump(meta, open(os.path.join(out, "seeds-1m.meta.json"), "w"), indent=1)
print("DONE")
