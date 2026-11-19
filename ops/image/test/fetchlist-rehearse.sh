#!/usr/bin/env bash
# fetchlist-rehearse.sh: rehearsal of the fetch-list step of tc-crawl.sh (step P5.6 part B). It runs the REAL tc-crawl.sh in its --fetchlist mode against a stub hdfs and a stub nutch (readseg) that print the real formats
# (Nutch's SegmentReader writes "Recno:: N" and "URL:: <url>" for every record of crawl_generate, in <output>/dump), and requires: the file format and the sorting, one file per segment in tc_receipts/, a scratch folder outside the segments
# that is removed, and a FAILURE (exit code 1, a named reason, and no marker) for a failed readseg, an empty fetch list, a line that is not an http(s) address, and no segment at all. It tests the LOGIC of the script; that the real
# hdfs and readseg behave as the stubs do is what the run on the cluster shows.   Usage: bash ops/image/test/fetchlist-rehearse.sh
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; LIBD="$HERE/../rootfs/usr/local/lib/tc"; CRAWL="$LIBD/tc-crawl.sh"; CONFSRC="$HERE/../rootfs/etc/tc/crawl"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT; bad=0; n=0
ok() { n=$((n+1)); if [ "$2" = 0 ]; then printf '  pass: %2d. %s\n' "$n" "$1"; else printf '  FAIL: %2d. %s\n' "$n" "$1"; bad=$((bad+1)); fi; }   # the form that the kit (s0-prepare.sh) reads: two spaces and FAIL for a failing check
newroot() {
  rm -rf "$T/root" "$T/fs" "$T/log"; mkdir -p "$T/root/etc/tc/crawl" "$T/root/opt/hadoop/bin" "$T/root/opt/tc/nutch/bin" "$T/fs/tc/crawl/segments" "$T/log"
  cp "$CONFSRC/params.env" "$CONFSRC/seeds.txt" "$T/root/etc/tc/crawl/"; echo '{}' > "$T/root/etc/tc/crawl/collection-policy.json"
  cat > "$T/root/opt/hadoop/bin/hdfs" <<'EOS'
#!/usr/bin/env bash
FS="$STUB_FS"; [ "$1" = dfs ] || exit 2; shift
case "$1" in
  -ls) p="$2"; [ -d "$FS$p" ] || { echo "ls: '$p': No such file or directory" >&2; exit 1; }
       for c in "$FS$p"/*; do [ -e "$c" ] || continue; b="$(basename "$c")"; if [ -d "$c" ]; then echo "drwxr-xr-x   - hadoop supergroup          0 2026-11-05 10:00 $p/$b"; else echo "-rw-r--r--   3 hadoop supergroup        100 2026-11-05 10:00 $p/$b"; fi; done ;;
  -cat) cat "$FS$2" ;;
  -put) shift; [ "$1" = -f ] && shift; mkdir -p "$(dirname "$FS$2")"; cp "$1" "$FS$2" ;;
  -mkdir) shift; [ "$1" = -p ] && shift; mkdir -p "$FS$1" ;;
  -rm) shift; while [ "${1:0:1}" = - ]; do shift; done; rm -rf "$FS$1" ;;
  *) echo "stub hdfs: unsupported $*" >&2; exit 2 ;;
esac
EOS
  cat > "$T/root/opt/tc/nutch/bin/nutch" <<'EOS'
#!/usr/bin/env bash
[ "$1" = readseg ] || exit 2; shift; while [ "$1" = -D ]; do shift 2; done; [ "$1" = -dump ] || exit 2; seg="$2"; out="$3"; shift 3
for f in -nocontent -nofetch -noparse -noparsedata -noparsetext; do case " $* " in *" $f "*) ;; *) echo "stub readseg: the option $f is missing" >&2; exit 2;; esac; done
[ -z "${STUB_NUTCH_FAIL:-}" ] || { echo "readseg: simulated failure" >&2; exit 1; }
mkdir -p "$STUB_FS$out"; i=0
{ if [ -f "$STUB_FS$seg/crawl_generate.txt" ]; then while IFS= read -r u; do printf '\nRecno:: %d\nURL:: %s\n\nCrawlDatum::\nVersion: 7\nStatus: 1 (db_unfetched)\nFetch time: Wed Nov 05 10:00:00 UTC 2026\nRetries since fetch: 0\nScore: 1.0\nMetadata: \n\t_ngt_=1793000000000\n\tURL:: not-a-record-key\n\t_depth_=1\n\n' "$i" "$u"; i=$((i+1)); done < "$STUB_FS$seg/crawl_generate.txt"; fi; } > "$STUB_FS$out/dump"
EOS
  chmod +x "$T/root/opt/hadoop/bin/hdfs" "$T/root/opt/tc/nutch/bin/nutch"
}
seg() { mkdir -p "$T/fs/tc/crawl/segments/$1"; [ -n "${2:-}" ] && printf '%s\n' "${@:2}" > "$T/fs/tc/crawl/segments/$1/crawl_generate.txt"; }
runit() { TC_ROOT="$T/root" TC_LOG="$T/log/crawl.log" TC_MARK="$T/log/marker" STUB_FS="$T/fs" bash "$CRAWL" "$@" > "$T/log/out.txt" 2>&1; echo $?; }
FL() { echo "$T/fs/tc/crawl/segments/$1/tc_receipts/fetchlist.txt"; }
newroot; seg 20261105100000 "https://b.example/page?x=1&y=%20z" "https://a.example/" "https://b.example/page?x=1&y=%20z" "http://c.example/z"; seg 20261105101500 "https://a.example/next" "https://a.example/"
rc="$(runit --fetchlist)"; ok "the fetch list of two segments is written (exit code 0)" "$rc"
f1="$(FL 20261105100000)"; [ "$(head -1 "$f1")" = "# tc-fetchlist v1 segment=20261105100000 count=3" ]; ok "the header names the segment and the number of URLs (duplicates counted once)" "$?"
[ "$(tail -n +2 "$f1")" = "$(printf '%s\n' 'http://c.example/z' 'https://a.example/' 'https://b.example/page?x=1&y=%20z')" ]; ok "the URLs are sorted (bytewise), unique and exactly as Nutch holds them, a query string included" "$?"
[ "$(head -1 "$(FL 20261105101500)")" = "# tc-fetchlist v1 segment=20261105101500 count=2" ]; ok "the second segment has its own file and its own count" "$?"
! grep -q "not-a-record-key" "$f1" "$(FL 20261105101500)"; ok "a line of the metadata that only looks like a URL line is not taken for a URL" "$?"
[ ! -e "$T/fs/tc/crawl-fetchlist-tmp" ]; ok "the scratch folder of the dumps is removed" "$?"
CD="$(grep '^HDFS_CRAWL_DIR=' "$CONFSRC/params.env" | cut -d= -f2)"; grep -q 'scratch="${P\[HDFS_CRAWL_DIR\]}-fetchlist-tmp"' "$CRAWL"; r1=$?; case "$CD-fetchlist-tmp" in "$CD"/*) r2=1;; *) r2=0;; esac; ok "the scratch folder (the crawl dir plus -fetchlist-tmp, here $CD-fetchlist-tmp) is outside the segments, so the export never picks it up" "$((r1+r2))"
grep -q "fetch lists: 2 segments, 5 urls" "$T/log/crawl.log"; ok "the log says how many segments and URLs" "$?"
! grep -q $'\r' "$f1" && [ "$(tail -c1 "$f1" | od -An -c | tr -d ' ')" = '\n' ]; ok "no carriage returns and the file ends with a newline" "$?"
rc="$(runit --fetchlist)"; [ "$rc" = 0 ] && [ "$(wc -l < "$f1")" = 4 ]; ok "running it again overwrites the files and gives the same result" "$?"
newroot; seg 20261105100000 "https://a.example/"; rc="$(STUB_NUTCH_FAIL=1 runit --fetchlist)"; [ "$rc" = 1 ] && grep -q "readseg could not dump" "$T/log/crawl.log" && [ ! -e "$(FL 20261105100000)" ]; ok "a failed readseg is a failure with its reason, and no fetch list is left" "$?"
newroot; seg 20261105100000 "https://a.example/"; seg 20261105101500; : > "$T/fs/tc/crawl/segments/20261105101500/crawl_generate.txt"; rc="$(runit --fetchlist)"; [ "$rc" = 1 ] && grep -q "fetch list of /tc/crawl/segments/20261105101500 is empty" "$T/log/crawl.log"; ok "an EMPTY fetch list is a failure, not a quiet success" "$?"
newroot; seg 20261105100000 "https://a.example/" "ftp://a.example/x"; rc="$(runit --fetchlist)"; [ "$rc" = 1 ] && grep -q "not a plain http(s) address" "$T/log/crawl.log"; ok "a line that is not an http(s) address is a failure" "$?"
newroot; seg 20261105100000 "https://a.example/ with space"; rc="$(runit --fetchlist)"; [ "$rc" = 1 ] && grep -q "not a plain http(s) address" "$T/log/crawl.log"; ok "a URL with a space in it is a failure" "$?"
newroot; rc="$(runit --fetchlist)"; [ "$rc" = 1 ] && grep -q "there is no segment" "$T/log/crawl.log"; ok "no segment at all is a failure" "$?"
newroot; python3 -c "
for i in range(20000): print('https://h%d.example/p/%d' % (i % 97, i))" > "$T/big.txt"; mkdir -p "$T/fs/tc/crawl/segments/20261105100000"; cp "$T/big.txt" "$T/fs/tc/crawl/segments/20261105100000/crawl_generate.txt"; rc="$(runit --fetchlist)"; [ "$rc" = 0 ] && [ "$(head -1 "$(FL 20261105100000)")" = "# tc-fetchlist v1 segment=20261105100000 count=20000" ] && [ "$(wc -l < "$(FL 20261105100000)")" = 20001 ]; ok "20,000 URLs: the count in the header and the number of lines agree" "$?"
newroot; rc="$(runit --check-params)"; [ "$rc" = 0 ] && grep -q "the parameters and the" "$T/log/out.txt"; ok "the existing --check-params mode still works" "$?"
bash -n "$CRAWL"; ok "tc-crawl.sh passes bash -n" "$?"
[ "$(grep -c '^fetchlist_all ||' "$CRAWL")" = 1 ] && [ "$(grep -n '^fetchlist_all ||' "$CRAWL" | cut -d: -f1)" -lt "$(grep -n "printf 'crawl done" "$CRAWL" | cut -d: -f1)" ]; ok "the crawl calls the fetch-list step exactly once, and before it leaves its marker" "$?"
grep -q -- "-nocontent -nofetch -noparse -noparsedata -noparsetext" "$CRAWL"; ok "readseg is asked for the fetch list only (the five options that drop everything else)" "$?"
echo; echo "pass: $((n-bad))   fail: $bad"; [ "$bad" = 0 ] && echo "FETCHLIST-REHEARSAL-PASS" || { echo "FETCHLIST-REHEARSAL-FAIL"; exit 1; }
