#!/usr/bin/env bash
# Step F0.3a on DISPOSABLE TDX VMs, driven from Cloud Shell: a builder VM bakes the software layer on top of the F0.1 and F0.2 preparation, its disk becomes an image, and a test VM made from the
# image is checked after each boot. Each stage stops at the first problem; everything it creates is yours to delete (stage delete).
#   bash f03-drive.sh STAGE [ARGS] [STAGE [ARGS]] ...
# Stages: builder | ship-builder | ship-source | prep | bake | job | bake-crawl | bake-fleet | clean | image | test-vm | ship-test | prove-units | patch-unit NAME | registers | compare-registers | check | reboot-test | compare A B same | compare A B changed NAME | fetch | delete
# Settings (environment): ZONE (us-central1-a), BUILDER (tc-builder), TESTVM (tc-f03a-test), IMG (tc-img-f03a-1), BASE_FAMILY (ubuntu-2204-lts), DRY=1 (print, run nothing),
#                         CONFIRM=yes (needed by delete), DELETE_IMAGE=yes (delete also removes the image),
#                         SRC_TGZ, SRC_SHA, PATCH, PATCH_SHA (used by ship-source and job), CHECK (the check script of stage check; default f03a-check.sh),
#                         HADOOP_URL_BASE (a faster mirror for the Hadoop tarball), HADOOP_SUM_BASE, HADOOP_ALLOW_SLOW=1 (used by bake).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$(cd "$HERE/../../.." && pwd)"
Z="${ZONE:-us-central1-a}"; B="${BUILDER:-tc-builder}"; T="${TESTVM:-tc-f03a-test}"; IMG="${IMG:-tc-img-f03a-1}"; FAM="${BASE_FAMILY:-ubuntu-2204-lts}"; DRY="${DRY:-0}"; OUT="${OUT:-$HOME/evidence-f03a}"
say() { echo; echo "== $*"; }
die() { echo "STOP: $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then echo "DRY: $*"; else "$@"; fi; }
# ssh and scp read the standard input, so their input is always /dev/null
rssh() { if [ "$DRY" = 1 ]; then echo "DRY: ssh $1: $2"; return 0; fi; gcloud compute ssh "$1" --zone="$Z" --quiet --command="$2" < /dev/null; }
wait_ssh() {
  [ "$DRY" = 1 ] && return 0; local last="" forgot=0
  for _ in $(seq 1 40); do
    last="$(gcloud compute ssh "$1" --zone="$Z" --quiet --command=true < /dev/null 2>&1)" && return 0
    # a changed host key is not a slow boot: forget the old key of this one instance (once) and try again at once, whatever way the VM was started
    if [ "$forgot" = 0 ] && grep -qiE 'host key.*(has )?changed|REMOTE HOST IDENTIFICATION' <<<"$last"; then forgot=1; forget_key "$1"; continue; fi
    sleep 10
  done
  echo "the last ssh message was:"; printf '%s\n' "$last" | tail -6
  if grep -qiE 'host key.*(has )?changed|REMOTE HOST IDENTIFICATION' <<<"$last"; then echo "hint: the VM has a new host key; run: ssh-keygen -f ~/.ssh/google_compute_known_hosts -R compute.<the instance id>"; fi
  return 1
}
# (forget_key is defined below and called from wait_ssh)
# A builder that was cleaned and restarted has made NEW ssh host keys (the cleaning deletes them on purpose), but Cloud Shell remembers the old key of the same instance and refuses to connect.
# Only gcloud's own file of remembered keys is touched, and only the entry of this one instance.
forget_key() {
  local id out; id="$(gcloud compute instances describe "$1" --zone="$Z" --format='value(id)' 2>/dev/null)"; [ -n "$id" ] && [ -f "$HOME/.ssh/google_compute_known_hosts" ] || return 0
  out="$(ssh-keygen -f "$HOME/.ssh/google_compute_known_hosts" -R "compute.$id" 2>&1)"; if grep -q 'found: line' <<<"$out"; then echo "forgot the remembered host key of $1 (the cleaning made a new one)"; fi; return 0
}
TDX=(--zone="$Z" --machine-type=c3-standard-4 --confidential-compute-type=TDX --maintenance-policy=TERMINATE --boot-disk-size=30GB --boot-disk-type=pd-balanced --no-service-account --no-scopes)
FEATURES="UEFI_COMPATIBLE,GVNIC,VIRTIO_SCSI_MULTIQUEUE,IDPF,TDX_CAPABLE,SEV_CAPABLE,SEV_SNP_CAPABLE,SEV_LIVE_MIGRATABLE,SEV_LIVE_MIGRATABLE_V2"
mkdir -p "$OUT"
while [ $# -gt 0 ]; do
  st="$1"; shift
  case "$st" in
    builder)
      say "create the builder $B (a disposable TDX VM from the current image family $FAM, no service account)"
      if [ "$DRY" != 1 ] && gcloud compute instances describe "$B" --zone="$Z" >/dev/null 2>&1; then echo "$B already exists"; [ "$(gcloud compute instances describe "$B" --zone="$Z" --format='value(status)')" = TERMINATED ] && { echo "it is stopped: starting it"; run gcloud compute instances start "$B" --zone="$Z" --quiet < /dev/null || die "could not start $B"; forget_key "$B"; }; else
        run gcloud compute instances create "$B" "${TDX[@]}" --image-family="$FAM" --image-project=ubuntu-os-cloud --labels=purpose=tc-f03a-builder < /dev/null || die "could not create $B"; fi
      wait_ssh "$B" || die "no ssh to $B"
      rssh "$B" 'hostname; uname -r; test -d /sys/kernel/config/tsm/report && echo "configfs-tsm: present"; sudo -n true && echo "sudo: ok"' | tee "$OUT/f03-builder-console.txt" ;;
    ship-builder|ship-test)
      V="$B"; [ "$st" = ship-test ] && V="$T"
      say "ship the kit to $V"
      run tar czf /tmp/f03-ship.tgz -C "$KIT" ops/image attest ops/rebuild/hadoop_conf.py ops/attested/wrapper-jar.sh || die "could not pack the kit"
      run gcloud compute scp /tmp/f03-ship.tgz "$V:~/f03-ship.tgz" --zone="$Z" --quiet < /dev/null || die "could not copy the kit"
      rssh "$V" 'rm -rf ~/f03 && mkdir ~/f03 && tar xzf ~/f03-ship.tgz -C ~/f03 && chmod +x ~/f03/ops/image/build/*.sh ~/f03/ops/image/rootfs/usr/local/lib/tc/*.sh ~/f03/ops/image/test/*.sh && ls ~/f03/ops/image' || die "could not unpack the kit" ;;
    prep)
      say "on the builder: 6.17 as the default kernel and the measurement unit (no stand-in unit)"
      rssh "$B" 'cd ~/f03 && bash ops/image/build/tc-image-prep.sh ~/f03' 2>&1 | tee "$OUT/f03-prep-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the preparation stopped" ;;
    bake)
      say "on the builder: the software layer (JDK, Hadoop, the service user, the configuration, the units, the longer measured list)"
      rssh "$B" "cd ~/f03 && HADOOP_URL_BASE='${HADOOP_URL_BASE:-}' HADOOP_SUM_BASE='${HADOOP_SUM_BASE:-}' HADOOP_ALLOW_SLOW='${HADOOP_ALLOW_SLOW:-0}' bash ops/image/build/tc-image-bake.sh ~/f03" 2>&1 | tee "$OUT/f03-bake-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the bake stopped" ;;
    clean)
      say "on the builder: remove what belongs to this machine (it is made into an image next)"
      rssh "$B" 'cd ~/f03 && bash ops/image/build/tc-image-clean.sh --this-machine-becomes-an-image' 2>&1 | tee "$OUT/f03-clean-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the cleaning stopped" ;;
    image)
      say "stop the builder and make the image $IMG from its disk"
      run gcloud compute instances stop "$B" --zone="$Z" --quiet < /dev/null || die "could not stop $B"
      if ! run gcloud compute images create "$IMG" --source-disk="$B" --source-disk-zone="$Z" --guest-os-features="$FEATURES" --description="step F0.3a: the software layer of the fixed-fleet image" --labels=purpose=tc-f03a < /dev/null; then
        echo "note: the full list of guest features was refused; trying the minimal list"
        run gcloud compute images create "$IMG" --source-disk="$B" --source-disk-zone="$Z" --guest-os-features="UEFI_COMPATIBLE,GVNIC,VIRTIO_SCSI_MULTIQUEUE,TDX_CAPABLE" --description="step F0.3a: the software layer of the fixed-fleet image" --labels=purpose=tc-f03a < /dev/null || die "could not create the image"; fi
      run gcloud compute images describe "$IMG" --format="yaml(name,status,diskSizeGb,guestOsFeatures[].type)" < /dev/null | tee "$OUT/f03-image-describe.txt" ;;
    test-vm)
      say "create the test VM $T from the image $IMG"
      if [ "$DRY" != 1 ] && gcloud compute instances describe "$T" --zone="$Z" >/dev/null 2>&1; then echo "$T already exists"; else
        run gcloud compute instances create "$T" "${TDX[@]}" --image="$IMG" --labels=purpose=tc-f03a-test < /dev/null || die "could not create $T"; fi
      wait_ssh "$T" || die "no ssh to $T"; rssh "$T" 'hostname; uname -r' ;;
    registers)
      say "the registers of the latest quote on $T (after a check): saved in $OUT/f03d-registers.txt"
      rssh "$T" 'n=$(cat /var/lib/tc/bootcount); python3 ~/f03/ops/image/test/f03-registers.py /var/lib/tc/f01-boot${n}-quote.bin "'"$T"'-boot${n}"' 2>&1 | tee -a "$OUT/f03d-registers.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "could not read the registers" ;;
    compare-registers)
      say "compare the registers of the VMs in $OUT/f03d-registers.txt"
      python3 "$HERE/f03-registers.py" --compare "$OUT/f03d-registers.txt" | tee "$OUT/f03d-registers-compare.txt" ;;
    ship-source)
      SRC="${SRC_TGZ:?set SRC_TGZ to the source archive made by git archive in Cloud Shell}"; PAT="${PATCH:-$KIT/inputs/source-receipt-841c1d3.lf.patch}"
      [ -f "$SRC" ] || die "no source archive at $SRC"; [ -f "$PAT" ] || die "no patch at $PAT (the teammate's pinned patch; its SHA-256 starts with 61dbff2e)"
      say "ship the source archive ($(sha256sum "$SRC" | cut -c1-16)...) and the patch ($(sha256sum "$PAT" | cut -c1-16)...) to $B"
      rssh "$B" 'mkdir -p ~/f03/inputs' || die "no inputs folder on $B"
      run gcloud compute scp "$SRC" "$PAT" "$B:~/f03/inputs/" --zone="$Z" --quiet < /dev/null || die "could not copy the inputs"
      rssh "$B" 'ls -l ~/f03/inputs' ;;
    job)
      SRC="${SRC_TGZ:?set SRC_TGZ to the source archive}"; PAT="${PATCH:-$KIT/inputs/source-receipt-841c1d3.lf.patch}"; PSHA="${PATCH_SHA:-61dbff2eca98cc7b9934f8e5e51e34265298aa22eb6cecf4d22c3bef44ad5516}"
      SSHA="${SRC_SHA:-$(sha256sum "$SRC" 2>/dev/null | cut -c1-64)}"; [ -n "${SRC_SHA:-}" ] || echo "note: SRC_SHA is not set, so the archive is pinned to the file as shipped ($SSHA)"
      say "on the builder: the job and the wrapper jar, from pinned inputs (about 15 minutes; a progress line every 30 seconds)"
      rssh "$B" "cd ~/f03 && bash ops/image/build/tc-image-job.sh ~/f03 ~/f03/inputs/$(basename "$SRC") $SSHA ~/f03/inputs/$(basename "$PAT") $PSHA" 2>&1 | tee "$OUT/f03-job-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the job build stopped" ;;
    bake-crawl)
      say "on the builder: the crawl driver, its parameters and seeds, and the unit that runs it (the measured list grows to 13 events)"
      rssh "$B" 'cd ~/f03 && bash ops/image/build/tc-image-crawl.sh ~/f03' 2>&1 | tee "$OUT/f03-crawl-bake-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the crawl bake stopped" ;;
    bake-fleet)
      say "on the builder: the fleet boot flow, the changed units and the 14-event measured list (step F1)"
      rssh "$B" 'cd ~/f03 && bash ops/image/build/tc-image-fleet.sh ~/f03' 2>&1 | tee "$OUT/f1-bake-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the fleet bake stopped" ;;
    prove-units)
      say "read only: what systemd says about the unit files on $T"
      rssh "$T" 'sudo systemd-analyze verify /usr/local/lib/tc/units/*.service 2>&1 | grep -v "^$" | cut -c1-200; echo "(end of systemd-analyze output)"' ;;
    patch-unit)
      NAME="${1:?patch-unit NAME  (for example tc-hdfs-format)}"; shift
      say "replace the unit $NAME on $T by the one in the shipped kit, and make systemd read it again"
      rssh "$T" "sudo install -m 0644 ~/f03/ops/image/rootfs/usr/local/lib/tc/units/$NAME.service /usr/local/lib/tc/units/$NAME.service && sudo systemctl daemon-reload && sudo systemctl reset-failed $NAME.service; sudo systemd-analyze verify /usr/local/lib/tc/units/*.service 2>&1 | grep -ci unknown | sed 's/^/unknown-key warnings now: /'" ;;
    check)
      say "check this boot of $T"
      rssh "$T" "sudo bash ~/f03/ops/image/test/${CHECK:-f03a-check.sh}" 2>&1 | tee "$OUT/f03a-check-console-$(date -u +%H%M%S).txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the check failed; read its FAIL lines" ;;
    reboot-test)
      say "a plain reboot of $T"
      old=""; [ "$DRY" = 1 ] || old="$(rssh "$T" 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null | tr -d '\r\n')"
      rssh "$T" 'sudo systemctl reboot' >/dev/null 2>&1 || true
      [ "$DRY" = 1 ] && continue
      sleep 25; new=""
      for _ in $(seq 1 40); do new="$(rssh "$T" 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null | tr -d '\r\n')"; [ -n "$new" ] && [ "$new" != "$old" ] && break; sleep 10; done
      [ -n "$new" ] && [ "$new" != "$old" ] || die "$T did not come back with a new boot id"; echo "rebooted: the boot id changed" ;;
    compare)
      A="${1:?compare A B same|changed [NAME]}"; Bn="${2:?compare A B same|changed [NAME]}"; M="${3:?compare A B same|changed [NAME]}"; shift 3; NAME=""
      if [ "$M" = changed ]; then NAME="${1:?compare A B changed NAME}"; shift; fi
      say "compare the logs of boot $A and boot $Bn ($M $NAME)"
      rssh "$T" "python3 ~/f03/ops/image/test/f01-compare.py /var/lib/tc/events-boot$A.tsv /var/lib/tc/events-boot$Bn.tsv $M $NAME" 2>&1 | tee -a "$OUT/f03a-compare-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the comparison failed" ;;
    fetch)
      say "fetch the evidence"
      mkdir -p "$OUT/vm"; run gcloud compute scp "$T:/var/lib/tc/*" "$OUT/vm/" --zone="$Z" --quiet < /dev/null || die "could not fetch /var/lib/tc"
      rssh "$T" 'uname -a; sudo grub-editenv list; cat /etc/tc/role /etc/tc/bake-versions.txt; cat /etc/tc/measured-paths.txt' > "$OUT/vm/f03a-final-info.txt" 2>&1; echo "saved in $OUT/vm" ;;
    delete)
      [ "${CONFIRM:-}" = yes ] || die "set CONFIRM=yes to delete $T and $B"
      say "delete $T and $B"; run gcloud compute instances delete "$T" "$B" --zone="$Z" --quiet < /dev/null
      [ "${DELETE_IMAGE:-}" = yes ] && { say "delete the image $IMG"; run gcloud compute images delete "$IMG" --quiet < /dev/null; } ;;
    *) die "unknown stage: $st" ;;
  esac
done
echo; echo "F03-DRIVE-DONE"
