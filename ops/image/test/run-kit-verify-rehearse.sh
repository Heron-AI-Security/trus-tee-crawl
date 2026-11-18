#!/usr/bin/env bash
# Rehearsal of crawl steps 11 to 13 (verify-run, verify-export, clean-up), run through the REAL run-kit.sh and the real steps.
#   bash run-kit-verify-rehearse.sh TREE        (no cloud and no network: fake verification tools, a fake driver, a fake curl and a fake gcloud, each with one switch for every failure; a throwaway HOME)
# Checked: step 11 gives every tool exactly what it must get (the export, the job console and the measurements of the builds FROM THE RECORD, the commit, R4_LOCKED), needs the success line AND the exit status of every
# tool, saves the serial consoles; step 12 downloads Google's endorsement of the MRTD of the published reference, needs ALL TEN checks to pass, runs every rehearsal of the verifier with the right arguments, and
# refuses a missing fetch list or acceptance; step 13 deletes the fleet only after the export is verified, deletes nothing else, checks that no VM is left, stops the poller and packs the evidence. Mutants of the
# steps (each check removed in turn, run in parallel) must all be caught by the same cases.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W0="$(mktemp -d)"; W="$W0"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W0"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1${3:+ | $3}"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
for f in 11-verify-run 12-verify-export 13-clean-up; do [ -f "$K/steps/$f.sh" ] || { echo "RUN-KIT-VERIFY-REHEARSAL-FAIL: $f.sh is missing in $K/steps"; exit 1; }; done
COMMIT_FULL=0123456789abcdef0123456789abcdef01234567; C9=${COMMIT_FULL:0:9}; RUN=1k-s1c0p1; M="tc-$RUN-m"; WB="tc-$RUN-w"; NV=4; MRTD="$(printf 'ab%.0s' $(seq 1 48))"

mkdir -p "$W0/fakebin"
cat > "$W0/fakebin/gcloud" <<'EOG'
#!/bin/sh
echo "$*" >> "$CTL/gcloud.log"
case "$*" in
  "compute instances list "*) [ -s "$CTL/vms" ] && cat "$CTL/vms"; exit 0 ;;
  "compute instances get-serial-port-output "*) echo "boot line"; n=$(cat "$CTL/ro-lines" 2>/dev/null || echo 0); i=0; while [ "$i" -lt "$n" ]; do echo "[ 1.0] sh: write error: Read-only file system"; i=$((i + 1)); done ;;
