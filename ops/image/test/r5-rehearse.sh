#!/usr/bin/env bash
# Rehearsal of step R5 (the export) with stand-ins: the REAL tc-export.sh and the REAL tc-extend.sh against a fake master (a fake HDFS that tells the wrapper from the plain client, what the crawl left in it (the WARC files and receipt outcomes), the metadata
# server, a bucket that never overwrites, the quote helper). Every check that matters is also made to FAIL on purpose.
#   bash r5-rehearse.sh KITDIR      KITDIR holds ops/image and attest
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; PASS=0; FAILN=0
chk() { local t="$1"; shift; if [ "${1:-1}" = 0 ]; then echo "  pass: $t"; PASS=$((PASS+1)); else echo "  FAIL: $t"; FAILN=$((FAILN+1)); fi; }
W="$(mktemp -d)"; STUB="$W/bin"; mkdir -p "$STUB" "$W/lib"; cp "$I/rootfs/usr/local/lib/tc/tc-extend.sh" "$KIT/attest/measure/treehash.sh" "$W/lib/"; chmod +x "$W/lib"/*
cat > "$W/fakewrite.py" <<'PYEOF'
import hashlib, sys
p = sys.argv[1]; d = sys.stdin.buffer.read(); cur = open(p, "rb").read(); open(p, "wb").write(hashlib.sha384(cur + d).digest())
PYEOF
cat > "$W/quote.py" <<'PYEOF'
import hashlib, sys
inp, out, reg = sys.argv[1:4]; q = bytearray(8000); q[520:568] = open(reg, "rb").read(); q[568:632] = hashlib.sha512(open(inp, "rb").read()).digest(); open(out, "wb").write(q)
PYEOF
printf '#!/usr/bin/env bash\nexec python3 "%s" "$1" "$2" "${FAKE_REG:?}"\n' "$W/quote.py" > "$W/quote.sh"; chmod +x "$W/quote.sh"
cat > "$W/mkattr.py" <<'PYEOF'
import base64, hashlib, sys
name, sign, wg, logf, regf, out = sys.argv[1:7]; log = open(logf, "rb").read(); ls = hashlib.sha512(log).hexdigest()
binding = ("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (name, sign, wg, ls)).encode(); q = bytearray(8000); q[520:568] = open(regf, "rb").read(); q[568:632] = hashlib.sha512(binding).digest()
open(out, "w").write("name=%s\nsign=%s\nwg=%s\nlog_sha512=%s\nquote_b64=%s\nlog_b64=%s\n" % (name, sign, wg, ls, base64.b64encode(bytes(q)).decode(), base64.b64encode(log).decode()))
PYEOF
cat > "$STUB/wg" <<'EOS'
#!/usr/bin/env bash
case "$1" in pubkey) python3 -c 'import sys,base64,hashlib; print(base64.b64encode(hashlib.sha256(sys.stdin.buffer.read()).digest()).decode())' ;; esac
EOS
cat > "$STUB/curl" <<'EOS'
#!/usr/bin/env bash
# fake metadata server and fake bucket: FAKE_SD (puts), FAKE_GCS (objects), FAKE_BUCKET, FAKE_TOKEN
method=GET; file=""; auth=""; args=("$@"); url="${args[$((${#args[@]}-1))]}"; i=0
while [ $i -lt ${#args[@]} ]; do a="${args[$i]}"; case "$a" in -X) i=$((i+1)); method="${args[$i]}" ;; -H) i=$((i+1)); case "${args[$i]}" in Authorization:*) auth="${args[$i]}" ;; esac ;; --data-binary) i=$((i+1)); file="${args[$i]#@}" ;; -T|--upload-file) i=$((i+1)); file="${args[$i]}" ;; esac; i=$((i+1)); done
case "$method $url" in
  "PUT "*/guest-attributes/tc/*) cp "$file" "$FAKE_SD/put.$(basename "$url")"; exit 0 ;;
  "GET "*/instance/name) echo "$FAKE_NAME"; exit 0 ;;
  "GET "*/instance/attributes/tc-export-bucket) [ -n "${FAKE_BUCKET:-}" ] && echo "$FAKE_BUCKET" && exit 0; exit 22 ;;
  "GET "*/service-accounts/default/token) [ -n "${FAKE_TOKEN:-}" ] && echo '{"access_token":"tok123","expires_in":3000}' && exit 0; exit 22 ;;
  "POST https://storage.googleapis.com/upload/storage/v1/b/"*)
    q="${url#*/b/}"; b="${q%%/*}"; qs="${q#*\?}"; name="$(python3 -c 'import sys,urllib.parse; print(urllib.parse.unquote(sys.argv[1].split("name=",1)[1]))' "$qs")"
    [ "$auth" = "Authorization: Bearer tok123" ] || exit 22; case "$qs" in *ifGenerationMatch=0*) ;; *) exit 22 ;; esac
    [ "$b" = "${FAKE_BUCKET:-}" ] || exit 22; dst="$FAKE_GCS/$b/$name"; [ -e "$dst" ] && exit 22; mkdir -p "$(dirname "$dst")"; cp "$file" "$dst"; echo "$name" >> "$FAKE_GCS/order.log"; exit 0 ;;
