#!/usr/bin/env bash
# ops/image/test/p42-rehearse.sh: the offline rehearsal of step P4.2 (no Google): ops/tree-manifest.py on a fixture tree with awkward names and files, ops/tree-diff.py on every kind of difference and of damaged manifest,
# and ops/tree-diff.sh against a fake gcloud, including the clean-up after a success and after every failure.
# Usage:  bash ops/image/test/p42-rehearse.sh [ROOT]      ROOT is the repository folder (default: three folders above this script).   Ends with  pass: N   fail: M  and P42-REHEARSAL-PASS or P42-REHEARSAL-FAIL.
# shellcheck disable=SC2015   # the chk lines are written as: test && chk ok || chk no (chk never fails, so this is safe)
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "P42-REHEARSAL-FAIL: no folder $1"; exit 2; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0; ONLY="${REHEARSE_ONLY:-MDO}"
chk() { if [ "$2" = ok ]; then pass=$((pass+1)); echo "  ok:   $1"; else fail=$((fail+1)); echo "  FAIL: $1"; fi; }
MAN="$ROOT/ops/tree-manifest.py"; DIF="$ROOT/ops/tree-diff.py"
# ---- the fixture tree
python3 - "$W/ta" <<'PY'
import os, sys
r = sys.argv[1]; os.makedirs(r + "/d1/d2"); os.makedirs(r + "/dir with space", mode=0o700); os.chmod(r + "/dir with space", 0o700)
def w(p, b, mode=None):
    open(p if isinstance(p, str) else p, "wb").write(b)
    if mode is not None: os.chmod(p, mode)
w(r + "/a.txt", b"hello\n"); w(r + "/empty", b""); w(r + "/big.bin", os.urandom(1) * 3145728 + b"tail"); w(r + "/run.sh", b"#!/bin/sh\n", 0o755); w(r + "/d1/d2/deep.txt", b"deep\n"); w(r + "/suid", b"x", 0o4755)
w(r + "/dir with space/tab\tname", b"t"); w(r + "/dir with space/new\nline", b"n"); w(r + "/back\\slash", b"b"); w(r + "/\u00e9.txt", b"u")
w(os.fsencode(r) + b"/bad\xff\xfename", b"bad"); os.makedirs(r + "/dz"); w(r + "/dz/child", b"c"); w(r + "/dz.txt", b"t")   # "/dz.txt" sorts before "/dz/child"
os.symlink("a.txt", r + "/link"); os.symlink("/etc/passwd", r + "/abs"); os.symlink("nowhere", r + "/dang"); os.symlink("d1", r + "/linkdir"); os.mkfifo(r + "/fifo"); os.link(r + "/a.txt", r + "/hard")
PY
man() { python3 "$MAN" "$@" 2>"$W/err.txt"; }
mkdir -p "$W/empty-tree"
want() { grep -q -- "$1" "$W/out.txt"; }
if [[ "$ONLY" == *M* ]]; then
echo "== M. ops/tree-manifest.py"
man "$W/ta" --label demo --out "$W/a.m"; rc=$?; [ "$rc" = 0 ] && head -3 "$W/a.m" | tr '\n' '|' | grep -q "^# tc-tree-manifest v1|# label: demo|# root: " && chk "a manifest has its header and label, exit code 0" ok || chk "header: rc=$rc" no
python3 - "$W/a.m" "$W/ta" <<'PY' > "$W/mcheck.txt"
import os, sys
L = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read().split("\n"); L.pop(); body = [l for l in L if not l.startswith("#")]; root = sys.argv[2]
n = {"D": 0, "F": 0, "L": 0, "O": 0}
for l in body: n[l[0]] += 1
walked = {"D": 1, "F": 0, "L": 0, "O": 0}
import stat
for dp, dn, fn in os.walk(root, followlinks=False):
    for x in dn + fn:
        m = os.lstat(os.path.join(dp, x)).st_mode
        if os.path.islink(os.path.join(dp, x)): walked["L"] += 1
        elif stat.S_ISDIR(m): walked["D"] += 1
        elif stat.S_ISREG(m): walked["F"] += 1
        else: walked["O"] += 1
