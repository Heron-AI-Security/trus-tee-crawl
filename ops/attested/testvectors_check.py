#!/usr/bin/env python3
"""An independent second implementation of the checks of ATTEST04 (a file record) and ATTEST05 (a folder identity), written ONLY from the specification in
docs/milestone-5-signed-records.md section 16.3 (it does not use any Java code). It reads the test vectors that the wrapper's own code made
(ops/attested/testvectors/attest-vectors-v1.json) and must give every vector the verdict that the vector says: a valid vector is accepted, and every other vector fails
at the check that it names (the order of checks is: decode, signature, binding-folder, binding-name, binding-parent, length, chunk-hash).
Usage: testvectors_check.py [VECTORS.json]      Needs the Python package 'cryptography'."""
import hashlib, json, struct, sys
from cryptography.exceptions import InvalidSignature
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

ID_CHARS = set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_.")

class Fail(Exception):
    def __init__(self, check, why): super().__init__(why); self.check = check

class Reader:
    def __init__(self, b): self.b, self.i = b, 0
    def take(self, n):
        if n < 0 or self.i + n > len(self.b): raise Fail("decode", "the record is too short")
        v = self.b[self.i:self.i + n]; self.i += n; return v
    def u8(self): return self.take(1)[0]
    def u16(self): return struct.unpack(">H", self.take(2))[0]
    def i32(self): return struct.unpack(">i", self.take(4))[0]
    def i64(self): return struct.unpack(">q", self.take(8))[0]
    def end(self):
        if self.i != len(self.b): raise Fail("decode", "the record has trailing bytes")

def utf(s): b = s.encode("utf-8"); return struct.pack(">H", len(b)) + b      # a string as the statements write it: a 2-byte length, then the bytes
def key_id_of(x509): return "FLEET-" + hashlib.sha256(x509).hexdigest()[:32]

def read_key_id(r):
    n = r.u8(); kid = r.take(n).decode("ascii", "replace")
    if not (1 <= n <= 64) or not set(kid) <= ID_CHARS: raise Fail("decode", "a bad key id")
    return kid

def read_name(r):
    n = r.u16(); nb = r.take(n)
    if not (1 <= n <= 1024): raise Fail("decode", "a bad name length")
    try: return nb, nb.decode("utf-8")
    except UnicodeDecodeError: raise Fail("decode", "the name is not UTF-8")

def decode_file(rec):
    r = Reader(rec)
    if r.take(8) != b"ATTEST04": raise Fail("decode", "bad magic")
    chunk = r.i32(); length = r.i64()
    if chunk < 1 or length < 0: raise Fail("decode", "bad chunk size or length")
    kid = read_key_id(r); folder = r.take(32); nb, name = read_name(r); count = r.i32()
    if count != -(-length // chunk) or count > 33554432: raise Fail("decode", "the chunk count does not fit the length")
    hs = [r.take(32) for _ in range(count)]; sl = r.u16()
    if not (1 <= sl <= 128): raise Fail("decode", "bad signature length")
    sig = r.take(sl); r.end()
    statement = utf("tc-attest-file-v1") + utf(kid) + folder + struct.pack(">i", len(nb)) + nb + struct.pack(">i", chunk) + struct.pack(">q", length) + hashlib.sha256(b"".join(hs)).digest()
    return dict(chunk=chunk, length=length, kid=kid, folder=folder, name=name, hashes=hs, sig=sig, statement=statement)

def decode_folder(rec):
    r = Reader(rec)
    if r.take(8) != b"ATTEST05": raise Fail("decode", "bad magic")
    folder = r.take(32); nb, name = read_name(r); parent = r.take(32); kid = read_key_id(r); sl = r.u16()
    if not (1 <= sl <= 128): raise Fail("decode", "bad signature length")
    sig = r.take(sl); r.end()
    statement = utf("tc-attest-folder-v1") + utf(kid) + folder + struct.pack(">i", len(nb)) + nb + parent
    return dict(kid=kid, folder=folder, name=name, parent=parent, sig=sig, statement=statement)

def check_signature(pub, d):
    if d["kid"] != key_id_of(pub["x509"]): raise Fail("signature", "the key id is not the id of the signer's key")
    try: pub["key"].verify(d["sig"], d["statement"], ec.ECDSA(hashes.SHA256()))
    except InvalidSignature: raise Fail("signature", "the signature does not verify")

def file_bytes(spec):
    b = bytearray(i % 251 for i in range(spec["length"]))
    if spec["flip_byte_at"] >= 0: b[spec["flip_byte_at"]] ^= 1
    return bytes(b) + bytes(spec["extra_bytes"])

def verdict(v, pub):
    """Returns '' if the vector is accepted, else the name of the check that fails first; and checks the statement of a valid vector."""
    rec = bytes.fromhex(v["record_hex"])
    try:
        if v["kind"] == "file":
            d = decode_file(rec); check_signature(pub, d)
            if d["folder"].hex() != v["expected_folder_id_hex"]: raise Fail("binding-folder", "the record belongs to another folder")
            if d["name"] != v["expected_name"]: raise Fail("binding-name", "the record is for another name")
            data = file_bytes(v["file"])
            if len(data) != d["length"]: raise Fail("length", "the file's length is not the record's")
            for i, h in enumerate(d["hashes"]):
                if hashlib.sha256(data[i * d["chunk"]:(i + 1) * d["chunk"]]).digest() != h: raise Fail("chunk-hash", "chunk %d does not match" % i)
        else:
            d = decode_folder(rec); check_signature(pub, d)
            if d["name"] != v["expected_name"]: raise Fail("binding-name", "the identity is for another name")
            if d["parent"].hex() != v["expected_parent_id_hex"]: raise Fail("binding-parent", "the identity's parent is not the folder above")
            if d["folder"].hex() != v["expected_folder_id_hex"]: raise Fail("binding-folder", "another folder id")
    except Fail as e:
        return e.check
    if v["valid"] and d["statement"].hex() != v["statement_hex"]: return "statement-differs"
    return ""

def main(path):
    doc = json.load(open(path, encoding="utf-8")); x509 = __import__("base64").b64decode(doc["key"]["public_x509_b64"])
    pub = {"x509": x509, "key": serialization.load_der_public_key(x509)}
    if doc["key"]["id"] != key_id_of(x509): sys.exit("STOP: the key id in the vectors is not the id of the key")
    bad = 0; valid = 0
    for v in doc["vectors"]:
        got = verdict(v, pub); want = "" if v["valid"] else v["failure"]; valid += 1 if v["valid"] else 0
        ok = got == want
        print("%s %-26s %s" % ("ok:  " if ok else "FAIL:", v["name"], "accepted" if not got else "fails at " + got + ("" if ok else "  (the vector says: %s)" % (want or "accepted"))))
        bad += 0 if ok else 1
    if bad: sys.exit("TESTVECTORS-FAILED (%d of %d)" % (bad, len(doc["vectors"])))
    print("TESTVECTORS-OK: %d vectors (%d valid, %d that must fail) give the verdicts that they say, by an implementation written only from the specification" % (len(doc["vectors"]), valid, len(doc["vectors"]) - valid))

if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else __file__.rsplit("/", 1)[0] + "/testvectors/attest-vectors-v1.json")
