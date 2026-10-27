#!/usr/bin/env python3
"""The collection policy that every source receipt names (its SHA-256 is each receipt's collection_policy_hash).
Made by tc-crawl.sh before the crawl, from measured things only: the JDK's CA store (the measured items jdk and java-ca-fingerprints), whose anchors the receipt
emitter uses and checks against this policy at start-up (it refuses to run if they differ), and the fixed text below (in the measured folder tc-lib). So the
policy needs no measured event of its own: the same image always makes the same policy, and the export carries it (collection-policy.json) for the consumer.
Same content as make_policy.py in training-custody source-provenance/ccbot (deployment: the fleet), except for one value: since 27 October 2026 file_sha256 is the hash of the keytool text WITHOUT its
"Creation date" lines. Those lines hold the day on which the JDK's store was generated on the machine (found by comparing builds of two different days: the same 120 certificates, a different policy), so a
rebuild on another day made another policy, another tc-conf and another reference. make_policy.py must drop the same lines for the two to give one policy on one machine. Canonical JSON (tc-canonical-json/1).
    tc-policy.py KEYTOOL OUT.json"""
import base64, hashlib, json, re, subprocess, sys

keytool, out = sys.argv[1:3]
pem = subprocess.run([keytool, "-list", "-rfc", "-cacerts", "-storepass", "changeit"], check=True, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL).stdout
ders = sorted({hashlib.sha256(base64.b64decode(b"".join(b.split()))).hexdigest() for b in re.findall(rb"-----BEGIN CERTIFICATE-----(.*?)-----END CERTIFICATE-----", pem, re.S)})
if not ders: sys.exit("tc-policy: no CA certificates in the JDK store")
# the day of the build must not reach the policy: drop exactly the lines "Creation date: ..." (the aliases, the entry types and the certificates stay in the hash)
text = re.sub(rb"(?m)^Creation date:[^\n]*\n", b"", pem)
enc = lambda v: json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False, allow_nan=False).encode("utf-8")
sha = lambda b: "sha256:" + hashlib.sha256(b).hexdigest()
client = "protocol-okhttp"
policy = {
    "version": 2,
    "collection_id": "ccbot-https-get-v0",
    "receipt_version": "tc-source-receipt/2",
    "outcome_version": "tc-fetch-outcome/2",
    "collector": "commoncrawl/nutch cc@3270a761e + source-receipt patch, " + client + ", the fleet (locked image, attested HDFS wrapper, receipts in the task output)",
    "artifact_definition": "ccbot-warc-response-payload/v1: Content.getContent() handed to WarcCapture; de-chunked, content-decoded (gzip/deflate best-effort); "
                           "no receipt if length >= http.content.limit or flagged truncated",
    "tls": {"validation": "post-handshake PKIX (CertPathBuilder, revocation off) + DNS-SAN hostname match, in the fetcher JVM, under the anchors below",
            "result": "recorded in the receipt (server.validation: chain valid / expired / not_yet_valid / untrusted, hostname match / mismatch); not a reason "
                      "to refuse unless tc.receipts.require.authenticated=true",
            "handshake": "JSSE (SunJSSE) completed handshake; CertificateVerify and Finished verified by JSSE",
            "facts": "recorded by the protocol plugin after the whole response is read; any server header named _tc_* is dropped first",
            "versions": "as negotiated; recorded per receipt",
            "sni_fallback": "no receipt"},
    "request": {"method": "GET", "template": client + " defaults (CCBot configuration)"},
    "require": {"http_status": 200},
    "time": "signed Roughtime readings at the start and end of each fetch task (tc-time-evidence/1)",
    "trust_anchors": {"source": "JDK cacerts (keytool -list -rfc -cacerts)", "count": len(ders), "anchor_set_sha256": sha(enc(ders)), "file_sha256": sha(text)},
}
open(out, "wb").write(enc(policy))
print("policy %s, %d anchors" % (sha(enc(policy)), len(ders)))
