#!/usr/bin/env python3
# Milestone 4, baby step 4.8.3 (updated for review 1 of the pull request, change 2): a structural check of the receipt files of one run (read-only).
# Usage: m483_receipts_check.py EXPORT_DIR JOB_SHA256 [--strict]
#   EXPORT_DIR holds one folder per segment with tc_receipts/, either directly under it with the WARC files in warc/ of each segment (the layout of step 4.8.3), or under tc/crawl/segments with the WARC files in tc/warc/*/ (the layout of the full export). A file nonce and a file policy.json or collection-policy.json are used when they exist.
#   JOB_SHA256 is the full SHA-256 of the job file that ran (the receipts must name it as code_hash)
#   --strict (default off): the old rule, every receipt authenticated, with a valid chain, a hostname match and certificate dates that enclose the fetch.
# It checks what can be checked WITHOUT her verifier: it is not a cryptographic check of the TLS evidence.
# Per receipt: the run's nonce (when the export has one), the policy hash, the format, TLS 1.2 or 1.3 (the crawler takes what the server offers: the real 1K run has 613 and 53), no lie about the authentication (a source whose certificate does not validate is a recorded outcome, not a failure; the rules are in ../image/test/r3_tls_honesty.py), a binding type that is present and the same for every receipt of the run (it is a setting of the crawl: tc.binding), the job's hash, the content hash equal to the SHA-256 of the page in the WARC (and its length), the document id equal to the WARC
# record id. Per outcome: ACCEPTED outcomes name exactly one receipt by its hash and document id; every other outcome has no receipt. The report ends with the breakdown by certificate chain and hostname.
import glob, hashlib, json, os, sys, zlib
from datetime import datetime, timezone
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "image", "test")); from r3_tls_honesty import evaluate, matrix, matrix_lines

args = [a for a in sys.argv[1:] if a != "--strict"]; strict_on = len(args) != len(sys.argv) - 1
if len(args) != 2: print("usage: m483_receipts_check.py EXPORT_DIR JOB_SHA256 [--strict]"); sys.exit(2)
X, JOB = args[0], args[1].lower()
nonce_f = os.path.join(X, "nonce"); nonce = open(nonce_f).read().strip() if os.path.exists(nonce_f) else None
polf = next((p for p in (os.path.join(X, "policy.json"), os.path.join(X, "collection-policy.json")) if os.path.exists(p)), None)
problems = []; tot = {}; unauth = {}; pairs = []; seen = set(); bindings = {}
def bump(k, n=1): tot[k] = tot.get(k, 0) + n
def bad(m): problems.append(m)
pol = None
if polf is None: bad("the export has neither policy.json nor collection-policy.json")
else: pol = "sha256:" + hashlib.sha256(open(polf, "rb").read()).hexdigest()

def warc_records(path):
    data = open(path, "rb").read(); pos = 0
    while pos < len(data):
        d = zlib.decompressobj(31); buf = d.decompress(data[pos:]); pos = len(data) - len(d.unused_data)
        i = buf.find(b"\r\n\r\n"); h = dict(l.split(": ", 1) for l in buf[:i].decode("utf-8", "replace").split("\r\n")[1:] if ": " in l)
        n = int(h.get("Content-Length", len(buf) - i - 4)); yield h, buf[i + 4:i + 4 + n]

def read_warcs(files, label):
    resp = {}
    for f in files:
        try:
            for h, body in warc_records(f):
                if h.get("WARC-Type") == "response": resp[h.get("WARC-Target-URI")] = (h, body)
        except Exception as e: bad("%s: unreadable WARC %s (%s)" % (label, os.path.basename(f), e))
    return resp

