#!/usr/bin/env bash
# Steps F0.1 and F0.2 on a DISPOSABLE TDX test VM, driven from Cloud Shell. Each stage stops at the first problem; the VM is yours to delete at the end (stage delete).
#   bash f01-drive.sh STAGE [ARGS] [STAGE [ARGS]] ...
# Stages:  create | ship | prep | reboot | check | compare A B same | compare A B changed NAME | change | unchange | fetch | delete
# Settings (environment): VM (tc-f01-test), ZONE (us-central1-a), IMAGE (ubuntu-2204-jammy-v20260918, the image the two cluster nodes were made from), DRY=1 (print the commands, run nothing), CONFIRM=yes (needed by delete).
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; KIT="$(cd "$HERE/../../.." && pwd)"
VM="${VM:-tc-f01-test}"; Z="${ZONE:-us-central1-a}"; IMAGE="${IMAGE:-ubuntu-2204-jammy-v20260918}"; DRY="${DRY:-0}"; OUT="${OUT:-$HOME/evidence-f01}"
say() { echo; echo "== $*"; }
die() { echo "STOP: $*" >&2; exit 1; }
run() { if [ "$DRY" = 1 ]; then echo "DRY: $*"; else "$@"; fi; }
# ssh and scp read the standard input, so their input is always /dev/null (they would swallow a loop's list)
rssh() { if [ "$DRY" = 1 ]; then echo "DRY: ssh $VM: $1"; return 0; fi; gcloud compute ssh "$VM" --zone="$Z" --quiet --command="$1" < /dev/null; }
wait_ssh() { [ "$DRY" = 1 ] && return 0; for _ in $(seq 1 40); do rssh true >/dev/null 2>&1 && return 0; sleep 10; done; return 1; }
mkdir -p "$OUT"
while [ $# -gt 0 ]; do
  st="$1"; shift
  case "$st" in
    create)
      say "create $VM (a disposable TDX VM from the image $IMAGE, no service account)"
      if [ "$DRY" != 1 ] && gcloud compute instances describe "$VM" --zone="$Z" >/dev/null 2>&1; then echo "$VM already exists"; else
        run gcloud compute instances create "$VM" --zone="$Z" --machine-type=c3-standard-4 --confidential-compute-type=TDX --maintenance-policy=TERMINATE --image="$IMAGE" --image-project=ubuntu-os-cloud --boot-disk-size=30GB --boot-disk-type=pd-balanced --no-service-account --no-scopes --labels=purpose=tc-f01-test < /dev/null || die "could not create $VM"
      fi
      wait_ssh || die "no ssh to $VM after 400 seconds"
      rssh 'hostname; uname -r; test -d /sys/kernel/config/tsm/report && echo "configfs-tsm: present"; sudo -n true && echo "sudo: ok"' | tee "$OUT/f01-create-console.txt" ;;
    ship)
      say "ship the kit to $VM"
      run tar czf /tmp/f01-ship.tgz -C "$KIT" ops/image attest || die "could not pack the kit"
      run gcloud compute scp /tmp/f01-ship.tgz "$VM:~/f01-ship.tgz" --zone="$Z" --quiet < /dev/null || die "could not copy the kit"
      rssh 'rm -rf ~/f01 && mkdir ~/f01 && tar xzf ~/f01-ship.tgz -C ~/f01 && chmod +x ~/f01/ops/image/build/*.sh ~/f01/ops/image/rootfs/usr/local/lib/tc/*.sh ~/f01/ops/image/test/*.sh && ls ~/f01/ops/image' || die "could not unpack the kit" ;;
    prep)
      say "prepare the image: 6.17 as the default kernel, the measurement unit, the stand-in daemons"
      rssh 'cd ~/f01 && bash ops/image/build/tc-image-prep.sh ~/f01 --with-placeholder' 2>&1 | tee "$OUT/f01-prep-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the preparation stopped; read its last lines" ;;
    reboot)
      say "a plain reboot (sudo systemctl reboot)"
      old=""; [ "$DRY" = 1 ] || old="$(rssh 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null | tr -d '\r\n')"
      rssh 'sudo systemctl reboot' >/dev/null 2>&1 || true
      [ "$DRY" = 1 ] && continue
      sleep 25; new=""
      for _ in $(seq 1 40); do new="$(rssh 'cat /proc/sys/kernel/random/boot_id' 2>/dev/null | tr -d '\r\n')"; [ -n "$new" ] && [ "$new" != "$old" ] && break; sleep 10; done
      [ -n "$new" ] && [ "$new" != "$old" ] || die "the VM did not come back with a new boot id"
      echo "rebooted: the boot id changed" ;;
    check)
      say "check this boot"
      rssh 'sudo bash ~/f01/ops/image/test/f01-check.sh' 2>&1 | tee "$OUT/f01-check-console-$(date -u +%H%M%S).txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the check failed; read its FAIL lines" ;;
    compare)
      A="${1:?compare A B same|changed [NAME]}"; B="${2:?compare A B same|changed [NAME]}"; M="${3:?compare A B same|changed [NAME]}"; shift 3; NAME=""
      if [ "$M" = changed ]; then NAME="${1:?compare A B changed NAME}"; shift; fi
      say "compare the logs of boot $A and boot $B ($M $NAME)"
      rssh "python3 ~/f01/ops/image/test/f01-compare.py /var/lib/tc/events-boot$A.tsv /var/lib/tc/events-boot$B.tsv $M $NAME" 2>&1 | tee -a "$OUT/f01-compare-console.txt"; [ "${PIPESTATUS[0]}" = 0 ] || die "the comparison failed" ;;
    change)
      say "the control: change one measured file on purpose (a comment line at the end of tc-extend.sh)"
      rssh "echo '# f01 control: a deliberate change' | sudo tee -a /usr/local/lib/tc/tc-extend.sh > /dev/null && sudo tail -1 /usr/local/lib/tc/tc-extend.sh" || die "could not change the file" ;;
    unchange)
      say "undo the control"
      rssh "[ \"\$(sudo tail -1 /usr/local/lib/tc/tc-extend.sh)\" = '# f01 control: a deliberate change' ] && sudo sed -i '\$ d' /usr/local/lib/tc/tc-extend.sh && sudo tail -1 /usr/local/lib/tc/tc-extend.sh" || die "the last line is not the control line; nothing was removed" ;;
    fetch)
      say "fetch the evidence of every boot"
      mkdir -p "$OUT/vm"; run gcloud compute scp "$VM:/var/lib/tc/*" "$OUT/vm/" --zone="$Z" --quiet < /dev/null || die "could not fetch /var/lib/tc"
      rssh 'uname -a; sudo grub-editenv list; systemctl is-enabled tc-measure.service tc-placeholder.service; cat /etc/tc/measured-paths.txt' > "$OUT/vm/f01-final-info.txt" 2>&1; echo "saved in $OUT/vm" ;;
    delete)
      [ "${CONFIRM:-}" = yes ] || die "set CONFIRM=yes to delete $VM"
      say "delete $VM"; run gcloud compute instances delete "$VM" --zone="$Z" --quiet < /dev/null ;;
    *) die "unknown stage: $st" ;;
  esac
done
echo; echo "F01-DRIVE-DONE"
