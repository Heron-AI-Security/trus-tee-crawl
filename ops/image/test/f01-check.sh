#!/usr/bin/env bash
# Steps F0.1 and F0.2, the check after EACH boot of a test VM (run as root): 6.17 is the default kernel and the running one, RTMR3 is not zero, the measurement unit ran and finished
# BEFORE the stand-in daemons started, the event log replays to the real RTMR3, and a hardware quote is bound to the log. Evidence is left in /var/lib/tc (world readable).
#   sudo bash f01-check.sh
# Hooks for the rehearsal only: TC_LIB, TC_RUN, TC_STATE, TC_OUT, TC_RTMR3, TC_UNAME, TC_SUDO.
set -uo pipefail
NEW=6.17.0-1022-gcp
LIB="${TC_LIB:-/usr/local/lib/tc}"; RUN="${TC_RUN:-/run/tc}"; STATE="${TC_STATE:-/var/lib/tc}"; OUT="${TC_OUT:-$STATE}"
RT="${TC_RTMR3:-/sys/devices/virtual/misc/tdx_guest/measurements/rtmr3:sha384}"; K="${TC_UNAME:-$(uname -r)}"; SUDO="${TC_SUDO-}"
bad=0; ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; bad=$((bad+1)); }
N="$(cat "$STATE/bootcount" 2>/dev/null || echo 0)"
echo "f01-check: $(date -u +%FT%TZ) on $(hostname), boot number $N"
echo "== the kernel"
[ "$K" = "$NEW" ] && ok "running $K" || no "running $K, expected $NEW"
ENV="$($SUDO grub-editenv list 2>&1)"
printf '%s\n' "$ENV" | grep -qxF "saved_entry=Advanced options for Ubuntu>Ubuntu, with Linux $NEW" && ok "the saved (permanent) default is $NEW" || no "the saved default is not $NEW: $(printf '%s' "$ENV" | tr '\n' ' ')"
printf '%s\n' "$ENV" | grep -q '^next_entry=' && no "a one-time entry (next_entry) is set: this boot may not be a plain one" || ok "no one-time entry is set (a plain boot)"
echo "== RTMR3"
if [ -e "$RT" ]; then R3="$(xxd -p "$RT" | tr -d '\n')"; else R3=""; fi
[ -n "$R3" ] && [ -n "$(printf '%s' "$R3" | tr -d 0)" ] && ok "RTMR3 is not zero: ${R3:0:16}..." || no "RTMR3 is zero or unreadable"
echo "== the measurement unit"
[ "$(systemctl is-active tc-measure.service 2>&1)" = active ] && ok "tc-measure.service is active" || no "tc-measure.service is not active"
[ "$(systemctl show tc-measure.service -p Result --value 2>&1)" = success ] && ok "its result is success" || no "its result is not success"
J="$(journalctl -b -u tc-measure.service --no-pager -o cat 2>&1 | grep 'TC-MEASURE-OK' | tail -1)"
[ -n "$J" ] && ok "journal: $J" || no "no TC-MEASURE-OK line in this boot's journal"
if systemctl cat tc-placeholder.service >/dev/null 2>&1; then
  ME="$(systemctl show tc-measure.service -p ExecMainExitTimestampMonotonic --value 2>&1)"; PS="$(systemctl show tc-placeholder.service -p ExecMainStartTimestampMonotonic --value 2>&1)"
  if [[ "$ME" =~ ^[0-9]+$ && "$PS" =~ ^[0-9]+$ && "$ME" -gt 0 && "$PS" -gt 0 ]]; then
    [ "$ME" -lt "$PS" ] && ok "the measurement finished (at $ME us) before the stand-in daemons started (at $PS us)" || no "the stand-in daemons started (at $PS us) before the measurement finished (at $ME us)"
  else no "no usable timestamps (measure exit '$ME', placeholder start '$PS')"; fi
  [ -f "$RUN/placeholder-started" ] && ok "the stand-in daemons started after /run/tc/measure-done existed" || no "the stand-in daemons did not start"
else echo "   (no stand-in unit on this machine: the ordering is not checked)"; fi
echo "== the event log replays to RTMR3"
if [ -s "$RUN/rtmr3-events.tsv" ]; then
  REP="$(python3 "$LIB/rtmr3_replay.py" "$RUN/rtmr3-events.tsv" 2>&1)"
  printf '%s\n' "$REP" | grep -q 'chain consistent: True' && ok "the log's chain is consistent ($(printf '%s\n' "$REP" | grep -c '^event [0-9]') events)" || no "the log's chain is not consistent"
  RP="$(printf '%s\n' "$REP" | sed -n 's/^replayed RTMR3: //p')"
  [ -n "$RP" ] && [ "${R3:0:12}" = "$RP" ] && ok "the replayed RTMR3 ($RP) equals the register" || no "the replayed RTMR3 ($RP) differs from the register (${R3:0:12})"
else no "no event log at $RUN/rtmr3-events.tsv"; fi
echo "== a quote bound to the log"
if QO="$("$LIB/quote.sh" "$RUN/rtmr3-events.tsv" "$OUT/f01-boot$N-quote.bin" 2>&1)"; then
  QR="$(python3 "$LIB/rtmr3_replay.py" "$RUN/rtmr3-events.tsv" "$OUT/f01-boot$N-quote.bin" 2>&1)"
  printf '%s\n' "$QR" | grep -q 'RTMR3 in quote: [0-9a-f]* -> MATCH$' && ok "RTMR3 in the hardware quote equals the replay" || no "RTMR3 in the quote does not match the replay"
  printf '%s\n' "$QR" | grep -q 'REPORTDATA = SHA-512 of this log: YES' && ok "the quote's REPORTDATA is the SHA-512 of the log" || no "the quote is not bound to the log"
else no "could not make a quote: $QO"; fi
echo "== evidence"
if [ -s "$RUN/rtmr3-events.tsv" ]; then
  cp "$RUN/rtmr3-events.tsv" "$OUT/f01-boot$N-events.tsv"; echo "$K" > "$OUT/f01-boot$N-uname.txt"; printf '%s\n' "$ENV" > "$OUT/f01-boot$N-grubenv.txt"
  journalctl -b -u tc-measure.service --no-pager -o cat > "$OUT/f01-boot$N-journal.txt" 2>&1; chmod 644 "$OUT"/f01-boot"$N"-* 2>/dev/null
  echo "saved: $OUT/f01-boot$N-{events.tsv,quote.bin,uname.txt,grubenv.txt,journal.txt}"
fi
if [ $bad -eq 0 ]; then echo "F01-CHECK-OK boot=$N kernel=$K rtmr3=${R3:0:16}"; else echo "F01-CHECK-FAILED ($bad) boot=$N"; fi
[ $bad -eq 0 ]
