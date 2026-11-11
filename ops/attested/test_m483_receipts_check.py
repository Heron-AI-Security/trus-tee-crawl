#!/usr/bin/env python3
"""Tests m483_receipts_check.py with small exports that the test builds itself, in both layouts (WARC files per segment with nonce, policy.json and an unattested binding; the full export with shared WARC files, collection-policy.json and the fleet binding). Honest receipts must pass (a source that was not authenticated is a recorded outcome); lying receipts, a wrong nonce, tampered content, a missing or mixed binding, a protocol that is not TLS 1.2 or 1.3 and a missing policy file must be refused; --strict must refuse every receipt that is not authenticated.
   python3 test_m483_receipts_check.py     -> M483-CHECK-TEST-OK: N cases   (exit 0), or a line per wrong case and M483-CHECK-TEST-FAILED (exit 1)"""
import gzip, hashlib, json, os, re, subprocess, sys, tempfile
from datetime import datetime, timezone
HERE = os.path.dirname(os.path.abspath(__file__)); SCRIPT = os.path.join(HERE, "m483_receipts_check.py")
JOB = hashlib.sha256(b"the job file of the test").hexdigest(); WDATE = "2026-11-05T18:00:00Z"; TS = datetime.strptime(WDATE, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc).timestamp()
sha = lambda b: hashlib.sha256(b).hexdigest()
KINDS = {  # kind: (flag in the receipt, chain label, hostname label, chain_valid, hostname_matches, certificate dates relative to the fetch, flag in the signed outcome)
    "ok": (True, "valid", "match", True, True, [(-1000, 1000)], True),
    "expired": (False, "expired", "match", False, True, [(-1000, -10)], False),
    "nyv": (False, "not_yet_valid", "match", False, True, [(10, 1000)], False),
    "mismatch": (False, "valid", "mismatch", True, False, [(-1000, 1000)], False),
    "lie": (True, "expired", "match", False, True, [(-1000, -10)], True),
    "outcome_differs": (True, "valid", "match", True, True, [(-1000, 1000)], False)}
def build(root, layout, kinds, nonce=None, policy="collection-policy.json", binding="tc-fleet-rtmr3/1", tamper=None, protos=None, bindings=None):
    pol = b'{"policy": "test"}\n'; polhash = "sha256:" + sha(pol); seg = "20261105180000"
    if layout == "current": segdir = os.path.join(root, "tc", "crawl", "segments", seg); warcdir = os.path.join(root, "tc", "warc", "warc")
    else: segdir = os.path.join(root, seg); warcdir = os.path.join(segdir, "warc")
    for d in (os.path.join(segdir, "tc_receipts"), warcdir): os.makedirs(d)
    if policy: open(os.path.join(root, policy), "wb").write(pol)
    if nonce: open(os.path.join(root, "nonce"), "w").write(nonce + "\n")
    rl, ol, wb = [], [], b""
    for i, k in enumerate(kinds):
        auth, ch, ho, cv, hm, dates, oflag = KINDS[k]; url = "https://h%d.example/" % i; payload = (b"page %d " % i) * 6; doc = "00000000-0000-4000-8000-%012d" % i
        r = {"binding": {"type": (bindings[i] if bindings else binding)}, "code_hash": "sha256:" + JOB, "collection_policy_hash": polhash, "document_id": "urn:uuid:" + doc, "http_status": 200, "nonce": nonce, "raw_content_hash": "sha256:" + sha(payload), "raw_content_length": len(payload), "source_url": url, "version": "tc-source-receipt/2",
             "server": {"protocol": (protos[i % len(protos)] if protos else "TLSv1.3"), "chain_valid": cv, "hostname_matches": hm, "chain_validity": [{"not_before": TS + a, "not_after": TS + b} for a, b in dates], "validation": {"authenticated": auth, "chain": ch, "hostname": ho}}}
        if tamper == "content" and i == 0: r["raw_content_hash"] = "sha256:" + sha(b"something else")
        if tamper == "wrong_nonce" and i == 0: r["nonce"] = "other"
        if tamper == "no_binding" and i == 0: del r["binding"]
        line = json.dumps(r, sort_keys=True); rl.append(line)
        ol.append(json.dumps({"detail": "", "document_id": "urn:uuid:" + doc, "nonce": nonce, "receipt_sha256": "sha256:" + sha(line.encode()), "source_authenticated": oflag, "source_url": url, "status": "ACCEPTED", "version": "tc-outcome/1"}, sort_keys=True))
        body = b"HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n\r\n" + payload
        wb += gzip.compress(("WARC/1.0\r\nWARC-Type: response\r\nWARC-Target-URI: %s\r\nWARC-Record-ID: <urn:uuid:%s>\r\nWARC-Date: %s\r\nContent-Length: %d\r\n\r\n" % (url, doc, WDATE, len(body))).encode() + body + b"\r\n\r\n")
    open(os.path.join(segdir, "tc_receipts", "receipts-attempt_1.jsonl"), "w").write("\n".join(rl) + "\n"); open(os.path.join(segdir, "tc_receipts", "outcomes-attempt_1.jsonl"), "w").write("\n".join(ol) + "\n")
    open(os.path.join(warcdir, "crawl-00000.warc.gz"), "wb").write(wb)
