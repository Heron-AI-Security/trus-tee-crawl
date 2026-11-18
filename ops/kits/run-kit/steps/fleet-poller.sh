#!/usr/bin/env bash
# fleet-poller.sh MASTER OUTDIR PIDFILE: every RK_POLL_SECS (45) it appends the lines of the master's serial console that hold tc-crawl: or tc-export: to OUTDIR/master-log-lines.raw. It ends by itself when
# the master cannot be read five times in a row (it is deleted), or after RK_POLL_MAX_SECS (4 hours), so that it never outlives a run that was abandoned.
M="$1"; OUTD="$2"; PIDF="$3"; SECS="${RK_POLL_SECS:-45}"; MAXS="${RK_POLL_MAX_SECS:-14400}"; t0="$(date +%s)"; fails=0
echo $$ > "$PIDF"
while :; do
  zz="$(tr -d ' \r\n' < "$OUTD/zone.txt" 2>/dev/null)"; [ -n "$zz" ] || zz="${RK_DEFAULT_ZONE:-us-central1-a}"
  if out="$(gcloud compute instances get-serial-port-output "$M" --zone "$zz" 2>/dev/null)"; then fails=0; printf '%s\n' "$out" | grep -a "tc-crawl:\|tc-export:" >> "$OUTD/master-log-lines.raw"; else fails=$((fails + 1)); fi
  [ "$fails" -lt 5 ] || break
  [ $(( $(date +%s) - t0 )) -lt "$MAXS" ] || break
  sleep "$SECS"
done
rm -f "$PIDF"
