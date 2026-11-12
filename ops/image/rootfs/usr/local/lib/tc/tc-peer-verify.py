#!/usr/bin/env python3
"""Mutual attestation at fleet start: this node verifies the announcement of every OTHER node of fleet.tsv before it accepts that node as a WireGuard peer.
    tc-peer-verify.py OWN_ANNOUNCE FLEET_TSV PEERS_JSON OUT_PEERS
OWN_ANNOUNCE is this node's own announcement (attr-announce.txt), FLEET_TSV the fleet list, PEERS_JSON the instance metadata tc-fleet-quotes ({node name: announcement text},
set by the operator next to tc-fleet). The operator only carries the announcements: it cannot make one, so it cannot add a node that the checks below refuse. For every other row:
  P0  the quote is a TDX v4 ECDSA quote signed by Intel: PCK chain to the pinned Intel SGX Root CA (openssl verify, validity at this VM's clock), the QE report signed by the PCK
      key and binding the attestation key, the quote signed by the attestation key (the checks of the consumer's rule E0, with openssl instead of a Python library)
  P1  the announcement is the row's: same name, same signing key, same WireGuard key
  P2  REPORTDATA = SHA-512 of the binding text; the log is the one hashed in it and replays to the quote's RTMR3
  P3  the same TD as this node: MRTD, RTMR0 to RTMR2, TD attributes and XFAM equal this node's own quote (so the debug bit is off, as it is here), and the log has the same events
      with the same digests (the same measured image; at announce time the log holds the stable events only)
OUT_PEERS (written only if every peer passes) has one line per peer, sorted: name, TAB, SHA-256 of its quote, for the log. No RTMR3 event is needed: this file is in the
verified root (its root hash is in RTMR2, which P3 requires to be equal to this node's own), so a node whose log reaches fleet-conf has passed these checks. Not checked: Intel's collateral (TCB status, revocation lists), which needs Intel's online
service, and the certificates' validity is judged by this VM's clock. Ends with TC-PEERS-OK n or TC-PEERS-FAIL (exit code 1)."""
import base64, hashlib, json, os, re, struct, subprocess, sys, tempfile
#: SHA-256 of the DER of "CN=Intel SGX Root CA, O=Intel Corporation" (valid 2018-05-21 to 2049-12-31), as in the consumer's verifier (custody/tdx_quote.py)
INTEL_SGX_ROOT_CA_SHA256 = "44a0196b2b99f889b8e149e95b807a350e7424964399e885a7cbb8ccfab674d3"
BODY_END = 632
OFF = {"mrtd": (184, 232), "rtmr0": (376, 424), "rtmr1": (424, 472), "rtmr2": (472, 520), "rtmr3": (520, 568), "tdattr": (168, 176), "xfam": (176, 184)}; REPORTDATA = (568, 632)
P256_SPKI = bytes.fromhex("3059301306072a8648ce3d020106082a8648ce3d030107034200")  # the DER prefix of a P-256 public key; then 04 || X || Y

class PeerError(Exception): pass

def announcement(text):
    d = {}
    for line in text.splitlines():
        if "=" in line: k, v = line.split("=", 1); d[k] = v
    miss = [k for k in ("name", "sign", "wg", "log_sha512", "quote_b64", "log_b64") if k not in d]
    if miss: raise PeerError("the announcement lacks " + ", ".join(miss))
    return d

def der_int(b):
    b = b.lstrip(b"\0") or b"\0"
    if b[0] & 0x80: b = b"\0" + b
    return b"\x02" + bytes([len(b)]) + b

def ecdsa_der(rs):  # a raw 64-byte r || s signature as the DER that openssl reads
    body = der_int(rs[:32]) + der_int(rs[32:])
    return b"\x30" + bytes([len(body)]) + body

def pem(der, kind): return ("-----BEGIN %s-----\n%s\n-----END %s-----\n" % (kind, base64.encodebytes(der).decode().strip(), kind)).encode()

