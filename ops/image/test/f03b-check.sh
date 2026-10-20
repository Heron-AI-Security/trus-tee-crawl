#!/usr/bin/env bash
# Step F0.3b, the check after EACH boot of a VM made from the image that holds the job and the wrapper jar (run as root): the checks of step F0.3a still pass (now with 11 measured events); the baked job and
# the wrapper jar are the recorded ones and are owned by root; the wrapper jar is on Hadoop's classpath, its classes equal the job's, and it loads and initializes (wrapper-jar.sh selftest);
# Hadoop's own Pi example runs on YARN; and a Nutch job from the baked job file (inject) runs on YARN and writes a crawl database to HDFS. Evidence is left in /var/lib/tc.
#   sudo bash f03b-check.sh        (TC_SKIP_JOBS=1 skips the two YARN jobs for a quick re-check)
# Hooks for the rehearsal only: TC_ROOT, TC_STATE, TC_OUT, TC_F03A, TC_WRAPJAR, TC_TIMEOUT, TC_SKIP_JOBS.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
R="${TC_ROOT:-}"; STATE="${TC_STATE:-/var/lib/tc}"; OUT="${TC_OUT:-$STATE}"; F03A="${TC_F03A:-$HERE/f03a-check.sh}"; WJ="${TC_WRAPJAR:-$HERE/../../attested/wrapper-jar.sh}"; JAVA=/usr/lib/jvm/java-11-openjdk-amd64; TJ="${TC_TIMEOUT:-420}"
JOB="$R/opt/tc/nutch/apache-nutch-1.22.job"; JARLIB="$R/opt/hadoop/share/hadoop/common/lib/attested-hdfs.jar"; V="$R/etc/tc/job-versions.txt"
bad=0; ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; bad=$((bad+1)); }
N="$(cat "$STATE/bootcount" 2>/dev/null || echo 0)"
echo "f03b-check: $(date -u +%FT%TZ) on $(hostname), boot number $N"
echo "== the checks of step F0.3a (the measurement, the units, the daemons, HDFS, ownership, ports)"
AOUT="$(bash "$F03A" 2>&1)"; ARC=$?; printf '%s\n' "$AOUT" | grep 'FAIL:' | sed 's/^/      /'
printf '%s\n' "$AOUT" | grep -E '^   (info|note):'   # the measurement time, the failed units and the ports to close later
[ $ARC = 0 ] && printf '%s\n' "$AOUT" | grep -q '^F03A-CHECK-OK' && ok "$(printf '%s\n' "$AOUT" | tail -1)" || no "the checks of step F0.3a did not pass"
echo "== the baked job and jar are the recorded ones, and owned by root"
want() { awk -v k="$1" '$1==k {for(i=1;i<=NF;i++) if($i=="sha256") print $(i+1)}' "$V" 2>/dev/null; }
WJOB="$(want job:)"; HJOB="$(sha256sum "$JOB" 2>/dev/null | cut -d' ' -f1)"
[ -n "$WJOB" ] && [ "$WJOB" = "$HJOB" ] && ok "the installed job equals the recorded one (${HJOB:0:16}...)" || no "the installed job ('${HJOB:0:16}') is not the recorded one ('${WJOB:0:16}')"
WJAR="$(want jar:)"; HJAR="$(sha256sum "$JARLIB" 2>/dev/null | cut -d' ' -f1)"
[ -n "$WJAR" ] && [ "$WJAR" = "$HJAR" ] && ok "the installed wrapper jar equals the recorded one (${HJAR:0:16}...)" || no "the installed wrapper jar ('${HJAR:0:16}') is not the recorded one ('${WJAR:0:16}')"
NREC="$(awk '$1=="jar:" {for(i=1;i<=NF;i++) if($i=="classes") print $(i+1)}' "$V" 2>/dev/null)"
NHAVE="$(python3 -c 'import sys,zipfile; print(len([n for n in zipfile.ZipFile(sys.argv[1]).namelist() if n.endswith(".class")]))' "$JARLIB" 2>/dev/null)"
[ -n "$NREC" ] && [ "$NREC" = "$NHAVE" ] && ok "the jar holds the $NHAVE wrapper classes that were recorded" || no "the jar holds '$NHAVE' classes, the record says '$NREC'"
for p in /opt/tc /opt/tc/nutch /opt/tc/nutch/apache-nutch-1.22.job /opt/tc/nutch/bin/nutch /opt/hadoop/share/hadoop/common/lib/attested-hdfs.jar; do
  O="$(stat -c '%U' "$R$p" 2>/dev/null)"; M="$(stat -c '%a' "$R$p" 2>/dev/null)"
  [ "$O" = root ] && [ -n "$M" ] && [ $(( 0$M & 022 )) -eq 0 ] && ok "$p is owned by root and not writable by group or others (mode $M)" || no "$p: owner '$O', mode '$M' (it must be root and not writable by group or others)"
