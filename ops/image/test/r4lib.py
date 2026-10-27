"""Shared helpers of step R4 (standard library only): the algorithm of treehash.sh and tc-extend.sh written again in Python, the hook strip of the image build, and the measured list."""
import hashlib, importlib.util, os

def sha384(b): return hashlib.sha384(b).hexdigest()

def commit_bytes(commit):
    """The content of /etc/tc/source.txt for a commit (step R4.2): one line."""
    return ("commit %s\n" % commit).encode()

def load_strip(repo):
    import sys; sys.dont_write_bytecode = True
    p = os.path.join(repo, "ops/image/build/tc-strip-hooks.py")
    spec = importlib.util.spec_from_file_location("tc_strip_hooks", p); m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m); return m

def stripped_bytes(strip_mod, path):
    """The bytes of the script after the strip, exactly as the image build writes them (text mode, the locale's encoding, as tc-strip-hooks.py does)."""
    return strip_mod.strip_text(open(path).read()).encode()

def tree_digest(entries):
    """entries: (relative path, mode, content sha384) or (relative path, 'L', link target). The digest of treehash.sh: SHA-384 over the sorted lines."""
    out = ""
    for rel, a, b in sorted(entries, key=lambda e: ("./" + e[0]).encode()):
        out += ("L ./%s -> %s\n" % (rel, b)) if a == "L" else ("F %s %s ./%s\n" % (a, b, rel))
    return sha384(out.encode())

def parse_measured(text):
    """The list of the image: NAME <TAB> PATH [<TAB> SKIP SKIP ...]  ->  [(name, path, [skips])]"""
    ev = []
    for line in text.splitlines():
        if not line.strip() or line.startswith("#"): continue
        p = line.split("\t"); ev.append((p[0], p[1], p[2].split() if len(p) > 2 else []))
    return ev

def under_skip(rel, skips): return any(rel == s or rel.startswith(s + "/") for s in skips)
