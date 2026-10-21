#!/usr/bin/env bash
# Step F4 on the MASTER of a formed fleet (the debug fleet, as root, after f1-check.sh): the tamper demonstrations with a clean control (6.2.1) and the two documented
# limits (6.2.2). "w" is the wrapper (what a reader of the fleet uses), "p" is the plain HDFS client (someone with the HDFS credentials behind the wrapper's back).
# Every attack must be REFUSED by the wrapper with a verification message; the control must read; the two limits must go undetected, as documented.
set -uo pipefail
LASTERR=""
bad=0; ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*${LASTERR:+   [a plain command failed during this attack: $LASTERR]}"; bad=$((bad+1)); }
HERE="$(cd "$(dirname "$0")" && pwd)"; CONF=/run/tc/conf; JH=/usr/lib/jvm/java-11-openjdk-amd64; T=/f4t; S=/tmp/f4; TOOL=/tmp/f4-tool
PLAIN=(-D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem)
hx() { local c="$1"; shift; runuser -u hadoop -- env JAVA_HOME=$JH HADOOP_HOME=/opt/hadoop HADOOP_CONF_DIR="$c" HADOOP_LOG_DIR=/var/log/hadoop PATH=$JH/bin:/opt/hadoop/bin:/usr/bin:/bin "$@"; }
w() { hx $CONF hdfs dfs "$@"; }
# p keeps the first line of the error of every plain command that fails, and no() prints it: a SETUP that failed must never look like an attack that was not refused
p() { local o rc; o="$(hx $CONF hdfs dfs "${PLAIN[@]}" "$@" 2>&1)"; rc=$?; [ $rc -ne 0 ] && LASTERR="$LASTERR [p $*: $(printf '%s' "$o" | head -1 | cut -c1-110)]"; printf '%s\n' "$o"; return $rc; }
sha_of() { w -cat "$1" 2>/dev/null | sha256sum | cut -c1-16; }
REFUSAL=""
refused() { local out rc; out="$(w -cat "$1" 2>&1 >/dev/null)"; rc=$?; REFUSAL="$(printf '%s\n' "$out" | grep -m1 -E 'Attested verification failed|no record|no identity|not trusted|record is damaged' | cut -c1-210)"; [ $rc -ne 0 ] && [ -n "$REFUSAL" ]; }
echo "f4-attacks: $(date -u +%FT%TZ) on $(hostname)"
t=0; until w -ls / >/dev/null 2>&1; do t=$((t+5)); [ $t -lt 300 ] || { echo "   FAIL: HDFS did not answer within 5 minutes"; exit 1; }; sleep 5; done
rm -rf $S; mkdir -p $S/rec $S/id; for n in a b a2 b2 v2; do head -c 200000 /dev/urandom > $S/$n.bin; done; chown -R hadoop:hadoop $S; chmod -R a+rX $S
LA=$(sha256sum $S/a.bin | cut -c1-16); LB=$(sha256sum $S/b.bin | cut -c1-16); LA2=$(sha256sum $S/a2.bin | cut -c1-16); LB2=$(sha256sum $S/b2.bin | cut -c1-16)
p -rm -r -f $T /f4o >/dev/null 2>&1
w -mkdir -p $T/a $T/b >/dev/null 2>&1
LASTERR=""
w -put -f $S/a.bin $T/a/good.bin >/dev/null 2>&1; w -put -f $S/b.bin $T/b/other.bin >/dev/null 2>&1; w -put -f $S/a2.bin $T/a/same.bin >/dev/null 2>&1; w -put -f $S/b2.bin $T/b/same.bin >/dev/null 2>&1
for f in a/good.bin b/other.bin a/same.bin b/same.bin; do p -get "$T/$(dirname $f)/.$(basename $f).attested" "$S/rec/$(echo $f | tr / _)" >/dev/null 2>&1; done
p -get $T/a/_attested-folder $S/id/a >/dev/null 2>&1; p -get $T/b/_attested-folder $S/id/b >/dev/null 2>&1
restore() {
  p -rm -r -f $T/a-copy $T/b/moved.bin $T/b/.moved.bin.attested $T/a/unsigned.bin >/dev/null 2>&1
  p -put -f $S/a.bin $T/a/good.bin >/dev/null 2>&1; p -put -f $S/rec/a_good.bin $T/a/.good.bin.attested >/dev/null 2>&1
  p -put -f $S/b.bin $T/b/other.bin >/dev/null 2>&1; p -put -f $S/rec/b_other.bin $T/b/.other.bin.attested >/dev/null 2>&1
  p -put -f $S/a2.bin $T/a/same.bin >/dev/null 2>&1; p -put -f $S/rec/a_same.bin $T/a/.same.bin.attested >/dev/null 2>&1
  p -put -f $S/b2.bin $T/b/same.bin >/dev/null 2>&1; p -put -f $S/rec/b_same.bin $T/b/.same.bin.attested >/dev/null 2>&1
  p -put -f $S/id/a $T/a/_attested-folder >/dev/null 2>&1; p -put -f $S/id/b $T/b/_attested-folder >/dev/null 2>&1
  LASTERR=""
}
undone() { [ "$(sha_of $T/a/good.bin)" = "$LA" ] && [ "$(sha_of $T/b/same.bin)" = "$LB2" ] && [ "$(sha_of $T/a/same.bin)" = "$LA2" ] && ok "undone: the files read again" || no "undone: the files do not read again after '$1'"; }
echo "== the clean control: four untouched files read through the wrapper"
[ "$(sha_of $T/a/good.bin)" = "$LA" ] && [ "$(sha_of $T/b/other.bin)" = "$LB" ] && [ "$(sha_of $T/a/same.bin)" = "$LA2" ] && [ "$(sha_of $T/b/same.bin)" = "$LB2" ] && ok "control: all four files read back byte for byte" || no "control: an untouched file does not read"
echo "== 6.2.1 the tamper demonstrations (each must be refused)"
python3 -c "d=bytearray(open('$S/a.bin','rb').read()); d[3*16384+5]^=1; open('$S/a-flip.bin','wb').write(d)"; chown hadoop:hadoop $S/a-flip.bin; chmod a+r $S/a-flip.bin
p -put -f $S/a-flip.bin $T/a/good.bin >/dev/null 2>&1
if refused $T/a/good.bin && grep -q 'chunk 3' <<<"$REFUSAL"; then ok "A1 a byte flipped in chunk 3: refused at that chunk ($REFUSAL)"; else no "A1 a flipped byte was not refused at its chunk: $REFUSAL"; fi
restore; undone "A1"
p -cp -f $T/b/other.bin $T/a/good.bin >/dev/null 2>&1; p -cp -f $T/b/.other.bin.attested $T/a/.good.bin.attested >/dev/null 2>&1
if refused $T/a/good.bin; then ok "A2 a file and its record replaced by another file's file and record: refused ($REFUSAL)"; else no "A2 a replaced file and record were not refused"; fi
restore; undone "A2"
p -mv $T/a/good.bin $T/b/moved.bin >/dev/null 2>&1; p -mv $T/a/.good.bin.attested $T/b/.moved.bin.attested >/dev/null 2>&1
if refused $T/b/moved.bin; then ok "A3 a signed file and its record moved to another folder: refused ($REFUSAL)"; else no "A3 a moved file was not refused"; fi
restore; undone "A3"
p -put -f $S/b2.bin $T/a/same.bin >/dev/null 2>&1; p -put -f $S/rec/b_same.bin $T/a/.same.bin.attested >/dev/null 2>&1; p -put -f $S/a2.bin $T/b/same.bin >/dev/null 2>&1; p -put -f $S/rec/a_same.bin $T/b/.same.bin.attested >/dev/null 2>&1
if refused $T/a/same.bin && refused $T/b/same.bin; then ok "A3b two files of the same name swapped between two folders (with their records): both refused ($REFUSAL)"; else no "A3b a swapped file was not refused"; fi
restore; undone "A3b"
p -cp $T/a $T/a-copy >/dev/null 2>&1   # cp has no -r: a folder is copied as a whole (the first fleet run used -r, which copies nothing: "Illegal option -r")
p -test -e $T/a-copy/good.bin && p -test -e $T/a-copy/_attested-folder || no "A4 setup: the copy of the folder (with its identity) was not made"
if refused $T/a-copy/good.bin; then ok "A4 a whole folder copied elsewhere (identity and records included): its files refused ($REFUSAL)"; else no "A4 a copied folder was not refused"; fi
restore; undone "A4"
p -put -f $S/a.bin $T/a/unsigned.bin >/dev/null 2>&1
if refused $T/a/unsigned.bin && grep -q 'no record' <<<"$REFUSAL"; then ok "A5 an unsigned file added (no record): refused ($REFUSAL)"; else no "A5 an unsigned file was not refused: $REFUSAL"; fi
restore
rm -rf /tmp/f4-src $TOOL; mkdir -p /tmp/f4-src $TOOL; cp "$HERE/../../attested/OutsiderWrite.java" /tmp/f4-src/; chown -R hadoop:hadoop /tmp/f4-src $TOOL
CP="$(hx $CONF hadoop classpath 2>/dev/null)"; hx $CONF javac -nowarn -cp "$CP" -d $TOOL /tmp/f4-src/OutsiderWrite.java 2>&1 | tail -3 | sed 's/^/      /'
hx $CONF java -cp "$TOOL:$CP" org.apache.nutch.attested.OutsiderWrite /f4o/evil.bin $S/a.bin >/dev/null 2>&1
if refused /f4o/evil.bin && grep -q 'not trusted' <<<"$REFUSAL"; then ok "A6 a record signed with a valid key that is not attested (in no fleet.tsv): refused ($REFUSAL)"; else no "A6 an outsider's file was not refused: $REFUSAL"; fi
p -rm $T/a/.good.bin.attested >/dev/null 2>&1
if refused $T/a/good.bin && grep -q 'no record' <<<"$REFUSAL"; then ok "A7 the record deleted: refused ($REFUSAL)"; else no "A7 a file without its record was not refused"; fi
restore; undone "A7"
p -rm $T/a/_attested-folder >/dev/null 2>&1
if refused $T/a/good.bin && grep -q 'no identity' <<<"$REFUSAL"; then ok "A8 the folder's identity deleted: refused ($REFUSAL)"; else no "A8 a file in a folder without identity was not refused: $REFUSAL"; fi
restore; undone "A8"
p -appendToFile $S/b.bin $T/a/good.bin >/dev/null 2>&1
if refused $T/a/good.bin && grep -q 'length' <<<"$REFUSAL"; then ok "A9 bytes appended behind the wrapper's back: refused ($REFUSAL)"; else no "A9 an extended file was not refused: $REFUSAL"; fi
restore; undone "A9"
w -mkdir -p $T/outer/inner $T/other >/dev/null 2>&1; w -put -f $S/a.bin $T/outer/inner/f.bin >/dev/null 2>&1; LASTERR=""
p -mv $T/outer/inner $T/other/inner >/dev/null 2>&1
if refused $T/other/inner/f.bin && grep -q 'another parent' <<<"$REFUSAL"; then ok "A10 a folder moved with the plain client (to another parent): its files are refused ($REFUSAL)"; else no "A10 a folder moved with the plain client was not refused: $REFUSAL"; fi
OUTR="$(w -mv $T/other/inner $T/other/inner2 2>&1)"; RCR=$?
if [ $RCR -ne 0 ] && grep -q 'Attested rename refused' <<<"$OUTR" && ! w -test -e $T/other/inner2 2>/dev/null; then ok "A10b the wrapper's own rename of that folder is REFUSED too, so it does not bless the move ($(grep -m1 'Attested rename refused' <<<"$OUTR" | cut -c1-170))"; else no "A10b the wrapper renamed a folder that had been moved behind its back: $OUTR"; fi
p -rm -r -f $T/outer $T/other >/dev/null 2>&1; LASTERR=""
echo "== 6.2.2 the two documented limits (both must go UNDETECTED, as documented)"
p -rm $T/a/good.bin >/dev/null 2>&1; p -rm $T/a/.good.bin.attested >/dev/null 2>&1
OUTL="$(w -cat $T/a/good.bin 2>&1 >/dev/null)"; RCL=$?
if [ $RCL -ne 0 ] && grep -q 'No such file' <<<"$OUTL" && ! grep -q 'Attested' <<<"$OUTL"; then ok "L1 a file deleted together with its record: UNDETECTED, as documented (the answer is simply: no such file)"; else no "L1 behaved differently from the documented limit: $OUTL"; fi
restore
w -put -f $S/v2.bin $T/a/good.bin >/dev/null 2>&1
[ "$(sha_of $T/a/good.bin)" = "$(sha256sum $S/v2.bin | cut -c1-16)" ] || no "L2 the new version does not read"
p -put -f $S/a.bin $T/a/good.bin >/dev/null 2>&1; p -put -f $S/rec/a_good.bin $T/a/.good.bin.attested >/dev/null 2>&1
if [ "$(sha_of $T/a/good.bin)" = "$LA" ]; then ok "L2 an older signed copy put back (the old file and its old record, both genuine): UNDETECTED, as documented (the wrapper returns the old version)"; else no "L2 the rollback was detected or failed, unlike the documented limit"; fi
restore
p -rm -r -f $T /f4o >/dev/null 2>&1
if [ $bad -eq 0 ]; then echo "F4-ATTACKS-OK"; else echo "F4-ATTACKS-FAILED ($bad)"; fi
[ $bad -eq 0 ]
