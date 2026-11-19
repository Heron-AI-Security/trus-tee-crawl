#!/usr/bin/env python3
"""Step R4.3: make the job file (a jar that holds other jars) REPRODUCIBLE, so that two builds of one commit give the same bytes.
   python3 tc-job-normalize.py IN OUT [--epoch YYYY-MM-DD]
The experiment of step R4 compared two builds of one commit and found that the job differed only by build-time stamps: the time in every zip header, and the line '#Mon Oct 26 15:01:49 UTC 2026'
that Java writes into the pom.properties of a library that the build compiles. A later comparison, on a newer base image, found one more difference: two class files of one jar in another order, because the machine that builds a jar decides the order in which the jar tool lists the files. This tool rewrites the job, and every jar inside it (up to three levels), with (1) the same entries with the same content and permissions, in a fixed order (META-INF/ and the manifest first, then the rest by name; a signed jar keeps the order it has, as its content is never changed), (2) one fixed time in every zip header (default 1980-01-01, the first time that a zip can hold), (3) no extra fields (they carry times), (4) the date comment removed from
META-INF/maven/**/pom.properties, but ONLY in a jar that is not signed (the content of a signed jar is never changed, so its signature stays valid), and (5) deflate at a fixed level. Before it writes
anything, it checks that the result has the same names, the same content (except the removed date lines), opens without error, and is itself unchanged by a second run. It never modifies IN.
Standard library only. Exit code 0 only when everything held."""
import sys; sys.dont_write_bytecode = True
import argparse, hashlib, io, os, re, zipfile

DATE_LINE = re.compile(rb"^#(Mon|Tue|Wed|Thu|Fri|Sat|Sun) (Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec) [ 0-3]\d \d\d:\d\d:\d\d [A-Za-z0-9+:_/-]+ \d{4}\r?$")
MAXDEPTH = 3
LEVEL = 6

class Stats:
    def __init__(self): self.pom = 0; self.nested = 0; self.signed = 0; self.entries = 0

def is_signed(names):
    return any(n.upper().startswith("META-INF/") and n.upper().rsplit(".", 1)[-1] in ("SF", "RSA", "DSA", "EC") and "/" not in n[len("META-INF/"):] for n in names)

def strip_date(content, st):
    lines = content.split(b"\n"); kept = [l for l in lines if not DATE_LINE.match(l)]
    st.pom += len(lines) - len(kept)
    return b"\n".join(kept)

def is_pom_properties(name): return os.path.basename(name) == "pom.properties" and "META-INF/maven/" in name

FIRST = ("META-INF/", "META-INF/MANIFEST.MF")

def entry_order(infos, signed):
    """The fixed order of the entries of a jar: META-INF/, the manifest, then the rest by name. A signed jar keeps the order that it has."""
    if signed: return list(infos)
    first = [i for n in FIRST for i in infos if i.filename == n]
    return first + sorted((i for i in infos if i.filename not in FIRST), key=lambda i: i.filename)

def normalize(data, depth, st, epoch):
    zin = zipfile.ZipFile(io.BytesIO(data)); infos = zin.infolist(); signed = is_signed([i.filename for i in infos])
    if signed: st.signed += 1
    out = io.BytesIO()
    with zipfile.ZipFile(out, "w") as zout:
        for i in entry_order(infos, signed):
            st.entries += 1
            if i.is_dir(): body = b""
            else:
                body = zin.read(i)
                if i.filename.lower().endswith(".jar") and depth < MAXDEPTH and zipfile.is_zipfile(io.BytesIO(body)):
                    body = normalize(body, depth + 1, st, epoch); st.nested += 1
                elif is_pom_properties(i.filename) and not signed:
                    body = strip_date(body, st)
            zi = zipfile.ZipInfo(i.filename, epoch); zi.compress_type = i.compress_type; zi.external_attr = i.external_attr; zi.create_system = 3
            zout.writestr(zi, body, compress_type=i.compress_type, compresslevel=LEVEL if i.compress_type == zipfile.ZIP_DEFLATED else None)
            zi.external_attr = i.external_attr   # Python's writestr turns a permission field of 0 (what the Java jar tool writes) into 0o600; the central directory is written from this record at close, so it is put back here
    return out.getvalue()

def problems(orig, new, depth, path=""):
    """Everything that would make the result NOT the same job: names, order, content (except removed date lines), times, unreadable archives."""
    p = []; zo = zipfile.ZipFile(io.BytesIO(orig)); zn = zipfile.ZipFile(io.BytesIO(new))
    if zn.testzip() is not None: p.append("%sthe result has a damaged entry: %s" % (path, zn.testzip()))
    io_, in_ = zo.infolist(), zn.infolist()
    signed = is_signed([i.filename for i in io_]); io_ = entry_order(io_, signed)
    if [i.filename for i in io_] != [i.filename for i in in_]: return p + ["%sthe names, or their order, are not the expected ones" % path]
    for a, b in zip(io_, in_):
        if a.is_dir(): continue
        ca, cb = zo.read(a), zn.read(b)
        if a.filename.lower().endswith(".jar") and depth < MAXDEPTH and zipfile.is_zipfile(io.BytesIO(ca)): p += problems(ca, cb, depth + 1, path + a.filename + "!/")
        elif is_pom_properties(a.filename) and not signed:
            if b"\n".join(l for l in ca.split(b"\n") if not DATE_LINE.match(l)) != cb: p.append("%s%s: more than the date line changed" % (path, a.filename))
        elif ca != cb: p.append("%s%s: the content changed" % (path, a.filename))
        if a.external_attr != b.external_attr: p.append("%s%s: the permissions changed" % (path, a.filename))
    return p

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("inp"); ap.add_argument("out"); ap.add_argument("--epoch", default="1980-01-01")
    a = ap.parse_args()
    def stop(m): print("JOB-NORMALIZE-FAILED: " + m); return 1
    try: y, mo, d = (int(x) for x in a.epoch.split("-")); epoch = (y, mo, d, 0, 0, 0)
    except ValueError: return stop("--epoch must be YYYY-MM-DD (not before 1980)")
    if epoch[0] < 1980: return stop("a zip cannot hold a time before 1980")
    try: data = open(a.inp, "rb").read()
    except OSError as e: return stop("cannot read %s (%s)" % (a.inp, e))
    if not zipfile.is_zipfile(io.BytesIO(data)): return stop("%s is not a zip or jar file" % a.inp)
    st = Stats()
    try: new = normalize(data, 0, st, epoch)
    except (zipfile.BadZipFile, OSError, ValueError, RuntimeError) as e: return stop("the job could not be read or rewritten (%s)" % e)
    bad = problems(data, new, 0)
    if bad: return stop("the rewritten job is not the same job: " + "; ".join(bad[:3]))
    if normalize(new, 0, Stats(), epoch) != new: return stop("a second run changes the result (not stable)")
    tmp = a.out + ".part"
    with open(tmp, "wb") as f: f.write(new)
    os.replace(tmp, a.out)
    print("JOB-NORMALIZED: %d entries, %d nested jars, %d date lines removed from pom.properties, %d signed jar(s) left unchanged in content; %d -> %d bytes; sha256 %s" % (st.entries, st.nested, st.pom, st.signed, len(data), len(new), hashlib.sha256(new).hexdigest()))
    return 0

if __name__ == "__main__": sys.exit(main())