def run(layout, kinds, extra=(), **kw):
    with tempfile.TemporaryDirectory() as t:
        build(t, layout, kinds, **kw); p = subprocess.run([sys.executable, "-B", SCRIPT, t, JOB] + list(extra), capture_output=True, text=True); return p.stdout + p.stderr
bad = []; n = [0]
def chk(name, ok):
    n[0] += 1; print("   %s %s" % ("ok:  " if ok else "FAIL:", name))
    if not ok: bad.append(name)
def row(out, cls): m = re.search(r"^\s+%s\s+(\d+)\s+(\d+)\s+(\d+)\s*$" % cls, out, re.M); return tuple(int(x) for x in m.groups()) if m else None
CLEAN, FIND = "RECEIPTS-CHECK-CLEAN", "RECEIPTS-CHECK-FINDINGS"
print("== honest receipts (current layout): they pass, and a source that was not authenticated is a recorded outcome")
o = run("current", ["ok", "ok", "ok"]); chk("three authenticated receipts: clean, 0 of 3 not authenticated", CLEAN in o and "not authenticated: 0 of 3" in o)
o = run("current", ["ok", "expired", "mismatch"]); chk("one expired and one hostname mismatch: still clean, 2 of 3 recorded as not authenticated", CLEAN in o and "not authenticated: 2 of 3" in o)
chk("the table has expired/match 1 and valid 1 match, 1 mismatch", row(o, "expired") == (1, 0, 1) and row(o, "valid") == (1, 1, 2) and row(o, "total") == (2, 1, 3))
o = run("current", ["ok", "nyv"]); chk("a not yet valid chain (honest): clean, and the table names it", CLEAN in o and row(o, "not_yet_valid") == (1, 0, 1))
o = run("current", ["ok"] * 5, protos=["TLSv1.3", "TLSv1.2", "TLSv1.3"]); chk("receipts with TLS 1.2 and TLS 1.3 together: clean, both counted (3 and 2 here)", CLEAN in o and re.search(r"TLS protocol TLSv1\.3\s+3\b", o) is not None and re.search(r"TLS protocol TLSv1\.2\s+2\b", o) is not None)
print("== --strict restores the old rule")
o = run("current", ["ok", "expired", "mismatch"], ["--strict"]); chk("--strict refuses the receipts that are not authenticated", FIND in o and "strict: the source was not authenticated (expired chain)" in o)
o = run("current", ["ok", "ok"], ["--strict"]); chk("--strict passes when every receipt is authenticated", CLEAN in o)
print("== the old layout of step 4.8.3 (WARC files per segment, nonce, policy.json, unattested binding)")
o = run("legacy", ["ok", "expired"], nonce="n1", policy="policy.json", binding="unattested"); chk("the old layout is clean, with its nonce and policy.json", CLEAN in o and "not authenticated: 1 of 2" in o)
o = run("legacy", ["ok", "ok"], nonce="n1", policy="policy.json", binding="unattested", tamper="wrong_nonce"); chk("a receipt with a wrong nonce is refused", FIND in o and "nonce differs" in o)
print("== mutants: what must be refused")
o = run("current", ["ok", "lie"]); chk("a receipt that claims authentication that its own facts deny", FIND in o and "not honest" in o)
o = run("current", ["ok", "outcome_differs"]); chk("a receipt whose signed outcome says the opposite", FIND in o and "not honest" in o)
o = run("current", ["ok", "ok"], tamper="content"); chk("a content hash that is not the page in the WARC", FIND in o and "content hash or length differs" in o)
o = run("current", ["ok", "ok"], binding="tc-custom/1"); chk("a binding type that the check does not know is a setting of the crawl, not a failure (it is reported)", CLEAN in o and "binding type tc-custom/1" in o)
o = run("current", ["ok", "ok"], bindings=["tc-fleet-rtmr3/1", "unattested"]); chk("receipts of one run with different binding types are refused", FIND in o and "different binding types" in o)
o = run("current", ["ok", "ok"], tamper="no_binding"); chk("a receipt without a binding type is refused", FIND in o and "no binding type" in o)
o = run("current", ["ok"], protos=["TLSv1.1"]); chk("a protocol that is not TLS 1.2 or 1.3 is refused", FIND in o and "protocol TLSv1.1" in o)
o = run("current", ["ok"], policy=None); chk("an export without any policy file", FIND in o and "neither policy.json nor collection-policy.json" in o)
REAL = ["ok"] * 653 + ["mismatch"] * 2 + ["expired"] * 9 + ["untrusted_like_expired"] * 1 + ["expired_mismatch"] * 1   # the size and the mix of the real 1K run: 666 receipts, 13 not authenticated
KINDS["untrusted_like_expired"] = (False, "untrusted", "match", False, True, [(-1000, 1000)], False); KINDS["expired_mismatch"] = (False, "expired", "mismatch", False, False, [(-1000, -10)], False)
PROTOS = ["TLSv1.3"] * 12 + ["TLSv1.2"]   # about 613 of 666 are TLS 1.3 and 53 are TLS 1.2
print("== a run of the size and the mix of the real 1K run (666 receipts, about 8 percent TLS 1.2, 13 not authenticated)")
o = run("current", REAL, protos=PROTOS); chk("default: clean, 666 receipts, 13 not authenticated, both TLS versions counted", CLEAN in o and re.search(r"^  receipts\s+666$", o, re.M) is not None and "not authenticated: 13 of 666" in o and "TLS protocol TLSv1.2" in o and "TLS protocol TLSv1.3" in o)
o = run("current", REAL, ["--strict"], protos=PROTOS); chk("--strict: findings for exactly the 13 receipts that are not authenticated", "RECEIPTS-CHECK-FINDINGS (13)" in o and "problems by kind (13 in all" in o)
o = run("current", ["ok", "lie", "lie"]); chk("the report summarises its problems by kind (2 receipts that lie)", FIND in o and "problems by kind (2 in all" in o)
p = subprocess.run([sys.executable, "-B", SCRIPT, "only-one-argument"], capture_output=True, text=True); chk("a call without the job hash is a usage error (exit 2)", p.returncode == 2 and "usage" in p.stdout)
print(("M483-CHECK-TEST-OK: %d cases" % n[0]) if not bad else "M483-CHECK-TEST-FAILED: %s" % bad); sys.exit(1 if bad else 0)
