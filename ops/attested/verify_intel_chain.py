#!/usr/bin/env python3
"""Step P5.3 (step 6 of ops/verify-export.py, rule E0): every quote of a run is a TDX v4 ECDSA quote that Intel's certificate chain signs.
   python3 verify_intel_chain.py EVIDENCE_DIR [PUBLISHED_DIR]
It REUSES check_intel() of the teammate's ops/image/rootfs/usr/local/lib/tc/tc-peer-verify.py, unchanged (the mentor asked for one implementation, not two). For every quote
it checks: the PCK certificate chain ends at the pinned Intel SGX Root CA (openssl verify -x509_strict), the QE report is signed by the PCK key and binds the attestation key,
and the quote is signed by that attestation key. The quotes are the quote_b64= line of announce-*.txt, final-*.txt and export-*.txt of EVIDENCE_DIR, and the raw quote-run*.bin
files of PUBLISHED_DIR when it is given (the dummy runs of the release).
NOT checked, and the output says so: Intel's collateral (TCB status and revocation lists, which need Intel's online service); the validity dates of the certificates are judged by the clock of
the machine that runs this check (openssl).
Needs the openssl command. Exit code 0: every quote verified. 1: a quote is refused. 3: nothing could be checked (no quote file, no openssl, or the file of the teammate is missing)."""
import base64, glob, importlib.util, os, re, shutil, sys
HERE = os.path.dirname(os.path.abspath(__file__))
PEER = os.path.join(HERE, "..", "image", "rootfs", "usr", "local", "lib", "tc", "tc-peer-verify.py")
PASS, FAIL, NOTC = "PASS", "FAIL", "NOT CHECKED"
NOT_CHECKED_HERE = "not checked here: Intel's collateral (TCB status, revocation lists: it needs Intel's online service); the certificate dates are judged by this machine's clock"
def load_peer():
    spec = importlib.util.spec_from_file_location("tc_peer_verify", PEER); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m
def quote_of(path):
    d = {}
    for line in open(path, encoding="utf-8", errors="replace").read().splitlines():
        if "=" in line: k, v = line.split("=", 1); d[k] = v
    if "quote_b64" not in d: raise ValueError("no quote_b64 line")
    return base64.b64decode(d["quote_b64"], validate=True)
def check(evid, pub=None):
    """(status, lines) for the quotes of the run in EVIDENCE_DIR and, if PUB is given, the quotes of the release."""
    if not shutil.which("openssl"): return NOTC, ["the Intel chain is checked with the openssl command, and it is not installed here"]
    if not os.path.isfile(PEER): return NOTC, ["the teammate's tc-peer-verify.py is missing at %s: nothing was checked" % os.path.normpath(PEER)]
    peer = load_peer()
    files = sorted(glob.glob(os.path.join(evid, "announce-*.txt")) + glob.glob(os.path.join(evid, "final-*.txt")) + glob.glob(os.path.join(evid, "export-*.txt")))
    pubs = sorted(glob.glob(os.path.join(pub, "quote-run*.bin"))) if pub else []
    if not files and not pubs: return NOTC, ["there is no quote file in %s" % evid]
    bad = []; nodes = set()
    for f in files:
        name = os.path.basename(f); nodes.add(re.sub(r"^(announce|final|export)-|\.txt$", "", name))
        try: peer.check_intel(quote_of(f))
        except peer.PeerError as e: bad.append("%s: %s" % (name, e))
        except Exception as e: bad.append("%s: cannot be read as a quote (%s: %s)" % (name, type(e).__name__, e))
    for f in pubs:
        try: peer.check_intel(open(f, "rb").read())
        except peer.PeerError as e: bad.append("published %s: %s" % (os.path.basename(f), e))
        except Exception as e: bad.append("published %s: cannot be read as a quote (%s: %s)" % (os.path.basename(f), type(e).__name__, e))
    if bad: return FAIL, bad[:6] + (["... and %d more" % (len(bad) - 6)] if len(bad) > 6 else [])
    return PASS, ["%d quote(s) of %d node(s)%s: each has a PCK chain that ends at the Intel SGX Root CA (openssl verify -x509_strict), a QE report signed by the PCK key that binds the attestation key, and a quote signed by that key" % (len(files), len(nodes), (" and %d published quote(s)" % len(pubs)) if pubs else ""), NOT_CHECKED_HERE]
def main(argv):
    if not argv or len(argv) > 2: print(__doc__.split("\n")[1]); return 2
    st, lines = check(argv[0].rstrip("/"), argv[1] if len(argv) > 1 else None)
    for l in lines: print("   " + l)
    print({PASS: "INTEL-CHAIN-OK", FAIL: "INTEL-CHAIN-FAILED", NOTC: "INTEL-CHAIN-NOT-CHECKED"}[st]); return {PASS: 0, FAIL: 1, NOTC: 3}[st]
if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