def run(args, what):
    r = subprocess.run(["openssl"] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if r.returncode != 0:
        last = (r.stderr.decode(errors="replace").strip().splitlines() or ["openssl failed"])[-1]
        raise PeerError("%s: %s" % (what, last[:120]))
    return r.stdout

def verify_sig(tmp, pub_pem, sig_rs, data, what):
    for name, b in (("pub.pem", pub_pem), ("sig.der", ecdsa_der(sig_rs)), ("data.bin", data)):
        with open(os.path.join(tmp, name), "wb") as f: f.write(b)
    run(["dgst", "-sha256", "-verify", os.path.join(tmp, "pub.pem"), "-signature", os.path.join(tmp, "sig.der"), os.path.join(tmp, "data.bin")], what)

def check_intel(q):
    """P0: the quote is a TDX v4 ECDSA quote that Intel's chain signs."""
    try:
        version, key_type = struct.unpack_from("<HH", q, 0); tee_type = struct.unpack_from("<I", q, 4)[0]
        if version != 4 or key_type != 2 or tee_type != 0x81: raise PeerError("not a TDX v4 ECDSA quote")
        sig_len = struct.unpack_from("<I", q, BODY_END)[0]; sd = q[BODY_END + 4:BODY_END + 4 + sig_len]
        if len(sd) != sig_len or any(q[BODY_END + 4 + sig_len:]): raise PeerError("the quote's length is wrong or it has trailing bytes")
        quote_sig, att_key = sd[:64], sd[64:128]
        cert_type, cert_size = struct.unpack_from("<HI", sd, 128)
        if cert_type != 6: raise PeerError("the quote has no QE report certification data")
        qe = sd[134:134 + cert_size]; qe_report, qe_sig = qe[:384], qe[384:448]
        auth_len = struct.unpack_from("<H", qe, 448)[0]; auth = qe[450:450 + auth_len]; inner = qe[450 + auth_len:]
        ptype, psize = struct.unpack_from("<HI", inner, 0)
        if ptype != 5: raise PeerError("the quote has no PCK certificate chain")
        pems = re.findall(rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", inner[6:6 + psize], re.S)
    except PeerError: raise
    except (struct.error, IndexError) as e: raise PeerError("the quote is malformed (%s)" % e)
    if len(pems) < 2: raise PeerError("the PCK chain is too short")
    root_der = base64.b64decode(b"".join(pems[-1].split(b"\n")[1:-1]))
    if hashlib.sha256(root_der).hexdigest() != INTEL_SGX_ROOT_CA_SHA256: raise PeerError("the chain does not end at the Intel SGX Root CA")
    with tempfile.TemporaryDirectory(dir="/run/tc" if os.path.isdir("/run/tc") else None) as tmp:
        paths = {}
        for name, b in (("root.pem", pems[-1] + b"\n"), ("inter.pem", b"\n".join(pems[1:-1]) + b"\n"), ("leaf.pem", pems[0] + b"\n")):
            paths[name] = os.path.join(tmp, name)
            with open(paths[name], "wb") as f: f.write(b)
        args = ["verify", "-x509_strict", "-CAfile", paths["root.pem"]] + (["-untrusted", paths["inter.pem"]] if len(pems) > 2 else []) + [paths["leaf.pem"]]
        run(args, "the PCK chain does not verify to the Intel SGX Root CA")
        pck_pub = run(["x509", "-in", paths["leaf.pem"], "-pubkey", "-noout"], "cannot read the PCK public key")
        verify_sig(tmp, pck_pub, qe_sig, qe_report, "the QE report is not signed by the PCK key")
        if qe_report[320:352] != hashlib.sha256(att_key + auth).digest() or any(qe_report[352:384]): raise PeerError("the QE report does not bind the attestation key")
        verify_sig(tmp, pem(P256_SPKI + b"\x04" + att_key, "PUBLIC KEY"), quote_sig, q[:BODY_END], "the quote is not signed by the attestation key")

def events(d, q):
    """P2: the binding, the log and its replay to RTMR3. Returns the events as (name, digest)."""
    binding = ("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"])).encode()
    if q[REPORTDATA[0]:REPORTDATA[1]] != hashlib.sha512(binding).digest(): raise PeerError("REPORTDATA is not the SHA-512 of the binding (name, keys, log)")
    log = base64.b64decode(d["log_b64"])
    if hashlib.sha512(log).hexdigest() != d["log_sha512"]: raise PeerError("the log is not the one hashed in the binding")
    reg = bytes(48); out = []
    for line in log.decode(errors="replace").splitlines():
        parts = line.split("\t")
        if len(parts) != 4: raise PeerError("a line of the log is malformed")
        name, digest, before, after = parts
        try:
            if bytes.fromhex(before) != reg: raise PeerError("event %s does not start from the previous register" % name)
            reg = hashlib.sha384(reg + bytes.fromhex(digest)).digest()
        except ValueError: raise PeerError("event %s has a digest that is not hexadecimal" % name)
        if reg.hex() != after: raise PeerError("event %s does not replay" % name)
        out.append((name, digest))
    if reg != q[OFF["rtmr3"][0]:OFF["rtmr3"][1]]: raise PeerError("the log does not replay to the quote's RTMR3")
    return out