cur = os.path.isdir(os.path.join(X, "tc", "crawl", "segments")); segdir = os.path.join(X, "tc", "crawl", "segments") if cur else X
shared = read_warcs(sorted(glob.glob(os.path.join(X, "tc", "warc", "*", "*.warc.gz"))), "export") if cur else None
for seg in sorted(d for d in glob.glob(os.path.join(segdir, "*")) if os.path.isdir(d)):
    rf = sorted(glob.glob(os.path.join(seg, "tc_receipts", "receipts-*.jsonl"))); of = sorted(glob.glob(os.path.join(seg, "tc_receipts", "outcomes-*.jsonl")))
    rlines = [l.rstrip("\n") for f in rf for l in open(f, encoding="utf-8") if l.strip()]
    outs = [json.loads(l) for f in of for l in open(f, encoding="utf-8") if l.strip()]
    resp = shared if cur else read_warcs(sorted(glob.glob(os.path.join(seg, "warc", "*.warc.gz"))), os.path.basename(seg))
    st = {}
    for o in outs: st[o["status"]] = st.get(o["status"], 0) + 1
    print("== segment %s: receipts %d, outcomes %s, WARC pages %d" % (os.path.basename(seg), len(rlines), st, len(resp)))
    by_hash = {}; out_by_hash = {o.get("receipt_sha256"): o for o in outs if o.get("receipt_sha256")}
    for l in rlines:
        r = json.loads(l); u = r["source_url"]; h = "sha256:" + hashlib.sha256(l.encode()).hexdigest(); by_hash[h] = r; bump("receipts"); seen.add(u)
        if nonce is not None and r.get("nonce") != nonce: bad("nonce differs: " + u)
        if pol is not None and r.get("collection_policy_hash") != pol: bad("policy hash differs: " + u)
        if r.get("version") != "tc-source-receipt/2": bad("format %s: %s" % (r.get("version"), u))
        if r.get("code_hash") != "sha256:" + JOB: bad("code_hash is not the job's hash: " + u)
        s = r.get("server", {}); v = s.get("validation", {})
        proto = s.get("protocol")
        if proto not in ("TLSv1.2", "TLSv1.3"): bad("protocol %s: %s" % (proto, u))
        else: bump("TLS protocol " + proto)
        bt = (r.get("binding") or {}).get("type")
        if not bt or not isinstance(bt, str): bad("the receipt has no binding type: " + u)
        else: bindings[bt] = bindings.get(bt, 0) + 1; bump("binding type " + bt)
        w = resp.get(u)
        if not w: bad("no WARC response record for " + u); continue
        hh, body = w; j = body.find(b"\r\n\r\n"); pl = body[j + 4:]
        try: ts = datetime.strptime(hh["WARC-Date"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
        except (KeyError, ValueError): bad("the WARC record has no usable WARC-Date: " + u); continue
        o = out_by_hash.get(h); flag = o.get("source_authenticated", v.get("authenticated")) if o else v.get("authenticated")
        honest, labels_ok, strict_ok, why = evaluate(v, s, flag, ts)
        if not honest: bad("the authentication of the receipt is not honest (its flag, its chain and hostname facts, the outcome and the certificate dates disagree): " + u)
        elif not labels_ok: bad("the labels of the receipt's validation disagree with its facts or with the certificate dates: " + u)
        else: bump("authentication honest and labels agree")
        if why: unauth[why] = unauth.get(why, 0) + 1
        if strict_on and not strict_ok: bad("strict: the source was not authenticated (%s): %s" % (why or "the certificate dates do not enclose the fetch", u))
        pairs.append((v.get("chain"), v.get("hostname")))
        if "sha256:" + hashlib.sha256(pl).hexdigest() != r["raw_content_hash"] or len(pl) != r["raw_content_length"]: bad("content hash or length differs from the WARC page: " + u)
        else: bump("content hash equals the WARC page")
        if "urn:uuid:" + hh.get("WARC-Record-ID", "").strip("<>").replace("urn:uuid:", "") != r["document_id"]: bad("document_id differs from the WARC record id: " + u)
        else: bump("document id equals the WARC record id")
    acc = 0
    for o in outs:
        if nonce is not None and o.get("nonce") != nonce: bad("outcome nonce differs: " + str(o.get("source_url")))
        if o["status"] == "ACCEPTED":
            acc += 1; r = by_hash.get(o.get("receipt_sha256"))
            if r is None: bad("ACCEPTED outcome names no receipt line: " + str(o.get("source_url")))
            elif r["document_id"] != o.get("document_id") or r["source_url"] != o.get("source_url"): bad("ACCEPTED outcome and its receipt disagree: " + str(o.get("source_url")))
            else: bump("ACCEPTED outcomes tied to their receipt by hash")
        else:
            bump("non-ACCEPTED outcomes (%s)" % o["status"])
            if o.get("receipt_sha256"): bad("a %s outcome names a receipt: %s" % (o["status"], o.get("source_url")))
    if acc != len(rlines): bad("segment %s: %d ACCEPTED outcomes but %d receipts" % (os.path.basename(seg), acc, len(rlines)))
    if not cur: bump("WARC pages without a receipt", len(set(resp) - {r["source_url"] for r in by_hash.values()}))
if cur: bump("WARC pages without a receipt", len(set(shared) - seen))
if len(bindings) > 1: bad("the receipts of one run carry different binding types: " + ", ".join("%s %d" % kv for kv in sorted(bindings.items(), key=lambda x: (-x[1], x[0]))))
print(); [print("  %-58s %d" % (k, v)) for k, v in sorted(tot.items())]
nu = sum(unauth.values()); n = tot.get("receipts", 0)
print("  receipts of sources that were not authenticated: %d of %d%s" % (nu, n, (" (" + ", ".join("%s %d" % kv for kv in sorted(unauth.items(), key=lambda x: (-x[1], x[0]))) + ")") if nu else ""))
cells, other = matrix(pairs); [print("  " + ln) for ln in matrix_lines(cells, other)]
print("\nPROBLEMS:", "none" if not problems else ""); [print("  - " + p) for p in problems[:20]]
if problems:
    kinds = {}
    for p in problems: k = p.rsplit(": ", 1)[0] if ": " in p else p; kinds[k] = kinds.get(k, 0) + 1
    print("  problems by kind (%d in all, the list above shows at most 20):" % len(problems)); [print("    %5d  %s" % (n, k[:110])) for k, n in sorted(kinds.items(), key=lambda x: (-x[1], x[0]))[:12]]
print("RECEIPTS-CHECK-CLEAN" if not problems and tot.get("receipts") else "RECEIPTS-CHECK-FINDINGS (%d)" % len(problems))
