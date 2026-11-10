#!/usr/bin/env python3
"""Test of run_tls_breakdown.py on a synthetic crawl with one outcome for every case: the counts must be the hand-counted ones, the cases must add up to the total, the plain-http rule must come first, and both pie charts must be valid XML. Prints TLS-BREAKDOWN-TEST-OK."""
import json, os, subprocess, sys, tempfile, xml.dom.minidom, collections
HERE = os.path.dirname(os.path.abspath(__file__)); T = tempfile.mkdtemp(); E = os.path.join(T, "evidence-tbtest-f"); seg = os.path.join(E, "export", "tc", "crawl", "segments", "20260101000000", "tc_receipts"); os.makedirs(seg)
def rc(url, auth, chain, host): return {"source_url": url, "server": {"protocol": "TLSv1.3", "cipher_suite": "TLS_AES_256_GCM_SHA384", "validation": {"authenticated": auth, "chain": chain, "hostname": host}}}
OUT = []; REC = []; WANT = collections.Counter()
def add(url, status, detail, case, receipt=None):
    OUT.append({"source_url": url, "status": status, "detail": detail}); WANT[case] += 1
    if receipt: REC.append(receipt)
for i in range(5): u = "https://ok%d.example/" % i; add(u, "ACCEPTED", "", "A", rc(u, True, "valid", "match"))
u = "https://exp.example/"; add(u, "ACCEPTED", "", "B1", rc(u, False, "expired", "match")); u = "https://exp2.example/"; add(u, "ACCEPTED", "", "B1", rc(u, False, "expired", "match"))
u = "https://expmis.example/"; add(u, "ACCEPTED", "", "B2", rc(u, False, "expired", "mismatch")); u = "https://mis.example/"; add(u, "ACCEPTED", "", "B3", rc(u, False, "valid", "mismatch"))
u = "https://untr.example/"; add(u, "ACCEPTED", "", "B4", rc(u, False, "untrusted", "match")); u = "https://untrmis.example/"; add(u, "ACCEPTED", "", "B5", rc(u, False, "untrusted", "mismatch")); u = "https://odd.example/"; add(u, "ACCEPTED", "", "B6", rc(u, False, "valid", "match"))
add("http://plain1.example/", "NOT_HTTPS", "not https", "C"); add("http://plain2.example/", "NOT_HTTPS", "not https", "C"); add("http://redir.example/", "HTTP_STATUS", "301", "C"); add("http://idle.example/", "NOT_ATTEMPTED", "task timeout", "C")
add("https://tls.example/", "NOT_FETCHED", "fetch_retry exception(16), lastModified=0: javax.net.ssl.SSLException: Received fatal alert: internal_error", "D")
add("https://dns.example/", "NOT_FETCHED", "fetch_retry exception(16), lastModified=0: java.net.UnknownHostException: dns.example", "E1"); add("https://slow.example/", "NOT_FETCHED", "fetch_retry exception(16), lastModified=0: java.net.SocketTimeoutException: connect timed out", "E1")
add("https://e403.example/", "NOT_FETCHED", "fetch_retry exception(16), lastModified=0: Http code=403, url=https://e403.example/", "E2"); add("https://robots.example/", "NOT_FETCHED", "fetch_gone robots_denied(18), lastModified=0", "E3")
add("https://gone.example/", "NOT_FETCHED", "fetch_gone notfound(14), lastModified=0: https://gone.example/", "E4"); add("https://redir.example/", "HTTP_STATUS", "301", "E5"); add("https://big.example/", "TRUNCATED", "content reached http.content.limit; possibly truncated", "E6")
add("https://idle2.example/", "NOT_ATTEMPTED", "task timeout", "E7"); add("https://weird.example/", "NOT_FETCHED", "something else entirely", "E8")
open(os.path.join(seg, "outcomes-attempt_1_0001_m_000000_0.jsonl"), "w").write("\n".join(json.dumps(o) for o in OUT) + "\n"); open(os.path.join(seg, "receipts-attempt_1_0001_m_000000_0.jsonl"), "w").write("\n".join(json.dumps(r) for r in REC) + "\n")
p = subprocess.run([sys.executable, "-B", os.path.join(HERE, "run_tls_breakdown.py"), E, "--run-name", "Test_Run_TLS_Test"], capture_output=True, text=True); j = json.load(open(os.path.join(E, "Test_Run_TLS_Test_tls_breakdown.json")))
bad = []
def chk(name, ok):
    print("   %s %s" % ("ok:  " if ok else "FAIL:", name)); 
    if not ok: bad.append(name)
chk("the tool ended with TLS-BREAKDOWN-DONE", "TLS-BREAKDOWN-DONE" in p.stdout and p.returncode == 0)
chk("every case has the hand-counted number: %s" % dict(WANT), {c: n for c, n in j["cases"].items() if n} == dict(WANT))
chk("the cases add up to the total of %d outcomes" % len(OUT), sum(j["cases"].values()) == len(OUT) == j["outcomes_total"])
chk("a plain http URL is C whatever its status (NOT_HTTPS, a redirect and never attempted: 4 in all)", j["cases"]["C"] == 4)
chk("an https URL that was never attempted is E7 and not C", j["cases"]["E7"] == 1)
chk("the HTTPS pages with a receipt are 5 + 7 = 12", j["https_pages_with_receipt"] == 12)
chk("the 7 sources that were not authenticated are listed with their case", len(j["not_authenticated_hosts"]) == 7 and {h["case"] for h in j["not_authenticated_hosts"]} == {"B1", "B2", "B3", "B4", "B5", "B6"})
chk("the protocol versions are counted for the 12 receipted pages", j["tls_protocols"] == {"TLSv1.3": 12})
for s in ("_all_outcomes.svg", "_https_pages.svg"):
    try: xml.dom.minidom.parse(os.path.join(E, "Test_Run_TLS_Test_tls_breakdown" + s)); ok = True
    except Exception: ok = False
    chk("the pie chart %s is valid XML" % s, ok)
csv = open(os.path.join(E, "Test_Run_TLS_Test_tls_breakdown.csv")).read().strip().split("\n"); chk("the CSV has a header and one line per case (%d)" % (len(csv) - 1), len(csv) == 18 and csv[0].startswith("case,group"))
print("TLS-BREAKDOWN-TEST-OK" if not bad else "TLS-BREAKDOWN-TEST-FAILED: %s" % bad); sys.exit(1 if bad else 0)
