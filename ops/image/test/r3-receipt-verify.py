#!/usr/bin/env python3
"""Independent verifier of the source receipts of an export (the receipts PR), standard library only; it uses none of the teammate's tools and trusts nothing that the crawl said about itself.
   python3 r3-receipt-verify.py EXPORT_DIR [JOB_CONSOLE_FILE] [--strict]
It recomputes, for every WARC response record, what its receipt claims: the receipt in the WARC and in the receipts file are the same bytes; the hashes that name it (TC-Content-SHA256 header, the outcome's receipt_sha256) are the SHA-256 of
those bytes; the receipt names the response (document id, URL) and the raw content hash and length are those of the payload (and the WARC's own SHA-1 payload digest is right); the policy hash is the policy file's; the code hash is the job's
(when the job console is given); the TLS facts agree with the outcome and no receipt lies about its authentication (a source whose certificate does not validate is recorded as such, not refused: ADR-106; the strict rule that every receipt be authenticated applies only when --strict, or TC_REQUIRE_AUTHENTICATED=1); every outcome is accounted for; and the signed time readings (Roughtime, structure and time window; the signature is NOT
verified here: that needs the server's key) enclose the fetches of their task. Exit code 0 when every recomputed check holds."""
import base64, glob, gzip, hashlib, json, os, re, struct, sys
from datetime import datetime, timezone
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from r3_tls_honesty import evaluate, matrix, matrix_lines   # the honesty rules of the TLS facts, tested with mutants in r3-tls-honesty-test.py
args = [x for x in sys.argv[1:] if x != "--strict"]; strict_on = len(args) != len(sys.argv) - 1 or os.environ.get("TC_REQUIRE_AUTHENTICATED") == "1"; root = args[0]; jobf = args[1] if len(args) > 1 else None; bad = []; sha = lambda b: "sha256:" + hashlib.sha256(b).hexdigest()
def warc_records(path):
    data = gzip.open(path, "rb").read(); i = 0
    while True:
        i = data.find(b"WARC/1.0\r\n", i)
        if i < 0: return
        j = data.find(b"\r\n\r\n", i); h = {}
        for ln in data[i:j].split(b"\r\n")[1:]:
            k, _, v = ln.partition(b":"); h[k.strip().decode("latin1")] = v.strip().decode("latin1")
        cl = int(h.get("Content-Length", 0)); yield h, data[j + 4: j + 4 + cl]; i = j + 4 + cl
def check(name, ok, detail=""):
    print("   %s %s%s" % ("ok:  " if ok else "FAIL:", name, ("  " + detail) if detail else ""))
    if not ok: bad.append(name)
policy_file = os.path.join(root, "collection-policy.json"); pol_hash = sha(open(policy_file, "rb").read())
receipts, outcomes, times = {}, {}, []
for seg in sorted(glob.glob(os.path.join(root, "tc/crawl/segments/*/tc_receipts"))):
    for f in glob.glob(seg + "/receipts-*.jsonl"):
        att = re.search(r"receipts-(attempt_\w+)\.jsonl", f).group(1)
        for ln in open(f, "rb").read().split(b"\n"):
            if ln.strip(): r = json.loads(ln); receipts[r["document_id"]] = (ln, r, att)
    for f in glob.glob(seg + "/outcomes-*.jsonl"):
        for ln in open(f, "rb").read().split(b"\n"):
            if ln.strip(): o = json.loads(ln); outcomes[(o["source_url"], o["document_id"])] = o
    for f in glob.glob(seg + "/time-*.jsonl"):
        for ln in open(f, "rb").read().split(b"\n"):
            if ln.strip(): times.append(json.loads(ln))
resp, rmeta = {}, {}
for f in sorted(glob.glob(os.path.join(root, "tc/warc/*/*.warc.gz"))):
    kind = f.split(os.sep)[-2]
    for h, body in warc_records(f):
        t = h.get("WARC-Type")
        if t == "response": resp[h["WARC-Record-ID"].strip("<>")] = (h, body, kind)
        elif t == "metadata" and h.get("Content-Type", "").startswith("application/vnd.tc.source-receipt"): rmeta[h["WARC-Refers-To"].strip("<>")] = (h, body)
