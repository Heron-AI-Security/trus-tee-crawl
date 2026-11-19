#!/usr/bin/env bash
# Step F0.3a on DISPOSABLE TDX VMs, driven from Cloud Shell: a builder VM bakes the software layer on top of the F0.1 and F0.2 preparation, its disk becomes an image, and a test VM made from the
# image is checked after each boot. Each stage stops at the first problem; everything it creates is yours to delete (stage delete).
#   bash f03-drive.sh STAGE [ARGS] [STAGE [ARGS]] ...
# Stages: builder | r3-disks | bake-seal | seal-stop | seal-disk | seal-image | seal-boot | seal-check | manifest | manifest-compare | recipe | seal-delete | ship-builder | ship-source | debs | debs-audit | prep | bake | job | bake-crawl | bake-fleet | contract-compile | bake-lock | clean | image | test-vm | ship-test | prove-units | patch-unit NAME | registers | compare-registers | check | reboot-test | compare A B same | compare A B changed NAME | fetch | delete
# Settings for step R4: BASE_IMAGE (pin the exact base image of the builder), COMMIT_FILE (the commit id that r4-archive.py wrote; shipped to the VM as ~/f03/COMMIT), MANIFEST_VM (run the manifest stage on a builder), REFERENCE, REPO_TREE.
# Settings (environment): ZONE (us-central1-a), BUILDER (tc-builder), KVER (the kernel of the sealed image, default 6.17.0-1022-gcp), SEAL_DISK (tc-seal-work), SEALER (tc-sealer), SEAL_TEST (tc-seal-test), SEAL_BLOCKS, SCRATCH_GB (10), HELPER_IMAGE (default tc-img-dbg-1: its disk identifiers differ from the builder's, so the helper cannot boot from the copy by mistake), EXTRA_DISK_GB (a second, spare disk of that size, device name tcscratch, deleted with the VM), TESTVM (tc-f03a-test), IMG (tc-img-f03a-1), BASE_FAMILY (ubuntu-2204-lts), DRY=1 (print, run nothing),
#                         CONFIRM=yes (needed by delete), DELETE_IMAGE=yes (delete also removes the image),
#                         SRC_TGZ, SRC_SHA (used by ship-source and job), CHECK (the check script of stage check; default f03a-check.sh),
#                         HADOOP_URL_BASE (a faster mirror for the Hadoop tarball), HADOOP_SUM_BASE, HADOOP_ALLOW_SLOW=1 (used by bake).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$(cd "$HERE/../../.." && pwd)"
Z="${ZONE:-us-central1-a}"; B="${BUILDER:-tc-builder}"; T="${TESTVM:-tc-f03a-test}"; IMG="${IMG:-tc-img-f03a-1}"; FAM="${BASE_FAMILY:-ubuntu-2204-lts}"; DRY="${DRY:-0}"; OUT="${OUT:-$HOME/evidence-f03a}"
say() { echo; echo "== $*"; }
die() { echo "STOP: $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then printf "DRY:"; printf " %q" "$@"; printf "\n"; else "$@"; fi; }   # a dry run prints every argument quoted exactly as it would be passed
# ssh and scp read the standard input, so their input is always /dev/null
# a creation of the cloud that fails (a transient error of the cloud, a disk that is not READY yet) is tried again, twice, with the error of every attempt shown; a permanent error fails the same way three times and is then reported
retry() { local n=0 f rc; f="$(mktemp)"; until "$@" 2> "$f"; do rc=$?; cat "$f" >&2
    # a stockout of the cloud lasts minutes to hours: trying again in the SAME zone is useless, the caller goes to the next zone
    if grep -qE 'ZONE_RESOURCE_POOL_EXHAUSTED|stockout' "$f"; then rm -f "$f"; return 75; fi
    n=$((n + 1)); [ "$n" -ge 3 ] && { rm -f "$f"; return 1; }; echo "the command failed; trying again in ${RETRY_SLEEP:-20} s (attempt $((n + 1)) of 3)" >&2; sleep "${RETRY_SLEEP:-20}"; done; cat "$f" >&2; rm -f "$f"; return 0; }
zones_in_order() { echo "$Z"; local z; for z in ${ZONE_LIST:-us-central1-a us-central1-b us-central1-c us-central1-f}; do [ "$z" = "$Z" ] || echo "$z"; done; }
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
ATK="${ATTACK_DISK:-tc-atk-disk}"; ATKVM="${ATTACK_VM:-tc-atk-test}"; WK="${SEAL_DISK:-tc-seal-work}"; HLP="${SEALER:-tc-sealer}"; ST="${SEAL_TEST:-tc-seal-test}"; KV="${KVER:-6.17.0-1022-gcp}"
NODEBS=(--exclude=ops/image/debs)   # the committed Ubuntu packages (about 184 MB) are needed by the builder only: no other VM runs apt for the build, and every copy through Cloud Shell is slow
shipkit() { # VM: the kit to a VM (the same steps as ship-builder)
  local V="$1"
  run tar czf "/tmp/f03-ship-$V.tgz" "${NODEBS[@]}" -C "$KIT" ops/image attest ops/rebuild/hadoop_conf.py ops/attested/wrapper-jar.sh ops/attested/OutsiderWrite.java ops/attested/contract ops/attested/contract-tests.sh ops/attested/contract_compare.py || die "could not pack the kit"
  run gcloud compute scp "/tmp/f03-ship-$V.tgz" "$V:~/f03-ship.tgz" --zone="$Z" --quiet < /dev/null || die "could not copy the kit to $V"
  rssh "$V" 'rm -rf ~/f03 && mkdir ~/f03 && tar xzf ~/f03-ship.tgz -C ~/f03 && chmod +x ~/f03/ops/image/build/*.sh ~/f03/ops/image/rootfs/usr/local/lib/tc/*.sh ~/f03/ops/image/test/*.sh' || die "could not unpack the kit on $V"
  if [ -n "${COMMIT_FILE:-}" ]; then [ "$DRY" = 1 ] || [ -s "$COMMIT_FILE" ] || die "COMMIT_FILE $COMMIT_FILE is empty or missing (step R4.2: python3 r4-archive.py ARCHIVE --commit-file FILE)"; run gcloud compute scp "$COMMIT_FILE" "$V:~/f03/COMMIT" --zone="$Z" --quiet < /dev/null || die "could not copy the COMMIT file to $V"; fi
}
attack_evidence() { # CONSOLE-FILE: the refusal of a corrupted root, as the console shows it: a verity error (or the init that cannot be read), an init that cannot run or a panic, and NO login
  grep -qE 'device-mapper: verity: .*corrupt|run-init: can.t execute .*Input/output error' "$1" && grep -qE "Kernel panic|can.t execute" "$1" && ! grep -q ' login: ' "$1"; }
watch_serial() { # VM: poll the serial console; stop at the FIRST failure marker, at a power-off, or at the timeout
  local max="${SEAL_WATCH_SECONDS:-300}" poll="${SEAL_POLL:-8}" stall="${SEAL_STALL:-90}" t=0 txt="" good="" vs st bad v=no s=no l=no len last_len=-1 last_change=0 lp more r
  while [ "$t" -lt "$max" ]; do
    txt="$(gcloud compute instances get-serial-port-output "$1" --zone="$Z" 2>/dev/null)"
    if [ -n "$txt" ]; then good="$txt"; printf '%s\n' "$txt" > "$OUT/serial-$1.txt"; else txt="$good"; fi   # an empty answer never replaces the evidence that was already read
    v=no; s=no; l=no
    grep -q 'tc-verity: the root disk matches the root hash' <<<"$txt" && v=yes
    grep -q 'tc-scratch: .* is the scratch disk (dm-integrity' <<<"$txt" && s=yes
    grep -q ' login: ' <<<"$txt" && l=yes
    len="${#txt}"; if [ "$len" != "$last_len" ]; then last_len="$len"; last_change="$t"; fi
    lp="$(grep -o 'tc-seal: .*' <<<"$txt" | tail -1 | cut -c1-90)"
    echo "   t=${t}s: verity=$v scratch=$s login=$l${lp:+   last step: $lp}"
    bad="$( { grep -E '(tc-verity|tc-scratch): ' <<<"$txt" | grep -vE 'the root disk matches the root hash|is the scratch disk \(dm-integrity' | head -3; grep -E 'ALERT!|Dropping to a shell|\(initramfs\)|Kernel panic|VFS: Cannot open root|Unable to mount root|Gave up waiting for root|^error: (file .* not found|no such device|unknown filesystem)|^grub> ' <<<"$txt" | head -3; } )"
    if [ -n "$bad" ]; then echo "THE BOOT FAILED:"; echo "$bad" | cut -c1-220; echo "--- the last 30 lines of the serial console:"; tail -30 <<<"$txt" | cut -c1-200; return 1; fi
    if [ "$v" = yes ] && [ "$s" = yes ] && [ "$l" = yes ]; then echo "the sealed boot worked: the root matched its hash, the scratch disk is encrypted, and the machine reached its login prompt"; return 0; fi
    vs="$(gcloud compute instances describe "$1" --zone="$Z" --format='value(status)' 2>/dev/null)"
    if [ -n "$vs" ] && [ "$vs" != RUNNING ]; then
      # the console of a VM that has just stopped may take a moment to come back: read it again (up to three times) before saying anything
      for r in 1 2 3; do more="$(gcloud compute instances get-serial-port-output "$1" --zone="$Z" 2>/dev/null)"; [ -z "$more" ] || break; sleep "${SEAL_REFETCH:-5}"; done
      if [ -n "$more" ]; then txt="$more"; good="$more"; printf '%s\n' "$txt" > "$OUT/serial-$1.txt"; fi
      echo "THE VM IS $vs before the boot was complete (our scripts power the machine off when a check fails)."
      bad="$( { grep -E '(tc-verity|tc-scratch): ' <<<"$txt" | grep -vE 'the root disk matches the root hash|is the scratch disk \(dm-integrity' | head -3; grep -E 'ALERT!|Kernel panic|^error: (file .* not found|no such device|unknown filesystem)' <<<"$txt" | head -3; } )"
      if [ -n "$bad" ]; then echo "THE REASON, from the console:"; echo "$bad" | cut -c1-220; else echo "(the console shows no reason of ours)"; fi
      echo "--- the last 30 lines of the serial console:"; tail -30 <<<"$txt" | cut -c1-200; return 1
    fi
    if [ $((t - last_change)) -ge "$stall" ]; then echo "STALLED: the serial console has not changed for ${stall}s (since t=${last_change}s), and the VM is still running. The step that was running:${lp:+ $lp}"; echo "--- the last 30 lines of the serial console:"; tail -30 <<<"$txt" | cut -c1-200; return 1; fi
    sleep "$poll"; t=$((t + poll))
  done
  echo "NO RESULT after ${max}s (verity=$v scratch=$s login=$l); the last 30 lines of the serial console:"; tail -30 <<<"$txt" | cut -c1-200; return 1
}
attack_root_zone() { # the whole attack in the zone $Z; returns 75 when the cloud has no capacity there
      if [ "$DRY" != 1 ]; then ! gcloud compute disks describe "$ATK" --zone="$Z" >/dev/null 2>&1 || die "the disk $ATK exists already (stage seal-delete)"; ! gcloud compute instances describe "$HLP" --zone="$Z" >/dev/null 2>&1 || die "the helper $HLP exists already (stage seal-delete)"; fi
      run gcloud compute disks create "$ATK" --image="$IMG" --type=pd-balanced --zone="$Z" --labels=purpose=tc-seal < /dev/null || die "could not make the disk $ATK"
      # a created resource proves its own properties at once (a c3 machine boots only from pd-balanced, pd-ssd or Hyperdisk; the default of "disks create" is pd-standard)
      [ "$DRY" = 1 ] || [ "$(gcloud compute disks describe "$ATK" --zone="$Z" --format='value(type.basename())' 2>/dev/null)" = pd-balanced ] || die "the disk $ATK is not pd-balanced: the c3 machine could not boot from it"
      [ "$DRY" = 1 ] || { for _i in $(seq 1 24); do [ "$(gcloud compute disks describe "$ATK" --zone="$Z" --format='value(status)' 2>/dev/null)" = READY ] && break; sleep 5; done; }   # a disk made from an image may need a moment
      retry run gcloud compute instances create "$HLP" --zone="$Z" --machine-type=n2-standard-2 --image="${HELPER_IMAGE:-tc-img-dbg-1}" --boot-disk-size=30GB --disk="name=$ATK,device-name=target,mode=rw,boot=no,auto-delete=no" --no-service-account --no-scopes --labels=purpose=tc-seal < /dev/null ; rc=$?; [ "$rc" = 75 ] && return 75; [ "$rc" = 0 ] || die "could not create $HLP"
      wait_ssh "$HLP" || die "no ssh to $HLP"; shipkit "$HLP"
      rssh "$HLP" "sudo bash ~/f03/ops/image/test/r3-flip.sh --p1 /dev/disk/by-id/google-target-part1" 2>&1 | tee "$OUT/attack-root-flip.txt"; [ "$DRY" = 1 ] || grep -q '^FLIP-OK' "$OUT/attack-root-flip.txt" || die "the flip did not happen"
      run gcloud compute instances delete "$HLP" --zone="$Z" --quiet < /dev/null || die "could not delete $HLP"
      retry run gcloud compute instances create "$ATKVM" --zone="$Z" --machine-type=c3-standard-4 --disk="name=$ATK,boot=yes,auto-delete=no" --create-disk="name=$ATKVM-scratch,size=${SCRATCH_GB:-10}GB,type=pd-balanced,device-name=tcscratch,auto-delete=yes" --no-service-account --no-scopes --labels=purpose=tc-seal < /dev/null ; rc=$?; [ "$rc" = 75 ] && return 75; [ "$rc" = 0 ] || die "could not create $ATKVM"
      if [ "$DRY" != 1 ]; then
        if watch_serial "$ATKVM" > "$OUT/attack-root-watch.txt" 2>&1; then cat "$OUT/attack-root-watch.txt"; die "ATTACK NOT REFUSED: the corrupted machine reached its login"; fi
        tail -12 "$OUT/attack-root-watch.txt" | cut -c1-190
        attack_evidence "$OUT/serial-$ATKVM.txt" && echo "ATTACK-ROOT-REFUSED: the machine did not reach its login, and the console shows the reason" || die "the boot stopped, but the console does not show the refusal (a verity corruption error and an init that cannot run, and no login): see $OUT/serial-$ATKVM.txt"
      fi
}
cleanup_zone() { local v; for v in "$HLP" "$ATKVM"; do gcloud compute instances describe "$v" --zone="$Z" >/dev/null 2>&1 && gcloud compute instances delete "$v" --zone="$Z" --quiet < /dev/null; done; gcloud compute disks describe "$ATK" --zone="$Z" >/dev/null 2>&1 && gcloud compute disks delete "$ATK" --zone="$Z" --quiet < /dev/null; return 0; }
while [ $# -gt 0 ]; do
  st="$1"; shift
  case "$st" in
    builder)
      say "create the builder $B (a disposable TDX VM from the current image family $FAM, no service account)"
      [[ "$B" =~ ^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$ ]] || die "the builder name '$B' is not a valid VM name (lower-case letters, digits and hyphens, starting with a letter): the cloud would refuse it"
      if [ "$DRY" != 1 ] && gcloud compute instances describe "$B" --zone="$Z" >/dev/null 2>&1; then echo "$B already exists"; [ "$(gcloud compute instances describe "$B" --zone="$Z" --format='value(status)')" = TERMINATED ] && { echo "it is stopped: starting it"; run gcloud compute instances start "$B" --zone="$Z" --quiet < /dev/null || die "could not start $B"; forget_key "$B"; }; else
        IMGARGS=(--image-family="$FAM" --image-project=ubuntu-os-cloud); [ -z "${BUILDER_FROM:-}" ] || IMGARGS=(--image="$BUILDER_FROM"); [ -z "${BASE_IMAGE:-}" ] || IMGARGS=(--image="$BASE_IMAGE" --image-project=ubuntu-os-cloud)   # BASE_IMAGE pins the exact base image (step R4.2); the family moves
        EXTRA=(); [ -z "${EXTRA_DISK_GB:-}" ] || EXTRA=(--create-disk="name=$B-scratch,size=${EXTRA_DISK_GB}GB,type=pd-balanced,device-name=tcscratch,auto-delete=yes")
        run gcloud compute instances create "$B" "${TDX[@]}" "${IMGARGS[@]}" "${EXTRA[@]}" --labels=purpose=tc-f03a-builder < /dev/null || die "could not create $B"; fi
      wait_ssh "$B" || die "no ssh to $B"
      [ "$DRY" = 1 ] || gcloud compute disks describe "$B" --zone="$Z" --format='value(sourceImage)' > "$OUT/base-image.txt" 2>/dev/null || true   # what the builder was really made from
      [ "$DRY" = 1 ] || [ -z "${BASE_IMAGE:-}" ] || grep -q "/$BASE_IMAGE\$" "$OUT/base-image.txt" 2>/dev/null || die "the builder was not made from the pinned base image $BASE_IMAGE (its disk says: $(cat "$OUT/base-image.txt" 2>/dev/null)): the committed packages were captured against that image"
      rssh "$B" 'hostname; uname -r; test -d /sys/kernel/config/tsm/report && echo "configfs-tsm: present"; sudo -n true && echo "sudo: ok"' | tee "$OUT/f03-builder-console.txt" ;;
    ship-builder|ship-test)
      V="$B"; [ "$st" = ship-test ] && V="$T"
      say "ship the kit to $V"
      XD=(); if [ "$st" = ship-test ]; then XD=("${NODEBS[@]}"); fi; run tar czf "/tmp/f03-ship-$V.tgz" "${XD[@]}" -C "$KIT" ops/image attest ops/rebuild/hadoop_conf.py ops/attested/wrapper-jar.sh ops/attested/OutsiderWrite.java ops/attested/contract ops/attested/contract-tests.sh ops/attested/contract_compare.py || die "could not pack the kit"
      run gcloud compute scp "/tmp/f03-ship-$V.tgz" "$V:~/f03-ship.tgz" --zone="$Z" --quiet < /dev/null || die "could not copy the kit"
      rssh "$V" 'rm -rf ~/f03 && mkdir ~/f03 && tar xzf ~/f03-ship.tgz -C ~/f03 && chmod +x ~/f03/ops/image/build/*.sh ~/f03/ops/image/rootfs/usr/local/lib/tc/*.sh ~/f03/ops/image/test/*.sh && ls ~/f03/ops/image' || die "could not unpack the kit"
      if [ -n "${COMMIT_FILE:-}" ]; then [ "$DRY" = 1 ] || [ -s "$COMMIT_FILE" ] || die "COMMIT_FILE $COMMIT_FILE is empty or missing (step R4.2: python3 r4-archive.py ARCHIVE --commit-file FILE)"; run gcloud compute scp "$COMMIT_FILE" "$V:~/f03/COMMIT" --zone="$Z" --quiet < /dev/null || die "could not copy the COMMIT file to $V"; fi ;;
    debs)
      say "on the builder: apt reads the committed packages only (ops/image/debs), no network is needed for them"
      rssh "$B" 'cd ~/f03 && bash ops/image/build/tc-image-debs.sh ~/f03' 2>&1 | tee "$OUT/f03-debs-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the committed packages stage stopped" ;;
    debs-audit)
      say "on the builder: the audit of apt after the build (no .deb downloaded, one source, the committed versions installed)"
      rssh "$B" 'cd ~/f03 && bash ops/image/build/tc-image-debs.sh ~/f03 --audit' 2>&1 | tee "$OUT/f03-debs-audit-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the audit of apt failed (the lines above say what apt did)" ;;
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
      SRC="${SRC_TGZ:?set SRC_TGZ to the source archive made by git archive in Cloud Shell}"
      [ -f "$SRC" ] || die "no source archive at $SRC"
      say "ship the source archive ($(sha256sum "$SRC" | cut -c1-16)...) to $B"
      rssh "$B" 'mkdir -p ~/f03/inputs' || die "no inputs folder on $B"
      run gcloud compute scp "$SRC" "$B:~/f03/inputs/" --zone="$Z" --quiet < /dev/null || die "could not copy the inputs"
      rssh "$B" 'ls -l ~/f03/inputs' ;;
    job)
      SRC="${SRC_TGZ:?set SRC_TGZ to the source archive}"
      SSHA="${SRC_SHA:-$(sha256sum "$SRC" 2>/dev/null | cut -c1-64)}"; [ -n "${SRC_SHA:-}" ] || echo "note: SRC_SHA is not set, so the archive is pinned to the file as shipped ($SSHA)"
      say "on the builder: the job and the wrapper jar, from pinned inputs (about 15 minutes; a progress line every 30 seconds)"
      SCOM=""; [ -s "${COMMIT_FILE:-/nonexistent}" ] && SCOM="$(tr -d ' \r\n' < "$COMMIT_FILE")"
      rssh "$B" "cd ~/f03 && SRC_COMMIT=$SCOM bash ops/image/build/tc-image-job.sh ~/f03 ~/f03/inputs/$(basename "$SRC") $SSHA" 2>&1 | tee "$OUT/f03-job-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the job build stopped" ;;
    bake-crawl)
      say "on the builder: the crawl driver, its parameters and seeds, and the unit that runs it (the measured list grows to 13 events)"
      rssh "$B" 'cd ~/f03 && bash ops/image/build/tc-image-crawl.sh ~/f03' 2>&1 | tee "$OUT/f03-crawl-bake-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the crawl bake stopped" ;;
    bake-fleet)
      say "on the builder: the fleet boot flow, the changed units, the commit record and the 15-event measured list (steps F1 and R4.2)"
      rssh "$B" 'cd ~/f03 && bash ops/image/build/tc-image-fleet.sh ~/f03' 2>&1 | tee "$OUT/f1-bake-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the fleet bake stopped" ;;
    seal-locked)
      say "on the builder: the lock, the cleaning and the power-off in ONE ssh session (the lock removes sshd, so a second session is impossible), then wait for the stop"
      rssh "$B" 'cd ~/f03 && bash ops/image/build/tc-image-lock.sh locked ~/f03 && bash ops/image/build/tc-image-clean.sh --this-machine-becomes-an-image && echo SEAL-DONE; rc=$?; if [ $rc = 0 ]; then nohup sh -c "sleep 3; sudo systemctl poweroff" > /dev/null 2>&1 & fi; exit $rc' 2>&1 | tee "$OUT/f4-seal-console.txt"
      grep -q 'SEAL-DONE' "$OUT/f4-seal-console.txt" || die "the lock or the cleaning did not finish (read the output above)"
      t=0; until [ "$(gcloud compute instances describe "$B" --zone="$Z" --format='value(status)' 2>/dev/null)" = TERMINATED ]; do t=$((t+10)); [ $t -lt 300 ] || die "the builder did not stop"; sleep 10; done; echo "the builder is stopped (no login was needed after the lock)" ;;
    r3-probe)
      say "R3.0, read-only: facts about a booted node of the debug image (initrd, device-mapper in the kernel, the boot log's registers, the user hadoop)"
      rssh "$B" "sudo bash ~/f03/ops/image/test/r3-probe.sh" 2>&1 | tee "$OUT/r3-probe.txt"; grep -q 'R3-PROBE-DONE' "$OUT/r3-probe.txt" || die "the probe did not finish (read the output above)" ;;
    bake-lock)
      [ "${LOCKMODE:-}" != locked ] || die "the locked mode removes sshd: use the stage seal-locked (one session), not bake-lock followed by clean"
      say "on the builder: the firewall, the report and (for the locked image) the lock; mode $LOCKMODE (step F0.4, F0.5, F0.6)"
      rssh "$B" "cd ~/f03 && bash ops/image/build/tc-image-lock.sh ${LOCKMODE:?set LOCKMODE to debug or locked} ~/f03" 2>&1 | tee "$OUT/f4-bake-$LOCKMODE-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the lock bake stopped" ;;
    contract-compile)
      say "on the builder: Hadoop's contract tests must COMPILE against the job and Hadoop's test jars (nothing is run; this catches in minutes what a cluster run would catch an hour later)"
      rssh "$B" 'rm -rf /tmp/f3cc && mkdir -p /tmp/f3cc/ops && cp -r ~/f03/ops/attested /tmp/f3cc/ops/ && env HOME=/tmp/f3cc COMPILE_ONLY=1 JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 HADOOP_HOME=/opt/hadoop PATH=/usr/lib/jvm/java-11-openjdk-amd64/bin:/opt/hadoop/bin:/usr/bin:/bin ATTESTED_JOB=/opt/tc/nutch/apache-nutch-1.22.job ATTESTED_CONTRACT_URI=hdfs://127.0.0.1:9000 ATTESTED_CONTRACT_DIR=/user/x/contract-tests-f3 bash /tmp/f3cc/ops/attested/contract-tests.sh /tmp/f3cc/out' 2>&1 | tee "$OUT/f3-contract-compile-console.txt"; grep -q "COMPILE-ONLY-OK" "$OUT/f3-contract-compile-console.txt" || die "the contract tests do not compile (read the output above)" ;;
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
    r3-disks)
      say "R3.1, read-only: how a second disk shows up, what GRUB's files and the initramfs tooling look like, which modules and packages the sealing needs"
      rssh "$B" "sudo bash ~/f03/ops/image/test/r3-disks.sh" 2>&1 | tee "$OUT/r3-disks.txt"; grep -q 'R3-DISKS-DONE' "$OUT/r3-disks.txt" || die "the probe did not finish (read the output above)" ;;
    bake-seal)
      say "R3.3 on the builder: the sealed initramfs (install the sources, build, verify in gates 1 to 5, install)"
      rssh "$B" "sudo bash ~/f03/ops/image/build/tc-image-refresh.sh --kit ~/f03 && sudo bash ~/f03/ops/image/build/tc-image-sealbake.sh --kit ~/f03 --kver $KV" 2>&1 | tee "$OUT/f03-sealbake-console.txt"
      grep -q '^REFRESH-OK' "$OUT/f03-sealbake-console.txt" && grep -q '^SEALBAKE-OK' "$OUT/f03-sealbake-console.txt" || die "the sealed initramfs was not built (the first SEALBAKE-STOP line above says why)" ;;
    seal-stop)
      say "stop the builder (its disk is COPIED next; the builder itself is never changed by the sealing)"
      run gcloud compute instances stop "$B" --zone="$Z" --quiet < /dev/null || die "could not stop $B" ;;
    seal-disk)
      say "R3.3: a COPY of the builder's disk ($B -> $WK), the helper VM $HLP that holds it as a second disk, and the offline sealing (gates 1 to 9)"
      if [ "$DRY" != 1 ]; then
        [ "$(gcloud compute instances describe "$B" --zone="$Z" --format='value(status)' 2>/dev/null)" = TERMINATED ] || die "the builder $B must be stopped first (stage seal-stop)"
        ! gcloud compute disks describe "$WK" --zone="$Z" >/dev/null 2>&1 || die "the disk $WK exists already: stage seal-delete removes it"
        ! gcloud compute instances describe "$HLP" --zone="$Z" >/dev/null 2>&1 || die "the helper VM $HLP exists already: stage seal-delete removes it"
        gcloud compute images describe "${HELPER_IMAGE:-tc-img-dbg-1}" >/dev/null 2>&1 || die "the image for the helper VM (${HELPER_IMAGE:-tc-img-dbg-1}) does not exist"
      fi
      run gcloud compute disks create "$WK" --source-disk="$B" --zone="$Z" --labels=purpose=tc-seal < /dev/null || die "could not copy the disk of $B"
      run gcloud compute instances create "$HLP" --zone="$Z" --machine-type=n2-standard-2 --image="${HELPER_IMAGE:-tc-img-dbg-1}" --boot-disk-size=30GB --disk="name=$WK,device-name=target,mode=rw,boot=no,auto-delete=no" --no-service-account --no-scopes --labels=purpose=tc-seal < /dev/null || die "could not create the helper VM $HLP"
      wait_ssh "$HLP" || die "no ssh to $HLP"
      shipkit "$HLP"
      rssh "$HLP" "sudo bash ~/f03/ops/image/build/tc-image-seal.sh --disk /dev/disk/by-id/google-target --p1 /dev/disk/by-id/google-target-part1 --esp /dev/disk/by-id/google-target-part15 --kver $KV --destructive-ok --blocks ${SEAL_BLOCKS:-2621440} --out /root" 2>&1 | tee "$OUT/seal-console.txt"
      grep -q '^SEAL-OK ' "$OUT/seal-console.txt" || die "the sealing stopped (the first SEAL-STOP line above says why; the copy $WK and the helper $HLP are kept: stage seal-delete removes them)"
      rssh "$HLP" 'sudo cat /root/seal-report.txt' > "$OUT/seal-report.txt" || die "could not read the seal report"
      rssh "$HLP" 'sudo cat /root/normalize-report.txt' > "$OUT/normalize-report.txt" 2>/dev/null || echo "note: no normalization report (the sealing script of this kit has no gate 6b)"   # step P4: what the normalization removed, kept as evidence
      say "delete the helper VM (only the helper; the sealed copy $WK stays)"; run gcloud compute instances delete "$HLP" --zone="$Z" --quiet < /dev/null || die "could not delete $HLP" ;;
    seal-image)
      if [ "$DRY" != 1 ]; then
        [ -s "$OUT/seal-report.txt" ] || die "no seal report in $OUT (run seal-disk first)"
        [ -z "$(gcloud compute disks describe "$WK" --zone="$Z" --format='value(users)' 2>/dev/null)" ] || die "the disk $WK is still attached to a VM"
      fi
      say "make the image $IMG from the sealed copy $WK"
      if ! run gcloud compute images create "$IMG" --source-disk="$WK" --source-disk-zone="$Z" --guest-os-features="$FEATURES" --description="step R3.3: the sealed debug image (verity root, RAM overlay, encrypted scratch disk)" --labels=purpose=tc-seal < /dev/null; then
        echo "note: the full list of guest features was refused; trying the minimal list"
        run gcloud compute images create "$IMG" --source-disk="$WK" --source-disk-zone="$Z" --guest-os-features="UEFI_COMPATIBLE,GVNIC,VIRTIO_SCSI_MULTIQUEUE,TDX_CAPABLE" --description="step R3.3: the sealed debug image" --labels=purpose=tc-seal < /dev/null || die "could not create the image"; fi
      run gcloud compute images describe "$IMG" --format="yaml(name,status,diskSizeGb,guestOsFeatures[].type)" < /dev/null | tee "$OUT/seal-image-describe.txt" ;;
    seal-boot)
      say "R3.4: boot the sealed image on a plain (not TDX) VM with a spare disk, and WATCH the serial console: it stops at the first failure"
      if [ "$DRY" != 1 ]; then
        gcloud compute images describe "$IMG" >/dev/null 2>&1 || die "the image $IMG does not exist (stage seal-image)"
        ! gcloud compute instances describe "$ST" --zone="$Z" >/dev/null 2>&1 || die "the VM $ST exists already: stage seal-delete removes it"
      fi
      run gcloud compute instances create "$ST" --zone="$Z" --machine-type=c3-standard-4 --image="$IMG" --boot-disk-size=30GB --boot-disk-type=pd-balanced --create-disk="name=$ST-scratch,size=${SCRATCH_GB:-10}GB,type=pd-balanced,device-name=tcscratch,auto-delete=yes" --no-service-account --no-scopes --labels=purpose=tc-seal < /dev/null || die "could not create $ST"
      if [ "$DRY" != 1 ]; then watch_serial "$ST" || die "the sealed boot did not work (see above; the VM $ST is kept for diagnosis: stage seal-delete removes it)"; fi ;;
    seal-check)
      say "R3.4: the checks inside the booted sealed VM (read-only)"
      wait_ssh "$ST" || die "no ssh to $ST"; shipkit "$ST"
      RH=""; [ -s "$OUT/seal-report.txt" ] && RH="$(awk -F= '/^roothash=/ {print $2}' "$OUT/seal-report.txt")"
      rssh "$ST" "sudo bash ~/f03/ops/image/test/r3-seal-check.sh $RH" 2>&1 | tee "$OUT/seal-check.txt"
      grep -q '^SEAL-CHECK-OK' "$OUT/seal-check.txt" || die "the sealed VM did not pass its checks (the FAIL lines above say which)" ;;
    manifest)
      VMX="${MANIFEST_VM:-$ST}"; say "R4.0: the ground truth: what is inside every measured item of the booted VM $VMX (read-only; the files go to $OUT/r4)"
      wait_ssh "$VMX" || die "no ssh to $VMX"; [ -n "${MANIFEST_VM:-}" ] || shipkit "$VMX"   # on a builder the kit is there already: shipping it again would replace the build state
      mkdir -p "$OUT"
      rssh "$VMX" "sudo bash ~/f03/ops/image/test/r4-manifest.sh /tmp/r4-out > /tmp/r4.log 2>&1; RC=\$?; cat /tmp/r4.log | tail -25; [ \$RC = 0 ] && sudo tar czf /tmp/r4-out.tgz -C /tmp r4-out && sha256sum /tmp/r4-out.tgz | cut -d' ' -f1 > /tmp/r4-out.sha && echo R4-REMOTE-DONE; exit \$RC" 2>&1 | tee "$OUT/r4-remote.txt"
      if [ "$DRY" != 1 ]; then grep -q '^R4-MANIFEST-OK' "$OUT/r4-remote.txt" && grep -q '^R4-REMOTE-DONE' "$OUT/r4-remote.txt" || die "the manifest run on $VMX did not finish (the lines above say why)"; fi
      run gcloud compute scp "$VMX:/tmp/r4-out.tgz" "$VMX:/tmp/r4-out.sha" "$OUT/" --zone="$Z" --quiet < /dev/null || die "could not copy the result from $VMX"
      if [ "$DRY" != 1 ]; then
        [ "$(sha256sum "$OUT/r4-out.tgz" | cut -d' ' -f1)" = "$(tr -d ' \n' < "$OUT/r4-out.sha")" ] || die "the copy of the result differs from the file on $VMX"
        rm -rf "$OUT/r4"; mkdir -p "$OUT/r4" && tar xzf "$OUT/r4-out.tgz" -C "$OUT/r4" --strip-components=1 || die "could not unpack the result"
        echo "the ground truth is in $OUT/r4 ($(find "$OUT/r4" -type f | wc -l) files; the archive has SHA-256 $(sha256sum "$OUT/r4-out.tgz" | cut -c1-16)...)"
      fi ;;
    manifest-compare)
      say "R4.0: the offline checks of the ground truth: against the reference values of the cluster, and against the files of the repository"
      REF="${REFERENCE:-}"; [ "$DRY" = 1 ] || { [ -n "$REF" ] && [ -s "$REF" ] || die "set REFERENCE to the reference-values.json of a fleet run on this image"; }
      run python3 "$HERE/r4-compare.py" "$OUT/r4" --reference "$REF" --repo "${REPO_TREE:-$KIT}" --candidates "$OUT/r4-install-candidates.tsv" 2>&1 | tee "$OUT/r4-compare.txt"
      if [ "$DRY" != 1 ]; then grep -q '^R4-COMPARE-OK' "$OUT/r4-compare.txt" || die "the comparison failed (the FAIL lines above say which)"; fi ;;
    recipe)
      say "R4.1 (offline, no VM): derive the recipe from the ground truth in $OUT/r4, then recompute the measured values from the COMMIT alone and compare them with the cluster's reference values"
      REF="${REFERENCE:-}"; [ "$DRY" = 1 ] || { [ -n "$REF" ] && [ -s "$REF" ] || die "set REFERENCE to the reference-values.json of a fleet run on this image"; [ -s "$OUT/r4/events.tsv" ] || die "no ground truth in $OUT/r4 (stage manifest)"; }
      run python3 "$HERE/r4-derive.py" --evidence "$OUT/r4" --repo "${REPO_TREE:-$KIT}" --out "$OUT/recipe" 2>&1 | tee "$OUT/r4-derive.txt"
      if [ "$DRY" != 1 ]; then grep -q '^R4-DERIVE-OK' "$OUT/r4-derive.txt" || die "the derivation failed (the lines above say why)"; fi
      run python3 "$HERE/r4-recompute.py" --repo "${REPO_TREE:-$KIT}" --recipe "$OUT/recipe" --reference "$REF" --json "$OUT/r4-recomputed.json" 2>&1 | tee "$OUT/r4-recompute.txt"
      if [ "$DRY" != 1 ]; then grep -q '^R4-RECOMPUTE-OK' "$OUT/r4-recompute.txt" || die "the recomputation does not equal the cluster's values (the FAIL lines above say which)"; fi ;;
    attack-scratch)
      say "R3.6 attacks 2 and 3 on the booted sealed VM $ST: garbage on the raw scratch disk is refused; a reset gives a new key and an empty disk"
      wait_ssh "$ST" || die "no ssh to $ST"; shipkit "$ST"
      rssh "$ST" "sudo bash ~/f03/ops/image/test/r3-attack-scratch.sh before" 2>&1 | tee "$OUT/attack-scratch-1.txt"
      [ "$DRY" = 1 ] || grep -q '^ATTACK-SCRATCH-1-OK' "$OUT/attack-scratch-1.txt" || die "attack 2 was not refused (the FAIL lines above)"
      OLDU="$(sed -n 's/^UUID=//p' "$OUT/attack-scratch-1.txt" | tail -1)"; [ -n "$OLDU" ] || [ "$DRY" = 1 ] || die "no file system UUID from the first part"
      run gcloud compute instances reset "$ST" --zone="$Z" < /dev/null || die "could not reset $ST"
      wait_ssh "$ST" || die "no ssh to $ST after the reset"; shipkit "$ST"
      rssh "$ST" "sudo bash ~/f03/ops/image/test/r3-attack-scratch.sh after $OLDU" 2>&1 | tee "$OUT/attack-scratch-2.txt"
      [ "$DRY" = 1 ] || grep -q '^ATTACK-SCRATCH-2-OK' "$OUT/attack-scratch-2.txt" || die "attack 3 failed (the FAIL lines above)" ;;
    attack-root)
      say "R3.6 attack 1: one bit of /usr/lib/systemd/systemd is flipped in a copy of the root of $IMG; the machine must NOT reach its login"
      Z0="$Z"; ORDER="$(zones_in_order | tr '\n' ' ')"; [ "$DRY" != 1 ] || ORDER="$Z0"; ok_zone=""
      for zz in $ORDER; do
        Z="$zz"; echo "--- attack-root in zone $Z"; attack_root_zone; rc=$?
        if [ "$rc" = 0 ]; then ok_zone="$Z"; break; fi
        [ "$rc" = 75 ] || die "the attack stage failed in zone $Z (read the lines above)"
        echo "NO CAPACITY in $Z (a stockout of the cloud, not a fault of ours): removing what was created there and trying the next zone"; cleanup_zone
      done
      Z="$Z0"; [ -n "$ok_zone" ] || die "no zone had capacity (tried: $ORDER): try again later, or set ZONE_LIST to other zones of the region"
      echo "$ok_zone" > "$OUT/zone-attack.txt" ;;
    seal-delete)
      [ "${CONFIRM:-}" = yes ] || die "set CONFIRM=yes to delete $ST, $HLP and the disk $WK (by these exact names)"
      ZSCAN="$Z"; [ "$DRY" = 1 ] || ZSCAN="$(zones_in_order | tr '
