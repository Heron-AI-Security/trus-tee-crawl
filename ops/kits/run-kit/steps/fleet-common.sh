#!/usr/bin/env bash
# Sourced by the crawl steps 7 to 10 (after names.sh, lib.sh, tools.sh and rk_load_names). The names of the fleet, the environment of the fleet driver, the driver call with a heartbeat, and the poller that
# collects the console of the master. The environment is the one of the run that passed in the old kit; ZONE is passed only until the driver has written the zone in which it found capacity (zone.txt),
# because a ZONE in the environment hides that file.
H="$HOME"; TREE="$H/$BUILD_TREE"; OUTF="$H/$EVIDENCE"; COMMIT="$(cat "$H/$BUILD_DIR/commit.txt" 2>/dev/null)"; NVM=$((WORKERS + 1))
PIDF="$H/$RUN_DIR/poller.pid"; RAWL="$OUTF/master-log-lines.raw"
mkdir -p "$OUTF" "$H/$RUN_DIR"
vm_names() { echo "$MASTER"; local i; for i in $(seq 1 "$WORKERS"); do rk_worker "$i"; done; }
existing_vms() { gcloud compute instances list --filter="labels.tc-run=$RUN_LABEL" --format='value(name)' 2>/dev/null | sort | tr '\n' ' ' | sed 's/ *$//'; }
fleet_drive() {  # LOGNAME LABEL STAGE...: one call of the fleet driver; its output goes to $OUTF/LOGNAME.log, a heartbeat shows its last line
  local lg="$1" label="$2"; shift 2
  local -a FENV=(IMG="$IMAGE_1" OUT="$OUTF" SCRATCH_GB="$RK_FLEET_SCRATCH_GB" WORKERS="$WORKERS" LOCKMODE="$RK_FLEET_LOCKMODE" EXPORT_BUCKET="$RK_EXPORT_BUCKET" EXPORT_SA="$RK_EXPORT_SA" PIN_COMMIT="$COMMIT"
                 VMM="$MASTER" VMW="$(rk_worker 1)" VMWBASE="$WORKER_BASE" EXTRA_LABELS="tc-run=$RUN_LABEL" MACHINE_TYPE="$MACHINE_TYPE")
  [ -s "$OUTF/zone.txt" ] || FENV+=(ZONE="$ZONE")
  rk_run_watched "$OUTF/$lg.log" "$label" env "${FENV[@]}" bash "$TREE/$RK_T_FLEET_DRIVER" "$@"
}
fleet_poller_start() {  # the console of a VM keeps only its last 1 MiB: a detached process collects the crawl and export lines of the master until the master is gone
  [ -e "$RAWL" ] || : > "$RAWL"
  if [ -s "$PIDF" ] && kill -0 "$(cat "$PIDF")" 2>/dev/null; then return 0; fi
  setsid nohup bash "$KD/steps/fleet-poller.sh" "$MASTER" "$OUTF" "$PIDF" > /dev/null 2>&1 < /dev/null &
}
fleet_poll_once() { local zz; zz="$(tr -d ' \r\n' < "$OUTF/zone.txt" 2>/dev/null)"; [ -n "$zz" ] || zz="$RK_DEFAULT_ZONE"; gcloud compute instances get-serial-port-output "$MASTER" --zone "$zz" 2>/dev/null | grep -a "tc-crawl:\|tc-export:" >> "$RAWL"; return 0; }
fleet_poller_stop() { [ -s "$PIDF" ] && kill "$(cat "$PIDF")" 2>/dev/null; rm -f "$PIDF"; fleet_poll_once; sort -u "$RAWL" > "$OUTF/master-log-lines.txt" 2>/dev/null; return 0; }