print("== inputs: %d WARC responses (%s), %d receipts in the receipts files, %d receipt records in the WARC, %d outcomes, %d time readings" % (len(resp), ", ".join("%s %d" % (k, sum(1 for v in resp.values() if v[2] == k)) for k in sorted({v[2] for v in resp.values()})), len(receipts), len(rmeta), len(outcomes), len(times)))
print("== 1. the receipts of the WARC and of the receipts files are the same, and the hashes that name them are right")
check("every receipt in the receipts files has a receipt record in the WARC, and the other way round", set(receipts) == set(rmeta), "(files %d, WARC %d)" % (len(receipts), len(rmeta)))
same = sum(1 for d in receipts if d in rmeta and rmeta[d][1] == receipts[d][0]); check("the receipt in the WARC is byte for byte the line of the receipts file", same == len(receipts), "%d of %d" % (same, len(receipts)))
hdr_ok = sum(1 for d in rmeta if rmeta[d][0].get("TC-Content-SHA256") == sha(rmeta[d][1])); check("the TC-Content-SHA256 header is the SHA-256 of the receipt it sits on", hdr_ok == len(rmeta), "%d of %d" % (hdr_ok, len(rmeta)))
oc_by_doc = {k[1]: v for k, v in outcomes.items()}; out_ok = sum(1 for d in receipts if d in oc_by_doc and oc_by_doc[d].get("receipt_sha256") == sha(receipts[d][0])); check("the outcome's receipt_sha256 is the SHA-256 of its receipt", out_ok == len(receipts), "%d of %d" % (out_ok, len(receipts)))
print("== 2. each receipt describes the response it belongs to")
rows = []; c = dict(id=0, url=0, hash=0, length=0, sha1=0, pol=0, code=0, status=0, tls=0, auth=0, dates=0, host=0, strict=0); unauth = {}; pairs = []
code_want = None
if jobf and os.path.exists(jobf):
    m = re.search(r"^job: ([0-9a-f]{16})", open(jobf, errors="replace").read(), re.M)
    code_want = m.group(1) if m else None
