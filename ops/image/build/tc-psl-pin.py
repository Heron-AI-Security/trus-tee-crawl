#!/usr/bin/env python3
"""Step R4.9: put the PINNED Public Suffix List into the crawler-commons jar, and make the jar reproducible.
The library downloads a moving copy of the list while it is built (download-maven-plugin in its pom), so two builds of one commit differed in the entry effective_tld_names.dat (28 October 2026).
  python3 tc-psl-pin.py JAR PSL_FILE EXPECTED_SHA256
It checks that PSL_FILE has the expected SHA-256, then rewrites JAR in place: that one entry is the pinned list, the manifest is first, the other entries are sorted by name, and every entry gets the same time, attributes and compression level.
It stops (and leaves the jar untouched) if the hash is wrong, if the entry is missing or appears twice, or if a file is missing."""
import hashlib, os, sys, tempfile, zipfile
NAME = "effective_tld_names.dat"; FIXED = (1980, 1, 1, 0, 0, 0)
def die(m): print("ABORT: " + m, file=sys.stderr); sys.exit(1)
def main(argv):
    if len(argv) != 3: die("usage: tc-psl-pin.py JAR PSL_FILE EXPECTED_SHA256")
    jar, psl, want = argv
    for p in (jar, psl):
        if not os.path.isfile(p): die("the file is missing: " + p)
    pdata = open(psl, "rb").read(); got = hashlib.sha256(pdata).hexdigest()
    if got != want: die("the Public Suffix List %s has SHA-256 %s, not the pinned %s" % (psl, got, want))
    with zipfile.ZipFile(jar) as z:
        infos = z.infolist(); names = [i.filename for i in infos]
        if names.count(NAME) != 1: die("the jar has the entry %s %d times (it must be exactly once)" % (NAME, names.count(NAME)))
        items = [(i.filename, b"" if i.filename.endswith("/") else (pdata if i.filename == NAME else z.read(i))) for i in infos]
    items.sort(key=lambda t: (t[0] != "META-INF/MANIFEST.MF", t[0]))
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(os.path.abspath(jar)), suffix=".tmp"); os.close(fd)
    try:
        with zipfile.ZipFile(tmp, "w") as out:
            for name, data in items:
                zi = zipfile.ZipInfo(name, FIXED); zi.create_system = 3; zi.extra = b""; zi.comment = b""
                if name.endswith("/"): zi.external_attr = (0o40755 << 16) | 0x10; out.writestr(zi, b"", compress_type=zipfile.ZIP_STORED)
                else: zi.external_attr = 0o100644 << 16; out.writestr(zi, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=6)
        with zipfile.ZipFile(tmp) as chk:
            if hashlib.sha256(chk.read(NAME)).hexdigest() != want: die("internal check failed: the entry is not the pinned list")
        os.replace(tmp, jar)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    print("Public Suffix List pinned in %s: %d entries, list sha256 %s, jar sha256 %s" % (os.path.basename(jar), len(items), want[:16] + "...", hashlib.sha256(open(jar, "rb").read()).hexdigest()[:16] + "..."))
main(sys.argv[1:])
