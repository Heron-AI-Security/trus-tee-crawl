#!/usr/bin/env bash
# Step R5, the export. On the MASTER of a formed fleet, once, after the crawl (no operator command):
#   1. the WARC files are the ones the fetcher wrote during the crawl (Common Crawl's writer, warc.export.path=/tc/warc, through the wrapper, so each file has its signed record),
#      with the source receipts inside them; the receipt outcomes (tc_receipts/ of every segment) and the collection policy the receipts name are exported with them;
#   2. every WARC file is copied to local disk through the wrapper (the copy is VERIFIED: a file that does not match its record is refused), and so are its record and the identities of its folders;
#   3. a manifest lists every exported file with its SHA-256 and size (manifest.tsv, sorted, one line per file);
#   4. the manifest's SHA-384 is extended into RTMR3 as the event `export` (the last event of the log), and a new quote C (the same binding text as quotes A and B, whose log now ends with `export`)
#      is published as the guest attribute tc/export;
#   5. if the instance metadata tc-export-bucket names a bucket, every file is uploaded to it (object-creator only, never overwriting) and a DONE object closes the export.
# Hooks for the rehearsal only: TC_ROOT, TC_RUN, TC_LIB, TC_META, TC_QUOTE, TC_EXTEND, TC_STATE, TC_OUT, TC_CRAWL_MARK, TC_EXPORT_LOG, TC_AS.
set -uo pipefail
R="${TC_ROOT:-}"; RUN="${TC_RUN:-$R/run/tc}"; LIB="${TC_LIB:-$R/usr/local/lib/tc}"; META="${TC_META:-http://169.254.169.254/computeMetadata/v1}"
QUOTE="${TC_QUOTE:-$LIB/tc-quote.sh}"; EXTEND="${TC_EXTEND:-$LIB/tc-extend.sh}"; CONF="$R/etc/tc/crawl"; NUTCH="$R/opt/tc/nutch"; HB="$R/opt/hadoop/bin"
# The copy of the export (tens of GB at 1M seeds) goes to /var/lib/hadoop, which tc-scratch-bind binds to the scratch disk; the small state (marker, error, quote C) stays in /var/lib/tc-export on the root overlay (7.4 GB, too small for the copy).
STATE="${TC_STATE:-/var/lib/tc-export}"; OUT="${TC_OUT:-/var/lib/hadoop/tc-export-out}"; MARK="$STATE/done"; CMARK="${TC_CRAWL_MARK:-/var/lib/tc-crawl/done}"; LOGF="${TC_EXPORT_LOG:-/var/log/hadoop/tc-export.log}"
RUNUSER=/usr/sbin/runuser; [ -x "$RUNUSER" ] || RUNUSER=/sbin/runuser   # the unit's PATH has no sbin folder: runuser is called by its full path
AS="${TC_AS-$RUNUSER -u hadoop --}"; WARC=/tc/warc; EVLOG="$RUN/rtmr3-events.tsv"
fail() { echo "TC-EXPORT-FAIL: $*" >&2; mkdir -p "$STATE" 2>/dev/null; printf '%s\n' "$*" > "$STATE/error.txt" 2>/dev/null && put export-error "$STATE/error.txt" 2>/dev/null; exit 1; }   # the reason is also published (tc/export-error), so that the operator does not wait for a quote that will not come
log() { echo "$(date -u +%FT%TZ) tc-export: $*"; }
md() { curl -sf -H 'Metadata-Flavor: Google' "$META/$1"; }
put() { curl -sf -X PUT -H 'Metadata-Flavor: Google' --data-binary @"$2" "$META/instance/guest-attributes/tc/$1" >/dev/null; }
HD() { $AS "$HB/hdfs" dfs "$@"; }                                                                  # through the wrapper: reads are verified
HDP() { $AS "$HB/hdfs" dfs -D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem "$@"; }   # the plain client: the signed records and identities are copied as they are
[ -z "$AS" ] || [ -x "$RUNUSER" ] || fail "runuser is not at /usr/sbin/runuser or /sbin/runuser"
[ -f "$RUN/role-master" ] || fail "this is not the master of a formed fleet (no $RUN/role-master)"
[ -s "$CMARK" ] || fail "the crawl has not finished (no marker $CMARK)"
[ ! -e "$MARK" ] || { echo "the export was made already: $(cat "$MARK")"; exit 0; }
# BENCHMARK ONLY (branch bench/layer-flag): a fleet whose bench-layers is anything but fleet-wireguard-signing is a benchmark run, never a custody run, so it makes no export (with signing
# off there are no signed records to copy either). The skip is published as tc/export-skipped, so that the operator does not wait for a quote C that will not come.
if [ -s "$RUN/bench-layers" ] && [ "$(cat "$RUN/bench-layers")" != fleet-wireguard-signing ]; then
  mkdir -p "$STATE"; printf 'benchmark run (bench-layers %s): no export\n' "$(cat "$RUN/bench-layers")" > "$STATE/skipped.txt"
  put export-skipped "$STATE/skipped.txt" 2>/dev/null; echo "TC-EXPORT-SKIPPED: $(cat "$STATE/skipped.txt")"; exit 0
