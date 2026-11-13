"""The 1/0.7 benchmark seed lists (about 70% of the seeds of a run are fetched, so a run of nominal size N gets ceil(N / 0.7) seeds).
    python extend_seeds.py GROUPS_DIR SEEDS-1M OUT_DIR
Offline: reads only the per-file checkpoints of gen_1m.py (GROUPS_DIR/000.json ... 299.json) and the committed seeds-1m.txt; nothing is downloaded.
seeds-1m.txt stays an exact prefix: the URLs after its first 1,000,000 continue the SAME host ranking as gen_1m.py phase 2 (SHA-256("SEED|host"), at most
2 URLs per host, hosts of the 100K list excluded) from exactly where the 900,000 new URLs stopped; the next 428,572 are shuffled with Random(SEED + 2) and appended.
Every list of size ceil(N / 0.7) is a prefix of the result, filtered by the fleet rule as before. Writes seeds-1.43m.txt, seeds-{1k,10k,100k,1m}-x07[-fleet].txt and extend.meta.json."""
import collections, hashlib, json, math, os, random, re, sys
from urllib.parse import urlsplit
SEED, PER_HOST, OLD_NEW, RULE = 20261022, 2, 900_000, re.compile(r"^https?://[A-Za-z0-9./:_-]+$")
SIZES = [(1000, "1k"), (10000, "10k"), (100000, "100k"), (1_000_000, "1m")]
groups, one_m, out = sys.argv[1:4]; os.makedirs(out, exist_ok=True)
full1m = [l.rstrip("\n") for l in open(one_m) if l.strip()]; assert len(full1m) == 1_000_000
old = full1m[:100_000]; old_hosts = {(urlsplit(u).hostname or "").lower() for u in old}; old_set = set(old)
by_host = collections.defaultdict(list)
for i in range(300):
    for h, u in json.load(open(os.path.join(groups, "%03d.json" % i)))["candidates"]:
        if h in old_hosts or u in old_set: continue
        if len(by_host[h]) < PER_HOST and u not in by_host[h]: by_host[h].append(u)
rank = sorted(by_host, key=lambda h: hashlib.sha256(("%d|%s" % (SEED, h)).encode()).hexdigest())
seq = [u for h in rank for u in by_host[h]]
assert set(seq[:OLD_NEW]) == set(full1m[100_000:]), "the checkpoints do not reproduce seeds-1m.txt"
target = math.ceil(1_000_000 / 0.7); ext = seq[OLD_NEW:OLD_NEW + target - 1_000_000]; assert len(ext) == target - 1_000_000, "only %d more URLs" % len(ext)
random.Random(SEED + 2).shuffle(ext)
full = full1m + ext; assert len(set(full)) == len(full)
hosts = collections.Counter((urlsplit(u).hostname or "").lower() for u in full[100_000:]); assert max(hosts.values()) <= PER_HOST
meta = {"method": "seeds-1m.txt + the next %d URLs of gen_1m.py's host ranking, shuffled with Random(%d)" % (len(ext), SEED + 2), "factor": "ceil(N / 0.7)", "lists": {}}
def write(name, lst):
    data = "".join(u + "\n" for u in lst).encode(); open(os.path.join(out, name), "wb").write(data)
    meta["lists"][name] = {"urls": len(lst), "sha256": hashlib.sha256(data).hexdigest()}; print("%-26s %9d urls  sha256 %s" % (name, len(lst), meta["lists"][name]["sha256"]))
write("seeds-1.43m.txt", full)
for n, name in SIZES:
    k = math.ceil(n / 0.7); write("seeds-%s-x07.txt" % name, full[:k]); write("seeds-%s-x07-fleet.txt" % name, [u for u in full[:k] if RULE.match(u)])
json.dump(meta, open(os.path.join(out, "extend.meta.json"), "w"), indent=1); print("DONE")
