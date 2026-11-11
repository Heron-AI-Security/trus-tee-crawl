#!/usr/bin/env python3
"""Step P5.2: verify EVERY record and EVERY folder identity of an export, from the signatures down to the bytes of each file.
   python3 verify_export_records.py EXPORT_DIR [--fleet FLEET.tsv] [-v]
EXPORT_DIR is the folder that holds fleet.tsv, manifest.tsv and the folder tc/ (the layout of the export, docs/milestone-6-verifier-and-evidence.md section 6.3).
It uses the decoding and the signature check of testvectors_check.py (written only from docs/milestone-5-signed-records.md section 16.3) and adds what that file does not do, because it
only handles the test vectors: it walks the real tree. For every folder under tc/: the identity (_attested-folder) exists, decodes, is signed by a signing key of fleet.tsv, is for the
folder's own name, and its parent id is the id of the folder above (all zeros for tc/). For every file: it has a record (.NAME.attested) and every record has its file; the record is signed
by a key of fleet.tsv, names the folder that holds the file and the file's own name, and the file has the length and the chunk hashes of the record. Nothing else is trusted.
The keys come from fleet.tsv. By default that is the export's own copy; to rest on the copy that the quotes measured (event 'fleet', rule E7 of f1-fleet.py), pass it with --fleet.
It does NOT check that the signing keys are bound to quotes, the Intel chain, the manifest or the receipts' content: those are other checks of step P5.
It prints EXPORT-RECORDS-OK, or each problem and EXPORT-RECORDS-FAILED (exit code 1). Needs the Python package 'cryptography'."""
import base64, hashlib, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from testvectors_check import Fail, decode_file, decode_folder, check_signature, key_id_of
from cryptography.hazmat.primitives import serialization

ZERO = bytes(32); IDENT = "_attested-folder"; SUFFIX = ".attested"

def load_fleet(path):
    keys = {}
    for line in open(path, encoding="utf-8"):
        if line.startswith("#") or not line.strip(): continue
        f = line.rstrip("\n").split("\t")
        if len(f) < 6: raise SystemExit("STOP: a row of %s has %d columns, expected at least 6" % (path, len(f)))
        x509 = base64.b64decode(f[4]); keys[key_id_of(x509)] = {"x509": x509, "key": serialization.load_der_public_key(x509), "node": f[0]}
    if not keys: raise SystemExit("STOP: %s holds no signing key" % path)
    return keys

class Report:
    def __init__(self): self.problems = []; self.folders = 0; self.files = 0; self.chunks = 0; self.bytes = 0; self.verbose = False
    def add(self, check, rel, why): self.problems.append((check, rel, why))

def signed_by_fleet(keys, d):
    pub = keys.get(d["kid"])
    if pub is None: raise Fail("unknown-key", "the key id %s is not a signing key of fleet.tsv" % d["kid"])
    check_signature(pub, d)

def check_file(path, rec_path, rel, folder_id, keys, rep):
    """The order of checks is that of the specification: decode, signature, binding-folder, binding-name, length, chunk-hash."""
    try:
        d = decode_file(open(rec_path, "rb").read()); signed_by_fleet(keys, d)
        if folder_id is None: raise Fail("binding-folder", "the folder that holds the file has no valid identity")
        if d["folder"] != folder_id: raise Fail("binding-folder", "the record belongs to another folder")
        if d["name"] != os.path.basename(path): raise Fail("binding-name", "the record is for the name %r" % d["name"])
        size = os.path.getsize(path)
        if size != d["length"]: raise Fail("length", "the file has %d bytes, the record says %d" % (size, d["length"]))
        with open(path, "rb") as f:
            for i, h in enumerate(d["hashes"]):
                if hashlib.sha256(f.read(d["chunk"])).digest() != h: raise Fail("chunk-hash", "chunk %d does not match the record" % i)
                rep.chunks += 1
        rep.files += 1; rep.bytes += size
        if rep.verbose: print("ok:   " + rel)
    except Fail as e: rep.add(e.check, rel, str(e))
    except OSError as e: rep.add("unreadable", rel, str(e))

