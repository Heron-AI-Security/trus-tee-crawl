#!/usr/bin/env python3
"""Rehearsal of verify_export_records.py (step P5.2). It takes a REAL export, checks that the untouched copy passes, then damages a fresh copy in many ways, one at a time, and requires that
every damage is rejected, at the check that is named (and at no check that does not belong to it). A damage that passes, or fails elsewhere, stops the rehearsal.
   python3 verify_export_records_rehearse.py EXPORT_DIR          (EXPORT_DIR holds fleet.tsv and tc/; it is only read, every copy is made in a temporary folder)"""
import hashlib, os, shutil, struct, sys, tempfile
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from verify_export_records import verify_export, IDENT, SUFFIX
from testvectors_check import utf, key_id_of, decode_folder
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec

SRC = sys.argv[1] if len(sys.argv) > 1 else sys.exit(__doc__.split("\n")[2])
def rd(p): return open(p, "rb").read()
def wr(p, b): open(p, "wb").write(b)
def flip(p, at): b = bytearray(rd(p)); b[at] ^= 1; wr(p, bytes(b))
def rec_of(p): return os.path.join(os.path.dirname(p), "." + os.path.basename(p) + SUFFIX)
def files_in(root, sub): d = os.path.join(root, sub); return [os.path.join(d, f) for f in sorted(os.listdir(d)) if os.path.isfile(os.path.join(d, f)) and not f.startswith(".") and f != IDENT]
def folder_id(d): return decode_folder(rd(os.path.join(d, IDENT)))["folder"]
def build_record(priv, kid, folder, name, data, chunk=16384):
    nb = name.encode(); hs = [hashlib.sha256(data[i:i + chunk]).digest() for i in range(0, len(data), chunk)]
    st = utf("tc-attest-file-v1") + utf(kid) + folder + struct.pack(">i", len(nb)) + nb + struct.pack(">i", chunk) + struct.pack(">q", len(data)) + hashlib.sha256(b"".join(hs)).digest()
    sig = priv.sign(st, ec.ECDSA(hashes.SHA256()))
    return b"ATTEST04" + struct.pack(">i", chunk) + struct.pack(">q", len(data)) + bytes([len(kid)]) + kid.encode() + folder + struct.pack(">H", len(nb)) + nb + struct.pack(">i", len(hs)) + b"".join(hs) + struct.pack(">H", len(sig)) + sig
def spki(priv): return priv.public_key().public_bytes(serialization.Encoding.DER, serialization.PublicFormat.SubjectPublicKeyInfo)
def fleet_kid(root):
    import base64; line = [l for l in open(os.path.join(root, "fleet.tsv")) if not l.startswith("#") and l.strip()][0]; return key_id_of(base64.b64decode(line.split("\t")[4]))

