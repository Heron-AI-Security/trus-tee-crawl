#!/usr/bin/env bash
# Steps F2 and F3 on the MASTER of a formed fleet (run as root after f1-check.sh has passed):  sudo bash f2-check.sh
# The wrapper is active and has no settings; a file written and read with the fleet's keys works, also directly under the root (F3.4); a changed file cannot be
# copied to local disk through the wrapper (F3.5); a file whose record was signed by a valid P-256 key that is NOT in fleet.tsv (an outsider's) is refused on the
# read, also in a fresh YARN container (F2); and the control job on a good file succeeds.   Mode: f2-check.sh [all|outsider]
# The outsider makes /f2e itself: a folder that the fleet's own wrapper made would carry an identity signed by a fleet key, which an outsider (rightly) cannot write into.
set -uo pipefail
bad=0; ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; bad=$((bad+1)); }
MODE="${1:-all}"   # all, or outsider: only the outsider and the fresh YARN container (after a first run passed the rest)
HERE="$(cd "$(dirname "$0")" && pwd)"; CONF=/run/tc/conf; TOOL=/tmp/f2-tool; SRC=/tmp/f2-src; JH=/usr/lib/jvm/java-11-openjdk-amd64
EX="$(ls /opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-*.jar 2>/dev/null | head -1)"
PLAIN=(-D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem)
hx() { local c="$1"; shift; runuser -u hadoop -- env JAVA_HOME=$JH HADOOP_HOME=/opt/hadoop HADOOP_CONF_DIR="$c" HADOOP_LOG_DIR=/var/log/hadoop PATH=$JH/bin:/opt/hadoop/bin:/usr/bin:/bin "$@"; }
echo "f2-check: $(date -u +%FT%TZ) on $(hostname)"
echo "== the wrapped configuration, and no settings"
[ "$(hx $CONF hdfs getconf -confKey fs.hdfs.impl 2>/dev/null)" = org.apache.nutch.attested.AttestedHdfsFileSystem ] && ! grep -q '<name>attested\.' $CONF/core-site.xml && ok "fs.hdfs.impl is the attested file system, and the configuration holds no setting of the wrapper (it has none)" || no "the configuration is not wrapped, or it still has attested.* settings"
if [ "$MODE" = all ]; then
echo "== a file with the fleet's own key"
echo "f2 good file $(date +%s)" > /tmp/f2-good.txt; chmod 644 /tmp/f2-good.txt
hx $CONF hdfs dfs -mkdir -p /f2g >/dev/null 2>&1; hx $CONF hdfs dfs -put -f /tmp/f2-good.txt /f2g/good.txt >/dev/null 2>&1
[ "$(hx $CONF hdfs dfs -cat /f2g/good.txt 2>/dev/null)" = "$(cat /tmp/f2-good.txt)" ] && ok "a file written through the wrapper reads back through the wrapper" || no "the good file does not read back"
NW="$(hx $CONF hdfs dfs -ls -R /f2g 2>/dev/null | grep -c '^[-d]')"; NP="$(hx $CONF hdfs dfs "${PLAIN[@]}" -ls -R /f2g 2>/dev/null | grep -c '^[-d]')"
[ "$NP" -gt "$NW" ] && ok "HDFS itself holds more entries ($NP) than the wrapper shows ($NW): the signed record and the folder identity are there, beside the data" || no "no record files beside the data (plain $NP, wrapped $NW)"
echo "== F3.4: a file directly under the root"
echo "f3 root file $(date +%s)" > /tmp/f2-root.txt; chmod 644 /tmp/f2-root.txt
hx $CONF hdfs dfs -put -f /tmp/f2-root.txt /f2root.txt >/dev/null 2>&1
[ "$(hx $CONF hdfs dfs -cat /f2root.txt 2>/dev/null)" = "$(cat /tmp/f2-root.txt)" ] && hx $CONF hdfs dfs "${PLAIN[@]}" -test -e /.f2root.txt.attested && ok "a file directly under / is bound (the root's fixed id) and reads, and its record is there" || no "a file under the root does not read, or has no record"
echo "== F3.5: a copy to local disk is verified"
sed 's/f2 good/f2 BAD!/' /tmp/f2-good.txt > /tmp/f2-changed.txt; chmod 644 /tmp/f2-changed.txt
hx $CONF hdfs dfs "${PLAIN[@]}" -put -f /tmp/f2-changed.txt /f2g/good.txt >/dev/null 2>&1
rm -f /tmp/f2-get1 /tmp/f2-get2
OUTG="$(hx $CONF hdfs dfs -get /f2g/good.txt /tmp/f2-get1 2>&1)"; RCG=$?
[ $RCG -ne 0 ] && grep -q "Attested verification failed" <<<"$OUTG" && ok "a file changed behind the wrapper's back cannot be copied to local disk through it (get fails: verification failed)" || { no "the changed file was copied (exit $RCG)"; printf '%s\n' "$OUTG" | tail -2 | sed 's/^/      /'; }
hx $CONF hdfs dfs "${PLAIN[@]}" -get /f2g/good.txt /tmp/f2-get2 >/dev/null 2>&1; [ -s /tmp/f2-get2 ] && ok "control: the plain client copies the same changed file without a word, so the refusal above is the wrapper's" || no "the control copy through the plain client failed"
hx $CONF hdfs dfs "${PLAIN[@]}" -put -f /tmp/f2-good.txt /f2g/good.txt >/dev/null 2>&1
[ "$(hx $CONF hdfs dfs -cat /f2g/good.txt 2>/dev/null)" = "$(cat /tmp/f2-good.txt)" ] && ok "with the bytes put back the file reads again" || no "the file does not read after it was put back"
else
  [ -s /tmp/f2-good.txt ] || { echo "f2 good file $(date +%s)" > /tmp/f2-good.txt; chmod 644 /tmp/f2-good.txt; }
  hx $CONF hdfs dfs -test -e /f2g/good.txt 2>/dev/null || { hx $CONF hdfs dfs -mkdir -p /f2g >/dev/null 2>&1; hx $CONF hdfs dfs -put -f /tmp/f2-good.txt /f2g/good.txt >/dev/null 2>&1; }
