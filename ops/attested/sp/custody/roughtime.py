"""Verify a recorded Roughtime response (IETF draft protocol) offline.

A Roughtime server signs (MIDP, RADI, ROOT): its time, an accuracy radius, and
the root of a Merkle tree whose leaves include the client's 32-byte request
nonce. Checking the response needs only the server's pinned long-term Ed25519
key, so a stored response proves, to anyone, that the server said "the time is
MIDP +- RADI" after the request nonce existed.

    verify(packet, request_nonce, long_term_key) -> (midp, radi)   seconds

Checks: framing; delegation signature (long-term key over DELE); response
signature (delegated key over SREP); MINT <= MIDP <= MAXT; the Merkle path from
H(0x00 || nonce) to ROOT, H = SHA-512 truncated to 32 bytes.
"""
import hashlib
import struct

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PublicKey

DELEGATION_CONTEXT = b"RoughTime v1 delegation signature--\x00"
RESPONSE_CONTEXT = b"RoughTime v1 response signature\x00"


class RoughtimeError(Exception):
    pass


def _decode(m):
    n = struct.unpack_from("<I", m, 0)[0]
    offs = [0] + [struct.unpack_from("<I", m, 4 + 4 * i)[0] for i in range(n - 1)]
    tags = [struct.unpack_from("<I", m, 4 + 4 * (n - 1) + 4 * i)[0] for i in range(n)]
    base = 4 + 8 * n - 4
    out = {}
    for i, t in enumerate(tags):
        end = offs[i + 1] if i + 1 < n else len(m) - base
        out[struct.pack("<I", t).rstrip(b"\0").decode("ascii")] = m[base + offs[i]:base + end]
    return out


def _h(b):
    return hashlib.sha512(b).digest()[:32]


def verify(packet: bytes, request_nonce: bytes, long_term_key: bytes):
    try:
        if packet[:8] != b"ROUGHTIM":
            raise RoughtimeError("not a Roughtime packet")
        r = _decode(packet[12:12 + struct.unpack_from("<I", packet, 8)[0]])
        srep, cert = _decode(r["SREP"]), _decode(r["CERT"])
        dele = _decode(cert["DELE"])
    except RoughtimeError:
        raise
    except Exception as e:
        raise RoughtimeError("malformed response: {}".format(e))
    try:
        Ed25519PublicKey.from_public_bytes(long_term_key).verify(
            cert["SIG"], DELEGATION_CONTEXT + cert["DELE"])
    except Exception:
        raise RoughtimeError("ROUGHTIME_DELEGATION_SIGNATURE_INVALID")
    try:
        Ed25519PublicKey.from_public_bytes(dele["PUBK"]).verify(
            r["SIG"], RESPONSE_CONTEXT + r["SREP"])
    except Exception:
        raise RoughtimeError("ROUGHTIME_RESPONSE_SIGNATURE_INVALID")
    midp = struct.unpack("<Q", srep["MIDP"])[0]
    radi = struct.unpack("<I", srep["RADI"])[0]
    mint, maxt = (struct.unpack("<Q", dele[k])[0] for k in ("MINT", "MAXT"))
    if not mint <= midp <= maxt:
        raise RoughtimeError("ROUGHTIME_OUTSIDE_DELEGATION")
    index, path = struct.unpack("<I", r["INDX"])[0], r.get("PATH", b"")
    h = _h(b"\x00" + request_nonce)
    for k in range(0, len(path), 32):
        node = path[k:k + 32]
        h = _h(b"\x01" + (node + h if index & 1 else h + node))
        index >>= 1
    if index != 0 or h != srep["ROOT"]:
        raise RoughtimeError("ROUGHTIME_NONCE_NOT_IN_SIGNED_TREE")
    return midp, radi
