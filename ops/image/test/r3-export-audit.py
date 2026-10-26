#!/usr/bin/env python3
"""Independent audit of an export folder (step R5 and the receipts PR). It uses the standard library only and recomputes everything from the files; it trusts nothing that the crawl said about itself.
   python3 r3-export-audit.py EXPORT_DIR
It prints: (1) every file against manifest.tsv (hash and size) and DONE against the manifest; (2) the WARC records: by type, how many responses carry HTTP headers, the WARC-IP-Address values (the old 'nutch warc' wrote the literal text IP),
how many records are https; (3) the receipt outcomes, tallied by TEXT SEARCH (this is a count, not a verification: the receipts are verified with the repo's own verifiers); (4) the collection policy.
Exit code 0 when the integrity part (1) is clean and no WARC-IP-Address is the literal IP, 1 otherwise."""
import gzip, hashlib, json, os, re, sys
from collections import Counter
root = sys.argv[1] if len(sys.argv) > 1 else "."; bad = 0
def sha256(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    return h.hexdigest()
files = sorted(os.path.relpath(os.path.join(d, f), root) for d, _, fs in os.walk(root) for f in fs)
print("== 1. integrity: %d files in %s" % (len(files), root))
man = os.path.join(root, "manifest.tsv"); listed = {}
if os.path.exists(man):
    for line in open(man, encoding="utf-8", errors="replace"):
        p = line.rstrip("\n").split("\t")
        if len(p) >= 3 and re.fullmatch(r"[0-9a-f]{64}", p[0]): listed[p[2]] = (p[0], p[1])
    ok = 0
    for path, (h, size) in listed.items():
        fp = os.path.join(root, path)
        if not os.path.exists(fp): print("   MISSING:", path); bad += 1
        elif str(os.path.getsize(fp)) != size: print("   SIZE DIFFERS:", path); bad += 1
        elif sha256(fp) != h: print("   HASH DIFFERS:", path); bad += 1
        else: ok += 1
    extra = [f for f in files if f not in listed and f not in ("manifest.tsv", "DONE")]
    print("   manifest lists %d files, %d verified by recomputing SHA-256 and size; files not in the manifest (besides manifest.tsv and DONE): %d" % (len(listed), ok, len(extra)))
    for f in extra[:10]: print("      not listed:", f)
    d = os.path.join(root, "DONE")
    if os.path.exists(d):
        want = hashlib.sha384(open(man, "rb").read()).hexdigest(); got = open(d).read().strip()
        print("   DONE names the manifest (SHA-384):", "yes" if got == want else "NO (DONE %s... manifest %s...)" % (got[:16], want[:16]))
        bad += 0 if got == want else 1
    else: print("   no DONE file in this folder (the driver keeps DONE outside the export folder; rule E8 checks it through quote C)")
else: print("   no manifest.tsv in this folder"); bad += 1
print("== 2. WARC files")
types = Counter(); resp = resp_http = https = 0; ips = Counter(); hdrs = Counter(); nrec = 0; wf = [f for f in files if re.search(r"\.warc(\.gz)?$", f)]
for f in wf:
    fp = os.path.join(root, f)
    try: data = (gzip.open(fp, "rb") if f.endswith(".gz") else open(fp, "rb")).read()
    except Exception as e: print("   cannot read", f, e); bad += 1; continue
    i = 0
    while True:
        i = data.find(b"WARC/1.0\r\n", i)
        if i < 0: break
        j = data.find(b"\r\n\r\n", i)
        if j < 0: break
        fields = {}
        for ln in data[i:j].split(b"\r\n")[1:]:
            k, _, v = ln.partition(b":"); fields[k.strip().decode("latin1")] = v.strip().decode("latin1")
        try: cl = int(fields.get("Content-Length", "0"))
        except ValueError: cl = 0
        body = data[j + 4: j + 4 + cl]; nrec += 1; t = fields.get("WARC-Type", "?"); types[t] += 1
        for k in fields:
            if re.search(r"tc|receipt", k, re.I) and not k.startswith(("WARC-Type", "WARC-Target")): hdrs[k] += 1
        if t == "response":
            resp += 1; resp_http += body.startswith(b"HTTP/")
            if fields.get("WARC-Target-URI", "").startswith("https:"): https += 1
        if "WARC-IP-Address" in fields: ips[fields["WARC-IP-Address"]] += 1
        i = j + 4 + cl
print("   %d WARC files, %d records; by type: %s" % (len(wf), nrec, dict(types)))
print("   response records: %d, of which with HTTP headers at the start of the payload: %d, https: %d" % (resp, resp_http, https))
lit = ips.get("IP", 0); print("   WARC-IP-Address: %d distinct values, the literal text IP (the old nutch warc bug) in %d records%s" % (len(ips), lit, "  <-- THE OLD BUG" if lit else ""))
bad += 1 if lit else 0
if hdrs: print("   headers that name tc or receipt (count of records): %s" % dict(hdrs))
print("== 3. receipt outcomes (a TEXT SEARCH tally, not a verification)")
rf = [f for f in files if "tc_receipts" in f]; lines = 0; sa = Counter(); nn = 0
for f in rf:
    for ln in open(os.path.join(root, f), encoding="utf-8", errors="replace"):
        lines += 1
        for m in re.finditer(r'"source_authenticated"\s*:\s*(true|false|null)', ln): sa[m.group(1)] += 1
        nn += len(re.findall(r'"nonce"\s*:\s*null', ln))
print("   %d receipt files, %d lines; source_authenticated: %s; records with nonce null: %d" % (len(rf), lines, dict(sa), nn))
print("== 4. collection policy")
pf = [f for f in files if f.endswith("collection-policy.json")]
for f in pf:
    b = open(os.path.join(root, f), "rb").read(); h = hashlib.sha256(b).hexdigest()
    try: j = json.loads(b); keys = sorted(j.keys()) if isinstance(j, dict) else type(j).__name__
    except Exception as e: keys = "NOT JSON: %s" % e
    print("   %s: %d bytes, SHA-256 %s, keys %s" % (f, len(b), h, keys))
if not pf: print("   no collection-policy.json in the export")
print(); print("AUDIT-OK" if bad == 0 else "AUDIT-PROBLEMS (%d)" % bad); sys.exit(0 if bad == 0 else 1)