for d, (ln, r, att) in sorted(receipts.items(), key=lambda kv: kv[1][1]["source_url"]):
    h, body, kind = resp.get(d, (None, None, None))
    if h is None: bad.append("receipt without a response: " + d); continue
    head, _, payload = body.partition(b"\r\n\r\n"); st = int(re.match(rb"HTTP/\S+ (\d+)", head).group(1))
    c["id"] += r["document_id"] == "urn:uuid:" + d.split(":")[-1]; c["url"] += r["source_url"] == h["WARC-Target-URI"]
    c["hash"] += r["raw_content_hash"] == sha(payload); c["length"] += r["raw_content_length"] == len(payload)
    c["sha1"] += h.get("WARC-Payload-Digest") == "sha1:" + base64.b32encode(hashlib.sha1(payload).digest()).decode()
    c["pol"] += r["collection_policy_hash"] == pol_hash; c["code"] += (code_want is None) or r["code_hash"].startswith("sha256:" + code_want)
    c["status"] += r["http_status"] == st == 200; s = r["server"]; v = s.get("validation", {})
    c["tls"] += bool(s.get("finished_verified")) and s.get("protocol", "").startswith("TLS") and s["leaf_sha256"] == s["chain_sha256"][0]
    ts = datetime.strptime(h["WARC-Date"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp(); nb, na = s["chain_validity"][0]["not_before"], s["chain_validity"][0]["not_after"]
    honest, labels_ok, strict_ok, why = evaluate(v, s, oc_by_doc[d]["source_authenticated"], ts); c["auth"] += honest; c["dates"] += labels_ok; c["strict"] += strict_ok; pairs.append((v.get("chain"), v.get("hostname")))
    if why: unauth[why] = unauth.get(why, 0) + 1
    c["host"] += s["hostname"] == re.match(r"https://([^/:]+)", r["source_url"]).group(1)
    rows.append((r["source_url"], len(payload), "yes" if r["raw_content_hash"] == sha(payload) else "NO"))
n = len(receipts)
for k, label in (("id", "the receipt names its response (document id equals the WARC record id)"), ("url", "the receipt's URL is the response's URL"), ("hash", "raw_content_hash is the SHA-256 of the payload of the response"), ("length", "raw_content_length is the length of that payload"),
                 ("sha1", "the WARC's own payload digest (SHA-1, base32) is right for that payload"), ("pol", "collection_policy_hash is the SHA-256 of the exported collection-policy.json"), ("code", "code_hash is the job's (%s)" % ("job console: " + code_want if code_want else "not checked: no job console given")),
                 ("status", "http_status is 200 and is the status line of the response"), ("tls", "the TLS facts are complete (handshake Finished verified, a TLS protocol, the leaf is the first of the chain)"), ("auth", "the authentication of each receipt is honest: its flag equals the result of its own chain and hostname facts, the outcome says the same, and an authenticated receipt has certificate dates that enclose the fetch"),
                 ("dates", "the labels of each receipt's validation (chain valid, expired, not_yet_valid or untrusted; hostname match or mismatch) agree with its own facts and with the certificate dates"), ("host", "the hostname of the receipt is the host of the URL")): check(label, c[k] == n, "%d of %d" % (c[k], n))
nu = sum(unauth.values()); print("   info: %d of %d receipts record a source that was not authenticated%s" % (nu, n, (": " + ", ".join("%s %d" % kv for kv in sorted(unauth.items(), key=lambda x: (-x[1], x[0])))) if nu else ""))
cells, other = matrix(pairs); [print("   info: " + ln) for ln in matrix_lines(cells, other)]
if strict_on: check("strict mode (--strict, or TC_REQUIRE_AUTHENTICATED=1): every receipt is authenticated, with a valid chain, a hostname match and certificate dates that enclose the fetch", c["strict"] == n, "%d of %d" % (c["strict"], n))
print("   the receipted pages:"); [print("      %-40s %7d bytes  payload hash matches: %s" % r) for r in rows]
print("== 3. every outcome is accounted for")
st = {}; 
for (u, d), o in outcomes.items(): st.setdefault(o["status"], []).append((u, o["detail"], d in receipts))
for k, v in sorted(st.items()): print("   %-11s %d: %s" % (k, len(v), "; ".join("%s (%s)" % (u.replace("https://", "")[:30], dt[:24]) for u, dt, _ in v[:4])))
check("every ACCEPTED outcome has a receipt, and no other outcome has one", all(x[2] for x in st.get("ACCEPTED", [])) and not any(x[2] for k, v in st.items() if k != "ACCEPTED" for x in v))
check("every response record WITH a receipt is an ACCEPTED outcome, and the responses without one are the others", len(receipts) == len(st.get("ACCEPTED", [])))
print("== 4. the signed time readings (Roughtime): structure and the window around the fetches; the signature is NOT verified here")
def parse_rt(b):
    assert b[:8] == b"ROUGHTIM"; ln = struct.unpack("<I", b[8:12])[0]; msg = b[12:12 + ln]
    def msg_tags(m):
        nt = struct.unpack("<I", m[:4])[0]; hdr = 4 + 4 * (nt - 1) + 4 * nt; offs = [0] + list(struct.unpack("<%dI" % (nt - 1), m[4:4 + 4 * (nt - 1)])); names = [m[4 + 4 * (nt - 1) + 4 * i: 8 + 4 * (nt - 1) + 4 * i] for i in range(nt)]
        vals = {}
        for i, nme in enumerate(names): end = offs[i + 1] if i + 1 < nt else len(m) - hdr; vals[nme] = m[hdr + offs[i]: hdr + end]
        return vals
    top = msg_tags(msg); srep = msg_tags(top[b"SREP"]); return struct.unpack("<Q", srep[b"MIDP"])[0], struct.unpack("<I", srep[b"RADI"])[0], top
by_att = {}
for t in times:
    try:
        mid, rad, top = parse_rt(base64.b64decode(t["response"]))
        u = 1e6 if mid > 1e12 else 1   # Google's Roughtime counts microseconds, the IETF version (Cloudflare's server) seconds
        by_att.setdefault(t["attempt"], {})[t["phase"]] = (mid / u, rad / u, t)
    except Exception as e: bad.append("time reading cannot be parsed: %s" % e)
ok = 0; nwin = 0
for att, ph in sorted(by_att.items()):
    if "start" in ph and "end" in ph:
        ok += ph["start"][0] <= ph["end"][0]
        fetch = [datetime.strptime(resp[d][0]["WARC-Date"], "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp() for d, (ln, r, a) in receipts.items() if a == att and d in resp]
        nwin += all(ph["start"][0] - ph["start"][1] - 2 <= x <= ph["end"][0] + ph["end"][1] + 2 for x in fetch)
check("every task has a start and an end reading, each a Roughtime message that parses, with the start not after the end", len(by_att) > 0 and ok == len(by_att) and all("start" in p and "end" in p for p in by_att.values()), "%d tasks" % len(by_att))
check("the WARC date of every receipted fetch lies between the start and the end reading of its task (plus their radii and 2 s)", nwin == len(by_att), "%d of %d tasks" % (nwin, len(by_att)))
for att, ph in sorted(by_att.items())[:3]: print("      %s: start %s +-%.1fs, end %s +-%.1fs (server %s)" % (att[-24:], datetime.fromtimestamp(ph["start"][0], timezone.utc).strftime("%H:%M:%S"), ph["start"][1], datetime.fromtimestamp(ph["end"][0], timezone.utc).strftime("%H:%M:%S"), ph["end"][1], ph["start"][2]["server"]))
print(); print("RECEIPT-VERIFY-OK" if not bad else "RECEIPT-VERIFY-PROBLEMS (%d): %s" % (len(bad), "; ".join(bad[:5]))); sys.exit(0 if not bad else 1)