print("summary", L[-1] == "# summary: dirs=%d files=%d symlinks=%d other=%d bytes=%d errors=0" % (n["D"], n["F"], n["L"], n["O"], sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(root) for f in fs if os.path.isfile(os.path.join(dp, f)) and not os.path.islink(os.path.join(dp, f)))))
print("counts", n == walked, n, walked)
print("sorted", [l.split("\t")[1] for l in body] == sorted(l.split("\t")[1] for l in body))
PY
grep -q "^summary True" "$W/mcheck.txt" && chk "the summary line counts exactly what is in the tree (dirs, files, symlinks, other, bytes)" ok || chk "summary: $(cat "$W/mcheck.txt")" no
grep -q "^counts True" "$W/mcheck.txt" && chk "every directory, file, link and special file of the tree is listed once" ok || chk "counts: $(grep counts "$W/mcheck.txt")" no
grep -q "^sorted True" "$W/mcheck.txt" && chk "the entries are sorted by path" ok || chk "not sorted" no
man "$W/ta" --label demo --out "$W/a2.m"; cmp -s "$W/a.m" "$W/a2.m" && chk "two runs give the same bytes (the manifest is deterministic)" ok || chk "not deterministic" no
[ "$(grep -P "^F\t/a.txt\t" "$W/a.m" | cut -f7)" = "$(sha256sum "$W/ta/a.txt" | cut -d' ' -f1)" ] && [ "$(grep -P "^F\t/big.bin\t" "$W/a.m" | cut -f7)" = "$(sha256sum "$W/ta/big.bin" | cut -d' ' -f1)" ] && chk "the SHA-256 of a small file and of a 3 MB file (read in chunks) are right" ok || chk "sha256 wrong" no
grep -qP "^L\t/link\t[0-7]+\t\d+\t\d+\ta.txt$" "$W/a.m" && grep -qP "^L\t/abs\t[0-7]+\t\d+\t\d+\t/etc/passwd$" "$W/a.m" && grep -qP "^L\t/dang\t[0-7]+\t\d+\t\d+\tnowhere$" "$W/a.m" && chk "relative, absolute and dangling symlinks are recorded with their target" ok || chk "symlinks" no
! grep -q "/linkdir/" "$W/a.m" && grep -qP "^L\t/linkdir\t" "$W/a.m" && chk "a symlink to a directory is not followed" ok || chk "linkdir followed" no
grep -qP "^O\t/fifo\t[0-7]+\t\d+\t\d+\tfifo$" "$W/a.m" && chk "a named pipe is recorded as a special file" ok || chk "fifo" no
grep -qP "^F\t/suid\t4755\t" "$W/a.m" && grep -qP "^D\t/dir with space\t700\t" "$W/a.m" && chk "modes are recorded with their special bits (4755, 700)" ok || chk "modes" no
grep -qF 'dir with space/tab\tname' "$W/a.m" && grep -qF 'dir with space/new\nline' "$W/a.m" && grep -qF '/back\\slash' "$W/a.m" && grep -qF '/bad\xff\xfename' "$W/a.m" && grep -qF "/é.txt" "$W/a.m" && chk "a tab, a newline, a backslash and a byte that is not UTF-8 in a name are escaped; UTF-8 is kept" ok || chk "escaping" no
[ "$(grep -c -v '^#' "$W/a.m" | head -1)" = "$(grep -v '^#' "$W/a.m" | awk -F'\t' '{print NF}' | grep -c -E '^(5|6|7)$')" ] && chk "every line has the right number of fields (a name never breaks a line)" ok || chk "fields" no
touch -d "2001-01-01" "$W/ta/a.txt" "$W/ta/d1"; man "$W/ta" --label demo --out "$W/a3.m"; cmp -s "$W/a.m" "$W/a3.m" && chk "changing the times of a file and a directory changes nothing (times are never recorded)" ok || chk "times matter" no
if [ "$(id -u)" = 0 ]; then chk "an unreadable file is recorded as an error (skipped: this test runs as root, who can read everything)" ok; else
  cp -r "$W/ta" "$W/tu"; chmod 000 "$W/tu/a.txt"; man "$W/tu" --out "$W/u.m"; rc=$?; [ "$rc" = 2 ] && grep -qP "^F\t/a.txt\t.*ERROR:13$" "$W/u.m" && grep -q "errors=1$" "$W/u.m" && chk "an unreadable file is recorded as ERROR, counted, and the exit code is 2" ok || chk "unreadable: rc=$rc" no; chmod 644 "$W/tu/a.txt"; fi