fi
P="$(grep '^HDFS_CRAWL_DIR=' "$CONF/params.env" | cut -d= -f2)"; [[ "$P" =~ ^/[A-Za-z0-9._/-]+$ ]] || fail "HDFS_CRAWL_DIR in $CONF/params.env is not an absolute HDFS path"
[ -s "$EVLOG" ] && [ -s "$RUN/sign.pub" ] && [ -s "$RUN/wg.key" ] && [ -s "$RUN/fleet.tsv" ] || fail "the fleet state in $RUN is incomplete"
NAME="$(md instance/name)" && [ -n "$NAME" ] || fail "could not read the instance name"
mkdir -p "$STATE" "$(dirname "$LOGF")" 2>/dev/null; : >> "$LOGF"
[ -s "$CONF/collection-policy.json" ] || fail "no collection policy in $CONF"
FILES="$(HD -ls -R "$WARC" 2>/dev/null | awk '$1 ~ /^-/ {print $NF}' | grep -E '\.warc(\.gz)?$' | LC_ALL=C sort)"; [ -n "$FILES" ] || fail "the crawl wrote no .warc or .warc.gz file under $WARC"
OUTC="$(HD -ls -R "$P/segments" 2>/dev/null | awk '$1 ~ /^-/ {print $NF}' | grep -E '/tc_receipts/[^/]+$' | LC_ALL=C sort)"; [ -n "$OUTC" ] || fail "the crawl wrote no receipt outcomes (tc_receipts/) under $P/segments"
FILES="$FILES
$OUTC"
rm -rf "$OUT"; mkdir -p "$OUT"; [ -z "$AS" ] || chown hadoop:hadoop "$OUT"
for f in $FILES; do
  [[ "$f" =~ ^/[A-Za-z0-9._/-]+$ ]] || fail "the name $f has characters that the manifest does not allow"
  d="$(dirname "$f")"; n="$(basename "$f")"; rel="${f#/}"
  $AS mkdir -p "$OUT/$(dirname "$rel")" || fail "could not make the folder for $f"
  HD -get "$f" "$OUT/$rel" >>"$LOGF" 2>&1 || fail "the verified copy of $f failed: the wrapper refused it, or the read failed (see $LOGF)"
  HDP -get "$d/.$n.attested" "$OUT/$(dirname "$rel")/.$n.attested" >>"$LOGF" 2>&1 || fail "the record of $f could not be copied"
  c="$d"; while [ "$c" != "/" ]; do
    rc="${c#/}"; if [ ! -f "$OUT/$rc/_attested-folder" ]; then $AS mkdir -p "$OUT/$rc"; HDP -get "$c/_attested-folder" "$OUT/$rc/_attested-folder" >>"$LOGF" 2>&1 || fail "the identity of the folder $c could not be copied"; fi
    c="$(dirname "$c")"; done
