#!/usr/bin/env python3
"""Rehearsal of verify_endorsement.py (step P5.5). It makes its own certificate hierarchies shaped like Google's (RSA-PSS signatures, a root with path length 0, a leaf that is not a CA), signs endorsements with the layout of
gce-tcb-verifier proto/endorsement.proto, requires the controls to be accepted, and damages the endorsement, the certificates, the MRTD, the RAM size and the time in many ways, one at a time: each must be rejected, FOR THE REASON that belongs to it.
   python3 verify_endorsement_rehearse.py            (needs only the Python package 'cryptography'; it writes nothing outside a temporary folder)"""
import datetime, os, subprocess, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import verify_endorsement as V
from cryptography import x509
from cryptography.x509.oid import NameOID
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa

NOW = datetime.datetime.now(datetime.timezone.utc); PSS = lambda: padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=padding.PSS.DIGEST_LENGTH)
def vi(n):
    o = b""
    while True:
        b = n & 0x7F; n >>= 7
        if n: o += bytes([b | 0x80])
        else: return o + bytes([b])
def tag(fn, wt): return vi(fn << 3 | wt)
def ld(fn, b): return tag(fn, 2) + vi(len(b)) + b
def num(fn, n): return tag(fn, 0) + vi(n)
def key(): return rsa.generate_private_key(65537, 2048)
def cert(cn, k, icn, ik, ca=False, plen=None, nb=None, na=None, usage=None, sign_pss=True):
    n = lambda c: x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, c)])
    ku = usage or (x509.KeyUsage(False, False, False, False, False, True, True, False, False) if ca else x509.KeyUsage(True, False, False, False, False, False, False, False, False))
    b = (x509.CertificateBuilder().subject_name(n(cn)).issuer_name(n(icn)).public_key(k.public_key()).serial_number(x509.random_serial_number()).not_valid_before(nb or NOW - datetime.timedelta(days=30)).not_valid_after(na or NOW + datetime.timedelta(days=1800))
         .add_extension(x509.BasicConstraints(ca=ca, path_length=plen if ca else None), critical=True).add_extension(ku, critical=True))
    return b.sign(ik, hashes.SHA256(), rsa_padding=PSS()) if sign_pss else b.sign(ik, hashes.SHA256())
DER = lambda c: c.public_bytes(serialization.Encoding.DER); PEM = lambda c: c.public_bytes(serialization.Encoding.PEM)
M16, M32, MEA, MD = bytes([1]) * 48, bytes([2]) * 48, bytes([3]) * 48, bytes([4]) * 48
MS = [(16, False, M16), (32, False, M32), (16, True, MEA)]
def golden(leaf_der, ca_pem=b"", ms=MS, svn=3, tdx=True):
    t = num(1, svn) + b"".join(ld(2, num(1, r) + (num(2, 1) if e else b"") + ld(3, m)) for r, e, m in ms)
    return ld(1, num(1, int(NOW.timestamp()))) + num(2, 12345) + ld(3, bytes([9]) * 20) + ld(4, leaf_der) + ld(5, bytes([7]) * 48) + (ld(6, ca_pem) if ca_pem else b"") + (ld(8, t) if tdx else b"")
def endorsement(g, k, sig=None): return ld(1, g) + ld(2, sig if sig is not None else k.sign(g, PSS(), hashes.SHA256()))
def flip(b, i): b = bytearray(b); b[i] ^= 1; return bytes(b)