man "$W/nonexistent"; rc=$?; [ "$rc" = 64 ] && chk "a ROOT that is not a directory is refused (exit code 64)" ok || chk "bad root" no
man "$W/ta" --nonsense; rc=$?; [ "$rc" = 64 ] && chk "an unknown option is refused (exit code 64)" ok || chk "bad option" no
man "$W/ta" --label x > "$W/stdout.m"; [ "$(head -1 "$W/stdout.m")" = "# tc-tree-manifest v1" ] && chk "without --out the manifest goes to the standard output" ok || chk "stdout" no
man "$W/empty-tree" --out "$W/e.m"; rc=$?; [ "$rc" = 0 ] && grep -q "^# summary: dirs=1 files=0 symlinks=0 other=0 bytes=0 errors=0$" "$W/e.m" && chk "an empty tree is a manifest with only the root directory" ok || chk "empty tree" no
fi
# ---------------------------------------------------------------- D. ops/tree-diff.py
if [[ "$ONLY" == *D* ]]; then
echo "== D. ops/tree-diff.py"
man "$W/ta" --label rel --out "$W/ma.m"
dif() { python3 "$DIF" "$@" > "$W/out.txt" 2>&1; echo $?; }
variant() { rm -rf "$W/tb"; cp -a "$W/ta" "$W/tb"; }
mb() { man "$W/tb" --label psl --out "$W/mb.m"; }

rc=$(dif "$W/ma.m" "$W/ma.m"); [ "$rc" = 0 ] && want "^TREE-DIFF-IDENTICAL files=" && chk "a tree against itself: TREE-DIFF-IDENTICAL, exit code 0" ok || chk "identical: rc=$rc" no
variant; mb; rc=$(dif "$W/ma.m" "$W/mb.m"); [ "$rc" = 0 ] && want "TREE-DIFF-IDENTICAL" && chk "a copy of the tree with other labels and the same files is identical" ok || chk "copy: rc=$rc" no
variant; echo "changed" > "$W/tb/a.txt"; mb; rc=$(dif "$W/ma.m" "$W/mb.m"); [ "$rc" = 1 ] && want "content differs: 2" && want "/a.txt   (size 6 -> 8)" && want "/hard   (size 6 -> 8)" && want "^TREE-DIFF-DIFFERENT differences=2" && chk "a changed file is named with its size (and so is its hard link: two paths, one inode)" ok || chk "content: rc=$rc $(grep -E 'differ|DIFF' "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
variant; rm "$W/tb/empty"; : > "$W/tb/added"; mb; rc=$(dif "$W/ma.m" "$W/mb.m"); [ "$rc" = 1 ] && want "only in A: 1" && want "only in B: 1" && want "/empty" && want "/added" && chk "a file only in A and a file only in B are named" ok || chk "only: rc=$rc" no
variant; chmod 600 "$W/tb/run.sh"; mb; rc=$(dif "$W/ma.m" "$W/mb.m"); [ "$rc" = 1 ] && want "mode differs: 1" && want "755 -> 600" && chk "a different mode is named (755 -> 600)" ok || chk "mode: rc=$rc" no
variant; chmod 755 "$W/tb/dir with space"; mb; rc=$(dif "$W/ma.m" "$W/mb.m"); [ "$rc" = 1 ] && want "mode differs: 1" && want "/dir with space" && chk "a different mode of a directory is named" ok || chk "dir mode: rc=$rc" no
variant; mb; python3 - "$W/mb.m" <<'PY'
import sys
p = sys.argv[1]; L = open(p, encoding="utf-8", errors="surrogateescape").read().split("\n"); out = []
for l in L:
    f = l.split("\t")
    if f[0] == "F" and f[1] == "/a.txt": f[3] = str(int(f[3]) + 1)   # another owner than the real one, whoever runs the test
    out.append("\t".join(f))
