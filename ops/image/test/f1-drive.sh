#!/usr/bin/env bash
# Step F1 on DISPOSABLE TDX VMs, operator side (Cloud Shell): two VMs from one image announce their keys, the operator checks the announcements and sets the fleet list as metadata, and the fleet forms.
#   bash f1-drive.sh STAGE [STAGE] ...
# Stages: fleet-vms | export-wait | export-fetch | export-check | announce-wait | fleet-build | final-wait | fleet-check | fleet-f2 | fleet-contract | fleet-contract-compare | fleet-attacks | reference-values | enforce | probe | locked-check | fleet-build-mismatch | mismatch-compare | images-compare | fleet-clear | fleet-reboot | negative-check | fleet-delete
# Settings: IMG (the image), VMM (tc-f1-m), VMW (tc-f1-w), WORKERS (how many workers, default 1; the others are VMW2, VMW3, ...), EXPORT_BUCKET and EXPORT_SA (step R5: the bucket for the export and the service account of the MASTER, which may only create objects in it; the workers never get one), ZONE (us-central1-a), OUT (~/evidence-f1), DRY=1, F2MODE (all, or outsider to repeat only that part).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$(cd "$HERE/../../.." && pwd)"
Z="${ZONE:-us-central1-a}"; IMG="${IMG:?set IMG to the image}"; VMM="${VMM:-tc-f1-m}"; VMW="${VMW:-tc-f1-w}"; OUT="${OUT:-$HOME/evidence-f1}"; DRY="${DRY:-0}"
[ -n "${ZONE:-}" ] || ! [ -s "$OUT/zone.txt" ] || Z="$(cat "$OUT/zone.txt")"   # the zone in which fleet-vms found capacity (a stockout of the cloud makes it try other zones)
WORKERS="${WORKERS:-1}"; ALL=("$VMM" "$VMW"); for i in $(seq 2 "$WORKERS"); do ALL+=("${VMW}$i"); done   # the master, the first worker, and more workers: ${VMW}2, ${VMW}3, ...
PAIRS=(); for v in "${ALL[@]:1}"; do PAIRS+=("$v:worker"); done; PAIRS+=("$VMM:master")
say() { echo; echo "== $*"; }
die() { echo "STOP: $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then printf "DRY:"; printf " %q" "$@"; printf "\n"; else "$@"; fi; }   # a dry run prints every argument quoted exactly as it would be passed
rssh() { if [ "$DRY" = 1 ]; then echo "DRY: ssh $1: $2"; return 0; fi; gcloud compute ssh "$1" --zone="$Z" --quiet --command="$2" < /dev/null; }
attr() { gcloud compute instances get-guest-attributes "$1" --zone="$Z" --query-path="$2" --format='value(value)' 2>/dev/null; }
ship() {  # ship V: the kit to a node, the output kept in $OUT/ship-V.txt and shown when it fails; one more try after a pause
  local v="$1" i
  for i in 1 2; do
    TESTVM="$v" OUT="$OUT" bash "$HERE/f03-drive.sh" ship-test > "$OUT/ship-$v.txt" 2>&1 && return 0
    echo "the copy of the kit to $v failed (try $i of 2); its output:"; tail -8 "$OUT/ship-$v.txt" | sed 's/^/   /'; sleep 15
  done
  die "could not ship the kit to $v (output above)"
}
ip_of() { gcloud compute instances describe "$1" --zone="$Z" --format='value(networkInterfaces[0].networkIP)'; }
mkdir -p "$OUT"
TDX=(--zone="$Z" --machine-type=c3-standard-4 --confidential-compute-type=TDX --maintenance-policy=TERMINATE --boot-disk-size=30GB --boot-disk-type=pd-balanced --no-service-account --no-scopes --metadata=enable-guest-attributes=TRUE)
for st in "$@"; do case "$st" in
  fleet-vms) say "create the master $VMM and the worker(s) ${ALL[*]:1} from $IMG (guest attributes on, no service account)"
    ZORD="$Z"; [ "$DRY" = 1 ] || ZORD="$Z $(for z in ${ZONE_LIST:-us-central1-a us-central1-b us-central1-c}; do [ "$z" = "$Z" ] || echo "$z"; done)"; made=""
    for zz in $ZORD; do
    echo "--- the fleet in zone $zz"; zok=1; created=()
    for v in "${ALL[@]}"; do
      A=("${TDX[@]/--zone=*/--zone=$zz}"); [ -z "${SCRATCH_GB:-}" ] || A+=(--create-disk="name=$v-scratch,size=${SCRATCH_GB}GB,type=pd-balanced,device-name=tcscratch,auto-delete=yes")   # step R3.5: the sealed image needs its spare disk
      if [ "$v" = "$VMM" ] && [ -n "${EXPORT_BUCKET:-}" ]; then
        [ -n "${EXPORT_SA:-}" ] || die "set EXPORT_SA (the service account that may only create objects in the bucket) together with EXPORT_BUCKET"
        A=("${A[@]/--no-service-account/--service-account=$EXPORT_SA}"); A=("${A[@]/--no-scopes/--scopes=https://www.googleapis.com/auth/devstorage.read_write}"); A=("${A[@]/--metadata=enable-guest-attributes=TRUE/--metadata=enable-guest-attributes=TRUE,tc-export-bucket=$EXPORT_BUCKET}")
        echo "(the master $v gets the service account $EXPORT_SA and the bucket $EXPORT_BUCKET; the workers get none)"
      fi
      # BENCHMARK ONLY (branch bench/layer-flag): BENCH_LAYERS (fleet, fleet-wireguard, fleet-wireguard-signing, all-off, receipts-only, wireguard-only or signing-only; docs/bench-layers.md) puts tc-bench-layers into every node's metadata at creation (tc-fleet.sh reads it once, early in the boot);
      # BENCH_LAYERS_<vm name with - as _> sets it for one node only (a mismatched fleet, which mutual attestation must refuse). Unset: nothing changes.
      BL_VAR="BENCH_LAYERS_${v//-/_}"; BL="${!BL_VAR:-${BENCH_LAYERS:-}}"
      [ -z "$BL" ] || A=("${A[@]/#--metadata=enable-guest-attributes=TRUE/--metadata=enable-guest-attributes=TRUE,tc-bench-layers=$BL}")
      if run gcloud compute instances create "$v" "${A[@]}" --image="$IMG" --labels=purpose=tc-f1 < /dev/null; then created+=("$v"); else zok=0; break; fi
    done
    if [ "$zok" = 1 ]; then made="$zz"; break; fi
    echo "zone $zz could not host the fleet (no capacity, or this machine type is not offered there): removing what was created there and trying the next zone"
    for c in ${created[@]+"${created[@]}"}; do gcloud compute instances delete "$c" --zone="$zz" --quiet < /dev/null; done
    done
    [ -n "$made" ] || die "no zone could host the fleet (tried: $ZORD): read the errors above, try again later, or set ZONE_LIST to other zones of the region"
    Z="$made"; [ "$DRY" = 1 ] || { echo "$made" > "$OUT/zone.txt"; echo "the fleet is in zone $Z (saved in $OUT/zone.txt; every later stage uses it)"; } ;;
  export-wait) say "step R5: wait for quote C of the master (the guest attribute tc/export), which the master publishes after the crawl, the verified copy and the manifest"
    t=0; until attr "$VMM" tc/export > "$OUT/export-$VMM.txt" && [ -s "$OUT/export-$VMM.txt" ]; do E="$(attr "$VMM" tc/export-error)"; [ -z "$E" ] || die "the export failed on the master: $E"; t=$((t+30)); [ $t -lt 3600 ] || die "no quote C from $VMM after 60 minutes (journalctl -u tc-export on the master, or its serial console)"; echo "   waiting for the export ($t s)"; sleep 30; done
    echo "$VMM published quote C ($(wc -c < "$OUT/export-$VMM.txt") bytes)" ;;
  export-fetch) say "step R5: the export folder of the master, from the bucket (EXPORT_BUCKET) or, on a debug fleet, from the master's disk"
    rm -rf "$OUT/export"; mkdir -p "$OUT/export"; FL="$(sha384sum "$OUT/fleet.tsv" | cut -c1-16)"
    if [ -n "${EXPORT_BUCKET:-}" ]; then
      run gcloud storage cp -r "gs://$EXPORT_BUCKET/export/$FL/$VMM/*" "$OUT/export/" < /dev/null || die "could not copy the export from gs://$EXPORT_BUCKET/export/$FL/$VMM/"
      [ "$DRY" = 1 ] || { [ -f "$OUT/export/DONE" ] && [ "$(tr -d '\n' < "$OUT/export/DONE")" = "$(sha384sum "$OUT/export/manifest.tsv" | cut -d' ' -f1)" ] || die "the bucket has no DONE object that names the manifest: the export is incomplete"; rm -f "$OUT/export/DONE" "$OUT/export/export-attr.txt"; }
    else
      run gcloud compute scp --recurse "$VMM:/var/lib/tc-export/out/*" "$OUT/export/" --zone="$Z" --quiet < /dev/null || die "could not copy the export from $VMM (a locked image has no login: use a bucket)"
    fi
    echo "export folder: $(find "$OUT/export" -type f | wc -l) files in $OUT/export" ;;
  export-check) say "step R5 (rule E8): quote C, the manifest and every exported file"
    python3 "$HERE/f1-fleet.py" export-check "$OUT" "$OUT/export" "$VMM" ${REFERENCE:+"$REFERENCE"} || die "the export is not accepted" ;;
  announce-wait) say "wait for both announcements (the guest attribute tc/announce)"
    for v in "${ALL[@]}"; do t=0; until attr "$v" tc/announce > "$OUT/announce-$v.txt" && [ -s "$OUT/announce-$v.txt" ]; do t=$((t+10)); [ $t -lt 900 ] || die "no announcement from $v after 15 minutes"; sleep 10; done; echo "$v announced ($(wc -c < "$OUT/announce-$v.txt") bytes)"; done ;;
  fleet-build) say "verify both announcements (the quote binds the keys and the log), write fleet.tsv, set it and the announcements (for the nodes' mutual attestation) as metadata"
    NODEARGS=("master:$VMM:$(ip_of "$VMM")"); for v in "${ALL[@]:1}"; do NODEARGS+=("worker:$v:$(ip_of "$v")"); done
    python3 "$HERE/f1-fleet.py" build "$OUT" "${REFERENCE:--}" "${NODEARGS[@]}" || die "the announcements were not accepted"
    for v in "${ALL[@]}"; do run gcloud compute instances add-metadata "$v" --zone="$Z" --metadata-from-file tc-fleet="$OUT/fleet.tsv",tc-fleet-quotes="$OUT/fleet-quotes.json" < /dev/null || die "could not set tc-fleet and tc-fleet-quotes on $v"; done ;;
  final-wait) say "wait for both final quotes, and check that both logs hold the same fleet event"
    for v in "${ALL[@]}"; do t=0; until attr "$v" tc/final > "$OUT/final-$v.txt" && [ -s "$OUT/final-$v.txt" ]; do t=$((t+10)); [ $t -lt 900 ] || die "no final quote from $v after 15 minutes (the node may have stopped: read its serial console)"; sleep 10; done; echo "$v published its final quote"; done
    python3 "$HERE/f1-fleet.py" final "$OUT" "${ALL[@]}" || die "the final quotes are not consistent" ;;
  fleet-check) say "the node-side checks (ssh)"
    bad=0; for pair in "${PAIRS[@]}"; do v="${pair%%:*}"; r="${pair##*:}"; ship "$v"
      rssh "$v" "sudo bash ~/f03/ops/image/test/f1-check.sh $r" 2>&1 | tee "$OUT/f1-check-$v.txt"; [ "${PIPESTATUS[0]}" = 0 ] || bad=1; done   # both nodes are looked at before the stage stops
    [ $bad = 0 ] || die "the check failed on at least one node (read both outputs)" ;;
  fleet-f2) say "step F2 on the master: an outsider's valid key is refused on the read, also in a fresh YARN container"
    ship "$VMM"
    rssh "$VMM" "sudo bash ~/f03/ops/image/test/f2-check.sh ${F2MODE:-all}" 2>&1 | tee -a "$OUT/f2-check-$VMM.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the F2 check failed (read the output)" ;;
  fleet-contract) say "step F3: Hadoop's file-system contract tests on the master, through the plain client (the control) and through the wrapper (about 10 to 20 minutes)"
    ship "$VMM"
    rssh "$VMM" 'sudo rm -rf /tmp/f3ct /tmp/f3ct-home /tmp/f3ct-out && sudo mkdir -p /tmp/f3ct/ops /tmp/f3ct-home && sudo cp -r ~/f03/ops/attested /tmp/f3ct/ops/ && sudo chown -R hadoop:hadoop /tmp/f3ct /tmp/f3ct-home && sudo -u hadoop env HOME=/tmp/f3ct-home JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 HADOOP_HOME=/opt/hadoop HADOOP_CONF_DIR=/run/tc/conf PATH=/usr/lib/jvm/java-11-openjdk-amd64/bin:/opt/hadoop/bin:/usr/bin:/bin ATTESTED_JOB=/opt/tc/nutch/apache-nutch-1.22.job ATTESTED_CONTRACT_URI=hdfs://10.10.0.1:9000 ATTESTED_CONTRACT_DIR=/user/hadoop/contract-tests-f3 bash /tmp/f3ct/ops/attested/contract-tests.sh /tmp/f3ct-home/out' 2>&1 | tee "$OUT/contract-console-$VMM.txt"
    rssh "$VMM" 'sudo cat /tmp/f3ct-home/out/comparison.txt; echo ---; sudo cat /tmp/f3ct-home/out/libs.txt | cut -c1-120' 2>&1 | tee "$OUT/contract-comparison-$VMM.txt"
    grep -q "CONTRACT-SAME-AS-HDFS" "$OUT/contract-comparison-$VMM.txt" || die "the wrapper differs from plain HDFS in the contract tests (read the comparison)" ;;
  fleet-contract-compare) say "the contract comparison again, from the results that the last fleet-contract saved on the master (the tests are not run again; the list of expected differences comes from this kit)"
    ship "$VMM"
    rssh "$VMM" 'sudo rm -rf /tmp/f3ct/ops/attested/contract && sudo cp -r ~/f03/ops/attested/contract /tmp/f3ct/ops/attested/ && sudo cp ~/f03/ops/attested/contract_compare.py /tmp/f3ct/ops/attested/ && sudo -u hadoop python3 /tmp/f3ct/ops/attested/contract_compare.py /tmp/f3ct-home/out/results-plain.tsv /tmp/f3ct-home/out/results-wrapped.tsv' 2>&1 | tee "$OUT/contract-comparison-again-$VMM.txt"
    grep -q "CONTRACT-SAME-AS-HDFS" "$OUT/contract-comparison-again-$VMM.txt" || die "the wrapper still differs from plain HDFS in the contract tests (read the comparison)" ;;
  fleet-attacks) say "F4 on the master (the debug fleet): the tamper demonstrations with a clean control, and the two documented limits"
    ship "$VMM"; rssh "$VMM" "sudo bash ~/f03/ops/image/test/f4-attacks.sh" 2>&1 | tee -a "$OUT/f4-attacks-$VMM.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the F4 attacks check failed (read the output)" ;;
  probe) say "from OUTSIDE the mesh: a plain VM in the same network tries every port of both nodes (mode ${LOCKMODE:?set LOCKMODE})"
    run gcloud compute instances create tc-probe --zone="$Z" --machine-type=e2-small --image-family=ubuntu-2204-lts --image-project=ubuntu-os-cloud --no-service-account --no-scopes < /dev/null > /dev/null 2>&1 || die "could not create the probe VM"
    t=0; until rssh tc-probe true >/dev/null 2>&1; do t=$((t+10)); [ $t -lt 300 ] || die "the probe VM does not answer ssh"; sleep 10; done
    : > "$OUT/probe-$LOCKMODE.txt"
    for v in "${ALL[@]}"; do ip="$(ip_of "$v")"
      rssh tc-probe "for p in 22 9000 9870 9864 9866 9867 8030 8031 8032 8033 8088 8042 8040 13562; do if timeout 4 bash -c \"</dev/tcp/$ip/\$p\" 2>/dev/null; then echo \"$v:\$p OPEN\"; else echo \"$v:\$p closed\"; fi; done; echo \"$v:webhdfs http \$(curl -s -m 5 -o /dev/null -w '%{http_code}' 'http://$ip:9870/webhdfs/v1/?op=LISTSTATUS')\"; echo \"$v:yarn-rest http \$(curl -s -m 5 -o /dev/null -w '%{http_code}' 'http://$ip:8088/ws/v1/cluster/info')\"" 2>/dev/null | tee -a "$OUT/probe-$LOCKMODE.txt"
    done
    run gcloud compute instances delete tc-probe --zone="$Z" --quiet < /dev/null > /dev/null 2>&1 || true
    OPEN="$(grep ' OPEN' "$OUT/probe-$LOCKMODE.txt" | sed 's/^[^:]*://; s/ OPEN//' | sort -u | tr '\n' ' ')"
    if [ "$LOCKMODE" = debug ]; then [ "$OPEN" = "22 " ] || die "from outside, these ports are open on the debug image: $OPEN (only 22 is expected)"; else [ -z "$OPEN" ] || die "from outside, these ports are open on the locked image: $OPEN"; fi
    if grep 'http ' "$OUT/probe-$LOCKMODE.txt" | grep -qv ' 000$'; then die "WebHDFS or the YARN REST interface answered from outside the mesh"; fi
    echo "PROBE-OK ($LOCKMODE): from outside the mesh ${OPEN:-no port} is open, and neither a WebHDFS read nor a YARN call is answered" ;;
  locked-check) say "what each VM says about itself (guest attribute tc/report), checked against what a $LOCKMODE image must say"
    for v in "${ALL[@]}"; do t=0; until attr "$v" tc/report > "$OUT/report-$v.txt" && [ -s "$OUT/report-$v.txt" ]; do t=$((t+10)); [ $t -lt 900 ] || die "no report from $v after 15 minutes (its serial console: gcloud compute instances get-serial-port-output $v --zone=$Z)"; sleep 10; done; done
    t=0; until attr "$VMM" tc/report > "$OUT/report-$VMM.txt" && grep -q '^crawl_marker=crawl done' "$OUT/report-$VMM.txt"; do t=$((t+30)); [ $t -lt 2700 ] || { echo "(the crawl has not finished after 45 minutes: the report is checked as it is)"; break; }; echo "   waiting for the crawl to finish ($t s)"; sleep 30; done
    for v in "${ALL[@]:1}"; do attr "$v" tc/report > "$OUT/report-$v.txt" || true; done
    python3 "$HERE/f1-fleet.py" report "$OUT" "$LOCKMODE" "$IMG" "${ALL[@]}" || die "the reports differ from what a $LOCKMODE image must say"
    if [ "$LOCKMODE" = locked ]; then
      echo "-- trying to log in (it must fail)"
      if timeout 150 gcloud compute ssh "$VMM" --zone="$Z" --quiet --command=true --ssh-flag="-oConnectTimeout=15" --ssh-flag="-oBatchMode=yes" < /dev/null > "$OUT/ssh-attempt-$VMM.txt" 2>&1; then die "gcloud compute ssh WORKED on a locked VM"; fi
      tail -2 "$OUT/ssh-attempt-$VMM.txt" | cut -c1-200 | sed 's/^/   /'; echo "ssh failed, as it must"
      gcloud compute instances get-serial-port-output "$VMM" --zone="$Z" > "$OUT/serial-$VMM.txt" 2>/dev/null || true
      L=$(grep -c ' login:' "$OUT/serial-$VMM.txt" || true); [ "$L" = 0 ] || die "the serial console shows a login prompt ($L lines)"
      if grep -q 'TC-REPORT-BEGIN' "$OUT/serial-$VMM.txt"; then echo "the serial console shows no login prompt, and it carries the VM's own report"; else die "the serial console has no report"; fi
    fi
    echo "LOCK-CHECK-OK ($LOCKMODE)" ;;
  fleet-build-mismatch) say "two nodes, two DIFFERENT fleet lists (each holds the node's own keys)"
    IPM="$(ip_of "$VMM")"; IPW="$(ip_of "$VMW")"
    python3 "$HERE/f1-fleet.py" build-mismatch "$OUT" "$VMM" "$IPM" "$VMW" "$IPW" || die "the announcements were not accepted"
    run gcloud compute instances add-metadata "$VMM" --zone="$Z" --metadata-from-file tc-fleet="$OUT/fleet.tsv",tc-fleet-quotes="$OUT/fleet-quotes.json" < /dev/null || die "could not set tc-fleet on $VMM"
    run gcloud compute instances add-metadata "$VMW" --zone="$Z" --metadata-from-file tc-fleet="$OUT/fleet-w.tsv",tc-fleet-quotes="$OUT/fleet-quotes.json" < /dev/null || die "could not set tc-fleet on $VMW"
    # with mutual attestation the worker now refuses the ghost row (it has no announcement) and stops before WireGuard: the mismatch is prevented, not only seen in the logs
    ;;
  mismatch-compare) say "the RTMR3 logs of the two nodes must show the mismatch"
    for v in "$VMM" "$VMW"; do t=0; until attr "$v" tc/final > "$OUT/final-$v.txt" && [ -s "$OUT/final-$v.txt" ]; do t=$((t+10)); [ $t -lt 900 ] || die "no final quote from $v after 15 minutes"; sleep 10; done; done
    python3 "$HERE/f1-fleet.py" final-mismatch "$OUT" "$VMM" "$VMW" || die "the mismatch was not visible in the logs" ;;
  images-compare) say "F0.6: the debug image and the locked image have different measurements (OUT_A and OUT_B hold their final quotes)"
    python3 "$HERE/f1-fleet.py" images "${OUT_A:?set OUT_A}" "${OUT_B:?set OUT_B}" "$VMM" tc-conf firewall || die "the two images are not told apart by their measurements" ;;
  enforce) say "decision 1 of the mentor's review: every row of fleet.tsv has a quote A and a quote B that match the reference values exactly (rules E1 to E7)"
    python3 "$HERE/f1-fleet.py" enforce "$OUT" "${REFERENCE:?set REFERENCE to the reference values file}" ${PIN_COMMIT:+"$PIN_COMMIT"} || die "the fleet is not accepted" ;;
  reference-values) say "the reference values of the final image (MRTD, RTMR0 to RTMR2, the stable events), from the final quotes of both nodes"
    TC_REF_COMMIT="${PIN_COMMIT:-}" python3 "$HERE/f1-fleet.py" reference "$OUT" "$IMG" "${MACHINE_TYPE:-c3-standard-4}" "${ALL[@]}" || die "the nodes do not agree" ;;
  fleet-clear) say "remove the old fleet list from both VMs (before a reboot makes new keys)"
    for v in "${ALL[@]}"; do run gcloud compute instances remove-metadata "$v" --zone="$Z" --keys=tc-fleet,tc-fleet-quotes < /dev/null || die "could not clear tc-fleet on $v"; done ;;
  fleet-reboot) say "reboot both VMs (new keys; an old fleet list must NOT be accepted)"
    for v in "${ALL[@]}"; do rssh "$v" 'sudo systemctl reboot' >/dev/null 2>&1 || true; done; [ "$DRY" = 1 ] || sleep 150 ;;
  negative-check) say "after the reboot with the OLD fleet list: each node must have stopped before Hadoop"
    for v in "${ALL[@]}"; do echo "-- $v"; rssh "$v" 'echo "tc-fleet: $(systemctl show tc-fleet.service -p Result --value)"; for u in tc-namenode tc-datanode tc-resourcemanager tc-nodemanager; do echo "$u: $(systemctl is-active $u.service)"; done; sudo journalctl -b -u tc-fleet.service --no-pager | grep "TC-FLEET-FAIL" | cut -c1-230' 2>&1 | tee "$OUT/negative-$v.txt"; done ;;
  fleet-delete) say "delete all the VMs of the fleet (${ALL[*]})"; run gcloud compute instances delete "${ALL[@]}" --zone="$Z" --quiet < /dev/null ;;
  *) die "unknown stage: $st" ;; esac; done
echo; echo "F1-DRIVE-DONE"
