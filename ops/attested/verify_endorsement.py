#!/usr/bin/env python3
"""Step P5.5: is the MRTD of a TD in Google's signed launch endorsement, for the RAM size of the VM?
   python3 verify_endorsement.py --endorsement FILE --root FILE --mrtd HEX (--ram-gib N | --machine-type c3-standard-N) [--early-accept any|0|1] [--at 2026-11-05T12:00:00Z]
FILE is the endorsement that Google publishes at  https://storage.googleapis.com/gce_tcb_integrity/ovmf_x64_csm/tdx/<MRTD in hex>.binarypb  (a serialized VMLaunchEndorsement of github.com/google/gce-tcb-verifier proto/endorsement.proto).
--root is Google's root certificate  https://pki.goog/cloud_integrity/GCE-cc-tcb-root_1.crt  (PEM or DER; several roots may be in one PEM file). Fetch it yourself over HTTPS: it is the pinned root of trust.
What it checks, as Google's verify/verify.go does and as the mentor's plan asks: (1) the endorsement decodes; (2) the certificate of the signing key chains to a pinned root (every signature of the chain, the validity dates, CA:TRUE and the path length of every CA,
the leaf is not a CA); (3) the signature of the golden measurement is RSA-PSS with SHA-256 under that certificate; (4) the golden measurement lists, in its TDX section, this MRTD either as the RAM-INDEPENDENT measurement (ram_gib unset: the only kind that Google's current code makes, because the RAM banks and the all-regions option that made the MRTD
depend on the RAM size are marked deprecated in gce-tcb-verifier tdx/mrtd_from_ovmf.go) or, for firmware that older VMMs launched, as a measurement for exactly this RAM size. An MRTD that is listed only for ANOTHER RAM size is refused.
Google's own code leaves step (4) to the caller (it only compares SEV-SNP measurements); this file does it. It prints ENDORSEMENT-OK or ENDORSEMENT-FAILED (exit code 0 or 1; 2 for wrong usage).
It does not check that the quote's own signature chain reaches Intel (step P5.3), and the endorsement covers the firmware measurement MRTD only, not RTMR0 to RTMR3. Needs the Python package 'cryptography'."""
import argparse, datetime, re, sys, warnings
warnings.filterwarnings("ignore", category=UserWarning, message=r"Attribute's length must be")   # Google's certificates write the country as USA (3 letters); the library only warns about it
from cryptography import x509
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.asymmetric import padding, rsa

class Bad(Exception): pass

def read_varint(b, i):
    r = s = 0
    while True:
        if i >= len(b): raise Bad("the message is cut short (a number is incomplete)")
        x = b[i]; i += 1; r |= (x & 0x7F) << s
        if not x & 0x80: return r, i
        s += 7
        if s > 63: raise Bad("a number is too long")

def fields(b):
    """The (field number, wire type, value) of every field of a protobuf message; strict: only the wire types that proto3 messages of this definition use."""
    i = 0; out = []
    while i < len(b):
        tag, i = read_varint(b, i); fn, wt = tag >> 3, tag & 7
        if fn == 0: raise Bad("a field has the number 0")
        if wt == 0: v, i = read_varint(b, i)
        elif wt == 2:
            n, i = read_varint(b, i)
            if i + n > len(b): raise Bad("a field is longer than the message")
            v = b[i:i + n]; i += n
        else: raise Bad("a field of the wire type %d: this is not an endorsement" % wt)
        out.append((fn, wt, v))
    return out

def get(fs, fn, wt, name):
    vals = [v for f, w, v in fs if f == fn]
    if len(vals) > 1: raise Bad("the field %s occurs %d times (it must occur once)" % (name, len(vals)))
    if not vals: return None
    if [w for f, w, v in fs if f == fn][0] != wt: raise Bad("the field %s has the wrong type" % name)
    return vals[0]

def decode(endorsement):
    fs = fields(endorsement); golden_b = get(fs, 1, 2, "serialized_uefi_golden"); sig = get(fs, 2, 2, "signature")
    if not golden_b or not sig: raise Bad("the endorsement has no golden measurement or no signature")
    g = fields(golden_b); d = {"golden_b": golden_b, "sig": sig}
    d["commit"] = get(g, 3, 2, "commit") or b""; d["cert"] = get(g, 4, 2, "cert") or b""; d["digest"] = get(g, 5, 2, "digest") or b""; d["ca_bundle"] = get(g, 6, 2, "ca_bundle") or b""; d["cl_spec"] = get(g, 2, 0, "cl_spec") or 0
    ts = get(g, 1, 2, "timestamp"); d["seconds"] = (get(fields(ts), 1, 0, "timestamp.seconds") or 0) if ts else 0
    tdx = get(g, 8, 2, "tdx"); d["tdx"] = None
    if tdx is not None:
        t = fields(tdx); d["svn"] = get(t, 1, 0, "tdx.svn") or 0; ms = []
        for f, w, v in t:
            if f == 2:
                if w != 2: raise Bad("a TDX measurement has the wrong type")
                m = fields(v); ms.append((get(m, 1, 0, "ram_gib") or 0, bool(get(m, 2, 0, "early_accept") or 0), get(m, 3, 2, "mrtd") or b""))
        d["tdx"] = ms
    return d