open(p, "w", encoding="utf-8", errors="surrogateescape").write("\n".join(out))
PY
rc=$(dif "$W/ma.m" "$W/mb.m"); [ "$rc" = 1 ] && want "owner differs: 1" && want "/a.txt   (" && chk "a different owner is named" ok || chk "owner: rc=$rc" no
variant; rm "$W/tb/link"; ln -s b.txt "$W/tb/link"; mb; rc=$(dif "$W/ma.m" "$W/mb.m"); [ "$rc" = 1 ] && want "link target differs: 1" && want "a.txt -> b.txt" && chk "a symlink that points somewhere else is named" ok || chk "link: rc=$rc" no
variant; rm "$W/tb/abs"; echo x > "$W/tb/abs"; mb; rc=$(dif "$W/ma.m" "$W/mb.m"); [ "$rc" = 1 ] && want "type differs: 1" && want "L -> F" && chk "a symlink replaced by a file is a type difference (L -> F)" ok || chk "type: rc=$rc" no
variant; echo "changed" > "$W/tb/d1/d2/deep.txt"; echo more >> "$W/tb/run.sh"; mb; printf '# ignore the d1 tree\n/d1/*\n' > "$W/ign.txt"; rc=$(dif "$W/ma.m" "$W/mb.m" --ignore "$W/ign.txt"); [ "$rc" = 1 ] && want "ignored by your patterns (1 differences)" && want "/d1/\*" && want "^TREE-DIFF-DIFFERENT differences=1 ignored=1" && chk "an ignore pattern hides only what it matches, the ignored count is shown, and the other difference still fails" ok || chk "ignore partial: rc=$rc $(tail -4 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
variant; echo "changed" > "$W/tb/d1/d2/deep.txt"; mb; rc=$(dif "$W/ma.m" "$W/mb.m" --ignore "$W/ign.txt"); [ "$rc" = 0 ] && want "^TREE-DIFF-IDENTICAL .* ignored=1" && chk "when everything that differs is ignored the verdict says so and shows how many were ignored" ok || chk "ignore all: rc=$rc" no
variant; for i in 1 2 3 4 5; do echo "c$i" > "$W/tb/d1/n$i"; done; mb; rc=$(dif "$W/ma.m" "$W/mb.m" --max 2 --report "$W/rep.tsv"); [ "$rc" = 1 ] && want "and 3 more" && [ "$(grep -c "/d1/n" "$W/out.txt")" = 2 ] && [ "$(grep -c '^DIFF' "$W/rep.tsv")" = 5 ] && chk "--max limits the lines printed (2 of 5 are shown), and --report writes every difference" ok || chk "max/report: rc=$rc" no
variant; echo "changed" > "$W/tb/d1/d2/deep.txt"; mb; dif "$W/ma.m" "$W/mb.m" --ignore "$W/ign.txt" --report "$W/rep2.tsv" >/dev/null; grep -q "^IGNORED" "$W/rep2.tsv" && chk "the report marks ignored differences as IGNORED, so they stay visible" ok || chk "report ignored" no
variant; touch -d "2001-01-01" "$W/tb/a.txt" "$W/tb/d1"; mb; rc=$(dif "$W/ma.m" "$W/mb.m"); [ "$rc" = 0 ] && chk "different times are not a difference" ok || chk "times: rc=$rc" no
head -n -1 "$W/ma.m" > "$W/trunc.m"; rc=$(dif "$W/ma.m" "$W/trunc.m"); [ "$rc" = 2 ] && want "TREE-DIFF-FAILED: .* has no summary line: it is truncated" && chk "a truncated manifest is refused, not compared" ok || chk "truncated: rc=$rc" no
grep -v "^F$(printf '\t')/a.txt$(printf '\t')" "$W/ma.m" > "$W/damaged.m"; rc=$(dif "$W/ma.m" "$W/damaged.m"); [ "$rc" = 2 ] && want "its summary does not match its lines" && chk "a manifest with a line removed is refused (its summary no longer matches)" ok || chk "damaged: rc=$rc" no
python3 - "$W/ma.m" "$W/err.m" <<'PY'
import sys
L = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read().split("\n"); out = []
for l in L:
    if l.startswith("# summary:"): l = l.replace("errors=0", "errors=1")
    out.append(l)