' ' ')"
      for zz in $ZSCAN; do for v in "$ST" "$HLP" "$ATKVM"; do if [ "$DRY" = 1 ] || gcloud compute instances describe "$v" --zone="$zz" >/dev/null 2>&1; then say "delete the VM $v ($zz)"; run gcloud compute instances delete "$v" --zone="$zz" --quiet < /dev/null; fi; done; done
      for zz in $ZSCAN; do for dk in "$WK" "$ATK"; do if [ "$DRY" = 1 ] || gcloud compute disks describe "$dk" --zone="$zz" >/dev/null 2>&1; then say "delete the disk $dk ($zz)"; run gcloud compute disks delete "$dk" --zone="$zz" --quiet < /dev/null; fi; done; done
      [ "${DELETE_IMAGE:-}" = yes ] && { say "delete the image $IMG"; run gcloud compute images delete "$IMG" --quiet < /dev/null; } ;;
    delete)
      [ "${CONFIRM:-}" = yes ] || die "set CONFIRM=yes to delete $T and $B"
      say "delete $T and $B"; run gcloud compute instances delete "$T" "$B" --zone="$Z" --quiet < /dev/null
      [ "${DELETE_IMAGE:-}" = yes ] && { say "delete the image $IMG"; run gcloud compute images delete "$IMG" --quiet < /dev/null; } ;;
    *) die "unknown stage: $st" ;;
  esac
done
echo; echo "F03-DRIVE-DONE"