def load_certs(data, what):
    if b"-----BEGIN CERTIFICATE-----" in data:
        out = [x509.load_pem_x509_certificate(m.group(0)) for m in re.finditer(rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", data, re.S)]
    else:
        try: out = [x509.load_der_x509_certificate(data)]
        except ValueError: raise Bad("%s holds no certificate (neither PEM nor DER)" % what)
    if not out: raise Bad("%s holds no certificate" % what)
    return out

def signed_by(cert, issuer):
    pub = issuer.public_key()
    try:
        if isinstance(pub, rsa.RSAPublicKey): pub.verify(cert.signature, cert.tbs_certificate_bytes, cert.signature_algorithm_parameters, cert.signature_hash_algorithm)
        else: pub.verify(cert.signature, cert.tbs_certificate_bytes, cert.signature_algorithm_parameters)
        return True
    except (InvalidSignature, ValueError, TypeError, AttributeError): return False

def chain_to_root(leaf, inter, roots):
    path = [leaf]; cur = leaf; seen = {leaf.fingerprint(hashes.SHA256())}
    while True:
        if any(cur.fingerprint(hashes.SHA256()) == r.fingerprint(hashes.SHA256()) for r in roots): return path
        nxt = next((c for c in roots + inter if c.subject == cur.issuer and signed_by(cur, c)), None)
        if nxt is None: raise Bad("no pinned root signed the certificate of the signing key (no certificate with the subject %s signed %s)" % (cur.issuer.rfc4514_string(), cur.subject.rfc4514_string()))
        fp = nxt.fingerprint(hashes.SHA256())
        if fp in seen or len(path) > 6: raise Bad("the certificate chain loops or is too long")
        seen.add(fp); path.append(nxt); cur = nxt

def check_chain(path, at):
    for i, c in enumerate(path):
        if not (c.not_valid_before_utc <= at <= c.not_valid_after_utc): raise Bad("the certificate %s is not valid at %s (valid %s to %s)" % (c.subject.rfc4514_string(), at.strftime("%Y-%m-%d"), c.not_valid_before_utc.strftime("%Y-%m-%d"), c.not_valid_after_utc.strftime("%Y-%m-%d")))
        try: bc = c.extensions.get_extension_for_class(x509.BasicConstraints).value
        except x509.ExtensionNotFound: bc = None
        try: ku = c.extensions.get_extension_for_class(x509.KeyUsage).value
        except x509.ExtensionNotFound: ku = None
        if i == 0:
            if bc is not None and bc.ca: raise Bad("the certificate of the signing key is a CA certificate")
            if ku is not None and not ku.digital_signature: raise Bad("the certificate of the signing key does not allow digital signatures")
        else:
            if bc is None or not bc.ca: raise Bad("the certificate %s signs a certificate but is not a CA (CA:TRUE is missing)" % c.subject.rfc4514_string())
            if ku is not None and not ku.key_cert_sign: raise Bad("the CA certificate %s does not allow certificate signing" % c.subject.rfc4514_string())
            if bc.path_length is not None and i - 1 > bc.path_length: raise Bad("the CA certificate %s allows at most %d CA(s) below it, the chain has %d" % (c.subject.rfc4514_string(), bc.path_length, i - 1))

def ram_gib_of(machine_type):
    m = re.fullmatch(r"c3-standard-(\d+)", machine_type or ""); return int(m.group(1)) * 4 if m else None

def check(endorsement, roots_data, mrtd_hex, ram_gib, at=None, early="any"):
    """Returns (ok, lines). Never raises."""
    at = at or datetime.datetime.now(datetime.timezone.utc)
    try:
        mrtd = bytes.fromhex(mrtd_hex)
        if len(mrtd) != 48: raise Bad("the MRTD must be 48 bytes (96 hex digits)")
        roots = load_certs(roots_data, "the root file"); d = decode(endorsement)
        if not d["cert"]: raise Bad("the golden measurement carries no certificate of its signing key")
        leaf = x509.load_der_x509_certificate(d["cert"]); inter = load_certs(d["ca_bundle"], "the ca_bundle") if d["ca_bundle"] else []
        path = chain_to_root(leaf, inter, roots); check_chain(path, at)
        pub = leaf.public_key()
        if not isinstance(pub, rsa.RSAPublicKey): raise Bad("the signing key is not an RSA key (Google signs endorsements with RSA-PSS)")
        try: pub.verify(d["sig"], d["golden_b"], padding.PSS(mgf=padding.MGF1(hashes.SHA256()), salt_length=hashes.SHA256().digest_size), hashes.SHA256())
        except InvalidSignature: raise Bad("the signature of the golden measurement is not valid (RSA-PSS with SHA-256 under the certificate of the signing key)")
        if d["tdx"] is None: raise Bad("the golden measurement has no TDX section: it is not an endorsement for TDX")
        ms = d["tdx"]; rs = "an unknown RAM size" if ram_gib is None else "%d GiB" % ram_gib; applies = lambda m: m[0] == 0 or (ram_gib is not None and m[0] == ram_gib); cand = [m for m in ms if applies(m) and (early == "any" or m[1] == (early == "1"))]; hit = [m for m in cand if m[2] == mrtd]
        if not hit:
            same_mrtd = [m for m in ms if m[2] == mrtd]; other = sorted({m[0] for m in same_mrtd if not applies(m)}); size = lambda r: "any RAM size" if r == 0 else "%d GiB" % r; rams = sorted({m[0] for m in ms})
            if early != "any" and any(applies(m) for m in same_mrtd): raise Bad("this MRTD is in the endorsement for %s, but only with early accept %s, and early accept %s was required" % (", ".join(sorted({size(m[0]) for m in same_mrtd if applies(m)})), ", ".join(sorted({"1" if m[1] else "0" for m in same_mrtd if applies(m)})), early))
            if other: raise Bad("this MRTD is in the endorsement, but for %s and not for %s: %s" % (", ".join(size(r) for r in other), rs, "the RAM size of the VM is not known, and only a RAM-independent entry can be accepted without it" if ram_gib is None else "the VM did not have the RAM size that this firmware was endorsed for"))
            raise Bad("this MRTD is not in the endorsement (it lists %d MRTD(s), for %s; none that applies to %s equals the quote's MRTD)" % (len(ms), ", ".join(size(r) for r in rams) or "no RAM size", rs))
        kind = ("the RAM-independent measurement (ram_gib unset, Google's current form: the RAM size of the VM, %d GiB, does not matter for it)" % ram_gib if ram_gib is not None else "the RAM-independent measurement (ram_gib unset, Google's current form: it applies to every RAM size, so the RAM size of the VM is not needed)") if any(m[0] == 0 for m in hit) else "a legacy measurement for exactly %d GiB of RAM" % ram_gib
    except Bad as e: return False, ["ENDORSEMENT-FAILED: %s" % e]
    except Exception as e: return False, ["ENDORSEMENT-FAILED: the check could not run (%s: %s)" % (type(e).__name__, e)]
    when = datetime.datetime.fromtimestamp(d["seconds"], datetime.timezone.utc).strftime("%Y-%m-%d") if d["seconds"] else "unknown"
    return True, ["the endorsement is signed by %s (chain of %d certificate(s) to a pinned root, valid at %s)" % (leaf.subject.rfc4514_string(), len(path), at.strftime("%Y-%m-%d")),
                  "endorsement made %s, TDX svn %d, firmware SHA-384 %s..., %d MRTD(s) listed" % (when, d["svn"], d["digest"].hex()[:16], len(ms)),
                  "ENDORSEMENT-OK: the MRTD %s... is endorsed by Google as %s%s" % (mrtd_hex[:16], kind, "" if early == "any" else " (early accept %s)" % early)]

def main(argv):
    ap = argparse.ArgumentParser(add_help=False); ap.add_argument("--endorsement", required=True); ap.add_argument("--root", required=True); ap.add_argument("--mrtd", required=True)
    g = ap.add_mutually_exclusive_group(required=True); g.add_argument("--ram-gib", type=int); g.add_argument("--machine-type"); ap.add_argument("--early-accept", choices=["any", "0", "1"], default="any"); ap.add_argument("--at")
    try: a = ap.parse_args(argv)
    except SystemExit: print(__doc__.split("\n")[1]); return 2
    ram = a.ram_gib if a.ram_gib else ram_gib_of(a.machine_type)
    if not ram or ram < 1: print("usage: the RAM size is unknown (--machine-type %s is not c3-standard-N); give --ram-gib" % a.machine_type); return 2
    try: at = datetime.datetime.fromisoformat(a.at.replace("Z", "+00:00")) if a.at else None
    except ValueError: print("usage: --at must look like 2026-11-05T12:00:00Z"); return 2
    if at is not None and at.tzinfo is None: at = at.replace(tzinfo=datetime.timezone.utc)
    try: end = open(a.endorsement, "rb").read(); roots = open(a.root, "rb").read()
    except OSError as e: print("usage: %s" % e); return 2
    ok, lines = check(end, roots, a.mrtd.lower(), ram, at, a.early_accept)
    for l in lines: print(l)
    return 0 if ok else 1

if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
