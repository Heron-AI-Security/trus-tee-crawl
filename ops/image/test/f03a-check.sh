#!/usr/bin/env bash
# Step F0.3a, the check after EACH boot of a VM made from the image (run as root): the measurement of step F0.2 still passes; the log holds the events of the list, in order; the four daemons run by
# themselves, as the user hadoop, and started after the measurement; HDFS works (a write and a read as hadoop); the code is owned by root and cannot be changed by the service user; the service user
# cannot log in; and the NameNode, DataNode and ResourceManager listen on the loopback address only. Other listeners are reported, for step F0.5. Evidence is left in /var/lib/tc.
#   sudo bash f03a-check.sh
# Hooks for the rehearsal only: TC_ROOT, TC_RUN, TC_STATE, TC_OUT, TC_LIST, TC_F01, TC_TRIES, TC_SLEEP.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="${TC_ROOT:-}"; RUN="${TC_RUN:-/run/tc}"; STATE="${TC_STATE:-/var/lib/tc}"; OUT="${TC_OUT:-$STATE}"; LIST="${TC_LIST:-$R/etc/tc/measured-paths.txt}"
F01="${TC_F01:-$HERE/f01-check.sh}"; JAVA=/usr/lib/jvm/java-11-openjdk-amd64; HDFS="$R/opt/hadoop/bin/hdfs"; TRIES="${TC_TRIES:-24}"; SLEEP="${TC_SLEEP:-5}"
bad=0; ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; bad=$((bad+1)); }
N="$(cat "$STATE/bootcount" 2>/dev/null || echo 0)"
echo "f03a-check: $(date -u +%FT%TZ) on $(hostname), boot number $N"
echo "== the measurement (the checks of step F0.2)"
F01OUT="$(bash "$F01" 2>&1)"; F01RC=$?
printf '%s\n' "$F01OUT" | grep 'FAIL:' | sed 's/^/      /'
[ $F01RC = 0 ] && printf '%s\n' "$F01OUT" | grep -q '^F01-CHECK-OK' && ok "$(printf '%s\n' "$F01OUT" | tail -1)" || no "the checks of step F0.2 did not pass"
echo "== the measured events"
WANT="$(awk -F'\t' '!/^#/ && NF>=2 {print $1}' "$LIST" | tr '\n' ' ')"; GOT="$(cut -f1 "$RUN/rtmr3-events.tsv" 2>/dev/null | tr '\n' ' ')"
[ -n "$WANT" ] && [ "$WANT" = "$GOT" ] && ok "the log holds the $(printf '%s\n' "$WANT" | wc -w) events of the list, in order: $GOT" || no "the log's events ($GOT) are not the list's ($WANT)"
MS="$(systemctl show tc-measure.service -p ExecMainStartTimestampMonotonic --value 2>/dev/null)"; ME="$(systemctl show tc-measure.service -p ExecMainExitTimestampMonotonic --value 2>/dev/null)"
if [[ "$MS" =~ ^[0-9]+$ && "$ME" =~ ^[0-9]+$ && "$ME" -gt "$MS" ]]; then echo "   info: the measurement took $(( (ME - MS) / 1000000 )) s"; else no "no usable timestamps for the measurement (start '$MS', exit '$ME')"; fi
echo "== the units, as systemd reads them"
UF=("$R"/usr/local/lib/tc/units/*.service)
if [ -e "${UF[0]}" ]; then
  VOUT="$(systemd-analyze verify "${UF[@]}" 2>&1 || true)"
  # only warnings that name OUR units count: systemd-analyze also prints warnings about Ubuntu's own files (the real output showed one for snapd.service)
  if printf '%s\n' "$VOUT" | grep -i 'unknown' | grep -q 'tc-[a-z-]*\.service'; then printf '%s\n' "$VOUT" | grep -i 'unknown' | grep 'tc-[a-z-]*\.service' | sed 's/^/      /'; no "systemd does not understand part of a unit file"; else ok "systemd reads all ${#UF[@]} unit files without an unknown key or section"; fi
else no "no unit files in /usr/local/lib/tc/units"; fi
echo "== the daemons"
for u in tc-namenode tc-datanode tc-resourcemanager tc-nodemanager; do
  [ "$(systemctl is-active $u.service 2>&1)" = active ] && ok "$u is active" || no "$u is not active"
  PID="$(systemctl show $u.service -p MainPID --value 2>/dev/null)"; USR="$(ps -o user= -p "$PID" 2>/dev/null | tr -d ' ')"
  [ "$USR" = hadoop ] && ok "$u runs as hadoop (pid $PID)" || no "$u runs as '$USR', not hadoop"
  ST="$(systemctl show $u.service -p ExecMainStartTimestampMonotonic --value 2>/dev/null)"
  if [[ "$ST" =~ ^[0-9]+$ && "$ME" =~ ^[0-9]+$ && "$ST" -gt "$ME" ]]; then ok "$u started after the measurement finished"; else no "$u did not start after the measurement finished (start '$ST', measurement end '$ME')"; fi
done
[ "$(systemctl show tc-hdfs-format.service -p Result --value 2>/dev/null)" = success ] && ok "the format unit's result is success (it formats the first time and is skipped later)" || no "the format unit's result is not success"
echo "== Hadoop works (a write and a read as the user hadoop)"
HD() { runuser -u hadoop -- env JAVA_HOME="$JAVA" HADOOP_CONF_DIR="$R/opt/hadoop/etc/hadoop" HADOOP_LOG_DIR=/var/log/hadoop "$HDFS" "$@"; }
t=0; until HD dfs -ls / >/dev/null 2>&1; do t=$((t+1)); [ $t -lt "$TRIES" ] || break; sleep "$SLEEP"; done
if [ $t -lt "$TRIES" ]; then ok "hdfs dfs -ls / works (after $((t*SLEEP)) s)"; else no "hdfs dfs -ls / did not work in $((TRIES*SLEEP)) s"; fi
echo "tc-f03a-boot$N" | HD dfs -put -f - /tc-f03a-check >/dev/null 2>&1; GOTV="$(HD dfs -cat /tc-f03a-check 2>/dev/null)"
[ "$GOTV" = "tc-f03a-boot$N" ] && ok "a file written to HDFS reads back the same" || no "the file read back from HDFS is '$GOTV'"
HD dfs -rm -f /tc-f03a-check >/dev/null 2>&1
echo "== ownership and login"
for p in /opt/hadoop /opt/hadoop/bin/hdfs; do
  O="$(stat -c '%U' "$R$p" 2>/dev/null)"; M="$(stat -c '%a' "$R$p" 2>/dev/null)"
  [ "$O" = root ] && [ -n "$M" ] && [ $(( 0$M & 022 )) -eq 0 ] && ok "$p is owned by root and not writable by group or others (mode $M)" || no "$p: owner '$O', mode '$M' (it must be root and not writable by group or others)"
done
SH="$(getent passwd hadoop | cut -d: -f7)"; case "$SH" in */nologin|*/false) ok "the user hadoop cannot log in (shell $SH)" ;; *) no "the user hadoop has a login shell: '$SH'" ;; esac
echo "== what listens"
SS="$(ss -H -lntp 2>/dev/null)"
for p in 9000 9870 9866 9864 9867 8030 8031 8032 8033 8088; do
  A="$(printf '%s\n' "$SS" | awk -v p=":$p" '$4 ~ (p "$") {print $4}' | head -1)"
  if [ -z "$A" ]; then no "nothing listens on port $p"; elif [ "${A%:*}" = 127.0.0.1 ]; then ok "port $p listens on 127.0.0.1"; else no "port $p listens on $A, not on 127.0.0.1"; fi
done
printf '%s\n' "$SS" | grep java | awk '{print $4}' | grep -v '^127\.0\.0\.1:' | sort -u | sed 's/^/   note: java also listens on /; s/$/ (to be bound or closed in step F0.5)/'
echo "   info: failed units: $(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | tr '\n' ' ' | sed 's/ $//' | grep . || echo none)"
echo "== evidence"
printf '%s\n' "$SS" > "$OUT/f03a-boot$N-listeners.txt"; ps -eo user,pid,args 2>/dev/null | grep -E 'java.*(NameNode|DataNode|ResourceManager|NodeManager)' | grep -v grep > "$OUT/f03a-boot$N-processes.txt"; cp "$R/etc/tc/bake-versions.txt" "$OUT/f03a-boot$N-bake-versions.txt" 2>/dev/null
chmod 644 "$OUT"/f03a-boot"$N"-* 2>/dev/null; echo "saved: $OUT/f03a-boot$N-{listeners,processes,bake-versions}.txt"
if [ $bad -eq 0 ]; then echo "F03A-CHECK-OK boot=$N"; else echo "F03A-CHECK-FAILED ($bad) boot=$N"; fi
[ $bad -eq 0 ]
