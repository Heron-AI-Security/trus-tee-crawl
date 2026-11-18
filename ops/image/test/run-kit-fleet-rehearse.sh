#!/usr/bin/env bash
# Rehearsal of crawl steps 7 to 10 (start-fleet, form-fleet, check-nodes, crawl-export), of the poller of the console of the master, and of stop crawl, run through the REAL run-kit.sh and the real steps.
#   bash run-kit-fleet-rehearse.sh TREE        (no cloud: a fake fleet driver and a fake gcloud, each with one switch for every failure; a throwaway HOME)
# Checked: every step calls the driver with the stages that belong to it and with exactly the environment of the run that passed in the old kit (ZONE only until the driver has recorded the zone, and no variable of
# the caller leaks); a rerun finds the VMs that exist and waits only for the announcements, and refuses a fleet of which only some VMs exist; the poller starts when the fleet is formed, starts only once, collects the
# console lines, ends by itself when the master is gone or after its maximum time, and is finished by step 10 (sorted, without doubles); the DONE object is waited for before the export is fetched, with the path of
# the fleet list and the master; and every failure says what went wrong. Mutants of the steps (each check removed in turn, run in parallel) must all be caught by the same cases.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W0="$(mktemp -d)"; W="$W0"; V=1; PASS=0; FAIL=0; trap 'pkill -f "fleet-poller.sh tc-1k[^ ]* $W0" 2>/dev/null; rm -rf "$W0"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1${3:+ | $3}"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
for f in 07-start-fleet 08-form-fleet 09-check-nodes 10-crawl-export fleet-common fleet-poller; do [ -f "$K/steps/$f.sh" ] || { echo "RUN-KIT-FLEET-REHEARSAL-FAIL: $f.sh is missing in $K/steps"; exit 1; }; done
COMMIT_FULL=0123456789abcdef0123456789abcdef01234567; C9=${COMMIT_FULL:0:9}; RUN=1k-s1c0p1; M="tc-$RUN-m"; WB="tc-$RUN-w"; IMG="tc-img-$C9-1"; NV=4; BUCKET=training-custody-export-test

mkdir -p "$W0/fakebin"
cat > "$W0/fakebin/gcloud" <<'EOG'
#!/bin/sh
echo "$*" >> "$CTL/gcloud.log"
case "$*" in
  "compute instances list "*) [ -s "$CTL/vms" ] && cat "$CTL/vms"; exit 0 ;;
  "compute instances get-serial-port-output "*) [ -e "$CTL/serial-gone" ] && exit 1; n=$(cat "$CTL/serial-n" 2>/dev/null || echo 0); n=$((n + 1)); echo $n > "$CTL/serial-n"; echo "kernel noise"; echo "tc-crawl: round 1 line $n"; echo "tc-export: published"; echo "tc-crawl: round 1 line 1" ;;
  "storage cat "*) [ -e "$CTL/done-never" ] && exit 1; c=$(cat "$CTL/done-n" 2>/dev/null || echo 0); c=$((c + 1)); echo $c > "$CTL/done-n"; if [ "$c" -ge "$(cat "$CTL/done-after" 2>/dev/null || echo 1)" ]; then exit 0; else exit 1; fi ;;
  "compute instances delete "*) : ;;