open(sys.argv[2], "w", encoding="utf-8", errors="surrogateescape").write("\n".join(out))
PY
rc=$(dif "$W/ma.m" "$W/err.m"); [ "$rc" = 2 ] && want "reports read errors" && chk "a manifest that reports a read error is refused: an unread tree cannot be compared" ok || chk "errors: rc=$rc" no
echo "not a manifest" > "$W/junk.m"; rc=$(dif "$W/ma.m" "$W/junk.m"); [ "$rc" = 2 ] && want "is not a tc-tree-manifest v1 file" && chk "a file that is not a manifest is refused" ok || chk "junk: rc=$rc" no
python3 - "$W/ma.m" "$W/dup.m" <<'PY'
import sys
L = open(sys.argv[1], encoding="utf-8", errors="surrogateescape").read().split("\n")
i = next(k for k, l in enumerate(L) if l.startswith("F\t/a.txt\t")); L.insert(i, L[i]); open(sys.argv[2], "w", encoding="utf-8", errors="surrogateescape").write("\n".join(L))
PY
rc=$(dif "$W/ma.m" "$W/dup.m"); [ "$rc" = 2 ] && want "is listed twice" && chk "a path listed twice is refused" ok || chk "dup: rc=$rc" no
rc=$(dif "$W/ma.m" "$W/nonexistent.m"); [ "$rc" = 2 ] && want "cannot be read" && chk "a missing manifest is named" ok || chk "missing: rc=$rc" no
rc=$(dif "$W/ma.m"); [ "$rc" = 64 ] && chk "one argument only: the usage, exit code 64" ok || chk "usage: rc=$rc" no
man "$W/empty-tree" --label e1 --out "$W/e1.m"; man "$W/empty-tree" --label e2 --out "$W/e2.m"; rc=$(dif "$W/e1.m" "$W/e2.m"); [ "$rc" = 0 ] && chk "two empty trees are identical" ok || chk "empty trees: rc=$rc" no
fi
# ---------------------------------------------------------------- O. ops/tree-diff.sh and ops/tree-helper.sh with a fake gcloud
if [[ "$ONLY" == *O* ]]; then
echo "== O. ops/tree-diff.sh (a fake gcloud; the clean-up is checked after every run)"
mkdir -p "$W/bin" "$W/stub"; export STUBDIR="$W/stub" LOG="$W/calls.log"
cat > "$W/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
echo "gcloud $*" >> "$LOG"; S="$STUBDIR"; H="$S/home"
case "$*" in
  "compute disks create"*) [ -f "$S/disk_fail" ] && { echo "ERROR: quota exceeded" >&2; exit 1; }; touch "$S/disk_$4";;
  "compute instances create"*) [ -f "$S/vm_fail" ] && { echo "ERROR: no capacity" >&2; exit 1; }; touch "$S/vm";;
  "compute ssh"*) [ -f "$S/vm" ] || { echo "ERROR: no such VM" >&2; exit 1; }
    cmd=""; prev=""; for a in "$@"; do [ "$prev" = "--command" ] && cmd="$a"; prev="$a"; done
    if [ "$cmd" = true ]; then n="$(cat "$S/sshcount" 2>/dev/null || echo 0)"; echo $((n+1)) > "$S/sshcount"; [ "$n" -ge "${STUB_SSH_FAILS:-0}" ]; exit $?; fi
    [ -f "$S/helper_fail" ] && { echo "TREE-HELPER-FAILED: cannot mount" >&2; exit 1; }
    c="${cmd//sudo /}"; c="${c//\~\//$H/}"; mkdir -p "$H"; ( cd "$H" && TC_FAKE_MOUNT_treea="$TREE_A" TC_FAKE_MOUNT_treeb="$TREE_B" bash -c "$c" );;
  "compute scp"*) src=(); skip=0; for a in "${@:3}"; do if [ "$skip" = 1 ]; then skip=0; continue; fi; case "$a" in --zone) skip=1;; --*) :;; *) src+=("$a");; esac; done
    dst="${src[-1]}"; unset 'src[-1]'; mkdir -p "$H"
    for s in "${src[@]}"; do case "$s" in *:*) f="${s#*:}"; f="${f/#\~/$H}"; cp "$f" "${dst}";; *) cp "$s" "$H/";; esac; done;;
  "compute instances delete"*) rm -f "$S/vm";;
  "compute disks delete"*) rm -f "$S/disk_$4";;
  *) echo "stub: unexpected gcloud call: $*" >&2; exit 99;;
