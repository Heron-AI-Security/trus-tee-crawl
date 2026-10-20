#!/usr/bin/env bash
# Step F0.3c, the check after EACH boot of a VM made from the image with the baked crawl (run as root). On the FIRST boot nobody has run any crawl command: the check only waits for the crawl that
# systemd started by itself, and then reads what it left. It checks that the unit started after the measurement and after the four daemons, ended with `success`, left its marker, and that HDFS holds
# a crawl database with at least the required number of fetched urls and at least one segment. On a later boot the unit is skipped (the marker exists), which is also checked. After that the checks
# of F0.3b (and F0.3a) run, including the Pi example and a Nutch inject job. Evidence is left in /var/lib/tc.
#   sudo bash f03c-check.sh
# Hooks for the rehearsal only: TC_ROOT, TC_STATE, TC_OUT, TC_F03B, TC_CRAWL_WAIT, TC_POLL, TC_BEAT, TC_MARK.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="${TC_ROOT:-}"; STATE="${TC_STATE:-/var/lib/tc}"; OUT="${TC_OUT:-$STATE}"; F03B="${TC_F03B:-$HERE/f03b-check.sh}"; WAIT="${TC_CRAWL_WAIT:-1500}"; POLL="${TC_POLL:-10}"; BEAT="${TC_BEAT:-60}"; MARK="${TC_MARK:-$R/var/lib/tc-crawl/done}"
JAVA=/usr/lib/jvm/java-11-openjdk-amd64; NUTCH="$R/opt/tc/nutch/bin/nutch"
bad=0; ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; bad=$((bad+1)); }
N="$(cat "$STATE/bootcount" 2>/dev/null || echo 0)"
ENVV=(JAVA_HOME="$JAVA" HADOOP_HOME="$R/opt/hadoop" HADOOP_CONF_DIR="$R/opt/hadoop/etc/hadoop" HADOOP_LOG_DIR=/var/log/hadoop NUTCH_LOG_DIR=/var/log/hadoop PATH="$R/opt/hadoop/bin:/usr/bin:/bin")
HD() { runuser -u hadoop -- env "${ENVV[@]}" "$R/opt/hadoop/bin/hdfs" "$@"; }
sd() { systemctl show "$1" -p "$2" --value 2>/dev/null; }
echo "f03c-check: $(date -u +%FT%TZ) on $(hostname), boot number $N"
echo "== the crawl that systemd started by itself (nobody ran a crawl command)"
t=0; while :; do st="$(sd tc-crawl.service ActiveState)"; { [ "$st" = activating ] || [ "$st" = active ]; } || break; t=$((t+POLL)); [ $t -lt "$WAIT" ] || break; [ $(( t % BEAT )) -eq 0 ] && echo "   still waiting for the crawl that systemd started ($t s, state $st)"; sleep "$POLL"; done
ST="$(sd tc-crawl.service ActiveState)"; COND="$(sd tc-crawl.service ConditionResult)"; RES="$(sd tc-crawl.service Result)"
if [ "$ST" = activating ] || [ "$ST" = active ]; then no "the crawl was still running after $t s"
elif [ "$COND" = no ]; then
  [ -s "$MARK" ] && ok "the unit was skipped because the crawl was done on an earlier boot (marker: $(head -c 120 "$MARK"))" || no "the unit was skipped, but there is no marker file"
else
  [ "$RES" = success ] && ok "tc-crawl.service ended with the result success (after about $t s of waiting)" || no "tc-crawl.service ended with the result '$RES' (state '$ST')"
  CS="$(sd tc-crawl.service ExecMainStartTimestampMonotonic)"; ME="$(sd tc-measure.service ExecMainExitTimestampMonotonic)"; LATEST=0
  for u in tc-namenode tc-datanode tc-resourcemanager tc-nodemanager; do x="$(sd $u.service ExecMainStartTimestampMonotonic)"; [[ "$x" =~ ^[0-9]+$ ]] && [ "$x" -gt "$LATEST" ] && LATEST="$x"; done
  if [[ "$CS" =~ ^[0-9]+$ && "$ME" =~ ^[0-9]+$ && "$CS" -gt "$ME" && "$CS" -ge "$LATEST" ]]; then ok "the crawl started after the measurement finished and after the four daemons had started"; else no "the crawl did not start after the measurement and the daemons (start '$CS', measurement end '$ME', last daemon '$LATEST')"; fi
  [ -s "$MARK" ] && ok "the marker exists: $(head -c 140 "$MARK")" || no "no marker file at $MARK"
  MIN="$(awk -F= '$1=="MIN_FETCHED" {print $2}' "$R/etc/tc/crawl/params.env" 2>/dev/null)"; CDIR="$(awk -F= '$1=="HDFS_CRAWL_DIR" {print $2}' "$R/etc/tc/crawl/params.env" 2>/dev/null)"; MIN="${MIN:-2}"; CDIR="${CDIR:-/tc/crawl}"
  HD dfs -test -d "$CDIR/crawldb/current" && ok "the crawl database exists in HDFS ($CDIR/crawldb/current)" || no "no crawl database in HDFS at $CDIR/crawldb/current"
  STATS="$(runuser -u hadoop -- env "${ENVV[@]}" "$NUTCH" readdb "$CDIR/crawldb" -stats 2>&1)"; printf '%s\n' "$STATS" > "$OUT/f03c-boot$N-readdb.txt"
  FETCHED="$(printf '%s\n' "$STATS" | grep -E 'db_fetched' | grep -o '[0-9][0-9]*$' | head -1)"; FETCHED="${FETCHED:-0}"; TOTAL="$(printf '%s\n' "$STATS" | grep -iE 'TOTAL urls' | grep -o '[0-9][0-9]*$' | head -1)"
  [ "$FETCHED" -ge "$MIN" ] && ok "the crawl database holds $FETCHED fetched urls (at least $MIN are required; $TOTAL urls in all)" || no "only $FETCHED urls are db_fetched (at least $MIN are required)"
  SEGS="$(HD dfs -ls "$CDIR/segments" 2>/dev/null | grep -c "$CDIR/segments/")"; [ "$SEGS" -ge 1 ] && ok "$SEGS segments were written" || no "no segment under $CDIR/segments"
  cp "$R/var/log/hadoop/tc-crawl.log" "$OUT/f03c-boot$N-crawl.log" 2>/dev/null && ok "the crawl's own log is saved as evidence ($(wc -l < "$OUT/f03c-boot$N-crawl.log") lines)" || no "no crawl log at /var/log/hadoop/tc-crawl.log"
fi
echo "== the checks of step F0.3b (the job, the wrapper, Pi, inject) and of F0.3a"
BOUT="$(bash "$F03B" 2>&1)"; BRC=$?; printf '%s\n' "$BOUT" | grep -E 'FAIL:|^   (info|note):' | sed 's/^/   /;s/^      //'
[ $BRC = 0 ] && printf '%s\n' "$BOUT" | grep -q '^F03B-CHECK-OK' && ok "$(printf '%s\n' "$BOUT" | tail -1)" || no "the checks of step F0.3b did not pass"
chmod 644 "$OUT"/f03c-boot"$N"-* 2>/dev/null
if [ $bad -eq 0 ]; then echo "F03C-CHECK-OK boot=$N"; else echo "F03C-CHECK-FAILED ($bad) boot=$N"; fi
[ $bad -eq 0 ]
