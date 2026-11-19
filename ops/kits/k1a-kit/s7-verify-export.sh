( set -uo pipefail
# Stage verify-export (step P5.6 part B and the whole verifier): the command ops/verify-export.py on the REAL run of this kit, with the published release of image A, the commit, and Google's endorsement and root,
# then the rehearsals on the same real run. What it requires of the real run: ALL TEN steps PASS (a full verification: the Intel chain of every quote, step 6; the signed Roughtime time, step 10), exit code 0, VERIFY-EXPORT-OK. Step 9 is the one that is new: every URL of the fetch list
# that tc-crawl.sh wrote from each segment's crawl_generate has exactly one outcome. If step 9 fails, its lines name the URLs, and "differs only by URL normalization" says that the two strings are the same address written differently.
cd ~/k1awork/tree || { echo "VERIFYEXPORT-FAILED: no ~/k1awork/tree"; exit 1; }
C="$(cat ~/k1a-commit.txt)"; E=~/evidence-k1a-f; P=~/k1a-p4/pub/publish; W=~/k1a-p56; rm -rf "$W"; mkdir -p "$W"
[ -d "$E/export" ] || { echo "VERIFYEXPORT-FAILED: no export in $E (the fleet stage did not finish)"; exit 1; }
[ -s "$P/reference.json" ] || { echo "VERIFYEXPORT-FAILED: no published reference in $P (the p4 stage publishes it: run the stages in order)"; exit 1; }
echo "== the fetch lists in the real export (written by tc-crawl.sh, signed by the wrapper, in the manifest):"
FLS="$(ls "$E"/export/tc/crawl/segments/*/tc_receipts/fetchlist.txt 2>/dev/null)"
[ -n "$FLS" ] || { echo "VERIFYEXPORT-FAILED: the export holds no fetchlist.txt in any segment: the image was built without the fetch-list step, or the crawl did not write it (see the crawl log on the master)"; exit 1; }
for f in $FLS; do echo "   $(echo "$f" | sed 's|.*/segments/||') : $(head -1 "$f") | record: $([ -f "$(dirname "$f")/.fetchlist.txt.attested" ] && echo present || echo MISSING) | in the manifest: $(grep -c "tc_receipts/fetchlist.txt$" "$E/export/manifest.tsv" | head -1) line(s) for all segments"; done
MRTD="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['mrtd'])" "$P/reference.json")"; MT="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['machine_type'])" "$P/reference.json")"
echo "== Google's endorsement of this MRTD (${MRTD:0:16}..., machine type $MT) and Google's root certificate, fetched over HTTPS"
curl -fsS -o "$W/endorsement.binarypb" "https://storage.googleapis.com/gce_tcb_integrity/ovmf_x64_csm/tdx/$MRTD.binarypb" || { echo "VERIFYEXPORT-FAILED: the endorsement could not be downloaded"; exit 1; }
curl -fsS -o "$W/root.crt" "https://pki.goog/cloud_integrity/GCE-cc-tcb-root_1.crt" || { echo "VERIFYEXPORT-FAILED: the root certificate could not be downloaded"; exit 1; }
echo "   endorsement $(stat -c %s "$W/endorsement.binarypb") bytes, root $(stat -c %s "$W/root.crt") bytes"
echo "== ops/verify-export.py on the real run (the published release of image A, the commit, the endorsement)"
OUT="$(PYTHONDONTWRITEBYTECODE=1 python3 ops/verify-export.py "$E" --published "$P" --commit "$C" --endorsement "$W/endorsement.binarypb" --google-root "$W/root.crt" 2>&1)"; RC=$?
printf '%s\n' "$OUT" > "$W/verify-export.txt"; printf '%s\n' "$OUT" | grep -E "^\[[0-9]+\]|^VERIFY-EXPORT" | cut -c1-175
printf '%s\n' "$OUT" | sed -n '/^\[9\]/,/^\[10\]/p' | grep -v "^\[10\]" | cut -c1-230; printf '%s\n' "$OUT" | sed -n '/^\[6\]/,/^\[7\]/p' | grep -v "^\[7\]" | cut -c1-230; printf '%s\n' "$OUT" | sed -n '/^\[10\]/,$p' | cut -c1-230
ok=1; for i in 1 2 3 4 5 6 7 8 9 10; do printf '%s\n' "$OUT" | grep -q "^\[$i\] PASS" || { echo "   step $i did not PASS"; ok=0; }; done
[ "$RC" = 0 ] && printf '%s\n' "$OUT" | grep -q "^VERIFY-EXPORT-OK" || { echo "   exit code $RC, expected 0 (VERIFY-EXPORT-OK: all ten steps)"; ok=0; }
[ "$ok" = 1 ] || { echo "VERIFYEXPORT-FAILED: the verifier did not give the expected result on the real run (the lines above say which step; the full output is $W/verify-export.txt)"; exit 1; }
echo "== the rehearsals on the real run (they damage COPIES of it; nothing of the evidence is changed)"
R1="$(PYTHONDONTWRITEBYTECODE=1 python3 ops/image/test/verify-export-rehearse.py "$E" --published "$P" --commit "$C" 2>&1)"; echo "$R1" > "$E/rehearsal-entry.txt"; echo "$R1" | grep -E "^FAIL|REHEARSAL" | cut -c1-300
echo "$R1" | grep -q "P5.1-REHEARSAL-OK" || { echo "$R1"; echo "VERIFYEXPORT-FAILED: the rehearsal of the entry point did not pass on the real run"; exit 1; }
R2="$(PYTHONDONTWRITEBYTECODE=1 python3 ops/attested/verify_fetchlist_rehearse.py "$E/export" 2>&1 | tail -3)"; echo "$R2" | tail -1 | cut -c1-200
echo "$R2" | grep -q "FETCHLIST-VERIFY-REHEARSAL-OK" || { echo "$R2"; echo "VERIFYEXPORT-FAILED: the rehearsal of the fetch-list check did not pass on the real export"; exit 1; }
R3="$(PYTHONDONTWRITEBYTECODE=1 python3 ops/attested/verify_export_records_rehearse.py "$E/export" 2>&1 | tail -1)"; echo "$R3" | cut -c1-200; echo "$R3" | grep -q "P5.2-REHEARSAL-OK" || { echo "VERIFYEXPORT-FAILED: the records rehearsal did not pass"; exit 1; }
R4F="$(PYTHONDONTWRITEBYTECODE=1 python3 ops/attested/verify_endorsement_rehearse.py 2>&1)"; echo "$R4F" > "$E/rehearsal-endorsement.txt"; R4="$(echo "$R4F" | tail -1)"; echo "$R4" | cut -c1-200; echo "$R4" | grep -q "P5.5-REHEARSAL-OK" || { echo "VERIFYEXPORT-FAILED: the endorsement rehearsal did not pass"; exit 1; }
R5="$(PYTHONDONTWRITEBYTECODE=1 python3 ops/attested/verify_intel_chain_rehearse.py "$E" "$P" 2>&1 | tail -1)"; echo "$R5" | cut -c1-200; echo "$R5" | grep -q "P5.3-REHEARSAL-OK" || { echo "VERIFYEXPORT-FAILED: the Intel chain rehearsal did not pass on the real run"; exit 1; }
R6="$(PYTHONDONTWRITEBYTECODE=1 python3 ops/attested/verify_time_export_rehearse.py "$E/export" 2>&1 | tail -1)"; echo "$R6" | cut -c1-200; echo "$R6" | grep -q "P5.7-REHEARSAL-OK" || { echo "VERIFYEXPORT-FAILED: the time rehearsal did not pass on the real export"; exit 1; }
PYTHONDONTWRITEBYTECODE=1 python3 ops/attested/verify_time_export.py "$E/export" > "$E/time-check.txt" 2>&1
echo "== the 1K report: the outcomes of the 908 seeds, the receipts, the timing, and then the mentor's eight tamper cases"; python3 -B "$(cd "$(dirname "$0")" && pwd)/k1a-report.py" "$E/export" "$(cd "$(dirname "$0")" && pwd)/profile-seeds.txt" "$E/master-log-lines.txt" | tee "$E/k1a-report.txt" | cut -c1-210; [ "${PIPESTATUS[0]}" = 0 ] || { echo "VERIFYEXPORT-FAILED: the seed report could not read the outcomes of the export"; exit 1; }
python3 -B "$(cd "$(dirname "$0")" && pwd)/k1a-eight.py" "$E" "$HOME/k1a-run/logs/verify.log" | tee "$E/eight-cases.txt" | cut -c1-230
tar czf ~/evidence-k1a-p56.tar.gz -C ~ k1a-p56 2>/dev/null; echo "evidence fingerprint of the stage: $(sha256sum ~/evidence-k1a-p56.tar.gz | cut -c1-64)"
echo "P56-VERIFY-OK commit=${C:0:9} fetch-lists=$(echo "$FLS" | wc -l) segments, ALL TEN steps PASS (VERIFY-EXPORT-OK)" )