def check_dir(d, rel, parent_id, keys, rep):
    folder_id = None; ident = os.path.join(d, IDENT)
    if not os.path.isfile(ident): rep.add("missing-identity", rel, "the folder has no %s" % IDENT)
    else:
        try:
            di = decode_folder(open(ident, "rb").read()); signed_by_fleet(keys, di)
            if di["name"] != os.path.basename(d): raise Fail("binding-name", "the identity is for the name %r" % di["name"])
            if di["parent"] != parent_id: raise Fail("binding-parent", "the identity's parent is not the identity of the folder above")
            folder_id = di["folder"]; rep.folders += 1
            if rep.verbose: print("ok:   %s/%s" % (rel, IDENT))
        except Fail as e: rep.add(e.check, rel + "/" + IDENT, str(e))
        except OSError as e: rep.add("unreadable", rel + "/" + IDENT, str(e))
    try: entries = sorted(os.listdir(d))
    except OSError as e: rep.add("unreadable", rel, str(e)); return
    data, recs, subs = [], [], []
    for e in entries:
        p = os.path.join(d, e); r = rel + "/" + e
        if os.path.islink(p): rep.add("unexpected-entry", r, "a symbolic link"); continue
        if os.path.isdir(p): subs.append(e)
        elif not os.path.isfile(p): rep.add("unexpected-entry", r, "not a regular file or folder")
        elif e == IDENT: continue
        elif e.startswith(".") and e.endswith(SUFFIX) and len(e) > len(SUFFIX) + 1: recs.append(e)
        else: data.append(e)
    for e in recs:
        if e[1:-len(SUFFIX)] not in data: rep.add("missing-file", rel + "/" + e, "the record has no file")
    for e in data:
        rp = os.path.join(d, "." + e + SUFFIX)
        if not os.path.isfile(rp): rep.add("missing-record", rel + "/" + e, "the file has no record")
        else: check_file(os.path.join(d, e), rp, rel + "/" + e, folder_id, keys, rep)
    for e in subs: check_dir(os.path.join(d, e), rel + "/" + e, folder_id, keys, rep)

def verify_export(root, fleet_path=None, verbose=False):
    fleet_path = fleet_path or os.path.join(root, "fleet.tsv"); keys = load_fleet(fleet_path); rep = Report(); rep.verbose = verbose
    rep.fleet_sha384 = hashlib.sha384(open(fleet_path, "rb").read()).hexdigest(); rep.keys = len(keys)
    tc = os.path.join(root, "tc")
    if not os.path.isdir(tc): rep.add("missing-folder", "tc", "the export has no folder tc/")
    else: check_dir(tc, "tc", ZERO, keys, rep)
    rep.outside = sorted(e for e in os.listdir(root) if e != "tc")
    return rep

def main(argv):
    args = [a for a in argv if not a.startswith("-")]; fleet = argv[argv.index("--fleet") + 1] if "--fleet" in argv else None
    if fleet: args.remove(fleet)
    if len(args) != 1: sys.exit(__doc__.split("\n")[1])
    rep = verify_export(args[0], fleet, "-v" in argv)
    print("keys of the fleet: %d (fleet.tsv SHA-384 %s...)" % (rep.keys, rep.fleet_sha384[:16]))
    print("outside tc/ (covered by manifest.tsv and quote C, not by records): %s" % (", ".join(rep.outside) or "nothing"))
    for check, rel, why in rep.problems[:60]: print("FAIL: %-17s %s: %s" % (check, rel, why))
    if len(rep.problems) > 60: print("... and %d more problems" % (len(rep.problems) - 60))
    if rep.problems: sys.exit("EXPORT-RECORDS-FAILED: %d problem(s) in %d check(s): %s" % (len(rep.problems), len({p[0] for p in rep.problems}), ", ".join(sorted({p[0] for p in rep.problems}))))
    print("EXPORT-RECORDS-OK: %d folder identities and %d files verified (%d chunks, %d bytes), every record is signed by a key of the fleet and binds the folder, the name, the length and each chunk" % (rep.folders, rep.files, rep.chunks, rep.bytes))

if __name__ == "__main__": main(sys.argv[1:])