def check_peer(row, d, own_q, own_events):
    q = base64.b64decode(d["quote_b64"])
    if len(q) < BODY_END: raise PeerError("a quote of %d bytes is too short" % len(q))
    check_intel(q)
    name, _, _, _, sign, wg = row
    if (d["name"], d["sign"], d["wg"]) != (name, sign, wg): raise PeerError("the announcement's name or keys are not the ones of its row in fleet.tsv")
    ev = events(d, q)
    for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2", "tdattr", "xfam"):
        a, b = OFF[k]
        if q[a:b] != own_q[a:b]: raise PeerError("its %s %s... differs from this node's %s..." % (k, q[a:b].hex()[:12], own_q[a:b].hex()[:12]))
    if own_q[OFF["tdattr"][0]] & 1: raise PeerError("this node itself runs with the TD debug bit on")
    if ev != own_events: raise PeerError("its measured events differ from this node's (%s)" % ", ".join(sorted({n for n, _ in set(ev) ^ set(own_events)}))[:120])
    return hashlib.sha256(q).hexdigest()

def main():
    if len(sys.argv) != 5: sys.exit(__doc__)
    own_path, fleet_path, peers_path, out_path = sys.argv[1:5]
    try:
        own = announcement(open(own_path, encoding="utf-8").read()); own_q = base64.b64decode(own["quote_b64"]); own_events = events(own, own_q)
    except (OSError, PeerError) as e: print("TC-PEERS-FAIL: this node's own announcement: %s" % e); sys.exit(1)
    rows = [l.split("\t") for l in open(fleet_path, encoding="utf-8").read().splitlines() if l and not l.startswith("#")]
    try: peers = json.load(open(peers_path, encoding="utf-8"))
    except (OSError, ValueError) as e: print("TC-PEERS-FAIL: tc-fleet-quotes cannot be read as JSON: %s" % e); sys.exit(1)
    if not isinstance(peers, dict): print("TC-PEERS-FAIL: tc-fleet-quotes is not an object of announcements"); sys.exit(1)
    done, bad = [], 0
    for row in rows:
        if len(row) != 6: print("TC-PEERS-FAIL: a line of fleet.tsv does not have 6 fields"); sys.exit(1)
        if row[0] == own["name"]: continue
        try:
            if not isinstance(peers.get(row[0]), str): raise PeerError("there is no announcement for it in tc-fleet-quotes")
            done.append((row[0], check_peer(row, announcement(peers[row[0]]), own_q, own_events))); print("peer %s: ok (Intel chain, keys, binding, log, same TD and image)" % row[0])
        except PeerError as e: bad += 1; print("peer %s: REFUSED: %s" % (row[0], e))
    if bad or not done: print("TC-PEERS-FAIL: %d of %d peers refused" % (bad, len(rows) - 1) if bad else "TC-PEERS-FAIL: no peer to verify"); sys.exit(1)
    with open(out_path, "w", encoding="utf-8") as f: f.write("".join("%s\t%s\n" % p for p in sorted(done)))
    print("TC-PEERS-OK %d" % len(done))

if __name__ == "__main__": main()