esac; exit 22
EOS
cat > "$STUB/nutch-warc" <<'EOS'
#!/usr/bin/env bash
# a tripwire: the export runs no Nutch job of its own any more (the fetcher wrote the WARC files during the crawl)
echo "$*" >> "$FAKE_HDFS/../nutch-called.log"; exit 1
EOS
cat > "$STUB/fake-crawl" <<'EOS'
#!/usr/bin/env bash
# what the crawl leaves in the fake HDFS: the fetcher's WARC files (warc.export.path=/tc/warc) with the source receipts inside, and the receipt outcomes of a segment
# (tc_receipts/), each file with a record that holds its SHA-256, and every folder with its identity
H="$FAKE_HDFS"; out=/tc/warc; idf() { local c="$1"; while [ "$c" != / ]; do mkdir -p "$H$c"; [ -f "$H$c/_attested-folder" ] || echo "ID-$(basename "$c")" > "$H$c/_attested-folder"; c="$(dirname "$c")"; done; }
rec() { [ -n "${FAKE_NORECORD:-}" ] || printf 'sha256=%s\n' "$(sha256sum "$1" | cut -d' ' -f1)" > "$(dirname "$1")/.$(basename "$1").attested"; }
if [ -z "${FAKE_NUTCH_NOFILES:-}" ]; then idf "$out"
  for n in $(seq 1 "${FAKE_NUTCH_N:-1}"); do b="NUTCH-CRAWL-00$n-0.warc.gz"; [ -n "${FAKE_NUTCH_REAL:-}" ] && b="part-r-0000$((n-1)).seg-00000.attempt-00000.warc"
    f="$H$out/$b"; head -c $((3000 + n)) /dev/urandom > "$f"; rec "$f"; done; fi
if [ -z "${FAKE_NO_OUTCOMES:-}" ]; then t=/tc/crawl/segments/20261022000000/tc_receipts; idf "$t"; f="$H$t/outcomes-attempt_1_0001_m_000000_0.jsonl"; head -c 500 /dev/urandom > "$f"; FAKE_NORECORD= rec "$f"; fi
EOS
cat > "$STUB/hdfs-fake" <<'EOS'
#!/usr/bin/env bash
# fake `hdfs dfs [-D k=v] -test -e P | -ls -R P | -get SRC DST`; the wrapper (no -D) hides the companions and VERIFIES every -get against the record; the plain client (-D) does neither
H="$FAKE_HDFS"; [ "$1" = dfs ] || exit 2; shift; plain=0; [ "$1" = -D ] && { plain=1; shift 2; }
case "$1" in
  -test) [ -e "$H$3" ] ;;
  -ls) for f in $(cd "$H$3" && find . -type f ! -name '.*' ! -name '_attested-folder' | sort); do printf -- '-rw-r--r--   2 hadoop supergroup %8d 2026-10-22 15:00 %s\n' "$(stat -c %s "$H$3/$f")" "$3/${f#./}"; done ;;
  -get) src="$H$2"; [ -f "$src" ] || { echo "get: no such file" >&2; exit 1; }
        if [ $plain = 0 ]; then rec="$(dirname "$src")/.$(basename "$src").attested"; [ -f "$rec" ] && [ "$(cut -d= -f2 "$rec")" = "$(sha256sum "$src" | cut -d' ' -f1)" ] || { echo "get: Attested verification failed for $2" >&2; exit 1; }; fi
        cp "$src" "$3" ;;
  *) exit 2 ;;