esac
exit 0
EOG
cat > "$W0/fakebin/curl" <<'EOC'
#!/bin/sh
echo "$*" >> "$CTL/curl.log"; out=""; url=""; while [ $# -gt 0 ]; do case "$1" in -o) out="$2"; shift ;; http*) url="$1" ;; esac; shift; done
[ -e "$CTL/curl-fail" ] && exit 22; echo "fake content of $url" > "$out"; exit 0
EOC
chmod +x "$W0/fakebin/gcloud" "$W0/fakebin/curl"
mkstepsdir() {  # KITDIR IDS...: a step folder whose crawl list holds only the named steps (11 12 13) and whose files are links to the kit in KITDIR
  local D="$1"; shift; rm -rf "$W/sd"; mkdir -p "$W/sd/steps"
  for f in names.sh lib.sh record.sh tools.sh steps-build.sh; do ln -s "$D/$f" "$W/sd/$f"; done
  for f in "$D"/steps/*.sh; do ln -s "$f" "$W/sd/steps/$(basename "$f")"; done
  { echo 'RK_STEPS=('; for id in "$@"; do case "$id" in 11) echo '"11|verify-run|Verify the run|steps/11-verify-run.sh"' ;; 12) echo '"12|verify-export|Verify the export|steps/12-verify-export.sh"' ;; 13) echo '"13|clean-up|Delete the fleet|steps/13-clean-up.sh"' ;; esac; done; echo ')'; } > "$W/sd/steps-crawl.sh"
}
pystub() {  # PATH BODY: a python tool that logs its call and then runs BODY (sw NAME is true when the switch file NAME exists)
  mkdir -p "$(dirname "$1")"; { echo 'import os, sys'; echo 'C = os.path.join(os.path.dirname(os.environ["HOME"]), "ctl")'; echo 'def sw(n): return os.path.exists(os.path.join(C, n))'; echo 'open(os.path.join(C, "tools.log"), "a").write("%s %s\n" % (os.path.basename(sys.argv[0]), " ".join(sys.argv[1:])))'; echo "$2"; } > "$1"
}
setup() {  # a fresh home: the tree with fake tools, the export of a run, the verified record, the evidence of the fleet
  rm -rf "$W/home" "$W/ctl"; mkdir -p "$W/home" "$W/ctl"; B="$W/home/build-$C9"; TR="$B/tree"; OUTD="$W/home/evidence-$RUN"; REC="$W/home/run-$RUN/record"; WDIR="$W/home/run-$RUN/verify-export"
  mkdir -p "$TR/ops/image/test" "$TR/ops/attested" "$OUTD/export/tc/crawl/segments/seg1/tc_receipts" "$REC/a/measurements" "$REC/b/measurements" "$REC/reference"
  echo "$COMMIT_FULL" > "$B/commit.txt"; echo us-central1-b > "$OUTD/zone.txt"; printf '# fleet\n1\tmaster\t%s\n' "$M" > "$OUTD/fleet.tsv"; echo f1 > "$OUTD/export/f1"; echo "1 url" > "$OUTD/export/tc/crawl/segments/seg1/tc_receipts/fetchlist.txt"
  printf '%s\n' "$M" "${WB}1" "${WB}2" "${WB}3" > "$W/ctl/vms"
  echo "$COMMIT_FULL" > "$REC/commit.txt"; echo abcd > "$REC/source.sha256"; printf 'img1\nimg2\n' > "$REC/images.txt"; echo agree > "$REC/compare.txt"; echo "{\"mrtd\": \"$MRTD\", \"machine_type\": \"c3-standard-4\"}" > "$REC/reference/reference.json"
  for i in a b; do echo ev > "$REC/$i/measurements/events.tsv"; echo us-central1-a > "$REC/$i/zone.txt"; echo r > "$REC/$i/seal-report.txt"; echo "job console $i" > "$REC/$i/job-console.txt"; done
  cat > "$TR/ops/image/test/f1-drive.sh" <<'EOD'
#!/usr/bin/env bash
C="$(dirname "$HOME")/ctl"; echo "ARGS $*" >> "$C/driver.log"
env | grep -E '^(IMG|OUT|WORKERS|VMM|VMW|VMWBASE|ZONE)=' | sort | sed 's/^/ENV /' >> "$C/driver.log"
for st in "$@"; do case "$st" in
  export-check) [ -e "$C/export-check-fail" ] && { echo "STOP: the export is not accepted: the manifest differs"; exit 1; }; echo "export accepted" ;;
  reference-values) [ -e "$C/refvals-none" ] || echo '{"commit": "x", "rtmr2": "y"}' > "$OUT/reference-values.json" ;;
  fleet-delete) [ -e "$C/delete-fail" ] && { echo "STOP: could not delete the fleet"; exit 1; }; [ -e "$C/delete-leaves" ] || : > "$C/vms" ;;
esac; done
exit 0
EOD
  pystub "$TR/ops/image/test/r3-export-audit.py" 'if sw("audit-fail"): print("AUDIT-PROBLEMS (2)"); sys.exit(1)
if not sw("audit-nomarker"): print("AUDIT-OK")
if sw("audit-rc1"): sys.exit(1)'
  pystub "$TR/ops/image/test/r3-receipt-verify.py" 'if sw("receipt-fail"): print("FAIL: receipt 7 does not verify"); print("RECEIPT-VERIFY-PROBLEMS (1): x"); sys.exit(1)
if not sw("receipt-nomarker"): print("RECEIPT-VERIFY-OK")
if sw("receipt-rc1"): sys.exit(1)'
  cat > "$TR/ops/image/test/r4-accept.sh" <<'EOD'
#!/usr/bin/env bash
C="$(dirname "$HOME")/ctl"; echo "r4-accept R4_LOCKED=${R4_LOCKED:-} $*" >> "$C/tools.log"
[ -e "$C/accept-fail" ] && { echo "R4-ACCEPT-FAILED: the builds disagree with the run"; exit 1; }
[ -e "$C/accept-nomarker" ] || echo "R4-ACCEPT-OK: the image was built by 2 independent builds"; [ -e "$C/accept-rc1" ] && exit 1; exit 0
EOD
  pystub "$TR/ops/verify-export.py" 'if sw("verify-fail"):
    print("[1] PASS ok"); print("[4] FAIL the quote does not chain"); print("VERIFY-EXPORT-FAILED: check(s) 4 failed"); sys.exit(1)
n = 9 if sw("verify-nine") else 10
for i in range(1, n + 1): print("[%d] PASS check %d" % (i, i))
if not sw("verify-nomarker"): print("VERIFY-EXPORT-OK: all %d checks passed" % n)
if sw("verify-rc1"): sys.exit(1)'
  for s in "ops/image/test/verify-export-rehearse.py|P5.1-REHEARSAL-OK" "ops/attested/verify_fetchlist_rehearse.py|FETCHLIST-VERIFY-REHEARSAL-OK" "ops/attested/verify_export_records_rehearse.py|P5.2-REHEARSAL-OK" "ops/attested/verify_endorsement_rehearse.py|P5.5-REHEARSAL-OK" "ops/attested/verify_intel_chain_rehearse.py|P5.3-REHEARSAL-OK" "ops/attested/verify_time_export_rehearse.py|P5.7-REHEARSAL-OK"; do
    pystub "$TR/${s%%|*}" "if sw('rehearsal-fail-$(basename "${s%%|*}")'): print('the rehearsal broke'); sys.exit(1)
if not sw('rehearsal-nomarker'): print('${s##*|}')
if sw('rehearsal-rc1'): sys.exit(1)"
  done
  pystub "$TR/ops/attested/verify_time_export.py" 'if sw("time-fail"): print("the signed time is wrong"); sys.exit(1)
print("time ok")'
  echo "R4-ACCEPT-OK: the image was built by 2 independent builds" > "$OUTD/accept.txt"
}

suite() {  # DIR: all the checks against the kit in DIR (W is the working folder of this suite)
  local D="$1" o rc SL
  rk() { env HOME="$W/home" CTL="$W/ctl" PATH="$W0/fakebin:$PATH" RK_STEPS_DIR="$W/sd" RK_HEARTBEAT_SECS=0.2 timeout 40 bash "$D/run-kit.sh" crawl --build "$COMMIT_FULL" --size 1k --storage on --comms off --provenance on --workers 3 --until "$1" 2>&1; }
  refused() { [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "^STEP $1 FAILED" && printf '%s' "$o" | grep -qF -- "$2: $3"; }
  t() { o="$(rk "$2")"; rc=$?; refused "$3" "$4" "$5" && chk "$1" ok || chk "$1" bad "exit $rc: $(printf '%s' "$o" | grep -E 'FAILED' | head -2 | tr '\n' ' ' | cut -c1-260)"; }
  tl() { grep -c "$1" "$W/ctl/tools.log" 2>/dev/null; }
  # ---- step 11
  mkstepsdir "$D" 11; setup; echo 3 > "$W/ctl/ro-lines"; o="$(rk verify-run)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 11 DONE: the run is verified against the build: the export passes the audit, the receipts verify independently of the fleet, and the independent builds of $C9 agree with every stable event of the real fleet (12 console lines say read-only file system: information only)" && chk "step 11: a good verification, with the number of read-only lines of the consoles (3 on each of the 4 consoles)" ok || chk "step 11: a good verification" bad "exit $rc: $(printf '%s' "$o" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  [ "$(grep ARGS "$W/ctl/driver.log" | tr -d '\n')" = "ARGS export-check reference-values" ] && ! grep -q '^ENV ZONE=' "$W/ctl/driver.log" && chk "step 11 calls the driver once with the stages export-check and reference-values, and passes no ZONE" ok || chk "step 11 calls the driver once with the stages export-check and reference-values, and passes no ZONE" bad "$(grep -E 'ARGS|ZONE' "$W/ctl/driver.log" | tr '\n' ' ')"
  grep -q "^r3-export-audit.py $OUTD/export\$" "$W/ctl/tools.log" && grep -q "^r3-receipt-verify.py $OUTD/export $REC/a/job-console.txt\$" "$W/ctl/tools.log" && chk "the audit gets the export, and the receipts are verified against the job console of build A FROM THE RECORD" ok || chk "the audit gets the export, and the receipts are verified against the job console of build A FROM THE RECORD" bad "$(grep -E 'audit|receipt' "$W/ctl/tools.log" | tr '\n' ' ')"
  grep -q "^r4-accept R4_LOCKED=1 $OUTD $COMMIT_FULL $REC/a/measurements $REC/b/measurements\$" "$W/ctl/tools.log" && chk "the acceptance gets the evidence folder, the full commit, and the measurements of builds A and B from the record, with R4_LOCKED=1" ok || chk "the acceptance gets the evidence folder, the full commit, and the measurements of builds A and B from the record, with R4_LOCKED=1" bad "$(grep r4-accept "$W/ctl/tools.log")"
  [ "$(ls "$OUTD"/serial-tc-"$RUN"-*.txt 2>/dev/null | wc -l)" = "$NV" ] && chk "the serial consoles of all $NV VMs are saved" ok || chk "the serial consoles of all $NV VMs are saved" bad "$(ls "$OUTD" | tr '\n' ' ')"
  setup; touch "$W/ctl/export-check-fail"; o="$(rk verify-run)"; rc=$?; refused 11 VERIFY-RUN-FAILED "the export is not accepted by the driver" && printf '%s' "$o" | grep -q "STOP: the export is not accepted" && chk "an export that the driver does not accept is refused, with the last lines of the driver" ok || chk "an export that the driver does not accept is refused, with the last lines of the driver" bad "exit $rc"
  setup; touch "$W/ctl/refvals-none"; t "a driver that writes no reference values is refused" verify-run 11 VERIFY-RUN-FAILED "the driver wrote no reference values"
  setup; touch "$W/ctl/audit-fail"; o="$(rk verify-run)"; rc=$?; refused 11 VERIFY-RUN-FAILED "the audit of the export found problems" && printf '%s' "$o" | grep -q "AUDIT-PROBLEMS" && chk "an audit that finds problems is refused, with its lines" ok || chk "an audit that finds problems is refused, with its lines" bad "exit $rc"
  setup; touch "$W/ctl/audit-nomarker"; t "an audit that ends without its success line is refused" verify-run 11 VERIFY-RUN-FAILED "the audit of the export found problems"
  setup; touch "$W/ctl/audit-rc1"; t "an audit that prints its success line but exits with an error is refused" verify-run 11 VERIFY-RUN-FAILED "the audit of the export found problems"
  setup; touch "$W/ctl/receipt-fail"; o="$(rk verify-run)"; rc=$?; refused 11 VERIFY-RUN-FAILED "the receipts do not verify" && printf '%s' "$o" | grep -q "FAIL: receipt 7" && chk "receipts that do not verify are refused, with the failing lines" ok || chk "receipts that do not verify are refused, with the failing lines" bad "exit $rc"
  setup; touch "$W/ctl/receipt-nomarker"; t "a receipt check that ends without its success line is refused" verify-run 11 VERIFY-RUN-FAILED "the receipts do not verify"
  setup; touch "$W/ctl/receipt-rc1"; t "a receipt check that prints its success line but exits with an error is refused" verify-run 11 VERIFY-RUN-FAILED "the receipts do not verify"
  setup; touch "$W/ctl/accept-fail"; t "an acceptance that fails is refused" verify-run 11 VERIFY-RUN-FAILED "the independent builds do not agree with the real run"
  setup; touch "$W/ctl/accept-nomarker"; t "an acceptance that ends without its success line is refused" verify-run 11 VERIFY-RUN-FAILED "the independent builds do not agree with the real run"
  setup; touch "$W/ctl/accept-rc1"; t "an acceptance that prints its success line but exits with an error is refused" verify-run 11 VERIFY-RUN-FAILED "the independent builds do not agree with the real run"
  setup; rm -rf "$OUTD/export"; t "a run without an export is refused, and step 10 is named" verify-run 11 VERIFY-RUN-FAILED "step 10 has not finished"
  setup; rm "$REC/compare.txt"; t "an incomplete build record is refused" verify-run 11 VERIFY-RUN-FAILED "the verified build record is missing or incomplete"
  setup; rm "$TR/ops/image/test/r4-accept.sh"; t "a missing tool is refused, and the tool is named" verify-run 11 VERIFY-RUN-FAILED "ops/image/test/r4-accept.sh is not in the commit tree"
  # ---- step 12
  mkstepsdir "$D" 11 12; setup; o="$(rk verify-export)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 12 DONE: the verifier accepts the real run end to end: all ten checks pass with the published release of image A, the commit $C9 and Google's endorsement, 1 fetch list(s) hold exactly one outcome per URL, and 6 rehearsals on copies of the run pass" && chk "step 12: the verifier accepts the run end to end, and all six rehearsals pass" ok || chk "step 12: the verifier accepts the run end to end" bad "exit $rc: $(printf '%s' "$o" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  grep -q "^verify-export.py $OUTD --published $REC/reference --commit $COMMIT_FULL --endorsement $WDIR/endorsement.binarypb --google-root $WDIR/root.crt\$" "$W/ctl/tools.log" && chk "the verifier gets the evidence folder, the published reference FROM THE RECORD, the full commit, the endorsement and the root" ok || chk "the verifier gets the evidence folder, the published reference FROM THE RECORD, the full commit, the endorsement and the root" bad "$(grep '^verify-export.py' "$W/ctl/tools.log" | cut -c1-250)"
  grep -q "tdx/$MRTD.binarypb" "$W/ctl/curl.log" && grep -q "GCE-cc-tcb-root_1.crt" "$W/ctl/curl.log" && chk "Google's endorsement is fetched for the MRTD of the published reference, and Google's root certificate with it" ok || chk "Google's endorsement is fetched for the MRTD of the published reference, and Google's root certificate with it" bad "$(cut -c1-150 "$W/ctl/curl.log" | tr '\n' ' ')"
  grep -q "^verify-export-rehearse.py $OUTD --published $REC/reference --commit $COMMIT_FULL\$" "$W/ctl/tools.log" && grep -q "^verify_fetchlist_rehearse.py $OUTD/export\$" "$W/ctl/tools.log" && grep -q "^verify_intel_chain_rehearse.py $OUTD $REC/reference\$" "$W/ctl/tools.log" && grep -q "^verify_endorsement_rehearse.py \$" "$W/ctl/tools.log" && chk "every rehearsal gets its own arguments (evidence folder, export, published reference, commit)" ok || chk "every rehearsal gets its own arguments" bad "$(grep rehearse "$W/ctl/tools.log" | tr '\n' ' ' | cut -c1-300)"
  setup; touch "$W/ctl/curl-fail"; t "an endorsement that cannot be downloaded is refused" verify-export 12 VERIFY-EXPORT-FAILED "the endorsement of Google could not be downloaded"
  setup; echo '{"mrtd": "xyz", "machine_type": "c3-standard-4"}' > "$REC/reference/reference.json"; t "a published reference without a valid MRTD is refused" verify-export 12 VERIFY-EXPORT-FAILED "the published reference holds no MRTD"
  setup; touch "$W/ctl/verify-fail"; o="$(rk verify-export)"; rc=$?; refused 12 VERIFY-EXPORT-FAILED "the verifier did not accept the real run" && printf '%s' "$o" | grep -q "\[4\] FAIL" && chk "a verifier that fails a check is refused, and the failing check is shown" ok || chk "a verifier that fails a check is refused, and the failing check is shown" bad "exit $rc"
  setup; touch "$W/ctl/verify-nine"; t "a verifier that passes only nine of the ten checks is refused, even with exit 0 and its success line" verify-export 12 VERIFY-EXPORT-FAILED "the verifier did not accept the real run (exit 0; checks that did not pass: 10"
  setup; touch "$W/ctl/verify-nomarker"; t "a verifier that passes ten checks but ends without its success line is refused" verify-export 12 VERIFY-EXPORT-FAILED "the verifier did not accept the real run"
  setup; touch "$W/ctl/verify-rc1"; t "a verifier that prints its success line but exits with an error is refused" verify-export 12 VERIFY-EXPORT-FAILED "the verifier did not accept the real run"
  setup; touch "$W/ctl/rehearsal-fail-verify_endorsement_rehearse.py"; t "a rehearsal that fails on the real run is refused, and the rehearsal is named" verify-export 12 VERIFY-EXPORT-FAILED "the rehearsal verify_endorsement_rehearse.py did not pass on the real run"
  setup; touch "$W/ctl/rehearsal-rc1"; t "a rehearsal that prints its success line but exits with an error is refused" verify-export 12 VERIFY-EXPORT-FAILED "the rehearsal verify-export-rehearse.py did not pass on the real run"
  setup; touch "$W/ctl/rehearsal-nomarker"; t "a rehearsal that ends without its success line is refused" verify-export 12 VERIFY-EXPORT-FAILED "the rehearsal verify-export-rehearse.py did not pass on the real run"
  setup; rm -rf "$OUTD/export/tc"; t "an export without any fetch list is refused" verify-export 12 VERIFY-EXPORT-FAILED "the export holds no fetchlist.txt in any segment"
  setup; touch "$W/ctl/time-fail"; t "a failing check of the signed time is refused" verify-export 12 VERIFY-EXPORT-FAILED "the check of the signed time of the export failed"
  mkstepsdir "$D" 12; setup; rm "$OUTD/accept.txt"; t "step 12 without the acceptance of step 11 is refused, and step 11 is named" verify-export 12 VERIFY-EXPORT-FAILED "step 11 has not finished"
  # ---- step 13
  mkstepsdir "$D" 11 12 13; setup; SL="3000.$BASHPID"; mkdir -p "$W/home/run-$RUN"; ( setsid nohup sleep "$SL" > /dev/null 2>&1 < /dev/null & echo $! > "$W/home/run-$RUN/poller.pid" ); o="$(rk clean-up)"; rc=$?; sleep 0.3
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 13 DONE: the $NV VMs of the run $RUN are deleted; the evidence is packed in $W/home/evidence-$RUN.tar.gz" && chk "step 13: the fleet is deleted and the evidence is packed" ok || chk "step 13: the fleet is deleted and the evidence is packed" bad "exit $rc: $(printf '%s' "$o" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  [ "$(grep ARGS "$W/ctl/driver.log" | tail -1)" = "ARGS fleet-delete" ] && [ ! -s "$W/ctl/vms" ] && chk "step 13 calls the driver with the stage fleet-delete only, and no VM of the run is left" ok || chk "step 13 calls the driver with the stage fleet-delete only, and no VM of the run is left" bad "$(grep ARGS "$W/ctl/driver.log" | tail -2 | tr '\n' ' ')"
  ! pgrep -f "^sleep $SL" > /dev/null && [ ! -e "$W/home/run-$RUN/poller.pid" ] && chk "step 13 stops the poller of the console" ok || { pkill -f "^sleep $SL"; chk "step 13 stops the poller of the console" bad; }
  tar tzf "$W/home/evidence-$RUN.tar.gz" 2>/dev/null | grep -q "evidence-$RUN/accept.txt" && chk "the packed evidence holds the evidence folder of the run" ok || chk "the packed evidence holds the evidence folder of the run" bad
  mkstepsdir "$D" 13; setup; t "step 13 before the export is verified is refused, and the fleet is kept" clean-up 13 CLEAN-UP-FAILED "step 12 has not finished: the export is not verified, so the fleet is kept"
  mkstepsdir "$D" 11 12 13; setup; touch "$W/ctl/delete-fail"; t "a fleet that cannot be deleted is refused" clean-up 13 CLEAN-UP-FAILED "the fleet could not be deleted"
  setup; touch "$W/ctl/delete-leaves"; t "a deletion that leaves VMs of the run is refused, and they are named" clean-up 13 CLEAN-UP-FAILED "VMs of this run still exist after the deletion: $M"
  mkstepsdir "$D" 13; setup; mkdir -p "$WDIR"; echo "VERIFY-EXPORT-OK: all 10 checks passed" > "$WDIR/verify-export.txt"; : > "$W/ctl/vms"; o="$(rk clean-up)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "no VM of this run exists" && [ ! -s "$W/ctl/driver.log" ] && chk "a run whose VMs are gone is cleaned up without any driver call" ok || chk "a run whose VMs are gone is cleaned up without any driver call" bad "exit $rc"
}

echo "== the checks of steps 11 to 13 with fake verification tools, a fake driver, curl and cloud"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
if [ -n "${NO_MUTANTS:-}" ]; then echo; echo "checks of steps 11 to 13 (mutants skipped): $REAL_PASS passed, $REAL_FAIL failed"; exit 0; fi
echo "== the mutants (each check removed in turn, run in parallel; each one must be caught by at least one check above)"
NM=0; mkdir -p "$W0/mres"
mutant() {  # NAME FILE OLD NEW: replaces the exact text OLD of the file (relative to the kit) by NEW, and runs the whole suite on the result in the background
  NM=$((NM + 1)); local n=$NM name="$1"
  ( W="$W0/m$n"; mkdir -p "$W/m/steps"; cp "$K"/*.sh "$W/m/"; cp "$K"/steps/*.sh "$W/m/steps/"
    python3 - "$W/m/$2" "$3" "$4" <<'PY' || { echo "changed-nothing" > "$W0/mres/$n"; exit 0; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PY
    V=0; PASS=0; FAIL=0; suite "$W/m" > /dev/null 2>&1; echo "$FAIL" > "$W0/mres/$n" ) &
  echo "$name" > "$W0/mres/$n.name"
  [ $((n % 9)) = 0 ] && wait
}
S11=steps/11-verify-run.sh; S12=steps/12-verify-export.sh; S13=steps/13-clean-up.sh
mutant "a run without an export is accepted"                    $S11 '[ "$(find "$OUTF/export" -type f 2>/dev/null | wc -l)" -ge 1 ] || fail'  'true || fail'
mutant "an incomplete build record is accepted"                 $S11 'rk_record_check "$REC" > /dev/null 2>&1 || fail'  'true || fail'
mutant "a missing tool is accepted"                             $S11 '[ -f "$TREE/$f" ] || fail "$f is not in the commit tree'  'true || fail "$f is not in the commit tree'
mutant "a failing driver check is accepted"                     $S11 'if [ "$RC" != 0 ]; then tail -n 10 "$OUTF/step11-check.log"'  'if false; then tail -n 10 "$OUTF/step11-check.log"'
mutant "missing reference values are accepted"                  $S11 '[ -s "$OUTF/reference-values.json" ] || fail'  'true || fail'
mutant "the success line of the audit is not required"          $S11 ' || ! grep -aqE "$RK_M_AUDIT_OK" "$OUTF/audit.txt"'  ''
mutant "the exit status of the audit is ignored"                $S11 'if [ "$RCA" != 0 ] ||'  'if'
mutant "the success line of the receipt check is not required"  $S11 ' || ! grep -aqE "$RK_M_RECEIPT_OK" "$OUTF/receipt-verify.txt"'  ''
mutant "the exit status of the receipt check is ignored"        $S11 'if [ "$RCR" != 0 ] ||'  'if'
mutant "the receipts are checked against the console of build B" $S11 '"$REC/a/job-console.txt"'  '"$REC/b/job-console.txt"'
mutant "the success line of the acceptance is not required"     $S11 ' || ! grep -aqE "$RK_M_ACCEPT_OK" "$OUTF/accept.txt"'  ''
mutant "the exit status of the acceptance is ignored"           $S11 'if [ "$RCC" != 0 ] ||'  'if'
mutant "the builds are given to the acceptance in the wrong order" $S11 '"$REC/a/measurements" "$REC/b/measurements"'  '"$REC/b/measurements" "$REC/a/measurements"'
mutant "the acceptance runs without R4_LOCKED"                  $S11 'R4_LOCKED=1 bash'  'bash'
mutant "step 12 does not need the acceptance"                   $S12 '[ -s "$OUTF/accept.txt" ] && grep -aqE "$RK_M_ACCEPT_OK" "$OUTF/accept.txt" || fail'  'true || fail'
mutant "an export without a fetch list is accepted"             $S12 '[ "$NFL" -ge 1 ] || fail'  'true || fail'
mutant "an invalid MRTD is accepted"                            $S12 '[[ "$MRTD" =~ ^[0-9a-f]{96}$ ]] || fail'  'true || fail'
mutant "a failed download of the endorsement is accepted"       $S12 '"$RK_GOOGLE_ENDORSEMENT_URL/$MRTD.binarypb" || fail'  '"$RK_GOOGLE_ENDORSEMENT_URL/$MRTD.binarypb" || :'
mutant "the success line of the verifier is not required"       $S12 ' || ! printf '"'"'%s\n'"'"' "$OUTV" | grep -aqE "$RK_M_VERIFY_EXPORT_OK"'  ''
mutant "the ten checks are not counted"                         $S12 ' || [ -n "$BAD" ]; then fail'  '; then fail'
mutant "the exit status of the verifier is ignored"             $S12 'if [ "$RCV" != 0 ] ||'  'if'
mutant "the verifier gets the whole record as published folder" $S12 'PUB="$REC/reference"'  'PUB="$REC"'
mutant "the success line of a rehearsal is not required"        $S12 ' || ! printf '"'"'%s\n'"'"' "$OR" | grep -aq -- "$marker"'  ''
mutant "the exit status of a rehearsal is ignored"              $S12 'if [ "$RCR" != 0 ] ||'  'if'
mutant "the check of the signed time is ignored"                $S12 '"$OUTF/time-check.txt" 2>&1 || fail'  '"$OUTF/time-check.txt" 2>&1 || :'
mutant "the fleet is deleted before the export is verified"     $S13 'grep -aqE "$RK_M_VERIFY_EXPORT_OK" "$WD/verify-export.txt" 2>/dev/null || fail'  'true || fail'
mutant "a failed deletion is accepted"                          $S13 'if [ "$RC" != 0 ]; then tail -n 8 "$OUTF/step13.log"'  'if false; then tail -n 8 "$OUTF/step13.log"'
mutant "VMs that are left are accepted"                         $S13 '[ -z "$LEFT" ] || fail'  'true || fail'
mutant "the poller is not stopped"                              $S13 'rk_stop_poller "$RUN_LABEL"'  ':'
wait
MC=0; MT=0
for n in $(seq 1 $NM); do MT=$((MT + 1)); r="$(cat "$W0/mres/$n" 2>/dev/null)"; nm="$(cat "$W0/mres/$n.name" 2>/dev/null)"
  if [ "$r" = "changed-nothing" ]; then echo "  FAIL: the mutant '$nm' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1))
  elif [ -n "$r" ] && [ "$r" -gt 0 ] 2>/dev/null; then MC=$((MC + 1)); echo "  pass: the mutant '$nm' is caught ($r check(s) fail)"
  else echo "  FAIL: the mutant '$nm' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
done
echo; echo "checks of steps 11 to 13: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$REAL_FAIL" = 0 ]; then echo "RUN-KIT-VERIFY-REHEARSAL-OK"; else echo "RUN-KIT-VERIFY-REHEARSAL-FAIL: $REAL_FAIL problem(s)"; exit 1; fi
