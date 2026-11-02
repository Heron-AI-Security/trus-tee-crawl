#!/usr/bin/env python3
"""Step P4.2: the manifest of a file tree.    python3 ops/tree-manifest.py ROOT [--label TEXT] [--out FILE]
Walks ROOT (a mounted, read-only root disk) without following links or crossing into other file systems, and writes one line per entry, sorted by path, with tab-separated fields:
  D path mode uid gid                      a directory
  F path mode uid gid size sha256          a regular file (the SHA-256 of its content)
  L path mode uid gid target               a symbolic link (where it points)
  O path mode uid gid kind                 anything else (a socket, a pipe, a device)
Never recorded: times, inode numbers, the order of the directory. A path is relative to ROOT with a leading slash; a backslash, a tab, a newline, a carriage return, and any byte that is not UTF-8
are written as \\\\, \\t, \\n, \\r and \\xNN. The header lines start with # and the last line (# summary) counts what was found, so that a truncated manifest is recognised. A file that cannot be read is
written with ERROR:<reason> instead of a hash, and the exit code is 2. Exit codes: 0 ok, 2 errors, 64 usage."""
import hashlib, os, stat, sys
def esc(b):
    out = []
    for ch in b.decode("utf-8", "surrogateescape"):
        o = ord(ch)
        if ch == "\\": out.append("\\\\")
        elif ch == "\t": out.append("\\t")
        elif ch == "\n": out.append("\\n")
        elif ch == "\r": out.append("\\r")
        elif 0xDC80 <= o <= 0xDCFF: out.append("\\x%02x" % (o - 0xDC00))
        else: out.append(ch)
    return "".join(out)
def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            c = f.read(1 << 20)
            if not c: break
            h.update(c)
    return h.hexdigest()
def main(argv):
    root = None; label = ""; out = None; i = 0
    while i < len(argv):
        a = argv[i]
        if a == "--label" and i + 1 < len(argv): label = argv[i + 1]; i += 2
        elif a == "--out" and i + 1 < len(argv): out = argv[i + 1]; i += 2
        elif a.startswith("--") or root is not None: print(__doc__.splitlines()[0], file=sys.stderr); return 64
        else: root = a; i += 1
    if root is None or not os.path.isdir(root): print("tree-manifest: ROOT must be a directory", file=sys.stderr); return 64
    rootb = os.fsencode(root.rstrip("/") or "/"); lines = []; cnt = {"D": 0, "F": 0, "L": 0, "O": 0}; size_total = 0; errors = 0; dev = os.lstat(rootb).st_dev
    def meta(p, st): return "%o\t%d\t%d" % (stat.S_IMODE(st.st_mode), st.st_uid, st.st_gid)
    def walk(dirb, rel):
        nonlocal size_total, errors
        try: names = sorted(os.listdir(dirb))
        except OSError as e: errors += 1; lines.append("O\t%s\t0\t0\t0\tERROR:%s" % (esc(rel or b"/"), e.errno)); return
        for n in names:
            p = os.path.join(dirb, n); r = rel + b"/" + n
            try: st = os.lstat(p)
            except OSError as e: errors += 1; lines.append("O\t%s\t0\t0\t0\tERROR:%s" % (esc(r), e.errno)); continue
            m = st.st_mode
            if stat.S_ISDIR(m):
                if st.st_dev != dev: continue
                cnt["D"] += 1; lines.append("D\t%s\t%s" % (esc(r), meta(p, st))); walk(p, r)
            elif stat.S_ISREG(m):
                cnt["F"] += 1; size_total += st.st_size
                try: h = digest(p)
                except OSError as e: errors += 1; h = "ERROR:%s" % e.errno
                lines.append("F\t%s\t%s\t%d\t%s" % (esc(r), meta(p, st), st.st_size, h))
            elif stat.S_ISLNK(m):
                cnt["L"] += 1
                try: t = esc(os.readlink(p))
                except OSError as e: errors += 1; t = "ERROR:%s" % e.errno
                lines.append("L\t%s\t%s\t%s" % (esc(r), meta(p, st), t))
            else:
                cnt["O"] += 1; kind = "socket" if stat.S_ISSOCK(m) else "fifo" if stat.S_ISFIFO(m) else "chardev" if stat.S_ISCHR(m) else "blockdev" if stat.S_ISBLK(m) else "other"
                lines.append("O\t%s\t%s\t%s" % (esc(r), meta(p, st), kind))
    rst = os.lstat(rootb); cnt["D"] += 1; lines.append("D\t/\t%s" % meta(rootb, rst)); walk(rootb, b"")
    lines.sort(key=lambda l: (l.split("\t", 2)[1], l[0]))
    head = ["# tc-tree-manifest v1", "# label: %s" % label.replace("\n", " "), "# root: %s" % root]
    tail = ["# summary: dirs=%d files=%d symlinks=%d other=%d bytes=%d errors=%d" % (cnt["D"], cnt["F"], cnt["L"], cnt["O"], size_total, errors)]
    text = "\n".join(head + lines + tail) + "\n"
    if out: open(out, "w", encoding="utf-8", errors="surrogateescape").write(text)
    else: sys.stdout.write(text)
    print("tree-manifest: %d dirs, %d files (%d bytes), %d symlinks, %d other, %d errors" % (cnt["D"], cnt["F"], size_total, cnt["L"], cnt["O"], errors), file=sys.stderr)
    return 2 if errors else 0
sys.exit(main(sys.argv[1:]))