esac
EOS
chmod +x "$STUB"/*; export PATH="$STUB:$PATH"
mkrun() { # NAME: a fresh fake master after a successful crawl, with the log of a formed fleet (quote B state)
  N="$W/$1"; rm -rf "$N"; mkdir -p "$N/run" "$N/state" "$N/root/etc/tc/crawl" "$N/root/opt/hadoop/bin" "$N/root/opt/tc/nutch/bin" "$N/sd" "$N/gcs" "$N/hdfs/tc/crawl/segments/20261022000000"
  cp "$STUB/hdfs-fake" "$N/root/opt/hadoop/bin/hdfs"; cp "$STUB/nutch-warc" "$N/root/opt/tc/nutch/bin/nutch"
  printf '{"version":2}' > "$N/root/etc/tc/crawl/collection-policy.json"; printf 'HDFS_CRAWL_DIR=/tc/crawl\nROUNDS=3\nMAP_MEMORY_MB=2048\nMAP_JAVA_OPTS=-Xmx1536m\nREDUCE_MEMORY_MB=2048\nREDUCE_JAVA_OPTS=-Xmx1536m\n' > "$N/root/etc/tc/crawl/params.env"; touch "$N/run/role-master"; printf 'MFkw' > "$N/run/sign.pub"; printf 'wgkeybytes' > "$N/run/wg.key"
  WGPUB="$(printf 'wgkeybytes' | wg pubkey)"; printf '# tc-fleet v1\ntc-r5-m\tmaster\t10.10.0.1\t10.0.0.1:51820\tMFkw\t%s\ntc-r5-w\tworker\t10.10.0.2\t10.0.0.2:51820\tCCC\tDDD\n' "$WGPUB" > "$N/run/fleet.tsv"
  head -c 48 /dev/zero > "$N/rtmr3.bin"; echo a > "$N/f1"; echo b > "$N/f2"
  for e in "tc-lib $N/f1" "tc-conf $N/f2" "fleet $N/run/fleet.tsv" "fleet-conf $N/f2"; do set -- $e; env TC_LOG="$N/run/rtmr3-events.tsv" TC_RTMR3="$N/rtmr3.bin" TC_WRITE="python3 $W/fakewrite.py $N/rtmr3.bin" bash "$W/lib/tc-extend.sh" "$1" "$2" >/dev/null; done
  cp "$N/run/rtmr3-events.tsv" "$N/logB.tsv"; cp "$N/rtmr3.bin" "$N/rtmr3-B.bin"; mkdir -p "$N/op"; cp "$N/run/fleet.tsv" "$N/op/"; python3 "$W/mkattr.py" tc-r5-m MFkw "$WGPUB" "$N/logB.tsv" "$N/rtmr3-B.bin" "$N/op/final-tc-r5-m.txt"; echo "crawl done 2026-10-22T15:05:09Z fetched=8 segments=3 rounds=3" > "$N/crawl-done"; }
runexp() { # [ENV=VALUE ...]: what the crawl left (once), then the real export script on the fake master $N
  [ -e "$N/crawled" ] || { env "$@" FAKE_HDFS="$N/hdfs" bash "$STUB/fake-crawl"; touch "$N/crawled"; }
  out="$(env "$@" TC_ROOT="$N/root" TC_RUN="$N/run" TC_LIB="$W/lib" TC_META=http://meta TC_QUOTE="$W/quote.sh" TC_EXTEND="$W/lib/tc-extend.sh" TC_STATE="$N/state" TC_OUT="$N/state/out" TC_CRAWL_MARK="$N/crawl-done" TC_EXPORT_LOG="$N/export.log" TC_AS="" \
    FAKE_SD="$N/sd" FAKE_GCS="$N/gcs" FAKE_HDFS="$N/hdfs" FAKE_NAME=tc-r5-m FAKE_REG="$N/rtmr3.bin" TC_RTMR3="$N/rtmr3.bin" TC_WRITE="python3 $W/fakewrite.py $N/rtmr3.bin" bash "$I/rootfs/usr/local/lib/tc/tc-export.sh" 2>&1)"; rc=$?; }
echo "=== A. a successful export, without a bucket"
mkrun a; runexp FAKE_NUTCH_N=2; echo "$out" | tail -2 | cut -c1-150
OUTD="$N/state/out"; M="$OUTD/manifest.tsv"
chk "the export runs no WARC job of its own: the WARC files are the ones the fetcher wrote during the crawl" $([ ! -e "$N/nutch-called.log" ]; echo $?)
chk "the export succeeds (exit 0) and writes its marker" $([ $rc = 0 ] && grep -q '^export done .* files=' "$N/state/done"; echo $?)
chk "both WARC files, their records and the identities of /tc/warc and /tc are exported, with fleet.tsv and the manifest (mirrored paths)" $(ok=0; for p in tc/warc/NUTCH-CRAWL-001-0.warc.gz tc/warc/NUTCH-CRAWL-002-0.warc.gz tc/warc/.NUTCH-CRAWL-001-0.warc.gz.attested tc/warc/.NUTCH-CRAWL-002-0.warc.gz.attested tc/warc/_attested-folder tc/_attested-folder fleet.tsv manifest.tsv; do [ -f "$OUTD/$p" ] || ok=1; done; echo $ok)
chk "the receipt outcomes are exported with their record and the identity of every folder up to /tc, and so is the collection policy the receipts name" $(ok=0; T=tc/crawl/segments/20261022000000/tc_receipts; for p in $T/outcomes-attempt_1_0001_m_000000_0.jsonl $T/.outcomes-attempt_1_0001_m_000000_0.jsonl.attested $T/_attested-folder tc/crawl/segments/20261022000000/_attested-folder tc/crawl/segments/_attested-folder tc/crawl/_attested-folder; do [ -f "$OUTD/$p" ] || ok=1; done; cmp -s "$OUTD/collection-policy.json" "$N/root/etc/tc/crawl/collection-policy.json" || ok=1; echo $ok)
chk "the manifest has one line per file (not itself), sorted, with the right SHA-256 and size" $(ok=0; [ "$(head -1 $M)" = "# tc-export-manifest v1" ] || ok=1; [ "$(grep -vc '^#' $M)" = 14 ] || ok=1; grep -q manifest.tsv <(grep -v '^#' $M) && ok=1; while IFS=$'\t' read -r h s p; do [ "$(sha256sum "$OUTD/$p" | cut -d' ' -f1)" = "$h" ] && [ "$(stat -c %s "$OUTD/$p")" = "$s" ] || ok=1; done < <(grep -v '^#' $M); [ "$(grep -v '^#' $M | cut -f3)" = "$(grep -v '^#' $M | cut -f3 | LC_ALL=C sort)" ] || ok=1; echo $ok)
chk "the log is the log of quote B plus ONE event, export, last, whose digest is the SHA-384 of the manifest" $([ "$(wc -l < $N/run/rtmr3-events.tsv)" = "$(( $(wc -l < $N/logB.tsv) + 1 ))" ] && cmp -s <(cut -f1-4 "$N/logB.tsv") <(head -n "$(wc -l < $N/logB.tsv)" "$N/run/rtmr3-events.tsv" | cut -f1-4) && [ "$(tail -1 $N/run/rtmr3-events.tsv | cut -f1)" = export ] && [ "$(tail -1 $N/run/rtmr3-events.tsv | cut -f2)" = "$(sha384sum $M | cut -d' ' -f1)" ]; echo $?)
ATT="$N/sd/put.export"; OP="$N/op"; cp "$ATT" "$OP/export-tc-r5-m.txt"
out2="$(python3 "$I/test/f1-fleet.py" export-check "$OP" "$OUTD" tc-r5-m 2>&1)"; chk "the operator's checker accepts the export: quote C is consistent (binding, chain, RTMR3), its log is the log of B plus export, the manifest matches the event, every file matches (rule E8)" $([ $? = 0 ] && grep -q '^EXPORT-OK' <<<"$out2"; echo $?)
chk "the attribute carries the manifest and its SHA-384" $(grep -q "^manifest_sha384=$(sha384sum $M | cut -d' ' -f1)" $ATT && [ "$(grep '^manifest_b64=' $ATT | cut -d= -f2- | base64 -d | sha384sum | cut -d' ' -f1)" = "$(sha384sum $M | cut -d' ' -f1)" ]; echo $?)
chk "nothing was uploaded: no bucket is named in the metadata" $([ ! -s "$N/gcs/order.log" ] && grep -q 'uploaded=0' "$N/state/done"; echo $?)
runexp FAKE_NUTCH_N=2; chk "a second run does nothing: the marker says that the export was made already (no new event)" $([ $rc = 0 ] && grep -q 'made already' <<<"$out" && [ "$(wc -l < $N/run/rtmr3-events.tsv)" = "$(( $(wc -l < $N/logB.tsv) + 1 ))" ]; echo $?)
echo "=== A2. the file names that the REAL exporter writes (plain .warc, as seen on the cluster on 23 October 2026)"
mkrun r; runexp FAKE_NUTCH_N=1 FAKE_NUTCH_REAL=1; OUTD="$N/state/out"; OP="$N/op"; cp "$N/sd/put.export" "$OP/export-tc-r5-m.txt"
chk "a plain .warc file named like the real exporter's (part-r-00000.seg-00000.attempt-00000.warc) is exported with its record and identities, and the export succeeds" $([ $rc = 0 ] && [ -f "$OUTD/tc/warc/part-r-00000.seg-00000.attempt-00000.warc" ] && [ -f "$OUTD/tc/warc/.part-r-00000.seg-00000.attempt-00000.warc.attested" ] && [ -f "$OUTD/tc/warc/_attested-folder" ] && [ -f "$OUTD/tc/_attested-folder" ]; echo $?)
out2="$(python3 "$I/test/f1-fleet.py" export-check "$OP" "$OUTD" tc-r5-m 2>&1)"; chk "the operator's checker accepts that export" $([ $? = 0 ] && grep -q '^EXPORT-OK' <<<"$out2"; echo $?)
XD="$W/xdr"; rm -rf "$XD"; cp -r "$OUTD" "$XD"; python3 - "$XD" <<'PYX'
import sys
d = sys.argv[1]; ls = [l for l in open(d + "/manifest.tsv").read().splitlines() if not l.endswith(".warc.attested")]; open(d + "/manifest.tsv", "w").write("\n".join(ls) + "\n")
PYX
rm "$XD/tc/warc/.part-r-00000.seg-00000.attempt-00000.warc.attested"; out2="$(python3 "$I/test/f1-fleet.py" export-check "$OP" "$XD" tc-r5-m 2>&1)"; chk "fault: a plain .warc file without its record is refused by the checker too (here the manifest was cut to fit, so the event catches it, and the record rule would)" $([ $? != 0 ] && grep -q 'SHA-384 of the manifest is not the digest\|has no record' <<<"$out2"; echo $?)
echo "=== B. with a bucket"
mkrun b; runexp FAKE_NUTCH_N=2 FAKE_BUCKET=bkt-tc FAKE_TOKEN=1; echo "$out" | tail -2 | cut -c1-160; OUTD="$N/state/out"; PFX="export/$(sha384sum $N/run/fleet.tsv | cut -c1-16)/tc-r5-m"
chk "the export succeeds with a bucket and says how many objects it uploaded" $([ $rc = 0 ] && grep -q 'uploaded=17' "$N/state/done"; echo $?)
chk "every exported file is in the bucket under the prefix export/<fleet SHA-384>/<node>/, identical to the local file, with manifest.tsv, export-attr.txt and DONE" $(ok=0; for p in $(cd $OUTD && find . -type f -printf '%P\n'); do cmp -s "$OUTD/$p" "$N/gcs/bkt-tc/$PFX/$p" || ok=1; done; cmp -s "$N/state/export-attr.txt" "$N/gcs/bkt-tc/$PFX/export-attr.txt" || ok=1; [ -f "$N/gcs/bkt-tc/$PFX/DONE" ] || ok=1; echo $ok)
chk "DONE is the LAST object, and DONE holds the manifest's SHA-384 (an export without DONE is incomplete)" $([ "$(tail -1 $N/gcs/order.log)" = "$PFX/DONE" ] && [ "$(cat $N/gcs/bkt-tc/$PFX/DONE)" = "$(sha384sum $OUTD/manifest.tsv | cut -d' ' -f1)" ]; echo $?)
mkrun b2; mkdir -p "$N/gcs/bkt-tc/export/$(sha384sum $N/run/fleet.tsv | cut -c1-16)/tc-r5-m"; echo old > "$N/gcs/bkt-tc/export/$(sha384sum $N/run/fleet.tsv | cut -c1-16)/tc-r5-m/manifest.tsv"
runexp FAKE_NUTCH_N=2 FAKE_BUCKET=bkt-tc FAKE_TOKEN=1; chk "fault: an object that exists is never overwritten: the upload fails, the export fails, and no marker is written" $([ $rc != 0 ] && grep -q 'never overwritten' <<<"$out" && [ ! -e "$N/state/done" ]; echo $?)
mkrun b3; runexp FAKE_NUTCH_N=1 FAKE_BUCKET=bkt-tc; chk "fault: a bucket without a service account token fails (the VM has no service account), nothing is uploaded" $([ $rc != 0 ] && grep -q 'no service account token' <<<"$out" && [ ! -s "$N/gcs/order.log" ]; echo $?)
mkrun b4; runexp FAKE_NUTCH_N=1 FAKE_BUCKET='bad bucket' FAKE_TOKEN=1; chk "fault: an invalid bucket name is refused before anything is sent" $([ $rc != 0 ] && grep -q 'not valid' <<<"$out"; echo $?)
echo "=== C. what the export refuses"
mkrun c1; rm "$N/crawl-done"; runexp; chk "fault: no crawl marker: refused" $([ $rc != 0 ] && grep -q 'crawl has not finished' <<<"$out"; echo $?)
mkrun c2; rm "$N/run/role-master"; runexp; chk "fault: not the master: refused" $([ $rc != 0 ] && grep -q 'not the master' <<<"$out"; echo $?)
mkrun c3; rm "$N/root/etc/tc/crawl/collection-policy.json"; runexp; chk "fault: no collection policy in the image: refused" $([ $rc != 0 ] && grep -q 'no collection policy' <<<"$out"; echo $?)
mkrun c4; runexp FAKE_NO_OUTCOMES=1; chk "fault: the crawl wrote no receipt outcomes: the export fails and no event is added" $([ $rc != 0 ] && grep -q 'no receipt outcomes' <<<"$out" && [ "$(wc -l < $N/run/rtmr3-events.tsv)" = "$(wc -l < $N/logB.tsv)" ]; echo $?)
chk "a failed export publishes its reason as the guest attribute tc/export-error (the operator need not wait for a quote that will not come)" $(grep -q 'no receipt outcomes' "$N/sd/put.export-error"; echo $?)
mkrun c5; runexp FAKE_NUTCH_NOFILES=1; chk "fault: a job that writes no .warc.gz file: refused" $([ $rc != 0 ] && grep -q 'no .warc or .warc.gz file' <<<"$out"; echo $?)
mkrun c6; runexp FAKE_NUTCH_N=1 FAKE_NORECORD=1; chk "fault: a WARC file without its record is refused by the wrapper (the verified copy fails), and no event is added" $([ $rc != 0 ] && grep -q 'verified copy' <<<"$out" && [ "$(wc -l < $N/run/rtmr3-events.tsv)" = "$(wc -l < $N/logB.tsv)" ] && [ ! -s "$N/sd/put.export" ]; echo $?)
mkrun c7; FAKE_NUTCH_N=1 FAKE_HDFS="$N/hdfs" bash "$STUB/fake-crawl"; touch "$N/crawled"; printf "x" >> "$N/hdfs/tc/warc/NUTCH-CRAWL-001-0.warc.gz"   # a byte is added after the record was made: the file no longer matches its record
runexp FAKE_NUTCH_N=1; chk "fault: a WARC file that does not match its record is refused by the wrapper (the verified copy fails), nothing is published" $([ $rc != 0 ] && grep -q 'verified copy' <<<"$out" && [ ! -s "$N/sd/put.export" ] && [ ! -e "$N/state/done" ]; echo $?)
echo "=== E. the operator's checker refuses a damaged export (rule E8)"
mkrun e; runexp FAKE_NUTCH_N=2; OUTD="$N/state/out"; OP="$N/op"; cp "$N/sd/put.export" "$OP/export-tc-r5-m.txt"
efault() { # TEXT EXPECTED-WORDS: the checker must refuse the export folder $XD (and the operator folder $OP) with those words
  out2="$(python3 "$I/test/f1-fleet.py" export-check "$OP" "$XD" tc-r5-m ${REF:+"$REF"} 2>&1)"; chk "fault: $1" $([ $? != 0 ] && grep -q "$2" <<<"$out2"; echo $?); }
XD="$W/xd1"; rm -rf "$XD"; cp -r "$OUTD" "$XD"; printf 'x' >> "$XD/tc/warc/NUTCH-CRAWL-001-0.warc.gz"; efault "a changed byte in an exported WARC file" 'differs from the manifest'
XD="$W/xd2"; rm -rf "$XD"; cp -r "$OUTD" "$XD"; rm "$XD/tc/warc/NUTCH-CRAWL-002-0.warc.gz"; efault "a file of the manifest that is missing" 'is not in the export'
XD="$W/xd3"; rm -rf "$XD"; cp -r "$OUTD" "$XD"; echo extra > "$XD/tc/warc/extra.txt"; efault "a file that is in the export and not in the manifest" 'not in the manifest'
XD="$W/xd4"; rm -rf "$XD"; cp -r "$OUTD" "$XD"; echo "$(cat $XD/manifest.tsv)" > "$XD/manifest.tsv"; printf '0000000000000000000000000000000000000000000000000000000000000000\t1\tzzz\n' >> "$XD/manifest.tsv"; efault "a manifest that is not the one that the event export measured" 'SHA-384 of the manifest is not the digest'
XD="$W/xd5"; rm -rf "$XD"; cp -r "$OUTD" "$XD"; echo changed >> "$XD/fleet.tsv"; python3 - "$XD" <<'PYX'
import hashlib, sys, os
d = sys.argv[1]; ls = []
for l in open(d + "/manifest.tsv").read().splitlines():
    if l.startswith("#") or not l.strip(): ls.append(l); continue
    h, sz, p = l.split("\t")
    if p == "fleet.tsv": h = hashlib.sha256(open(d + "/fleet.tsv", "rb").read()).hexdigest(); sz = str(os.path.getsize(d + "/fleet.tsv"))
    ls.append("\t".join([h, sz, p]))
open(d + "/manifest.tsv", "w").write("\n".join(ls) + "\n")
PYX
efault "a fleet.tsv that is not the list that the nodes measured (even with a manifest that was made to fit)" 'SHA-384 of the manifest is not the digest\|exported fleet.tsv is not the list'
XD="$W/xd6"; rm -rf "$XD"; cp -r "$OUTD" "$XD"; python3 - "$XD" <<'PYX'
import hashlib, sys
d = sys.argv[1]; ls = [l for l in open(d + "/manifest.tsv").read().splitlines() if not l.endswith(".NUTCH-CRAWL-001-0.warc.gz.attested")]; open(d + "/manifest.tsv", "w").write("\n".join(ls) + "\n")
PYX
rm "$XD/tc/warc/.NUTCH-CRAWL-001-0.warc.gz.attested"; efault "a WARC file without its record in the export (the manifest was cut to fit, so only the event can catch it)" 'SHA-384 of the manifest is not the digest\|has no record'
XD="$OUTD"; cp "$OP/final-tc-r5-m.txt" "$W/B.keep"; grep -v '^tc-conf' "$N/logB.tsv" > /dev/null; python3 - "$N" "$W" <<'PYX'
import hashlib, sys
n, w = sys.argv[1:3]; ls = open(n + "/logB.tsv").read().splitlines(); reg = bytes(48); out = []
for l in ls:
    name, digest, before, after = l.split("\t")
    if name == "tc-conf": continue
    nr = hashlib.sha384(reg + bytes.fromhex(digest)).digest(); out.append("\t".join([name, digest, reg.hex(), nr.hex()])); reg = nr
open(w + "/logB2.tsv", "w").write("\n".join(out) + "\n"); open(w + "/regB2.bin", "wb").write(reg)
PYX
python3 "$W/mkattr.py" tc-r5-m MFkw "$(printf 'wgkeybytes' | wg pubkey)" "$W/logB2.tsv" "$W/regB2.bin" "$OP/final-tc-r5-m.txt"; efault "quote B whose log is not the log that C continues (C is not B plus export)" 'not the log of quote B followed by exactly one event'
cp "$W/B.keep" "$OP/final-tc-r5-m.txt"; python3 "$W/mkattr.py" tc-r5-m OTHERKEY "$(printf 'wgkeybytes' | wg pubkey)" "$N/logB.tsv" "$N/rtmr3-B.bin" "$OP/final-tc-r5-m.txt"; efault "quote B and quote C that carry different keys" 'different keys\|not the keys of its row'
cp "$W/B.keep" "$OP/final-tc-r5-m.txt"; REF="$W/ref.json"; python3 - "$N" "$REF" <<'PYX'
import json, sys
n, out = sys.argv[1:3]; ev = [l.split("\t")[:2] for l in open(n + "/logB.tsv").read().splitlines()]
json.dump({"image": "tc-img-test", "machine_type": "c3-standard-4", "mrtd": "00" * 48, "rtmr0": "ff" * 48, "rtmr1": "00" * 48, "rtmr2": "00" * 48, "events_in_order": [e[0] for e in ev], "stable_events": {e[0]: e[1] for e in ev if e[0] not in ("fleet", "fleet-conf")}, "per_run_events": ["fleet", "fleet-conf"]}, open(out, "w"))
PYX
XD="$OUTD"; efault "a quote C whose platform register differs from the reference values" 'RTMR0'
REF=""
echo "=== D. the files"
U="$I/rootfs/usr/local/lib/tc/units/tc-export.service"; S="$I/rootfs/usr/local/lib/tc/tc-export.sh"; UP="$(grep '^Environment=' "$U" | grep -o 'PATH=[^ ]*' | head -1 | cut -d= -f2)"
chk "every external command of tc-export.sh that is installed here lives in a folder of the unit's PATH ($UP); runuser, which does not, is called by its full path and never by its bare name" $(ok=0; for c in curl python3 wg sha256sum sha384sum sha512sum base64 stat find awk grep cut sort mkdir chown cp mv cat date dirname basename printf head tail tr rm xxd dd; do p="$(PATH=/usr/bin:/bin:/usr/sbin:/sbin command -v $c 2>/dev/null)"; [ -n "$p" ] || continue; case "$p" in /*) ;; *) continue ;; esac; case ":$UP:" in *":$(dirname "$p"):"*) ;; *) echo "   outside the unit's PATH: $c ($p)" >&2; ok=1 ;; esac; done; grep -q '^RUNUSER=/usr/sbin/runuser' "$S" || ok=1; [ -z "$(grep -v '^#' "$S" | grep -E '(^|[^/A-Za-z_$])runuser([^A-Za-z_]|$)' | grep -v 'RUNUSER=' | grep -v 'fail "runuser is not at')" ] || ok=1; echo $ok)
echo "--- the operator's wait for quote C stops at once when the master reports a failure"
FG="$W/fg"; mkdir -p "$FG"; cat > "$FG/gcloud" <<'EOS'
#!/usr/bin/env bash
q=""; for a in "$@"; do case "$a" in --query-path=*) q="${a#--query-path=}" ;; esac; done
case "$q" in tc/export-error) [ -n "${FAKE_EXPORT_ERROR:-}" ] && echo "$FAKE_EXPORT_ERROR" ;; tc/export) [ -n "${FAKE_EXPORT_OK:-}" ] && echo "name=tc-f1-m" ;; esac; exit 0
EOS
chmod +x "$FG/gcloud"; OPD="$W/opwait"; rm -rf "$OPD"; mkdir -p "$OPD"
out3="$(PATH="$FG:$PATH" IMG=x OUT="$OPD" FAKE_EXPORT_ERROR='the WARC export job failed (see /var/log/hadoop/tc-export.log)' timeout 20 bash "$I/test/f1-drive.sh" export-wait 2>&1)"; chk "fault: a failure reported by the master ends export-wait at once, with the reason" $([ $? != 0 ] && grep -q 'the export failed on the master: the WARC export job failed' <<<"$out3"; echo $?)
out3="$(PATH="$FG:$PATH" IMG=x OUT="$OPD" FAKE_EXPORT_OK=1 timeout 20 bash "$I/test/f1-drive.sh" export-wait 2>&1)"; chk "control: when quote C is published, export-wait ends and says so" $([ $? = 0 ] && grep -q 'published quote C' <<<"$out3"; echo $?)
chk "the operator tool states rule E8 and has the mode export-check" $(grep -q " E8 " "$I/test/f1-fleet.py" && grep -q 'mode == "export-check"' "$I/test/f1-fleet.py"; echo $?)
chk "the unit runs on the master only, once, after the crawl, as root with the baked script, and systemd keys are the usual ones" $(U="$I/rootfs/usr/local/lib/tc/units/tc-export.service"; grep -q '^ConditionPathExists=/run/tc/role-master' $U && grep -q '^ConditionPathExists=!/var/lib/tc-export/done' $U && grep -q '^After=.*tc-crawl.service' $U && grep -q '^Requires=tc-crawl.service' $U && grep -q '^ExecStart=/usr/local/lib/tc/tc-export.sh' $U && grep -q '^StateDirectory=tc-export' $U; echo $?)
chk "the fleet bake installs the script and the unit and enables it" $(grep -q 'tc-export.sh' "$I/build/tc-image-fleet.sh" && grep -q 'tc-crawl tc-export"' "$I/build/tc-image-fleet.sh"; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "R5-REHEARSAL-PASS: the real export script and the real extend script, against a fake master"; else echo "R5-REHEARSAL-FAIL"; fi
[ "$FAILN" = 0 ]
