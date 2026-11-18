#!/usr/bin/env bash
# Step 12, verify-export: the verifier of an export (ops/verify-export.py) on the REAL run, with the published release of image A, the commit, Google's endorsement of the firmware and Google's root certificate. ALL TEN
# checks must pass (the Intel chain of every quote, the signed time, and that every URL of every fetch list has exactly one outcome). Then the rehearsals of the verifier run on COPIES of the real run: they damage
# the copies, never the evidence. Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; . "$KD/record.sh"; rk_load_names; . "$KD/steps/fleet-common.sh"
REC="$H/$CRAWL_RECORD"; PUB="$REC/reference"; WD="$H/$RUN_DIR/verify-export"; export PYTHONDONTWRITEBYTECODE=1; fail() { echo "VERIFY-EXPORT-FAILED: $*"; exit 1; }
[ -d "$OUTF/export" ] || fail "step 11 has not finished: there is no export in $OUTF"
[ -s "$PUB/reference.json" ] || fail "the published reference is missing in the build record ($PUB/reference.json): step 6 makes the verified copy"
[ -s "$OUTF/accept.txt" ] && grep -aqE "$RK_M_ACCEPT_OK" "$OUTF/accept.txt" || fail "step 11 has not finished: the acceptance of the run is not in $OUTF/accept.txt"
for f in $RK_T_VERIFY_EXPORT $RK_T_TIME_CHECK; do [ -f "$TREE/$f" ] || fail "$f is not in the commit tree $TREE"; done
rm -rf "$WD"; mkdir -p "$WD"
echo "== 1. the fetch lists in the real export"
FLS="$(ls "$OUTF"/export/tc/crawl/segments/*/tc_receipts/fetchlist.txt 2>/dev/null)"; NFL="$(echo "$FLS" | grep -c .)"
[ "$NFL" -ge 1 ] || fail "the export holds no fetchlist.txt in any segment (the image was built without the fetch-list step, or the crawl did not write it: see the crawl log on the master)"
echo "   $NFL fetch list(s), one per segment"
echo "== 2. Google's endorsement of the MRTD of image A, and Google's root certificate (over HTTPS)"
MRTD="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['mrtd'])" "$PUB/reference.json" 2>/dev/null)"; [[ "$MRTD" =~ ^[0-9a-f]{96}$ ]] || fail "the published reference holds no MRTD of 96 hexadecimal digits ($PUB/reference.json)"
curl -fsS --max-time 90 -o "$WD/endorsement.binarypb" "$RK_GOOGLE_ENDORSEMENT_URL/$MRTD.binarypb" || fail "the endorsement of Google could not be downloaded ($RK_GOOGLE_ENDORSEMENT_URL/${MRTD:0:16}...)"
curl -fsS --max-time 90 -o "$WD/root.crt" "$RK_GOOGLE_ROOT_URL" || fail "the root certificate of Google could not be downloaded ($RK_GOOGLE_ROOT_URL)"
echo "   endorsement $(stat -c %s "$WD/endorsement.binarypb") bytes, root certificate $(stat -c %s "$WD/root.crt") bytes"
echo "== 3. the verifier on the real run: all ten checks must pass"
OUTV="$(python3 "$TREE/$RK_T_VERIFY_EXPORT" "$OUTF" --published "$PUB" --commit "$COMMIT" --endorsement "$WD/endorsement.binarypb" --google-root "$WD/root.crt" 2>&1)"; RCV=$?
printf '%s\n' "$OUTV" > "$WD/verify-export.txt"; printf '%s\n' "$OUTV" | grep -aE "^\[[0-9]+\]|^VERIFY-EXPORT" | cut -c1-175 | sed 's/^/   /'
BAD=""; for i in 1 2 3 4 5 6 7 8 9 10; do printf '%s\n' "$OUTV" | grep -aq "^\[$i\] PASS" || BAD="$BAD $i"; done
if [ "$RCV" != 0 ] || ! printf '%s\n' "$OUTV" | grep -aqE "$RK_M_VERIFY_EXPORT_OK" || [ -n "$BAD" ]; then fail "the verifier did not accept the real run (exit $RCV; checks that did not pass:${BAD:- none}; the whole output is $WD/verify-export.txt)"; fi
echo "== 4. the rehearsals of the verifier, on COPIES of the real run (nothing of the evidence is changed)"
NR=0
for spec in "${RK_VERIFY_REHEARSALS[@]}"; do
  IFS='|' read -r script args marker <<< "$spec"; [ -f "$TREE/$script" ] || fail "$script is not in the commit tree $TREE"
  args="${args//\{E\}/$OUTF}"; args="${args//\{X\}/$OUTF/export}"; args="${args//\{P\}/$PUB}"; args="${args//\{C\}/$COMMIT}"
  OR="$(python3 "$TREE/$script" $args 2>&1)"; RCR=$?; printf '%s\n' "$OR" > "$WD/rehearsal-$(basename "$script" .py).txt"
  if [ "$RCR" != 0 ] || ! printf '%s\n' "$OR" | grep -aq -- "$marker"; then printf '%s\n' "$OR" | tail -n 6 | cut -c1-300 | sed 's/^/   | /'; fail "the rehearsal $(basename "$script") did not pass on the real run (the lines above; the whole output is $WD/rehearsal-$(basename "$script" .py).txt)"; fi
  NR=$((NR + 1)); echo "   $(basename "$script"): passed"
done
python3 "$TREE/$RK_T_TIME_CHECK" "$OUTF/export" > "$OUTF/time-check.txt" 2>&1 || fail "the check of the signed time of the export failed ($OUTF/time-check.txt)"
tar czf "$H/$RUN_DIR/verify-export.tar.gz" -C "$H/$RUN_DIR" verify-export 2>/dev/null; echo "   evidence fingerprint of this step: $(sha256sum "$H/$RUN_DIR/verify-export.tar.gz" | cut -c1-64)"
rk_result "the verifier accepts the real run end to end: all ten checks pass with the published release of image A, the commit $C9 and Google's endorsement, $NFL fetch list(s) hold exactly one outcome per URL, and $NR rehearsals on copies of the run pass"