fi
hx $CONF hdfs dfs -rm -r -f /f2e /f2g/out-evil >/dev/null 2>&1   # a clean start for the outsider part
echo "== an outsider: a valid P-256 key that is in no fleet.tsv"
rm -rf $TOOL $SRC; mkdir -p $TOOL $SRC; cp "$HERE/../../attested/OutsiderWrite.java" $SRC/ 2>/dev/null; chown -R hadoop:hadoop $TOOL $SRC
CP="$(hx $CONF hadoop classpath 2>/dev/null)"
hx $CONF javac -nowarn -cp "$CP" -d $TOOL $SRC/OutsiderWrite.java 2>&1 | tail -3 | sed 's/^/      /'
OUTW="$(hx $CONF java -cp "$TOOL:$CP" org.apache.nutch.attested.OutsiderWrite /f2e/evil.txt /tmp/f2-good.txt 2>&1)"
grep -q "OUTSIDER-WROTE" <<<"$OUTW" && ok "the outsider wrote a file with its own valid key, into a new top-level folder that it made itself: $(grep OUTSIDER-WROTE <<<"$OUTW" | sed 's/OUTSIDER-WROTE //')" || { no "the outsider tool did not write its file"; printf '%s\n' "$OUTW" | grep -E 'Exception|Caused by|OUTSIDER|Attested|not trusted' | head -5 | cut -c1-260 | sed 's/^/      /'; }
OUT1="$(hx $CONF hdfs dfs -cat /f2e/evil.txt 2>&1)"; RC1=$?
[ $RC1 -ne 0 ] && grep -q "not trusted here" <<<"$OUT1" && ok "the read through the fleet's wrapper FAILS: the record is signed by a key that is not trusted here" || { no "the outsider's file was not refused (exit $RC1)"; printf '%s\n' "$OUT1" | tail -3 | sed 's/^/      /'; }
echo "== a fresh YARN container"
[ -f "$EX" ] || no "no examples jar"
OUT2="$(hx $CONF yarn jar "$EX" wordcount /f2e/evil.txt /f2g/out-evil 2>&1)"; RC2=$?   # the output is in a fleet folder, so the job fails on the READ of the input, in its container
CT="$(grep -rl 'not trusted here' /var/log/hadoop/userlogs 2>/dev/null | head -1)"
{ [ $RC2 -ne 0 ] && { grep -q "not trusted here" <<<"$OUT2" || [ -n "$CT" ]; }; } && ok "a MapReduce job (wordcount) that reads the outsider's file FAILS in its container: not trusted here ${CT:+(container log $(dirname "$CT" | sed 's#.*/userlogs/##'))}" || { no "the job on the outsider's file was not refused (exit $RC2)"; printf '%s\n' "$OUT2" | tail -4 | sed 's/^/      /'; }
hx $CONF hdfs dfs -test -e /f2g/out-evil/_SUCCESS 2>/dev/null && no "the job left a _SUCCESS marker" || ok "no _SUCCESS marker for the refused job"
OUTD=/f2g/out-ctl-$(date +%s)
OUT3="$(hx $CONF yarn jar "$EX" wordcount /f2g/good.txt $OUTD 2>&1)"; RC3=$?
[ $RC3 -eq 0 ] && hx $CONF hdfs dfs -test -e $OUTD/_SUCCESS 2>/dev/null && [ -n "$(hx $CONF hdfs dfs -cat "$OUTD/part-r-*" 2>/dev/null)" ] && ok "control: the same job on a good file succeeds, in containers with the same wrapper, writes signed output, and the output reads" || { no "the control job failed (exit $RC3)"; printf '%s\n' "$OUT3" | tail -4 | sed 's/^/      /'; }
if [ $bad -eq 0 ]; then echo "F2-CHECK-OK"; else echo "F2-CHECK-FAILED ($bad)"; fi
[ $bad -eq 0 ]
