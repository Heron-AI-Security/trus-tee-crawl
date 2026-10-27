#!/usr/bin/env python3
"""Step R4.2: check a `git archive` of a named commit and take the commit id FROM THE ARCHIVE, not from a person.
   python3 r4-archive.py ARCHIVE [--sha256 HEX] [--expect COMMIT] [--extract DIR] [--commit-file FILE]
`git archive COMMIT` writes the commit id into the header of the tar (the 'comment' of the pax global header), so the archive says by itself which commit it is. This tool: (1) checks the SHA-256 of the file
when it is given (the value that was made on the machine that made the archive); (2) reads the commit id from the header and refuses an archive that has none (an archive of a tree, not of a commit) or whose id does not start
with the expected one (the full id or at least its first 9 characters, as `git log --oneline` shows it); (3) optionally unpacks it into a new folder (refusing absolute paths, '..' and links that point outside); (4) optionally writes the id into a file, which the build ships to the builder.
Standard library only. Exit code 0 only when every given check passed."""
import sys; sys.dont_write_bytecode = True
import argparse, hashlib, os, re, tarfile

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("archive"); ap.add_argument("--sha256"); ap.add_argument("--expect"); ap.add_argument("--extract"); ap.add_argument("--commit-file")
    a = ap.parse_args()
    def stop(m): print("R4-ARCHIVE-FAILED: " + m); return 1
    if not os.path.isfile(a.archive): return stop("no archive at %s" % a.archive)
    h = hashlib.sha256()
    with open(a.archive, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""): h.update(b)
    digest = h.hexdigest()
    if a.sha256 and digest != a.sha256.lower(): return stop("the SHA-256 of the file is %s, expected %s (the file was changed or damaged after it was made)" % (digest, a.sha256.lower()))
    try:
        tf = tarfile.open(a.archive, "r:*")
    except (tarfile.TarError, OSError) as e: return stop("not a readable tar archive (%s)" % e)
    with tf:
        first = tf.next(); commit = tf.pax_headers.get("comment", "") if first is not None else ""
        if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", commit): return stop("the archive has no commit id in its header: it was not made by `git archive COMMIT` (an archive of a tree or of a folder is not accepted)")
        if a.expect:
            e = a.expect.lower()
            if not re.fullmatch(r"[0-9a-f]{9,64}", e): return stop("--expect needs the commit id or at least its first 9 hex characters (got '%s')" % a.expect)
            if not commit.startswith(e): return stop("the archive is of commit %s, expected %s" % (commit, e))
        members = tf.getmembers()
        for m in members:
            n = m.name
            if n.startswith("/") or ".." in n.split("/"): return stop("the member '%s' has an absolute path or '..'" % n)
            if m.issym() or m.islnk():
                t = m.linkname; base = os.path.dirname(n)
                tgt = os.path.normpath(os.path.join(base, t)) if not t.startswith("/") else t
                if t.startswith("/") or tgt.startswith(".."): return stop("the link '%s' points outside the archive (%s)" % (n, t))
        if a.extract:
            if os.path.exists(a.extract) and os.listdir(a.extract): return stop("%s exists and is not empty" % a.extract)
            os.makedirs(a.extract, exist_ok=True)
            try: tf.extractall(a.extract, filter="data")
            except TypeError: tf.extractall(a.extract)
    if a.commit_file:
        with open(a.commit_file, "w") as o: o.write(commit + "\n")
    print("ARCHIVE-OK commit=%s sha256=%s members=%d%s" % (commit, digest, len(members), " extracted=" + a.extract if a.extract else ""))
    return 0

if __name__ == "__main__": sys.exit(main())
