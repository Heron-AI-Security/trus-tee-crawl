#!/usr/bin/env bash
# Step F1 on DISPOSABLE TDX VMs, operator side (Cloud Shell): two VMs from one image announce their keys, the operator checks the announcements and sets the fleet list as metadata, and the fleet forms.
#   bash f1-drive.sh STAGE [STAGE] ...
# Stages: fleet-vms | announce-wait | fleet-build | final-wait | fleet-check | fleet-f2 | fleet-contract | fleet-contract-compare | fleet-clear | fleet-reboot | negative-check | fleet-delete
# Settings: IMG (the image), VMM (tc-f1-m), VMW (tc-f1-w), ZONE (us-central1-a), OUT (~/evidence-f1), DRY=1, F2MODE (all, or outsider to repeat only that part).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$(cd "$HERE/../../.." && pwd)"
Z="${ZONE:-us-central1-a}"; IMG="${IMG:?set IMG to the image}"; VMM="${VMM:-tc-f1-m}"; VMW="${VMW:-tc-f1-w}"; OUT="${OUT:-$HOME/evidence-f1}"; DRY="${DRY:-0}"
say() { echo; echo "== $*"; }
die() { echo "STOP: $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then echo "DRY: $*"; else "$@"; fi; }
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
TDX=(--zone="$Z" --machine-type=c3-standard-4 --confidential-compute-type=TDX --maintenance-policy=TERMINATE --boot-disk-size=30GB --boot-disk-type=pd-balanced --no-service-account --no-scopes --metadata=enable-guest-attributes=TRUE)
mkdir -p "$OUT"
for st in "$@"; do case "$st" in
  fleet-vms) say "create the master $VMM and the worker $VMW from $IMG (guest attributes on, no service account)"
    for v in "$VMM" "$VMW"; do run gcloud compute instances create "$v" "${TDX[@]}" --image="$IMG" --labels=purpose=tc-f1 < /dev/null || die "could not create $v"; done ;;
  announce-wait) say "wait for both announcements (the guest attribute tc/announce)"
    for v in "$VMM" "$VMW"; do t=0; until attr "$v" tc/announce > "$OUT/announce-$v.txt" && [ -s "$OUT/announce-$v.txt" ]; do t=$((t+10)); [ $t -lt 900 ] || die "no announcement from $v after 15 minutes"; sleep 10; done; echo "$v announced ($(wc -c < "$OUT/announce-$v.txt") bytes)"; done ;;
  fleet-build) say "verify both announcements (the quote binds the keys and the log), write fleet.tsv, set it as metadata"
    IPM="$(ip_of "$VMM")"; IPW="$(ip_of "$VMW")"
    python3 "$HERE/f1-fleet.py" build "$OUT" "$VMM" "$IPM" "$VMW" "$IPW" || die "the announcements were not accepted"
    for v in "$VMM" "$VMW"; do run gcloud compute instances add-metadata "$v" --zone="$Z" --metadata-from-file tc-fleet="$OUT/fleet.tsv" < /dev/null || die "could not set tc-fleet on $v"; done ;;
  final-wait) say "wait for both final quotes, and check that both logs hold the same fleet event"
    for v in "$VMM" "$VMW"; do t=0; until attr "$v" tc/final > "$OUT/final-$v.txt" && [ -s "$OUT/final-$v.txt" ]; do t=$((t+10)); [ $t -lt 900 ] || die "no final quote from $v after 15 minutes (the node may have stopped: read its serial console)"; sleep 10; done; echo "$v published its final quote"; done
    python3 "$HERE/f1-fleet.py" final "$OUT" "$VMM" "$VMW" || die "the final quotes are not consistent" ;;
  fleet-check) say "the node-side checks (ssh)"
    bad=0; for pair in "$VMW:worker" "$VMM:master"; do v="${pair%%:*}"; r="${pair##*:}"; ship "$v"
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
  fleet-clear) say "remove the old fleet list from both VMs (before a reboot makes new keys)"
    for v in "$VMM" "$VMW"; do run gcloud compute instances remove-metadata "$v" --zone="$Z" --keys=tc-fleet < /dev/null || die "could not clear tc-fleet on $v"; done ;;
  fleet-reboot) say "reboot both VMs (new keys; an old fleet list must NOT be accepted)"
    for v in "$VMM" "$VMW"; do rssh "$v" 'sudo systemctl reboot' >/dev/null 2>&1 || true; done; [ "$DRY" = 1 ] || sleep 150 ;;
  negative-check) say "after the reboot with the OLD fleet list: each node must have stopped before Hadoop"
    for v in "$VMM" "$VMW"; do echo "-- $v"; rssh "$v" 'echo "tc-fleet: $(systemctl show tc-fleet.service -p Result --value)"; for u in tc-namenode tc-datanode tc-resourcemanager tc-nodemanager; do echo "$u: $(systemctl is-active $u.service)"; done; sudo journalctl -b -u tc-fleet.service --no-pager | grep "TC-FLEET-FAIL" | cut -c1-230' 2>&1 | tee "$OUT/negative-$v.txt"; done ;;
  fleet-delete) say "delete both VMs"; run gcloud compute instances delete "$VMM" "$VMW" --zone="$Z" --quiet < /dev/null ;;
  *) die "unknown stage: $st" ;; esac; done
echo; echo "F1-DRIVE-DONE"