esac
STUB
chmod +x "$W/bin/gcloud"
rm -rf "$W/ta2"; cp -a "$W/ta" "$W/ta2"; rm -rf "$W/tc2"; cp -a "$W/ta" "$W/tc2"; echo changed > "$W/tc2/d1/d2/deep.txt"
export TREE_A="$W/ta2" TREE_B="$W/ta2"
run() { rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; ( cd "$W" && env PATH="$W/bin:$PATH" TREE_A="$TREE_A" TREE_B="$TREE_B" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 "$@" ) > "$W/out.txt" 2>&1; echo $?; }
nothing_left() { [ ! -e "$STUBDIR/vm" ] && ! ls "$STUBDIR"/disk_* >/dev/null 2>&1; }
made() { grep -c -E "^gcloud compute (disks|instances) create" "$LOG"; }; deleted() { grep -c -E "^gcloud compute (disks|instances) delete" "$LOG"; }
D="bash $ROOT/ops/tree-diff.sh"
export TREE_A="$W/ta2" TREE_B="$W/ta2"; rc=$(run $D diff tc-img-A tc-img-B --work "$W/work")
[ "$rc" = 0 ] && want "^TREE-DIFF-IDENTICAL" && [ "$(made)" = 3 ] && [ "$(deleted)" = 3 ] && nothing_left && chk "two identical trees: IDENTICAL; 2 disks and 1 VM made and all 3 deleted afterwards" ok || chk "diff identical: rc=$rc made=$(made) deleted=$(deleted)" no
grep -q -- "--disk name=tc-tree-.*-a,device-name=treea,mode=ro,boot=no --disk name=tc-tree-.*-b,device-name=treeb,mode=ro,boot=no" "$LOG" && grep -q -- "--no-service-account --no-scopes" "$LOG" && grep -q -- "--labels purpose=tc-tree-diff" "$LOG" && chk "the helper VM gets both disks READ-ONLY, no service account, no scopes, and the label purpose=tc-tree-diff" ok || chk "vm flags" no
grep -q "^# label: tc-img-A$" "$W/work/a.manifest" && grep -q "^# label: tc-img-B$" "$W/work/b.manifest" && [ -f "$W/work/differences.tsv" ] && chk "the manifests carry the image names, and the manifests and the report stay in the work folder" ok || chk "work files" no
export TREE_A="$W/ta2" TREE_B="$W/tc2"; rc=$(run $D diff tc-img-A tc-img-B --work "$W/work")
[ "$rc" = 1 ] && want "^TREE-DIFF-DIFFERENT differences=1" && want "/d1/d2/deep.txt" && nothing_left && chk "two trees that differ: DIFFERENT (exit code 1), the file is named, and everything is deleted" ok || chk "diff different: rc=$rc" no
export TREE_A="$W/ta2" TREE_B="$W/ta2"; rc=$(run env STUB_DUMMY=1 bash -c "touch $W/stub/helper_fail 2>/dev/null; true"); : > "$LOG"
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; touch "$STUBDIR/helper_fail"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 bash "$ROOT/ops/tree-diff.sh" diff tc-img-A tc-img-B --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 2 ] && want "the manifest a.manifest could not be made" && want "TREE-HELPER-FAILED: cannot mount" && nothing_left && [ "$(deleted)" = "$(made)" ] && chk "a failure of the helper stops with its message, and the VM and both disks are still deleted" ok || chk "helper fail: rc=$rc made=$(made) deleted=$(deleted)" no
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; touch "$STUBDIR/disk_fail"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 bash "$ROOT/ops/tree-diff.sh" diff tc-img-A tc-img-B --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 2 ] && want "the disk tc-tree-.*-a could not be made from the image tc-img-A: ERROR: quota exceeded" && ! grep -q "instances create" "$LOG" && chk "a disk that cannot be made stops everything before a VM is made" ok || chk "disk fail: rc=$rc" no
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; touch "$STUBDIR/vm_fail"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 bash "$ROOT/ops/tree-diff.sh" diff tc-img-A tc-img-B --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 2 ] && want "the helper VM could not be made: ERROR: no capacity" && nothing_left && [ "$(grep -c 'disks delete' "$LOG")" = 2 ] && ! grep -q "instances delete" "$LOG" && chk "a VM that cannot be made: the two disks are deleted, and no VM delete is attempted" ok || chk "vm fail: rc=$rc" no
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 STUB_SSH_FAILS=2 bash "$ROOT/ops/tree-diff.sh" diff tc-img-A tc-img-B --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 0 ] && want "not yet (attempt 2 of 12)" && chk "a VM that is slow to accept SSH is waited for" ok || chk "slow ssh: rc=$rc" no
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 STUB_SSH_FAILS=99 bash "$ROOT/ops/tree-diff.sh" diff tc-img-A tc-img-B --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 2 ] && want "does not accept SSH after 12 attempts" && nothing_left && chk "a VM that never accepts SSH: it stops, and everything is deleted" ok || chk "no ssh: rc=$rc" no
export TREE_A="$W/ta2" TREE_B="$W/ta2"; rc=$(run $D diff proj-x/tc-img-A tc-img-B --work "$W/work"); grep -q -- "--image tc-img-A --image-project proj-x" "$LOG" && ! grep -q -- "--image tc-img-B --image-project" "$LOG" && chk "PROJECT/IMAGE uses the image of another project (--image-project), and a plain name does not" ok || chk "image project" no
rc=$(run $D diff tc-img-A tc-img-B --partuuid-a 11111111-2222-3333-4444-555555555555 --work "$W/work"); grep -q "tree-helper.sh treea .*a.manifest 'tc-img-A' 11111111-2222-3333-4444-555555555555" "$LOG" && chk "--partuuid-a is handed to the helper for the first disk" ok || chk "partuuid" no
printf '/d1/d2/deep.txt\n' > "$W/ign2.txt"; export TREE_A="$W/ta2" TREE_B="$W/tc2"; rc=$(run $D diff tc-img-A tc-img-B --ignore "$W/ign2.txt" --work "$W/work"); [ "$rc" = 0 ] && want "ignored by your patterns" && chk "--ignore is handed to the comparison, and the ignored differences are still reported" ok || chk "ignore: rc=$rc" no
export TREE_A="$W/ta2"; rc=$(run $D manifest tc-img-A "$W/one.m" --work "$W/work"); [ "$rc" = 0 ] && want "^TREE-MANIFEST-OK image=tc-img-A" && [ -s "$W/one.m" ] && [ "$(made)" = 2 ] && [ "$(deleted)" = 2 ] && nothing_left && chk "manifest mode: one disk and one VM, the manifest is written, and both are deleted" ok || chk "manifest mode: rc=$rc made=$(made) deleted=$(deleted)" no
rc=$(run $D diff tc-img-A tc-img-B --ignore "$W/nonexistent" --work "$W/work"); [ "$rc" = 2 ] && want "the ignore file .* does not exist" && [ "$(made)" = 0 ] && chk "a missing ignore file is refused before anything is made" ok || chk "no ignore file: rc=$rc" no
rc=$(run $D); [ "$rc" = 64 ] && chk "no mode: the usage, exit code 64" ok || chk "no mode: rc=$rc" no
rc=$(run $D nonsense a b); [ "$rc" = 64 ] && chk "an unknown mode is refused" ok || chk "bad mode: rc=$rc" no
rc=$(run $D diff only-one); [ "$rc" = 64 ] && chk "diff with one image is refused" ok || chk "one image: rc=$rc" no
rc=$(run $D diff a b --nonsense); [ "$rc" = 64 ] && want "unknown option: --nonsense" && chk "an unknown option is refused" ok || chk "bad option: rc=$rc" no
# the helper script alone
H="$ROOT/ops/tree-helper.sh"; rm -rf "$W/hh"; mkdir "$W/hh"; cp "$ROOT/ops/tree-manifest.py" "$H" "$W/hh/"
( cd "$W/hh" && env TC_FAKE_MOUNT_treea="$W/ta2" bash tree-helper.sh treea out.m lbl ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 0 ] && grep -q "^# label: lbl$" "$W/hh/out.m" && chk "the helper makes the manifest of the tree that is mounted for it" ok || chk "helper: rc=$rc" no
( cd "$W/hh" && bash tree-helper.sh nodisk out2.m lbl ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 1 ] && want "TREE-HELPER-FAILED: the disk /dev/disk/by-id/google-nodisk is not attached" && chk "a disk that is not attached is named" ok || chk "no disk: rc=$rc" no
( cd "$W/hh" && bash tree-helper.sh ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 1 ] && want "usage: tree-helper.sh" && chk "no arguments: the usage of the helper" ok || chk "helper usage: rc=$rc" no
grep -q "ro,noload,nosuid,nodev,noexec" "$H" && ! grep -q "mount -o rw" "$H" && chk "the helper only mounts READ-ONLY, without replaying the journal" ok || chk "mount flags" no
fi
echo; echo "pass: $pass   fail: $fail"
if [ "$fail" = 0 ]; then echo "P42-REHEARSAL-PASS"; else echo "P42-REHEARSAL-FAIL"; exit 1; fi