rk, lk, ak, alk, ik = key(), key(), key(), key(), key()   # root, leaf, attacker root, attacker leaf, intermediate
root = cert("GCE-cc-tcb-root", rk, "GCE-cc-tcb-root", rk, ca=True, plen=0); leaf = cert("GCE-uefi-signer", lk, "GCE-cc-tcb-root", rk)
root2 = cert("Root-B", rk, "Root-B", rk, ca=True, plen=None); inter = cert("Inter-B", ik, "Root-B", rk, ca=True, plen=0); leafB = cert("Signer-B", lk, "Inter-B", ik)
aroot = cert("GCE-cc-tcb-root", ak, "GCE-cc-tcb-root", ak, ca=True, plen=0); aleaf = cert("GCE-uefi-signer", alk, "GCE-cc-tcb-root", ak)
E = endorsement(golden(DER(leaf)), lk)
def run(end, roots, mrtd=M16, ram=16, **kw): return V.check(end, roots, mrtd.hex(), ram, **kw)
ED = endorsement(golden(DER(leaf), ms=[(0, False, MD)]), lk); EMIX = endorsement(golden(DER(leaf), ms=MS + [(0, False, MD)]), lk)   # Google's current form (one measurement, ram_gib unset), and a mix with legacy entries
def bad(reason): return lambda r: (not r[0]) and reason in r[1][0]
good = lambda r: r[0] and r[1][-1].startswith("ENDORSEMENT-OK")
g0 = golden(DER(leaf)); sig0 = lk.sign(g0, PSS(), hashes.SHA256()); sigidx = g0 and None
nonca = cert("Not-A-CA", rk, "Not-A-CA", rk, ca=False, usage=x509.KeyUsage(True, False, False, False, False, False, False, False, False)); leafN = cert("Signer-N", lk, "Not-A-CA", rk)
ecleaf = cert("Signer-EC", lk, "GCE-cc-tcb-root", rk); eckey = ec.generate_private_key(ec.SECP256R1())
ecb = (x509.CertificateBuilder().subject_name(x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Signer-EC")])).issuer_name(root.subject).public_key(eckey.public_key()).serial_number(1).not_valid_before(NOW - datetime.timedelta(days=1)).not_valid_after(NOW + datetime.timedelta(days=100)).add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True).sign(rk, hashes.SHA256(), rsa_padding=PSS()))
ms_early = lambda m, e: V.check(endorsement(golden(DER(leaf)), lk), PEM(root), m.hex(), 16, early=e)
CASES = [
 ("control: a Google-shaped endorsement (root path length 0, leaf signed directly), PEM root", lambda: run(E, PEM(root)), good),
 ("control: the same with the root as DER, in a file with another unrelated root", lambda: run(E, PEM(aroot) + PEM(root)), good),
 ("control: the same with the root file as DER", lambda: run(E, DER(root)), good),
 ("control: a chain with an intermediate that is in the ca_bundle", lambda: run(endorsement(golden(DER(leafB), PEM(inter)), lk), PEM(root2)), good),
 ("the MRTD with one bit changed", lambda: run(E, PEM(root), mrtd=flip(M16, 5)), bad("is not in the endorsement")),
 ("an MRTD that is endorsed, but for 32 GiB, claimed for 16 GiB of RAM", lambda: run(E, PEM(root), mrtd=M32, ram=16), bad("but for 32 GiB")),
 ("the right MRTD but a RAM size that the endorsement does not list (8 GiB)", lambda: run(E, PEM(root), ram=8), bad("but for 16 GiB and not for 8 GiB")),
 ("the golden measurement changed after it was signed (svn 3 to 4)", lambda: run(endorsement(golden(DER(leaf), svn=4), lk, sig=sig0), PEM(root)), bad("signature of the golden measurement is not valid")),
 ("one bit of the signature changed", lambda: run(endorsement(g0, lk, sig=flip(sig0, 7)), PEM(root)), bad("signature of the golden measurement is not valid")),
 ("the signature made with PKCS#1 v1.5 and not RSA-PSS", lambda: run(endorsement(g0, lk, sig=lk.sign(g0, padding.PKCS1v15(), hashes.SHA256())), PEM(root)), bad("signature of the golden measurement is not valid")),
 ("a chain from an attacker's own root while the pinned root is Google's", lambda: run(endorsement(golden(DER(aleaf)), alk), PEM(root)), bad("no pinned root signed")),
 ("the certificate expired (checked at a date after its end)", lambda: run(E, PEM(root), at=NOW + datetime.timedelta(days=3000)), bad("is not valid at")),
 ("the certificate not yet valid (checked at a date before its start)", lambda: run(E, PEM(root), at=NOW - datetime.timedelta(days=400)), bad("is not valid at")),
 ("the signing certificate is itself a CA", lambda: run(endorsement(golden(DER(cert("Signer-CA", lk, "GCE-cc-tcb-root", rk, ca=True, plen=0))), lk), PEM(root)), bad("is a CA certificate")),
 ("an intermediate without CA:TRUE between the root and the signer", lambda: run(endorsement(golden(DER(cert("Signer-X", lk, "Inter-X", ik)), PEM(cert("Inter-X", ik, "Root-B", rk, ca=False, usage=x509.KeyUsage(True, False, False, False, False, False, False, False, False)))), lk), PEM(root2)), bad("not a CA")),
 ("an intermediate CA under the pinned root, whose path length is 0", lambda: run(endorsement(golden(DER(cert("Signer-P", lk, "Inter-P", ik)), PEM(cert("Inter-P", ik, "GCE-cc-tcb-root", rk, ca=True, plen=0))), lk), PEM(root)), bad("allows at most 0 CA(s) below it")),
 ("an intermediate that the endorsement does not carry", lambda: run(endorsement(golden(DER(leafB)), lk), PEM(root2)), bad("no pinned root signed")),
 ("a pinned 'root' that is not a CA and signed the leaf", lambda: run(endorsement(golden(DER(leafN)), lk), PEM(nonca)), bad("not a CA")),
 ("the endorsement cut short", lambda: run(E[:len(E) // 2], PEM(root)), lambda r: not r[0] and r[1][0].startswith("ENDORSEMENT-FAILED")),
 ("an empty endorsement", lambda: run(b"", PEM(root)), bad("no golden measurement")),
 ("random bytes as an endorsement", lambda: run(os.urandom(300), PEM(root)), lambda r: not r[0] and r[1][0].startswith("ENDORSEMENT-FAILED")),
 ("a golden measurement without a TDX section", lambda: run(endorsement(golden(DER(leaf), tdx=False), lk), PEM(root)), bad("no TDX section")),
 ("the signature field twice (an ambiguous message)", lambda: run(E + ld(2, sig0), PEM(root)), bad("occurs 2 times")),
 ("a root file that holds no certificate", lambda: run(E, b"not a certificate"), bad("holds no certificate")),
 ("early accept: the endorsed MRTD for early accept, asked without it", lambda: ms_early(MEA, "0"), bad("only with early accept 1, and early accept 0 was required")),
 ("early accept: the endorsed MRTD without early accept, asked with it", lambda: ms_early(M16, "1"), bad("only with early accept 0, and early accept 1 was required")),
 ("a signing key that is not an RSA key", lambda: run(endorsement(golden(DER(ecb)), lk), PEM(root)), bad("not an RSA key")),
 ("control: early accept asked for the MRTD that is endorsed for it", lambda: ms_early(MEA, "1"), good),
 ("control: Google's current form, one RAM-independent MRTD (ram_gib unset), a VM with 16 GiB", lambda: run(ED, PEM(root), mrtd=MD, ram=16), lambda r: good(r) and "RAM-independent" in r[1][-1]),
 ("control: the same MRTD, a VM with 64 GiB (the RAM size must not matter for it)", lambda: run(ED, PEM(root), mrtd=MD, ram=64), lambda r: good(r) and "RAM-independent" in r[1][-1]),
 ("control: a mix of legacy and RAM-independent entries, the RAM-independent MRTD on 8 GiB", lambda: run(EMIX, PEM(root), mrtd=MD, ram=8), lambda r: good(r) and "RAM-independent" in r[1][-1]),
 ("control: the same mix, the legacy MRTD on exactly its 16 GiB says that it is a legacy measurement", lambda: run(EMIX, PEM(root), mrtd=M16, ram=16), lambda r: good(r) and "legacy measurement for exactly 16 GiB" in r[1][-1]),
 ("a legacy MRTD (16 GiB) asked for 8 GiB, although a RAM-independent entry exists: the wildcard must not apply to it", lambda: run(EMIX, PEM(root), mrtd=M16, ram=8), bad("but for 16 GiB and not for 8 GiB")),
 ("the RAM-independent MRTD with one bit changed", lambda: run(ED, PEM(root), mrtd=flip(MD, 9)), bad("is not in the endorsement")),
 ("the RAM-independent MRTD asked with early accept 1", lambda: run(ED, PEM(root), mrtd=MD, early="1"), bad("only with early accept 0, and early accept 1 was required")),
 ("control: the RAM size of the VM unknown (None), the MRTD is the RAM-independent one", lambda: run(EMIX, PEM(root), mrtd=MD, ram=None), lambda r: good(r) and "the RAM size of the VM is not needed" in r[1][-1]),
 ("the RAM size unknown (None), but the MRTD is only a legacy entry for 16 GiB: it must not be accepted without the RAM size", lambda: run(EMIX, PEM(root), mrtd=M16, ram=None), bad("the RAM size of the VM is not known")),
]
def main():
    bad_n = 0
    for n, (name, fn, ok) in enumerate(CASES, 1):
        r = fn(); good_ = ok(r); bad_n += 0 if good_ else 1; print("%s %2d. %-82s -> %s" % ("ok:  " if good_ else "FAIL:", n, name, (r[1][-1] if r[0] else r[1][0])[:118]))
    tmp = tempfile.mkdtemp(prefix="p5endorse-"); open(tmp + "/e.bin", "wb").write(E); open(tmp + "/root.pem", "wb").write(PEM(root))
    cli = lambda *a: subprocess.run([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "verify_endorsement.py")] + list(a), capture_output=True, text=True)
    base = ["--endorsement", tmp + "/e.bin", "--root", tmp + "/root.pem", "--mrtd", M16.hex()]
    for name, p, want in (("the command line: accepted (exit 0)", cli(*base, "--ram-gib", "16"), 0), ("the command line: rejected (exit 1)", cli(*base, "--ram-gib", "8"), 1), ("the command line: the RAM size from the machine type c3-standard-4 (exit 0)", cli(*base, "--machine-type", "c3-standard-4"), 0),
                          ("the command line: a machine type with an unknown RAM size (exit 2)", cli(*base, "--machine-type", "n2-standard-4"), 2), ("the command line: a missing file (exit 2)", cli("--endorsement", tmp + "/none", "--root", tmp + "/root.pem", "--mrtd", M16.hex(), "--ram-gib", "16"), 2),
                          ("the command line: a bad date (exit 2)", cli(*base, "--ram-gib", "16", "--at", "yesterday"), 2), ("the command line: an MRTD that is not hex (exit 1, no crash)", cli("--endorsement", tmp + "/e.bin", "--root", tmp + "/root.pem", "--mrtd", "zz", "--ram-gib", "16"), 1)):
        ok = p.returncode == want and "Traceback" not in p.stderr; bad_n += 0 if ok else 1; print("%s     %-82s -> exit %d" % ("ok:  " if ok else "FAIL:", name, p.returncode))
    if bad_n: sys.exit("P5.5-REHEARSAL-FAILED: %d case(s) went wrong" % bad_n)
    ctl = sum(1 for c in CASES if c[0].startswith("control"))
    print("P5.5-REHEARSAL-OK: %d endorsement cases (%d controls, %d damages rejected for the right reason) and 7 command line cases" % (len(CASES), ctl, len(CASES) - ctl))


if __name__ == "__main__": main()