def m_flip_warc(r): f = files_in(r, "tc/warc/warc")[0]; flip(f, os.path.getsize(f) // 2)
def m_truncate(r): f = files_in(r, "tc/warc/warc")[0]; wr(f, rd(f)[:-10])
def m_append(r): f = files_in(r, "tc/warc/warc")[0]; wr(f, rd(f) + b"x")
def m_del_record(r): os.remove(rec_of(files_in(r, "tc/warc/warc")[0]))
def m_del_file(r): os.remove(files_in(r, "tc/warc/warc")[0])
def m_flip_sig(r): p = rec_of(files_in(r, "tc/warc/warc")[0]); flip(p, len(rd(p)) - 1)
def m_flip_hash(r): p = rec_of(files_in(r, "tc/warc/warc")[0]); flip(p, len(rd(p)) - 60)
def m_flip_recname(r): p = rec_of(files_in(r, "tc/warc/warc")[0]); b = rd(p); i = b.rindex(b"NUTCH-CRAWL") + 2; flip(p, i)
def m_swap_records(r): a, b = files_in(r, "tc/warc/warc")[:2]; ra, rb = rd(rec_of(a)), rd(rec_of(b)); wr(rec_of(a), rb); wr(rec_of(b), ra)
def m_swap_folders(r):
    a = files_in(r, "tc/warc/warc")[0]; b = os.path.join(r, "tc/warc/robotstxt", os.path.basename(a)); t = a + ".tmp"
    for x, y in ((a, b), (rec_of(a), rec_of(b))): xb, yb = rd(x), rd(y); wr(x, yb); wr(y, xb)
def m_del_ident(r): os.remove(os.path.join(r, "tc/warc/robotstxt", IDENT))
def m_flip_ident(r): p = os.path.join(r, "tc/warc/robotstxt", IDENT); flip(p, len(rd(p)) - 1)
def m_copy_ident(r): shutil.copy(os.path.join(r, "tc/warc/robotstxt", IDENT), os.path.join(r, "tc/warc/warc", IDENT))
def m_extra_file(r): wr(os.path.join(r, "tc/warc/warc", "evil.warc.gz"), b"evil")
def m_extra_dir(r): os.makedirs(os.path.join(r, "tc/warc/warc/evil-folder"))
def m_attacker_record(r):
    priv = ec.generate_private_key(ec.SECP256R1()); data = b"forged page"; d = os.path.join(r, "tc/warc/warc"); wr(os.path.join(d, "evil.warc.gz"), data)
    wr(os.path.join(d, ".evil.warc.gz" + SUFFIX), build_record(priv, key_id_of(spki(priv)), folder_id(d), "evil.warc.gz", data))
def m_forged_kid(r):
    priv = ec.generate_private_key(ec.SECP256R1()); data = b"forged page"; d = os.path.join(r, "tc/warc/warc"); wr(os.path.join(d, "evil.warc.gz"), data)
    wr(os.path.join(d, ".evil.warc.gz" + SUFFIX), build_record(priv, fleet_kid(r), folder_id(d), "evil.warc.gz", data))
def m_rename_pair(r): f = files_in(r, "tc/warc/warc")[0]; g = os.path.join(os.path.dirname(f), "renamed.warc.gz"); os.rename(f, g); os.rename(rec_of(f), rec_of(g))
def m_swap_contents(r): a, b = files_in(r, "tc/warc/warc")[:2]; x, y = rd(a), rd(b); wr(a, y); wr(b, x)
def m_other_fleet(r):
    import base64; priv = ec.generate_private_key(ec.SECP256R1()); lines = open(os.path.join(r, "fleet.tsv")).read().split("\n"); out = []
    for l in lines:
        f = l.split("\t")
        if len(f) >= 6 and not l.startswith("#"): f[4] = base64.b64encode(spki(priv)).decode()
        out.append("\t".join(f))
    open(os.path.join(r, "fleet.tsv"), "w").write("\n".join(out))
def m_flip_receipts(r):
    segs = os.path.join(r, "tc/crawl/segments"); s = sorted(x for x in os.listdir(segs) if os.path.isdir(os.path.join(segs, x)))[0]; d = "tc/crawl/segments/%s/tc_receipts" % s
    f = [x for x in files_in(r, d) if os.path.basename(x).startswith("receipts-")][0]; flip(f, 5)
def m_del_receipts_record(r):
    segs = os.path.join(r, "tc/crawl/segments"); s = sorted(x for x in os.listdir(segs) if os.path.isdir(os.path.join(segs, x)))[0]; d = "tc/crawl/segments/%s/tc_receipts" % s
    os.remove(rec_of([x for x in files_in(r, d) if os.path.basename(x).startswith("outcomes-")][0]))
def m_symlink(r): f = files_in(r, "tc/warc/warc")[0]; t = rd(f); os.remove(f); open(f + ".real", "wb").write(t); os.symlink(f + ".real", f)
def m_no_tc(r): shutil.rmtree(os.path.join(r, "tc"))

# name, damage, the check that must fire, and the checks that may fire with it (a damaged folder identity also makes the folder's files and subfolders fail to bind)
M = [("a changed byte in a WARC", m_flip_warc, "chunk-hash", {"chunk-hash"}), ("a WARC cut short", m_truncate, "length", {"length"}), ("a byte added to a WARC", m_append, "length", {"length"}),
     ("a record file deleted", m_del_record, "missing-record", {"missing-record"}), ("a WARC deleted, its record left", m_del_file, "missing-file", {"missing-file"}),
     ("one byte of a record's signature changed", m_flip_sig, "signature", {"signature"}), ("one byte of a record's chunk hashes changed", m_flip_hash, "signature", {"signature"}),
     ("one byte of the file name inside a record changed", m_flip_recname, "signature", {"signature", "binding-name"}), ("the records of two files swapped", m_swap_records, "binding-name", {"binding-name"}),
     ("two files moved to the other folder with their records", m_swap_folders, "binding-folder", {"binding-folder"}), ("a folder identity deleted", m_del_ident, "missing-identity", {"missing-identity", "binding-folder"}),
     ("one byte of a folder identity changed", m_flip_ident, "signature", {"signature", "binding-folder"}), ("the identity of another folder copied in", m_copy_ident, "binding-name", {"binding-name", "binding-folder"}),
     ("a file added without a record", m_extra_file, "missing-record", {"missing-record"}), ("a folder added without an identity", m_extra_dir, "missing-identity", {"missing-identity"}),
     ("a forged file signed by a key that is not in the fleet", m_attacker_record, "unknown-key", {"unknown-key"}), ("a forged file signed by another key but with the id of a fleet key", m_forged_kid, "signature", {"signature"}),
     ("a file and its record renamed", m_rename_pair, "binding-name", {"binding-name"}), ("the contents of two files swapped", m_swap_contents, {"length", "chunk-hash"}, {"chunk-hash", "length"}),
     ("a fleet.tsv with another signing key", m_other_fleet, "unknown-key", {"unknown-key"}), ("a changed byte in a signed receipts file", m_flip_receipts, "chunk-hash", {"chunk-hash"}),
     ("the record of an outcomes file deleted", m_del_receipts_record, "missing-record", {"missing-record"}), ("a file replaced by a symbolic link", m_symlink, "unexpected-entry", {"unexpected-entry", "missing-record", "missing-file"}),
     ("the folder tc/ missing", m_no_tc, "missing-folder", {"missing-folder"})]
tmp = tempfile.mkdtemp(prefix="p5rehearse-"); bad = 0
try:
    c = os.path.join(tmp, "control"); shutil.copytree(SRC, c, symlinks=True); rep = verify_export(c)
    if rep.problems: print("STOP: the untouched export does not pass: %s" % rep.problems[:3]); sys.exit(1)
    print("control: the untouched export passes (%d folder identities, %d files, %d chunks)" % (rep.folders, rep.files, rep.chunks))
    for n, (name, fn, primary, allowed) in enumerate(M, 1):
        d = os.path.join(tmp, "m%d" % n); shutil.copytree(SRC, d, symlinks=True); fn(d); checks = {p[0] for p in verify_export(d).problems}
        ok = bool(checks & ({primary} if isinstance(primary, str) else primary)) and checks <= allowed; bad += 0 if ok else 1
        print("%s %2d. %-62s -> %s" % ("ok:  " if ok else "FAIL:", n, name, ", ".join(sorted(checks)) or "ACCEPTED (it must be rejected)"))
        shutil.rmtree(d)
finally: shutil.rmtree(tmp, ignore_errors=True)
if bad: sys.exit("P5.2-REHEARSAL-FAILED: %d of %d damages were not rejected at the right check" % (bad, len(M)))
print("P5.2-REHEARSAL-OK: the untouched export passes and all %d damages are rejected, each at the check that belongs to it" % len(M))