done
echo "== the wrapper"
VER="$(env JAVA_HOME="$JAVA" HADOOP_HOME="$R/opt/hadoop" bash "$WJ" verify "$JOB" 2>&1)"
{ printf '%s\n' "$VER" | grep -q "entries on Hadoop's classpath: 1" && printf '%s\n' "$VER" | grep -q "CLASSES-SAME"; } && ok "the jar is on Hadoop's classpath and its classes are identical to the job's" || { printf '%s\n' "$VER" | tail -4 | sed 's/^/      /'; no "the wrapper jar is not on the classpath or differs from the job"; }
# the helper may live in the home folder of whoever shipped it, which the user hadoop cannot read: run a copy from /tmp
WJC="$(mktemp /tmp/tc-wrapper-jar.XXXXXX)"; cp "$WJ" "$WJC" && chmod 755 "$WJC"
SELF="$(runuser -u hadoop -- env JAVA_HOME="$JAVA" HADOOP_HOME="$R/opt/hadoop" bash "$WJC" selftest 2>&1)"; rm -f "$WJC"
printf '%s\n' "$SELF" | grep -q "JAR-LOADS-FROM-LIB-OK" && ok "the wrapper loads from the library folder and initializes (wrapper-jar.sh selftest, as hadoop)" || { printf '%s\n' "$SELF" | tail -3 | sed 's/^/      /'; no "the wrapper self-test failed"; }
if [ "${TC_SKIP_JOBS:-0}" = 1 ]; then echo "   info: the two YARN jobs were skipped (TC_SKIP_JOBS=1)"; else
  ENVV=(JAVA_HOME="$JAVA" HADOOP_HOME="$R/opt/hadoop" HADOOP_CONF_DIR="$R/opt/hadoop/etc/hadoop" HADOOP_LOG_DIR=/var/log/hadoop NUTCH_LOG_DIR=/var/log/hadoop PATH="$R/opt/hadoop/bin:/usr/bin:/bin")
  HD() { runuser -u hadoop -- env "${ENVV[@]}" "$R/opt/hadoop/bin/hdfs" "$@"; }
  echo "== Hadoop's own Pi example on YARN"
  EX="$(ls "$R"/opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar 2>/dev/null | head -1)"
  timeout "$TJ" runuser -u hadoop -- env "${ENVV[@]}" "$R/opt/hadoop/bin/hadoop" jar "$EX" pi 2 10 > "$OUT/f03b-boot$N-pi.txt" 2>&1
  PIV="$(grep -o 'Estimated value of Pi is [0-9.]*' "$OUT/f03b-boot$N-pi.txt" | head -1)"
  [ -n "$PIV" ] && ok "Hadoop's Pi example ran on YARN: $PIV" || { tail -5 "$OUT/f03b-boot$N-pi.txt" | sed 's/^/      /'; no "Hadoop's Pi example did not finish"; }
  echo "== a Nutch job from the baked job file (inject) on YARN"
  HD dfs -rm -r -f /tc-f03b >/dev/null 2>&1; HD dfs -mkdir -p /tc-f03b/seeds >/dev/null 2>&1
  printf 'https://books.toscrape.com/\nhttps://quotes.toscrape.com/\n' | HD dfs -put -f - /tc-f03b/seeds/seeds.txt >/dev/null 2>&1
  timeout "$TJ" runuser -u hadoop -- env "${ENVV[@]}" "$R/opt/tc/nutch/bin/nutch" inject /tc-f03b/crawldb /tc-f03b/seeds > "$OUT/f03b-boot$N-inject.txt" 2>&1
  grep -q 'Total new urls injected: 2' "$OUT/f03b-boot$N-inject.txt" && ok "the Nutch job injected the 2 seed urls" || { tail -6 "$OUT/f03b-boot$N-inject.txt" | sed 's/^/      /'; no "the Nutch inject job did not report 2 new urls"; }
  HD dfs -test -d /tc-f03b/crawldb/current && ok "the crawl database exists in HDFS (/tc-f03b/crawldb/current)" || no "no crawl database in HDFS after the inject job"
  HD dfs -rm -r -f /tc-f03b >/dev/null 2>&1
fi
echo "== evidence"
cp "$V" "$OUT/f03b-boot$N-job-versions.txt" 2>/dev/null; chmod 644 "$OUT"/f03b-boot"$N"-* 2>/dev/null; echo "saved: $OUT/f03b-boot$N-{pi,inject,job-versions}.txt"
if [ $bad -eq 0 ]; then echo "F03B-CHECK-OK boot=$N"; else echo "F03B-CHECK-FAILED ($bad) boot=$N"; fi
[ $bad -eq 0 ]