esac
exit 0
EOG
chmod +x "$W0/fakebin/gcloud"
mkstepsdir() {  # KITDIR IDS...: a step folder whose crawl list holds only the named steps (07 08 ...) and whose files are links to the kit in KITDIR
  local D="$1"; shift; rm -rf "$W/sd"; mkdir -p "$W/sd/steps"
  for f in names.sh lib.sh record.sh tools.sh steps-build.sh; do ln -s "$D/$f" "$W/sd/$f"; done
  for f in "$D"/steps/*.sh; do ln -s "$f" "$W/sd/steps/$(basename "$f")"; done
  { echo 'RK_STEPS=('; for id in "$@"; do case "$id" in 07) echo '"7|start-fleet|Start the fleet|steps/07-start-fleet.sh"' ;; 08) echo '"8|form-fleet|Form the fleet|steps/08-form-fleet.sh"' ;; 09) echo '"9|check-nodes|Check every node|steps/09-check-nodes.sh"' ;; 10) echo '"10|crawl-export|Fetch the export|steps/10-crawl-export.sh"' ;; esac; done; echo ')'; } > "$W/sd/steps-crawl.sh"
}
setup() {  # a fresh home with the unpacked tree, the commit file, and a fake driver
  pkill -f "fleet-poller.sh tc-1k[^ ]* $W/home" 2>/dev/null; rm -rf "$W/home" "$W/ctl"; mkdir -p "$W/home" "$W/ctl"; B="$W/home/build-$C9"; TR="$B/tree/ops/image/test"; mkdir -p "$TR"; echo "$COMMIT_FULL" > "$B/commit.txt"; OUTD="$W/home/evidence-$RUN"
  cat > "$TR/f1-drive.sh" <<'EOD'
#!/usr/bin/env bash
C="$(dirname "$HOME")/ctl"; echo "ARGS $*" >> "$C/driver.log"
env | grep -E '^(IMG|OUT|SCRATCH_GB|WORKERS|LOCKMODE|EXPORT_BUCKET|EXPORT_SA|PIN_COMMIT|VMM|VMW|VMWBASE|EXTRA_LABELS|MACHINE_TYPE|ZONE|REFERENCE|DRY|CONFIRM|ZONE_LIST)=' | sort | sed 's/^/ENV /' >> "$C/driver.log"
ALLV=("$VMM" "$VMW"); for i in $(seq 2 "$WORKERS"); do ALLV+=("${VMWBASE}$i"); done
for st in "$@"; do case "$st" in
  fleet-vms) [ -e "$C/fleet-vms-fail" ] && { echo "STOP: no zone could host the fleet"; exit 1; }; printf '%s\n' "${ALLV[@]}" > "$C/vms"; mkdir -p "$OUT"; [ -e "$C/no-zone" ] || echo us-central1-b > "$OUT/zone.txt"; echo "the fleet is in zone us-central1-b" ;;
  announce-wait) [ -e "$C/announce-fail" ] && { echo "STOP: no announcement from ${ALLV[1]} after 15 minutes"; exit 1; }; mkdir -p "$OUT"; [ -e "$C/announce-nofile" ] || for v in "${ALLV[@]}"; do echo "announce $v" > "$OUT/announce-$v.txt"; echo "$v announced (9 bytes)"; done ;;
  fleet-build) [ -e "$C/fleet-build-fail" ] && { echo "STOP: the announcements were not accepted"; exit 1; }; printf '# fleet\n1\tmaster\t%s\n' "$VMM" > "$OUT/fleet.tsv"; for v in "${ALLV[@]:1}"; do printf '2\tworker\t%s\n' "$v" >> "$OUT/fleet.tsv"; done; [ -e "$C/fleet-short" ] && sed -i '$d' "$OUT/fleet.tsv"; echo "fleet.tsv written" ;;
  final-wait) [ -e "$C/final-fail" ] && { echo "STOP: no final quote from ${ALLV[1]} after 15 minutes"; exit 1; }; [ -e "$C/final-nofile" ] || for v in "${ALLV[@]}"; do echo final > "$OUT/final-$v.txt"; done ;;
  locked-check) [ -e "$C/locked-fail" ] && { echo "STOP: the early check failed: the image is not what a locked image must be"; exit 1; }; for v in "${ALLV[@]}"; do echo "report $v" > "$OUT/report-$v.txt"; done; [ -e "$C/crawl-notdone" ] || echo "crawl_marker=crawl done" >> "$OUT/report-$VMM.txt"; [ -e "$C/locked-nomarker" ] || echo "LOCK-CHECK-OK (locked)"; [ -e "$C/locked-rc1" ] && exit 1 ;;
  export-wait) [ -e "$C/export-fail" ] && { echo "STOP: the export failed on the master: no space"; exit 1; }; echo quoteC > "$OUT/export-$VMM.txt"; echo "$VMM published quote C" ;;
  export-fetch) rm -rf "$OUT/export"; mkdir -p "$OUT/export"; [ -e "$C/export-empty" ] || for i in 1 2 3 4 5; do echo "f$i" > "$OUT/export/f$i"; done; echo "export folder: $(find "$OUT/export" -type f | wc -l) files in $OUT/export" ;;
esac; done
exit 0
EOD
}
EXPECT_ENV() { cat <<EOE
ENV EXPORT_BUCKET=$BUCKET
ENV EXPORT_SA=tc-export@training-custody.iam.gserviceaccount.com
ENV EXTRA_LABELS=tc-run=$RUN
ENV IMG=$IMG
ENV LOCKMODE=locked
ENV MACHINE_TYPE=c3-standard-4
ENV OUT=$OUTD
ENV PIN_COMMIT=$COMMIT_FULL
ENV SCRATCH_GB=10
ENV VMM=$M
ENV VMW=${WB}1
ENV VMWBASE=$WB
ENV WORKERS=3
ENV ZONE=us-central1-a
EOE
}

suite() {  # DIR: all the checks against the kit in DIR (W is the working folder of this suite)
  local D="$1" o rc pid1 pid2 lines
  rk() { env HOME="$W/home" CTL="$W/ctl" PATH="$W0/fakebin:$PATH" RK_STEPS_DIR="$W/sd" RK_HEARTBEAT_SECS=0.2 RK_POLL_SECS=0.2 RK_DONE_POLL=0.2 RK_DONE_MAX=3 RK_POLL_MAX_SECS=60 timeout 40 bash "$D/run-kit.sh" crawl --build "$COMMIT_FULL" --size 1k --storage on --comms off --provenance on --workers 3 --until "$1" 2>&1; }
  call() { awk -v s="$1" 'index($0, "ARGS " s) == 1 { f = 1; print; next } /^ARGS / { f = 0 } f' "$W/ctl/driver.log"; }   # the block of the driver log of the call with these stages
  refused() { [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "^STEP $2 FAILED" && printf '%s' "$o" | grep -qF -- "$3: $4"; }
  t() { o="$(rk "$2")"; rc=$?; refused "$o" "$3" "$4" "$5" && chk "$1" ok || chk "$1" bad "exit $rc: $(printf '%s' "$o" | grep -E 'FAILED' | head -2 | tr '\n' ' ' | cut -c1-260)"; }
  # ---- step 7
  mkstepsdir "$D" 07; setup; o="$(rk start-fleet)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 7 DONE: the fleet of $NV VMs (a master and 3 workers of c3-standard-4) runs in zone us-central1-b from $IMG, and every node has announced itself" && chk "step 7: a good start, with the zone in which the driver found capacity" ok || chk "step 7: a good start" bad "exit $rc: $(printf '%s' "$o" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  [ "$(call 'fleet-vms announce-wait' | head -1)" = "ARGS fleet-vms announce-wait" ] && chk "step 7 calls the driver with the stages fleet-vms and announce-wait" ok || chk "step 7 calls the driver with the stages fleet-vms and announce-wait" bad "$(grep ARGS "$W/ctl/driver.log" | tr '\n' ' ')"
  diff <(call 'fleet-vms announce-wait' | grep '^ENV ') <(EXPECT_ENV) > "$W/envdiff.txt" && chk "step 7 gives the driver exactly the environment of the run that passed in the old kit (names from the run, the image, the bucket, the commit)" ok || chk "step 7 gives the driver exactly the environment of the run that passed in the old kit" bad "$(head -4 "$W/envdiff.txt" | tr '\n' ' ')"
  setup; o="$(env REFERENCE=/x DRY=1 CONFIRM=yes ZONE_LIST="a b" HOME="$W/home" CTL="$W/ctl" PATH="$W0/fakebin:$PATH" RK_STEPS_DIR="$W/sd" RK_HEARTBEAT_SECS=0.2 timeout 40 bash "$D/run-kit.sh" crawl --build "$COMMIT_FULL" --size 1k --storage on --comms off --provenance on --workers 3 --until start-fleet 2>&1)"; rc=$?
  [ "$rc" = 0 ] && ! grep -qE "^ENV (REFERENCE|DRY|CONFIRM|ZONE_LIST)=" "$W/ctl/driver.log" && chk "variables of the caller (REFERENCE, DRY, CONFIRM, ZONE_LIST) do not reach the driver" ok || chk "variables of the caller do not reach the driver" bad "exit $rc: $(grep -E '^ENV (REFERENCE|DRY|CONFIRM|ZONE_LIST)=' "$W/ctl/driver.log" | tr '\n' ' ')"
  setup; mkdir -p "$OUTD"; echo us-central1-b > "$OUTD/zone.txt"; printf '%s\n' "$M" "${WB}1" "${WB}2" "${WB}3" > "$W/ctl/vms"; o="$(rk start-fleet)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "all $NV VMs exist already" && [ "$(grep ARGS "$W/ctl/driver.log" | tr -d '\n')" = "ARGS announce-wait" ] && chk "a rerun finds the VMs that exist and waits for the announcements only (no second fleet)" ok || chk "a rerun finds the VMs that exist and waits for the announcements only" bad "exit $rc: $(grep ARGS "$W/ctl/driver.log" | tr '\n' ' ')"
  setup; printf '%s\n' "$M" "${WB}1" > "$W/ctl/vms"; t "a fleet of which only some VMs exist is refused, the VMs are named, and the command that deletes them is given" start-fleet 7 START-FLEET-FAILED "2 of the $NV VMs of this run exist ($M ${WB}1): delete them with  bash run-kit.sh stop crawl"
  setup; touch "$W/ctl/announce-fail"; o="$(rk start-fleet)"; rc=$?; refused "$o" 7 START-FLEET-FAILED "the fleet did not start" && printf '%s' "$o" | grep -q "STOP: no announcement from ${WB}1" && chk "a driver failure is refused, the last lines of the driver are shown, and the VMs are kept" ok || chk "a driver failure is refused, the last lines of the driver are shown, and the VMs are kept" bad "exit $rc"
  setup; touch "$W/ctl/fleet-vms-fail"; t "a fleet that no zone can host is refused" start-fleet 7 START-FLEET-FAILED "the fleet did not start"
  setup; touch "$W/ctl/no-zone"; t "a driver that records no zone is refused" start-fleet 7 START-FLEET-FAILED "the driver did not record the zone of the fleet"
  setup; touch "$W/ctl/announce-nofile"; t "an announcement that is not saved is refused, and the node is named" start-fleet 7 START-FLEET-FAILED "the announcement of $M is not saved"
  # ---- step 8
  mkstepsdir "$D" 07 08; setup; o="$(rk form-fleet)"; rc=$?; FL="$(sha384sum "$OUTD/fleet.tsv" 2>/dev/null | cut -c1-16)"
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 8 DONE: the fleet is formed: $NV nodes in the fleet list $FL; the quotes of all nodes were verified" && chk "step 8: the fleet is formed, and the result names the fleet list" ok || chk "step 8: the fleet is formed" bad "exit $rc: $(printf '%s' "$o" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  [ "$(call 'fleet-build final-wait' | head -1)" = "ARGS fleet-build final-wait" ] && ! call 'fleet-build final-wait' | grep -q '^ENV ZONE=' && chk "step 8 calls fleet-build and final-wait, and passes no ZONE (the zone is the one the driver recorded)" ok || chk "step 8 calls fleet-build and final-wait, and passes no ZONE" bad "$(call 'fleet-build final-wait' | grep -E 'ARGS|ZONE' | tr '\n' ' ')"
  sleep 1; pid1="$(cat "$W/home/run-$RUN/poller.pid" 2>/dev/null)"; { [ -n "$pid1" ] && kill -0 "$pid1" 2>/dev/null && grep -q "tc-crawl: round 1" "$OUTD/master-log-lines.raw"; } && chk "the poller of the console of the master starts with the fleet and collects the lines of the crawl" ok || chk "the poller of the console of the master starts with the fleet and collects the lines of the crawl" bad "pid '$pid1'"
  setup; touch "$W/ctl/final-fail"; t "a node that publishes no final quote is refused" form-fleet 8 FORM-FLEET-FAILED "the fleet was not formed"
  setup; touch "$W/ctl/fleet-short"; t "a fleet list with fewer nodes than the run is refused" form-fleet 8 FORM-FLEET-FAILED "the fleet list has 3 nodes, the run has $NV"
  setup; touch "$W/ctl/final-nofile"; t "a final quote that is not saved is refused, and the node is named" form-fleet 8 FORM-FLEET-FAILED "the final quote of $M is not saved"
  mkstepsdir "$D" 08; setup; t "step 8 alone, without step 7: refused, and step 7 is named" form-fleet 8 FORM-FLEET-FAILED "step 7 has not finished: there is no announcement of $M"
  # ---- step 9
  mkstepsdir "$D" 07 08 09; setup; o="$(rk check-nodes)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 9 DONE: all $NV nodes report what a locked image must report" && [ "$(call 'locked-check' | head -1)" = "ARGS locked-check" ] && chk "step 9: every node is checked with the stage locked-check, and the crawl is done" ok || chk "step 9: every node is checked with the stage locked-check" bad "exit $rc: $(printf '%s' "$o" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  pid2="$(cat "$W/home/run-$RUN/poller.pid" 2>/dev/null)"; [ -n "$pid2" ] && kill -0 "$pid2" 2>/dev/null && [ "$(pgrep -fc "fleet-poller.sh $M $W/home")" = 1 ] && chk "there is exactly one poller after step 9 (the later steps do not start another)" ok || chk "there is exactly one poller after step 9" bad "pid '$pid2', processes $(pgrep -fc "fleet-poller.sh $M $W/home")"
  setup; touch "$W/ctl/locked-fail"; o="$(rk check-nodes)"; rc=$?; refused "$o" 9 CHECK-NODES-FAILED "the nodes are not what a locked image must be" && printf '%s' "$o" | grep -q "STOP: the early check failed" && chk "a node that is not what a locked image must be is refused, with the last lines of the driver" ok || chk "a node that is not what a locked image must be is refused, with the last lines of the driver" bad "exit $rc"
  setup; touch "$W/ctl/locked-nomarker"; t "a driver that ends without its success line is refused" check-nodes 9 CHECK-NODES-FAILED "the nodes are not what a locked image must be"
  setup; touch "$W/ctl/locked-rc1"; t "a driver that prints its success line but exits with an error is refused" check-nodes 9 CHECK-NODES-FAILED "the nodes are not what a locked image must be"
  setup; touch "$W/ctl/crawl-notdone"; t "a master whose report does not say that the crawl is done is refused" check-nodes 9 CHECK-NODES-FAILED "the report of the master does not say that the crawl is done"
  # ---- step 10
  mkstepsdir "$D" 07 08 09 10; setup; echo 3 > "$W/ctl/done-after"; o="$(rk crawl-export)"; rc=$?; FL="$(sha384sum "$OUTD/fleet.tsv" 2>/dev/null | cut -c1-16)"
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 10 DONE: quote C of $M is published and its export of 5 files is fetched from gs://$BUCKET into $OUTD/export" && chk "step 10: quote C, the DONE object and the export" ok || chk "step 10: quote C, the DONE object and the export" bad "exit $rc: $(printf '%s' "$o" | tail -3 | tr '\n' ' ' | cut -c1-300)"
  [ "$(grep -c '^storage cat' "$W/ctl/gcloud.log")" = 3 ] && grep -q "^storage cat gs://$BUCKET/export/$FL/$M/DONE\$" "$W/ctl/gcloud.log" && chk "the DONE object is waited for (three tries here) at the path of the bucket, the fleet list and the master" ok || chk "the DONE object is waited for at the path of the bucket, the fleet list and the master" bad "$(grep '^storage cat' "$W/ctl/gcloud.log" | head -2 | tr '\n' ' ')"
  [ "$(grep ARGS "$W/ctl/driver.log" | tail -2 | tr '\n' ' ')" = "ARGS export-wait ARGS export-fetch " ] && chk "quote C is waited for first, and the export is fetched after the DONE object" ok || chk "quote C is waited for first, and the export is fetched after the DONE object" bad "$(grep ARGS "$W/ctl/driver.log" | tail -2 | tr '\n' ' ')"
  [ ! -e "$W/home/run-$RUN/poller.pid" ] && [ "$(sort "$OUTD/master-log-lines.txt" | uniq -d | wc -l)" = 0 ] && grep -q "tc-crawl: round 1 line 1" "$OUTD/master-log-lines.txt" && chk "step 10 finishes the poller, and the lines of the console are saved sorted and without doubles" ok || chk "step 10 finishes the poller, and the lines of the console are saved sorted and without doubles" bad "$(ls "$W/home/run-$RUN" 2>/dev/null | tr '\n' ' ')"
  setup; touch "$W/ctl/done-never"; o="$(rk crawl-export)"; rc=$?; refused "$o" 10 CRAWL-EXPORT-FAILED "no DONE object after" && chk "an export without a DONE object is refused after the waiting time (the export is incomplete)" ok || chk "an export without a DONE object is refused after the waiting time" bad "exit $rc: $(printf '%s' "$o" | tail -2 | tr '\n' ' ' | cut -c1-200)"
  setup; touch "$W/ctl/export-fail"; o="$(rk crawl-export)"; rc=$?; refused "$o" 10 CRAWL-EXPORT-FAILED "quote C of the master did not come" && printf '%s' "$o" | grep -q "STOP: the export failed on the master" && chk "a master that fails to export is refused, with the last lines of the driver" ok || chk "a master that fails to export is refused, with the last lines of the driver" bad "exit $rc"
  setup; touch "$W/ctl/export-empty"; t "an empty export folder is refused" crawl-export 10 CRAWL-EXPORT-FAILED "the export folder $OUTD/export is empty"
  # ---- the poller and stop crawl
  setup; mkdir -p "$W/home/ev" "$W/home/run-$RUN"; touch "$W/ctl/serial-gone"; S0=$(date +%s); env HOME="$W/home" CTL="$W/ctl" PATH="$W0/fakebin:$PATH" RK_POLL_SECS=0.1 timeout 20 bash "$D/steps/fleet-poller.sh" "$M" "$W/home/ev" "$W/home/run-$RUN/poller.pid"; rc=$?
  [ "$rc" = 0 ] && [ "$(( $(date +%s) - S0 ))" -le 8 ] && [ ! -e "$W/home/run-$RUN/poller.pid" ] && chk "the poller ends by itself when the master cannot be read five times (it is deleted), and removes its pid file" ok || chk "the poller ends by itself when the master cannot be read five times" bad "exit $rc, $(( $(date +%s) - S0 )) s"
  setup; mkdir -p "$W/home/ev" "$W/home/run-$RUN"; S0=$(date +%s); env HOME="$W/home" CTL="$W/ctl" PATH="$W0/fakebin:$PATH" RK_POLL_SECS=0.2 RK_POLL_MAX_SECS=1 timeout 20 bash "$D/steps/fleet-poller.sh" "$M" "$W/home/ev" "$W/home/run-$RUN/poller.pid"; rc=$?
  [ "$rc" = 0 ] && [ "$(( $(date +%s) - S0 ))" -le 8 ] && chk "the poller ends by itself after its maximum time, so that it never outlives an abandoned run" ok || chk "the poller ends by itself after its maximum time" bad "exit $rc, $(( $(date +%s) - S0 )) s"
  setup; mkdir -p "$W/home/run-$RUN"; SL="3000.$BASHPID"; ( setsid nohup sleep "$SL" > /dev/null 2>&1 < /dev/null & echo $! > "$W/home/run-$RUN/poller.pid" ); o="$(env HOME="$W/home" CTL="$W/ctl" PATH="$W0/fakebin:$PATH" RUN_DIR="run-$RUN" YES=1 bash -c ". '$D/lib.sh'; rk_stop_crawl $RUN" 2>&1)"; sleep 0.3
  ! pgrep -f "^sleep $SL" > /dev/null && [ ! -e "$W/home/run-$RUN/poller.pid" ] && chk "stop crawl stops the poller, also when no VM is left" ok || { pkill -f "^sleep $SL"; chk "stop crawl stops the poller, also when no VM is left" bad "$o"; }
}

echo "== the checks of steps 7 to 10 with a fake fleet driver and a fake cloud"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
if [ -n "${NO_MUTANTS:-}" ]; then echo; echo "checks of steps 7 to 10 (mutants skipped): $REAL_PASS passed, $REAL_FAIL failed"; exit 0; fi
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
    V=0; PASS=0; FAIL=0; suite "$W/m" > /dev/null 2>&1; echo "$FAIL" > "$W0/mres/$n"; echo "$name" > "$W0/mres/$n.name" ) &
  echo "$name" > "$W0/mres/$n.name"
  [ $((n % 8)) = 0 ] && wait
}
mutant "ZONE is always passed to the driver"                steps/fleet-common.sh  '[ -s "$OUTF/zone.txt" ] || FENV+=(ZONE="$ZONE")'  'FENV+=(ZONE="$ZONE")'
mutant "the scratch disk setting is wrong"                  steps/fleet-common.sh  'SCRATCH_GB="$RK_FLEET_SCRATCH_GB"'  'SCRATCH_GB=0'
mutant "the labels of the run are missing"                  steps/fleet-common.sh  'EXTRA_LABELS="tc-run=$RUN_LABEL"'  'EXTRA_LABELS=""'
mutant "the first worker has the wrong name"                steps/fleet-common.sh  'VMW="$(rk_worker 1)"'  'VMW="$(rk_worker 2)"'
mutant "a rerun does not find the VMs that exist"           steps/07-start-fleet.sh '"$NHAVE" = "$NVM" ]'  '"$NHAVE" = 99 ]'
mutant "a partial fleet is accepted"                        steps/07-start-fleet.sh 'elif [ "$NHAVE" = "$NVM" ]'  'elif [ "$NHAVE" -ge 1 ]'
mutant "the zone of the driver is not required"             steps/07-start-fleet.sh '[ -n "$ZF" ] || fail'  'true || fail'
mutant "a missing announcement is accepted"                 steps/07-start-fleet.sh '[ -s "$OUTF/announce-$v.txt" ] || fail "the announcement'  'true || fail "the announcement'
mutant "a failed start is accepted"                         steps/07-start-fleet.sh 'if [ "$RC" != 0 ]; then tail'  'if false; then tail'
mutant "the poller is not started"                          steps/08-form-fleet.sh 'fleet_poller_start'  ':'
mutant "a short fleet list is accepted"                     steps/08-form-fleet.sh '[ "$NROWS" = "$NVM" ] || fail'  'true || fail'
mutant "a missing final quote is accepted"                  steps/08-form-fleet.sh '[ -s "$OUTF/final-$v.txt" ] || fail "the final quote'  'true || fail "the final quote'
mutant "step 8 does not require step 7"                     steps/08-form-fleet.sh '[ -s "$OUTF/announce-$v.txt" ] || fail "step 7'  'true || fail "step 7'
mutant "a failed formation is accepted"                     steps/08-form-fleet.sh 'if [ "$RC" != 0 ]; then tail'  'if false; then tail'
mutant "the success line of the node check is not required" steps/09-check-nodes.sh ' || ! grep -aqE "$RK_M_LOCK_OK" "$OUTF/step9.log"'  ''
mutant "the exit status of the node check is ignored"       steps/09-check-nodes.sh 'if [ "$RC" != 0 ] ||'  'if'
mutant "an unfinished crawl is accepted"                    steps/09-check-nodes.sh "grep -aq '^crawl_marker=crawl done'"  'true #'
mutant "step 9 starts a second poller"                      steps/09-check-nodes.sh 'fleet_poller_start'  'setsid nohup bash "$KD/steps/fleet-poller.sh" "$MASTER" "$OUTF" "$PIDF.2" > /dev/null 2>&1 < /dev/null &'
mutant "the DONE object is not waited for"                  steps/10-crawl-export.sh 'until gcloud storage cat "$DB" > /dev/null 2>&1; do'  'until true; do'
mutant "the wait for the DONE object has no end"            steps/10-crawl-export.sh 'if awk -v t="$t" -v m="${RK_DONE_MAX:-1800}" '"'"'BEGIN { exit !(t > m) }'"'"'; then fail'  'if false; then fail'
mutant "the DONE path has the wrong master"                 steps/10-crawl-export.sh '/export/$FL/$MASTER/DONE'  '/export/$FL/other/DONE'
mutant "an empty export is accepted"                        steps/10-crawl-export.sh '[ "$NF" -ge 1 ] || fail'  'true || fail'
mutant "the poller is not finished"                         steps/10-crawl-export.sh 'fleet_poller_stop;'  ':;'
mutant "a failed export wait is accepted"                   steps/10-crawl-export.sh 'if [ "$RC" != 0 ]; then tail -n 8 "$OUTF/step10-wait.log"'  'if false; then tail -n 8 "$OUTF/step10-wait.log"'
mutant "the poller never ends when the master is gone"      steps/fleet-poller.sh '[ "$fails" -lt 5 ] || break'  'true'
mutant "the poller has no maximum time"                     steps/fleet-poller.sh '[ $(( $(date +%s) - t0 )) -lt "$MAXS" ] || break'  'true'
mutant "stop crawl does not stop the poller"                lib.sh                 '[ -n "$rows" ] || { echo "no VM carries the label tc-run=$1: nothing to delete"; rk_stop_poller "$1"; return 0; }'  '[ -n "$rows" ] || { echo "no VM carries the label tc-run=$1: nothing to delete"; return 0; }'
wait
MC=0; MT=0
for n in $(seq 1 $NM); do MT=$((MT + 1)); r="$(cat "$W0/mres/$n" 2>/dev/null)"; nm="$(cat "$W0/mres/$n.name" 2>/dev/null)"
  if [ "$r" = "changed-nothing" ]; then echo "  FAIL: the mutant '$nm' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1))
  elif [ -n "$r" ] && [ "$r" -gt 0 ] 2>/dev/null; then MC=$((MC + 1)); echo "  pass: the mutant '$nm' is caught ($r check(s) fail)"
  else echo "  FAIL: the mutant '$nm' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
done
echo; echo "checks of steps 7 to 10: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$REAL_FAIL" = 0 ]; then echo "RUN-KIT-FLEET-REHEARSAL-OK"; else echo "RUN-KIT-FLEET-REHEARSAL-FAIL: $REAL_FAIL problem(s)"; exit 1; fi