done
cp "$RUN/fleet.tsv" "$OUT/fleet.tsv" || fail "could not copy fleet.tsv"
cp "$CONF/collection-policy.json" "$OUT/collection-policy.json" || fail "could not copy the collection policy"
# the files are final: hand the folder to root and take write permission from everyone else BEFORE any hash is taken, so that a process of the hadoop user cannot swap a file between the check and the manifest (it can still read the files, for the upload)
[ -z "$AS" ] || { chown -R root:root "$OUT" && chmod -R go-w "$OUT"; } || fail "could not hand the export folder to root and make it read-only for the hadoop user"
LIST="$(cd "$OUT" && find . -type f ! -name manifest.tsv -printf '%P\n' | LC_ALL=C sort)"
{ echo "# tc-export-manifest v1"; while IFS= read -r p; do [[ "$p" =~ ^[A-Za-z0-9._/-]+$ ]] || fail "the file name $p is not allowed in the manifest"; printf '%s\t%s\t%s\n' "$(sha256sum "$OUT/$p" | cut -d' ' -f1)" "$(stat -c %s "$OUT/$p")" "$p"; done <<< "$LIST"; } > "$STATE/manifest.tmp" || fail "could not write the manifest"
mv "$STATE/manifest.tmp" "$OUT/manifest.tsv"; MSHA="$(sha384sum "$OUT/manifest.tsv" | cut -d' ' -f1)"; NF="$(grep -vc '^#' "$OUT/manifest.tsv")"
log "manifest: $NF files, SHA-384 ${MSHA:0:16}..."
TC_LOG="$EVLOG" "$EXTEND" export "$OUT/manifest.tsv" >/dev/null || fail "could not extend RTMR3 with the event export"
[ "$(cut -f1 "$EVLOG" | tail -1)" = export ] && [ "$(tail -1 "$EVLOG" | cut -f2)" = "$MSHA" ] || fail "the last event of the log is not export with the manifest's digest"
SIGN_PUB="$(cat "$RUN/sign.pub")"; WG_PUB="$(wg pubkey < "$RUN/wg.key" 2>/dev/null)"; [ -n "$WG_PUB" ] || fail "could not read the WireGuard public key"
LSHA="$(sha512sum "$EVLOG" | cut -d' ' -f1)"
printf 'tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n' "$NAME" "$SIGN_PUB" "$WG_PUB" "$LSHA" > "$RUN/binding-export.txt"
"$QUOTE" "$RUN/binding-export.txt" "$RUN/quote-export.bin" >/dev/null 2>&1 || fail "could not make quote C (the quote after the export)"
{ printf 'name=%s\nsign=%s\nwg=%s\nlog_sha512=%s\nmanifest_sha384=%s\n' "$NAME" "$SIGN_PUB" "$WG_PUB" "$LSHA" "$MSHA"; printf 'quote_b64=%s\n' "$(base64 -w0 "$RUN/quote-export.bin")"; printf 'log_b64=%s\n' "$(base64 -w0 "$EVLOG")"
  [ "$(stat -c %s "$OUT/manifest.tsv")" -lt 120000 ] && printf 'manifest_b64=%s\n' "$(base64 -w0 "$OUT/manifest.tsv")"; } > "$STATE/export-attr.txt"
put export "$STATE/export-attr.txt" || echo "note: could not publish quote C to the guest attributes" >&2
BUCKET="$(md instance/attributes/tc-export-bucket 2>/dev/null || true)"; UP=0
if [ -n "$BUCKET" ]; then
  [[ "$BUCKET" =~ ^[a-z0-9._-]{3,222}$ ]] || fail "the bucket name in tc-export-bucket is not valid"
  TOKEN="$(md instance/service-accounts/default/token 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["access_token"])' 2>/dev/null)"; [ -n "$TOKEN" ] || fail "no service account token: the VM has no service account, so nothing can be uploaded"
  PFX="export/$(sha384sum "$RUN/fleet.tsv" | cut -c1-16)/$NAME"
  up() { # OBJECT FILE: create only, never overwrite (ifGenerationMatch=0); the file is streamed (-T): --data-binary @file reads it into memory, and curl 7.81 refuses files over 2 GB (the 1M WARCs are 2.7 GB)
    local en; en="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$PFX/$1")"
    curl -sf -X POST -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/octet-stream' -T "$2" "https://storage.googleapis.com/upload/storage/v1/b/$BUCKET/o?uploadType=media&ifGenerationMatch=0&name=$en" >/dev/null || fail "the upload of $1 failed (an object that exists is never overwritten)"; UP=$((UP+1)); }
  while IFS= read -r p; do up "$p" "$OUT/$p"; done <<< "$LIST"
  up manifest.tsv "$OUT/manifest.tsv"; up export-attr.txt "$STATE/export-attr.txt"; printf '%s\n' "$MSHA" > "$STATE/done.tmp"; up DONE "$STATE/done.tmp"; rm -f "$STATE/done.tmp"
  log "uploaded $UP objects to gs://$BUCKET/$PFX/"
fi
printf 'export done %s files=%s manifest_sha384=%s uploaded=%s\n' "$(date -u +%FT%TZ)" "$NF" "$MSHA" "$UP" > "$MARK" || fail "could not write the marker $MARK"
log "done: $NF files, quote C published (tc/export), $UP objects uploaded"
