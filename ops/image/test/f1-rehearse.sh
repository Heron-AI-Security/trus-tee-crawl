#!/usr/bin/env bash
# Rehearsal of step F1 with stand-ins: TWO nodes run the REAL tc-fleet.sh (master and worker) with the REAL tc-extend.sh, hadoop_conf.py, openssl and base64, against a fake register that extends like the hardware, a fake
# metadata server (curl), wg, ip and quote helper; the operator side (f1-fleet.py) then verifies THEIR announcements, builds fleet.tsv from them and verifies their final quotes. The bake script and the unit files are
# tested too. Every check that matters is also made to FAIL on purpose.      bash f1-rehearse.sh KITDIR
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; echo "${out:-}" | grep -v "^      " | tail -5 | sed "s/^/        | /"; fi; }
W="$(mktemp -d)"; STUB="$W/bin"; mkdir -p "$STUB" "$W/lib"
cp "$I"/rootfs/usr/local/lib/tc/tc-extend.sh "$KIT/attest/measure/treehash.sh" "$KIT/ops/rebuild/hadoop_conf.py" "$W/lib/"; chmod +x "$W/lib"/*
cat > "$W/fakewrite.py" <<'PYEOF'
import hashlib, sys
p = sys.argv[1]; d = sys.stdin.buffer.read(); cur = open(p, "rb").read(); open(p, "wb").write(hashlib.sha384(cur + d).digest())
PYEOF
cat > "$W/quote.py" <<'PYEOF'
import hashlib, sys
inp, out, reg = sys.argv[1:4]; q = bytearray(8000); q[520:568] = open(reg, "rb").read(); q[568:632] = hashlib.sha512(open(inp, "rb").read()).digest(); open(out, "wb").write(q)
PYEOF
cat > "$STUB/curl" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; put=0; file=""; url="${@: -1}"
for a in "$@"; do case "$a" in PUT) put=1 ;; @*) file="${a#@}" ;; esac; done
if [ $put = 1 ]; then cp "$file" "$SD/put.$(basename "$url")"; exit 0; fi
case "$url" in */instance/name) echo "$FAKE_NAME" ;; */instance/attributes/tc-fleet) [ -s "$SD/fleet" ] && cat "$SD/fleet" || exit 22 ;; *) exit 22 ;; esac
EOS
printf '#!/usr/bin/env bash\necho "hostnamectl $*" >> "${FAKE_SD}/hostname.log"\n' > "$STUB/hostnamectl"
cat > "$STUB/getent" <<'EOS'
#!/usr/bin/env bash
[ -n "${FAKE_NOHOST:-}" ] && exit 2; echo "127.0.0.1 $2"
EOS
cat > "$STUB/wg" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"
case "$1" in genkey) python3 -c 'import os,base64; print(base64.b64encode(os.urandom(32)).decode())' ;; pubkey) python3 -c 'import sys,base64,hashlib; print(base64.b64encode(hashlib.sha256(sys.stdin.buffer.read()).digest()).decode())' ;; *) echo "wg $*" >> "$SD/net.log" ;; esac
EOS
printf '#!/usr/bin/env bash\necho "ip $*" >> "${FAKE_SD:?}/net.log"\n' > "$STUB/ip"
printf '#!/usr/bin/env bash\nexec python3 "%s" "$1" "$2" "${FAKE_REG:?}"\n' "$W/quote.py" > "$W/quote.sh"
chmod +x "$STUB"/* "$W/quote.sh"; export PATH="$STUB:$PATH"
# ---------------------------------------------------------------- a node: its fake machine, and a runner
mknode() { local n="$W/$1"; rm -rf "$n"; mkdir -p "$n/run" "$n/sd" "$n/root/opt/hadoop/etc/hadoop" "$n/root/etc/tc"; cp -r "$I/rootfs/etc/tc/fleet-props" "$n/root/etc/tc/"; echo "<configuration/>" > "$n/root/opt/hadoop/etc/hadoop/core-site.xml"; echo "x" > "$n/root/opt/hadoop/etc/hadoop/log4j.properties"
  head -c 48 /dev/zero > "$n/rtmr3.bin"; echo a > "$n/f1"; echo b > "$n/f2"
  for e in "tc-lib f1" "tc-conf f2" "nutch-deploy f1"; do set -- $e; env TC_LOG="$n/run/rtmr3-events.tsv" TC_RTMR3="$n/rtmr3.bin" TC_WRITE="python3 $W/fakewrite.py $n/rtmr3.bin" bash "$W/lib/tc-extend.sh" "$1" "$n/$2" >/dev/null; done; date > "$n/run/measure-done"; }
nodeenv() { local n="$W/$1"; echo "TC_ROOT=$n/root TC_RUN=$n/run TC_LIB=$W/lib TC_META=http://meta TC_QUOTE=$W/quote.sh TC_POLL=1 TC_FLEET_WAIT=${FWAIT:-30} FAKE_SD=$n/sd FAKE_NAME=$2 FAKE_REG=$n/rtmr3.bin TC_RTMR3=$n/rtmr3.bin TC_WRITE=python3\ $W/fakewrite.py\ $n/rtmr3.bin"; }
startnode() { local n="$W/$1"; ( env TC_ROOT="$n/root" TC_RUN="$n/run" TC_LIB="$W/lib" TC_META=http://meta TC_QUOTE="$W/quote.sh" TC_POLL=1 TC_FLEET_WAIT="${FWAIT:-30}" FAKE_SD="$n/sd" FAKE_NAME="$2" FAKE_REG="$n/rtmr3.bin" TC_RTMR3="$n/rtmr3.bin" TC_WRITE="python3 $W/fakewrite.py $n/rtmr3.bin" bash "$I/rootfs/usr/local/lib/tc/tc-fleet.sh" > "$n/out.txt" 2>&1; echo $? > "$n/rc" ) & }
waitfile() { for _ in $(seq 1 60); do [ -s "$1" ] && return 0; sleep 0.5; done; return 1; }
attrval() { grep "^$2=" "$W/$1/sd/put.announce" | cut -d= -f2-; }
# ---------------------------------------------------------------- A. two nodes form a fleet, the operator side verifies them
echo "=== A. a fleet of two, end to end (the real node script and the real operator script)"
OUT="$W/opout"; rm -rf "$OUT"; mkdir -p "$OUT"; mknode m; mknode w; startnode m tc-f1-m; startnode w tc-f1-w
waitfile "$W/m/sd/put.announce"; waitfile "$W/w/sd/put.announce"
cp "$W/m/sd/put.announce" "$OUT/announce-tc-f1-m.txt"; cp "$W/w/sd/put.announce" "$OUT/announce-tc-f1-w.txt"
out="$(python3 "$I/test/f1-fleet.py" build "$OUT" tc-f1-m 10.128.0.2 tc-f1-w 10.128.0.3 2>&1)"; rcb=$?
chk "the operator accepts both announcements: each quote binds the name, both public keys and the log, and each log replays to its quote" $([ $rcb = 0 ] && grep -q 'ANNOUNCEMENTS-VERIFIED' <<<"$out"; echo $?)
cp "$OUT/fleet.tsv" "$W/m/sd/fleet"; cp "$OUT/fleet.tsv" "$W/w/sd/fleet"; wait
chk "both nodes join the fleet and exit 0" $([ "$(cat $W/m/rc)" = 0 ] && [ "$(cat $W/w/rc)" = 0 ] && grep -q 'fleet joined: tc-f1-m is the master at 10.10.0.1' "$W/m/out.txt" && grep -q 'fleet joined: tc-f1-w is the worker at 10.10.0.2' "$W/w/out.txt"; echo $?)
cp "$W/m/sd/put.final" "$OUT/final-tc-f1-m.txt"; cp "$W/w/sd/put.final" "$OUT/final-tc-f1-w.txt"
out="$(python3 "$I/test/f1-fleet.py" final "$OUT" tc-f1-m tc-f1-w 2>&1)"; chk "the operator verifies both final quotes: the same fleet event (the SHA-384 of fleet.tsv) in both logs, then fleet-conf last" $([ $? = 0 ] && grep -q 'FLEET-DIGEST-EQUAL' <<<"$out"; echo $?)
chk "each node got the role file the units test, and the number of workers" $([ -f "$W/m/run/role-master" ] && [ ! -f "$W/m/run/role-worker" ] && [ -f "$W/w/run/role-worker" ] && [ "$(cat $W/m/run/workers)" = 1 ]; echo $?)
chk "each node configured wg0 with the OTHER node as its only peer, at the address from fleet.tsv" $(grep -q "^ip addr add 10.10.0.1/24 dev wg0" "$W/m/sd/net.log" && grep -q "peer $(attrval w wg) allowed-ips 10.10.0.2/32 endpoint 10.128.0.3:51820" "$W/m/sd/net.log" && ! grep -q "peer $(attrval m wg)" "$W/m/sd/net.log" && grep -q "peer $(attrval m wg) allowed-ips 10.10.0.1/32" "$W/w/sd/net.log"; echo $?)
chk "the Hadoop configuration is rendered into memory from fleet.tsv: the master's address everywhere, each node bound to its own wg0 address, WebHDFS off, one replica for one worker" $(grep -q 'hdfs://10.10.0.1:9000' "$W/m/run/conf/core-site.xml" && grep -q '<value>10.10.0.1:9870</value>' "$W/m/run/conf/hdfs-site.xml" && grep -q '<value>10.10.0.2:9866</value>' "$W/w/run/conf/hdfs-site.xml" && grep -q 'hdfs://10.10.0.1:9000' "$W/w/run/conf/core-site.xml" && grep -A1 'dfs.webhdfs.enabled' "$W/m/run/conf/hdfs-site.xml" | grep -q false && grep -A1 'dfs.replication' "$W/m/run/conf/hdfs-site.xml" | grep -q '<value>1</value>' && [ -f "$W/m/run/conf/log4j.properties" ]; echo $?)
chk "the two private keys are different per node and per boot, and are not readable by others" $([ "$(attrval m sign)" != "$(attrval w sign)" ] && [ "$(attrval m wg)" != "$(attrval w wg)" ] && [ "$(stat -c %a $W/m/run/sign.key)" -le 640 ] && [ "$(stat -c %a $W/m/run/wg.key)" = 600 ]; echo $?)
# the operator side refuses tampered announcements and a changed fleet list
cp "$OUT/announce-tc-f1-m.txt" "$W/ann.keep"; sed -i 's/^sign=\(.\)/sign=A\1/' "$OUT/announce-tc-f1-m.txt"; out="$(python3 "$I/test/f1-fleet.py" build "$OUT" tc-f1-m 10.128.0.2 tc-f1-w 10.128.0.3 2>&1)"; chk "fault: an announcement whose public key was changed is refused (the quote no longer binds it)" $([ $? != 0 ] && grep -q "REPORTDATA is not the SHA-512 of its binding" <<<"$out"; echo $?); cp "$W/ann.keep" "$OUT/announce-tc-f1-m.txt"
python3 - "$OUT/announce-tc-f1-w.txt" <<'PYEOF'
import base64, sys
p = sys.argv[1]; L = open(p).read().splitlines(); out = []
for l in L:
    if l.startswith("log_b64="):
        log = base64.b64decode(l[8:]).decode().splitlines(); f = log[0].split("\t"); f[1] = "00" * 48; log[0] = "\t".join(f); l = "log_b64=" + base64.b64encode(("\n".join(log) + "\n").encode()).decode()
    out.append(l)
open(p, "w").write("\n".join(out) + "\n")
PYEOF
out="$(python3 "$I/test/f1-fleet.py" build "$OUT" tc-f1-m 10.128.0.2 tc-f1-w 10.128.0.3 2>&1)"; chk "fault: a log that was changed after the quote is refused" $([ $? != 0 ] && grep -q "STOP" <<<"$out"; echo $?)
cp "$W/w/sd/put.announce" "$OUT/announce-tc-f1-w.txt"; echo "# tc-fleet v1" > "$OUT/fleet.tsv"; echo "tampered" >> "$OUT/fleet.tsv"; out="$(python3 "$I/test/f1-fleet.py" final "$OUT" tc-f1-m tc-f1-w 2>&1)"; chk "fault: a fleet list that differs from the one the nodes measured is refused" $([ $? != 0 ] && grep -q "not the SHA-384 of fleet.tsv" <<<"$out"; echo $?)
# ---------------------------------------------------------------- B. faults of the node script
echo "=== A2. F4: two nodes given DIFFERENT fleet lists, the self-report check, and the comparison of two images"
OUT2="$W/opout2"; rm -rf "$OUT2"; mkdir -p "$OUT2"; mknode m2; mknode w2; startnode m2 tc-f1-m; startnode w2 tc-f1-w
waitfile "$W/m2/sd/put.announce"; waitfile "$W/w2/sd/put.announce"; cp "$W/m2/sd/put.announce" "$OUT2/announce-tc-f1-m.txt"; cp "$W/w2/sd/put.announce" "$OUT2/announce-tc-f1-w.txt"
out="$(python3 "$I/test/f1-fleet.py" build-mismatch "$OUT2" tc-f1-m 10.128.0.2 tc-f1-w 10.128.0.3 2>&1)"; rcm=$?
chk "two different lists are written: the master's with 2 nodes, the worker's with 3 (the third does not exist), each holding the node's own keys" $([ $rcm = 0 ] && grep -q 'MISMATCH-LISTS-WRITTEN' <<<"$out" && [ "$(grep -vc '^#' $OUT2/fleet.tsv)" = 2 ] && [ "$(grep -vc '^#' $OUT2/fleet-w.tsv)" = 3 ]; echo $?)
cp "$OUT2/fleet.tsv" "$W/m2/sd/fleet"; cp "$OUT2/fleet-w.tsv" "$W/w2/sd/fleet"; wait
chk "both nodes JOIN although their lists differ (each list holds the node's own keys), and exit 0" $([ "$(cat $W/m2/rc)" = 0 ] && [ "$(cat $W/w2/rc)" = 0 ]; echo $?)
cp "$W/m2/sd/put.final" "$OUT2/final-tc-f1-m.txt"; cp "$W/w2/sd/put.final" "$OUT2/final-tc-f1-w.txt"
out="$(python3 "$I/test/f1-fleet.py" final-mismatch "$OUT2" tc-f1-m tc-f1-w 2>&1)"; chk "the RTMR3 logs show the mismatch: different fleet events and different final registers (FLEET-LISTS-DIFFER)" $([ $? = 0 ] && grep -q 'FLEET-LISTS-DIFFER' <<<"$out"; echo $?)
rm -rf "$W/opout3"; cp -r "$OUT" "$W/opout3"; cp "$W/m/sd/fleet" "$W/opout3/fleet.tsv"; cp "$W/m/sd/fleet" "$W/opout3/fleet-w.tsv";   # the real list that node m was given (scenario A overwrote $OUT/fleet.tsv for a fault test)
 out="$(python3 "$I/test/f1-fleet.py" final-mismatch "$W/opout3" tc-f1-m tc-f1-w 2>&1)"; chk "fault: two nodes that were given the SAME list do not look mismatched, and the check says so" $([ $? != 0 ] && grep -q 'mismatch was not visible' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" images "$OUT" "$OUT2" tc-f1-m fleet 2>&1)"; chk "two images: the final registers differ and the named event differs (IMAGES-DIFFER)" $([ $? = 0 ] && grep -q 'IMAGES-DIFFER' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" images "$OUT" "$OUT2" tc-f1-m tc-conf 2>&1)"; chk "fault: an event that did not change is not accepted as a difference between two images" $([ $? != 0 ] && grep -q 'must differ' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" images "$OUT" "$OUT" tc-f1-m 2>&1)"; chk "fault: one image against itself is refused (equal registers)" $([ $? != 0 ] && grep -q 'not told apart' <<<"$out"; echo $?)
FS="$(sha384sum $OUT/fleet.tsv | cut -d' ' -f1)"
mkrep() { # name role kind: a report that says what that kind of image must say
  { echo "name=$1"; echo "hostname=${HOSTFAKE:-$1}"; echo "image=tc-img-test-1"; echo "mode=$3"; echo "input_policy=policy drop"; echo "nft_rules_sha=0123456789abcdef"; echo "failed_units="; echo "unit_tc-measure=active/success"; echo "unit_tc-fleet=active/success"; echo "fleet_done=2026-10-21T00:00:00Z"; echo "fleet_event=$FS"; echo "wg_peers=1"
    if [ "$3" = locked ]; then echo "openssh_server_installed=no"; echo "guest_agent_installed=no"; echo "oslogin_installed=no"; echo "port22_listening=0"; echo "serial_getty=masked"; else echo "openssh_server_installed=yes"; echo "port22_listening=1"; echo "serial_getty=enabled"; fi
    if [ "$2" = master ]; then echo "unit_tc-namenode=active/success"; echo "unit_tc-resourcemanager=active/success"; echo "crawl_marker=crawl done 2026-10-21T00:00:00Z fetched=8 segments=3"; else echo "unit_tc-datanode=active/success"; echo "unit_tc-nodemanager=active/success"; fi; } > "$W/rep/report-$1.txt"; }
rm -rf "$W/rep"; mkdir -p "$W/rep"; cp "$OUT/fleet.tsv" "$W/rep/"
mkrep tc-f1-m master locked; mkrep tc-f1-w worker locked; out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "a locked image's reports (no sshd, no guest agent, no OS Login, nothing on port 22, serial login masked, firewall dropping, daemons of the role, the crawl done) are accepted (REPORT-OK)" $([ $? = 0 ] && grep -q 'REPORT-OK' <<<"$out"; echo $?)
for fault in "openssh_server_installed=no|openssh_server_installed=yes|sshd" "port22_listening=0|port22_listening=1|port22_listening" "guest_agent_installed=no|guest_agent_installed=yes|guest_agent_installed" "serial_getty=masked|serial_getty=enabled|serial_getty" "input_policy=policy drop|input_policy=policy accept|input_policy" "fleet_event=$FS|fleet_event=0000|fleet_event" "failed_units=|failed_units=tc-crawl.service,|failed_units" "crawl_marker=crawl done|crawl_marker=crawl running|crawl_marker"; do
  from="${fault%%|*}"; r="${fault#*|}"; to="${r%%|*}"; what="${r##*|}"; mkrep tc-f1-m master locked; mkrep tc-f1-w worker locked; sed -i "s#^$from#$to#" "$W/rep/report-tc-f1-m.txt"
  out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "fault: a locked image whose report has $to is refused ($what)" $([ $? != 0 ] && grep -q "$what" <<<"$out"; echo $?); done
HOSTFAKE=tc-builder mkrep tc-f1-m master locked; mkrep tc-f1-w worker locked; out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "fault: a node that still has the builder's host name is refused (hostname)" $([ $? != 0 ] && grep -q 'hostname' <<<"$out"; echo $?)
mkrep tc-f1-m master debug; mkrep tc-f1-w worker debug; out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w debug tc-img-test-1 2>&1)"; chk "a debug image's reports (sshd installed and listening, otherwise the same) are accepted as DEBUG" $([ $? = 0 ] && grep -q 'REPORT-OK' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "fault: the debug image's reports are NOT accepted as a locked image" $([ $? != 0 ] && grep -q 'openssh_server_installed' <<<"$out"; echo $?)
echo "=== B. what a node refuses"
fleetwith() { # MODE NODEDIR NAME: write a fleet list into the node's fake metadata, built from ITS announcement
  local n="$W/$2" nm="$3" s w; s="$(grep '^sign=' "$n/sd/put.announce" | cut -d= -f2-)"; w="$(grep '^wg=' "$n/sd/put.announce" | cut -d= -f2-)"; local H=$'# tc-fleet v1'; local T=$'\t'
  local OTHER="other${T}worker${T}10.10.0.9${T}10.128.0.9:51820${T}QUJD${T}REVG"
  case "$1" in
    good) printf '%s\n%s\n%s\n' "$H" "$nm${T}master${T}10.10.0.1${T}10.128.0.2:51820${T}$s${T}$w" "$OTHER" ;;
    wrongkeys) printf '%s\n%s\n%s\n' "$H" "$nm${T}master${T}10.10.0.1${T}10.128.0.2:51820${T}QUJDRA==${T}$w" "$OTHER" ;;
    absent) printf '%s\n%s\n%s\n' "$H" "someone${T}master${T}10.10.0.1${T}10.128.0.2:51820${T}$s${T}$w" "$OTHER" ;;
    noheader) printf '%s\n%s\n' "$nm${T}master${T}10.10.0.1${T}10.128.0.2:51820${T}$s${T}$w" "$OTHER" ;;
    onenode) printf '%s\n%s\n' "$H" "$nm${T}master${T}10.10.0.1${T}10.128.0.2:51820${T}$s${T}$w" ;;
    twomasters) printf '%s\n%s\n%s\n' "$H" "$nm${T}master${T}10.10.0.1${T}10.128.0.2:51820${T}$s${T}$w" "$OTHER" | sed 's/worker/master/' ;;
    dupname) printf '%s\n%s\n%s\n' "$H" "$nm${T}master${T}10.10.0.1${T}10.128.0.2:51820${T}$s${T}$w" "$nm${T}worker${T}10.10.0.2${T}10.128.0.9:51820${T}QUJD${T}REVG" ;;
    badrole) printf '%s\n%s\n%s\n' "$H" "$nm${T}boss${T}10.10.0.1${T}10.128.0.2:51820${T}$s${T}$w" "$OTHER" ;;
    badaddr) printf '%s\n%s\n%s\n' "$H" "$nm${T}master${T}192.168.0.1${T}10.128.0.2:51820${T}$s${T}$w" "$OTHER" ;;
    badkey) printf '%s\n%s\n%s\n' "$H" "$nm${T}master${T}10.10.0.1${T}10.128.0.2:51820${T}$s\$(touch /tmp/f1-pwned)${T}$w" "$OTHER" ;;
  esac; }
refuse() { local label="$1" mode="$2" want="$3"; mknode x; startnode x tc-f1-x; waitfile "$W/x/sd/put.announce"; fleetwith "$mode" x tc-f1-x > "$W/x/sd/fleet"; wait; out="$(cat $W/x/out.txt)"; chk "fault: $label" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "TC-FLEET-FAIL: .*$want" <<<"$out" && ! [ -f "$W/x/run/role-master" ] && ! [ -f "$W/x/run/role-worker" ] && ! grep -q '^fleet' "$W/x/run/rtmr3-events.tsv" && [ ! -f "$W/x/sd/net.log" ] && [ ! -f "$W/x/run/fleet-done" ]; echo $?); }
mknode x; startnode x tc-f1-x; waitfile "$W/x/sd/put.announce"; fleetwith good x tc-f1-x > "$W/x/sd/fleet"; wait; out="$(cat $W/x/out.txt)"; chk "control: a fleet list that holds this node's keys is accepted (so the refusals below are about the keys, not the format)" $([ "$(cat $W/x/rc)" = 0 ]; echo $?)
refuse "the list holds this node's name but OTHER keys (what a rebooted node meets: it made new keys)" wrongkeys "keys are not the keys listed"
refuse "this node is not in the list at all" absent "not in fleet.tsv"
refuse "the list has no header line" noheader "does not start with"
refuse "the list has fewer than two nodes" onenode "fewer than two"
refuse "the list has two masters" twomasters "exactly one master"
refuse "a name appears twice" dupname "appears twice"
refuse "a role is neither master nor worker" badrole "malformed"
refuse "an address is not a 10.10.0.x address" badaddr "malformed"
refuse "a key field is not plain base64 (a command in it is refused and NOT run)" badkey "malformed"; chk "control: nothing in the key field was executed" $([ ! -e /tmp/f1-pwned ]; echo $?)
mknode x; FWAIT=2 startnode x tc-f1-x; wait; out="$(cat $W/x/out.txt)"; chk "fault: no fleet list within the wait: the node stops" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "no fleet list" <<<"$out"; echo $?)
mknode x; rm -f "$W/x/run/measure-done"; startnode x tc-f1-x; wait; out="$(cat $W/x/out.txt)"; chk "fault: the measurement has not finished: the node does not even make keys" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "measurement has not finished" <<<"$out" && [ ! -f "$W/x/run/sign.key" ]; echo $?)
mknode x; rm -f "$W/x/run/measure-done"; FAKE_NOHOST=1 startnode x tc-f1-x; wait; NH="$(hostname)"
chk "a machine whose own name does not resolve (no guest agent) gets it into /etc/hosts at boot, by tc-fleet.sh, before any Hadoop daemon" $(grep -qx "127.0.1.1 $NH" "$W/x/root/etc/hosts" 2>/dev/null; echo $?)
mknode x; rm -f "$W/x/run/measure-done"; startnode x tc-f1-x; wait
chk "control: a machine whose name resolves is left alone (no line is added)" $(! grep -q "127.0.1.1" "$W/x/root/etc/hosts" 2>/dev/null; echo $?)
mknode x; ( env TC_ROOT="$W/x/root" TC_RUN="$W/x/run" TC_LIB="$W/lib" TC_META=http://meta TC_QUOTE=/bin/false TC_POLL=1 FAKE_SD="$W/x/sd" FAKE_NAME=tc-f1-x TC_RTMR3="$W/x/rtmr3.bin" bash "$I/rootfs/usr/local/lib/tc/tc-fleet.sh" > "$W/x/out.txt" 2>&1; echo $? > "$W/x/rc" ); out="$(cat $W/x/out.txt)"; chk "fault: no quote can be made: the node stops" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "could not make the quote" <<<"$out"; echo $?)
# ---------------------------------------------------------------- C. the bake and the unit files
echo "=== C. the bake script and the unit files"
SD="$W/bsd"; mkdir -p "$SD"; cat > "$STUB/systemctl" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; case "$1" in daemon-reload) echo reload >> "$SD/sc.log" ;; enable) [ -f "$SD/enable_fails" ] && exit 1; echo "enable $2" >> "$SD/sc.log" ;; esac
EOS
printf '#!/usr/bin/env bash\n[ -f "${FAKE_SD:?}/analyze_warns" ] && echo "/usr/local/lib/tc/units/tc-fleet.service:5: Unknown key name '"'"'ConditionPathExists'"'"' in section '"'"'Service'"'"', ignoring."\nexit 0\n' > "$STUB/systemd-analyze"; chmod +x "$STUB/systemctl" "$STUB/systemd-analyze"
mkbake() { rm -rf "$W/br" "$SD"; mkdir -p "$SD"; BR="$W/br"; for d in usr/local/lib/tc/units etc/tc/crawl etc/systemd/system usr/bin usr/lib/jvm/java-11-openjdk-amd64 etc/java-11-openjdk opt/hadoop/etc/hadoop opt/tc/nutch; do mkdir -p "$BR/$d"; done
  cp "$I"/rootfs/usr/local/lib/tc/tc-measure.sh "$I"/rootfs/usr/local/lib/tc/tc-extend.sh "$KIT/attest/measure/treehash.sh" "$KIT/attest/measure/rtmr3_replay.py" "$BR/usr/local/lib/tc/"; cp "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" "$BR/usr/local/lib/tc/"; chmod +x "$BR"/usr/local/lib/tc/*
  cp "$I/rootfs/etc/tc/measured-paths-f03c.txt" "$BR/etc/tc/measured-paths.txt"; cp "$I/rootfs/etc/tc/crawl/"* "$BR/etc/tc/crawl/"; cp "$I/rootfs/etc/systemd/system/tc-measure.service" "$BR/etc/systemd/system/"
  echo o > "$BR/usr/bin/openssl"; echo w > "$BR/usr/bin/wg"; echo j > "$BR/usr/lib/jvm/java-11-openjdk-amd64/release"; echo c > "$BR/etc/java-11-openjdk/jvm.cfg"; echo f > "$BR/etc/tc/java-ca-fingerprints.txt"; echo x > "$BR/opt/hadoop/etc/hadoop/core-site.xml"; echo job > "$BR/opt/tc/nutch/apache-nutch-1.22.job"; }
bake() { out="$(env TC_ROOT="$BR" TC_SUDO="" FAKE_SD="$SD" bash "$I/build/tc-image-fleet.sh" "${BKIT:-$KIT}" 2>&1)"; rc=$?; }
mkbake; bake; echo "$out" | tail -1 | cut -c1-100
chk "happy path: exit 0 and READY" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
chk "the fleet script, the quote helper, the templates and the 7 units are installed, and the units are enabled" $([ -x "$BR/usr/local/lib/tc/tc-fleet.sh" ] && [ -x "$BR/usr/local/lib/tc/tc-quote.sh" ] && [ -f "$BR/etc/tc/fleet-props/hdfs-site.props" ] && [ "$(grep -c '^enable ' "$SD/sc.log")" = 7 ] && [ -f "$BR/usr/local/lib/tc/units/tc-fleet.service" ]; echo $?)
chk "the measured list has 14 entries, ending with fleet-props" $(grep -q 'TC-LIST-OK: 14 entries' <<<"$out" && [ "$(awk -F'\t' '!/^#/ && NF>=2 {print $1}' "$BR/etc/tc/measured-paths.txt" | tail -1)" = fleet-props ]; echo $?)
abortb() { local label="$1" want="$2"; bake; chk "fault: $label" $([ $rc != 0 ] && grep -q "ABORT: .*$want" <<<"$out"; echo $?); }
mkbake; rm -f "$BR/usr/local/lib/tc/tc-crawl.sh"; abortb "the crawl is not in place" "run tc-image-crawl.sh first"
mkbake; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; rm -f "$W/badkit/attest/quote.sh"; BKIT="$W/badkit" abortb "the quote helper is missing from the kit" "quote.sh"
mkbake; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; rm -f "$W/badkit/ops/image/rootfs/usr/local/lib/tc/units/tc-fleet.service"; BKIT="$W/badkit" abortb "the fleet unit is missing from the kit" "missing in"
mkbake; touch "$SD/analyze_warns"; abortb "systemd reports a key of our unit in the wrong section" "systemd does not understand"
mkbake; touch "$SD/enable_fails"; abortb "a unit cannot be enabled" "could not enable"
rm -rf "$W/badkit"
UV="$W/unitcheck.py"; cat > "$UV" <<'PYEOF'
import re, sys
ALLOWED = {"Unit": {"Description", "Requires", "After", "Wants", "Before"}, "Service": {"Type", "RemainAfterExit", "User", "Group", "Environment", "WorkingDirectory", "ExecStart", "NoNewPrivileges", "ProtectHome", "ProtectSystem", "PrivateTmp", "StateDirectory", "TimeoutStartSec"}, "Install": {"WantedBy"}}
cond = re.compile(r"^(Condition|Assert)\w+$"); sec = None; keys = []; bad = []
for ln in open(sys.argv[1], encoding="utf-8"):
    ln = ln.strip()
    if not ln or ln.startswith("#"): continue
    m = re.match(r"^\[(\w+)\]$", ln)
    if m: sec = m.group(1); continue
    k, v = ln.split("=", 1); keys.append((sec, k, v))
    if not ((sec == "Unit" and (k in ALLOWED["Unit"] or cond.match(k))) or (sec in ("Service", "Install") and k in ALLOWED[sec])): bad.append("%s in [%s]" % (k, sec))
if bad: print("keys in the wrong or an unknown section: " + ", ".join(bad)); sys.exit(1)
for s, k, v in keys: print(s, k, v)
PYEOF
U="$I/rootfs/usr/local/lib/tc/units"; ok=0; for u in tc-fleet tc-namenode tc-datanode tc-resourcemanager tc-nodemanager tc-hdfs-format tc-crawl; do python3 "$UV" "$U/$u.service" > "$W/k.$u" 2>&1 || { ok=1; cat "$W/k.$u"; }; done
chk "every key of the 7 units is in a section where systemd reads it" $ok
ok=0; for u in tc-namenode tc-resourcemanager tc-datanode tc-nodemanager tc-hdfs-format; do grep -q '^Unit Requires tc-measure.service tc-fleet.service' "$W/k.$u" && grep -q '^Unit After tc-measure.service tc-fleet.service' "$W/k.$u" && grep -q '^Service Environment .*HADOOP_CONF_DIR=/run/tc/conf' "$W/k.$u" || ok=1; done
chk "every daemon unit requires and follows tc-fleet.service and reads its configuration from /run/tc/conf (memory)" $ok
chk "the roles: NameNode, ResourceManager and the format unit only on the master; DataNode and NodeManager only on a worker; the crawl only on the master, and it requires only units that run on the master" $(grep -q 'ConditionPathExists /run/tc/role-master' "$W/k.tc-namenode" && grep -q 'ConditionPathExists /run/tc/role-master' "$W/k.tc-resourcemanager" && grep -q 'ConditionPathExists /run/tc/role-master' "$W/k.tc-hdfs-format" && grep -q 'ConditionPathExists /run/tc/role-worker' "$W/k.tc-datanode" && grep -q 'ConditionPathExists /run/tc/role-worker' "$W/k.tc-nodemanager" && grep -q 'ConditionPathExists /run/tc/role-master' "$W/k.tc-crawl" && grep -q '^Unit Requires tc-measure.service tc-fleet.service tc-namenode.service tc-resourcemanager.service$' "$W/k.tc-crawl" && ! grep -q 'Service Condition' "$W"/k.tc-*; echo $?)
chk "the fleet unit runs after the measurement and the network, as root, with a long time limit, and needs no condition" $(grep -q '^Unit After tc-measure.service network-online.target' "$W/k.tc-fleet" && ! grep -q '^Service User' "$W/k.tc-fleet" && grep -q '^Service TimeoutStartSec 2400' "$W/k.tc-fleet"; echo $?)
echo "--- the first fleet run's root cause: the builder's HDFS travelled inside the image"
chk "the cleaning has no unprivileged test of /var/lib/hadoop (a plain [ -d ] of the normal user cannot see inside a 0750 folder and skips the deletion silently)" $(! grep -q '\[ -d "\$R/var/lib/hadoop' "$I/build/tc-image-clean.sh"; echo $?)
KR2="$W/kr2"; rm -rf "$KR2"; mkdir -p "$KR2/etc/ssh" "$KR2/var/lib/dbus" "$KR2/var/lib/hadoop/namenode/current" "$KR2/var/lib/hadoop/datanode/current" "$KR2/etc/tc"; echo id > "$KR2/etc/machine-id"; echo v > "$KR2/var/lib/hadoop/namenode/current/VERSION"; echo b > "$KR2/var/lib/hadoop/datanode/current/blk_1"
out="$(env TC_ROOT="$KR2" TC_SUDO="" bash "$I/build/tc-image-clean.sh" --this-machine-becomes-an-image 2>&1)"; chk "the cleaning removes the NameNode namespace and the DataNode blocks, and says that it verified it" $([ ! -e "$KR2/var/lib/hadoop/namenode/current" ] && [ ! -e "$KR2/var/lib/hadoop/datanode/current" ] && [ -d "$KR2/var/lib/hadoop/namenode" ] && grep -q "verified: no HDFS data is left" <<<"$out"; echo $?)
mkdir -p "$KR2/var/lib/hadoop/namenode/current"; echo v > "$KR2/var/lib/hadoop/namenode/current/VERSION"; out="$(env TC_ROOT="$KR2" TC_SUDO="" TC_FIND=true bash "$I/build/tc-image-clean.sh" --this-machine-becomes-an-image 2>&1)"; rc=$?; chk "fault: if the deletion silently does nothing, the cleaning now ABORTS with a message instead of making an image that carries the data" $([ $rc != 0 ] && grep -q "Hadoop's data is still on disk" <<<"$out"; echo $?)
echo "--- the cluster checks of F2 and F3 (static: they only run on a fleet)"
bash -n "$I/test/f2-check.sh"; chk "f2-check.sh parses, uses the outsider tool and the plain client for the control, and does not mention a setting of the wrapper" $([ $? = 0 ] && grep -q 'OutsiderWrite' "$I/test/f2-check.sh" && grep -q 'org.apache.hadoop.hdfs.DistributedFileSystem' "$I/test/f2-check.sh" && ! grep -q 'attested\.keys\|attested\.signature\|attested\.folder' "$I/test/f2-check.sh"; echo $?)
chk "f2-check.sh does NOT make /f2e with the fleet's wrapper (a fleet folder cannot be written by an outsider), lets the outsider make it, fails the evil job on the read (output in a fleet folder), prints the exception lines of the tool, and has an outsider-only mode" $(! grep -q 'dfs -mkdir -p /f2e' "$I/test/f2-check.sh" && grep -q '/f2g/out-evil' "$I/test/f2-check.sh" && grep -q "grep -E 'Exception|Caused by|OUTSIDER" "$I/test/f2-check.sh" && grep -q 'MODE="${1:-all}"' "$I/test/f2-check.sh" && grep -q 'F2MODE' "$I/test/f1-drive.sh"; echo $?)
chk "the fleet's NameNode accepts the 1 KiB blocks of Hadoop's contract tests (template and rendered configuration), so that all of them run against this configuration" $(grep -q '^dfs.namenode.fs-limits.min-block-size=1024$' "$I/rootfs/etc/tc/fleet-props/hdfs-site.props" && grep -A1 'dfs.namenode.fs-limits.min-block-size' "$W/m/run/conf/hdfs-site.xml" | grep -q '<value>1024</value>'; echo $?)
chk "the contract script can compile only, the builder has a stage for it right after the job, and the fleet driver copies the kit with its output kept and a second try" $(grep -q 'COMPILE_ONLY' "$I/../attested/contract-tests.sh" && grep -q 'contract-compile)' "$I/test/f03-drive.sh" && grep -q 'COMPILE-ONLY-OK' "$I/test/f03-drive.sh" && grep -q '^ship() ' "$I/test/f1-drive.sh" && ! grep -q 'ship-test >/dev/null' "$I/test/f1-drive.sh"; echo $?)
chk "the fleet driver has the stage fleet-contract, which asks for CONTRACT-SAME-AS-HDFS" $(grep -q 'fleet-contract)' "$I/test/f1-drive.sh" && grep -q 'CONTRACT-SAME-AS-HDFS' "$I/test/f1-drive.sh"; echo $?)
chk "the kit that is shipped to a node carries the outsider tool and the contract tests" $(grep -q 'ops/attested/OutsiderWrite.java ops/attested/contract ops/attested/contract-tests.sh' "$I/test/f03-drive.sh"; echo $?)
echo "--- the crawl driver waits for the DataNodes (the second flaw of the first fleet run)"
CR="$W/cr"; rm -rf "$CR"; mkdir -p "$CR/etc/tc/crawl" "$CR/opt/hadoop/bin" "$CR/opt/tc/nutch/bin" "$CR/run/tc" "$W/crsd"; cp "$I/rootfs/etc/tc/crawl/seeds.txt" "$CR/etc/tc/crawl/"; sed 's/^WAIT_FOR_CLUSTER_SECONDS=600/WAIT_FOR_CLUSTER_SECONDS=2/' "$I/rootfs/etc/tc/crawl/params.env" > "$CR/etc/tc/crawl/params.env"
printf '# tc-fleet v1\nm\tmaster\t10.10.0.1\t1.1.1.1:51820\tQQ\tQQ\nw\tworker\t10.10.0.2\t1.1.1.2:51820\tQQ\tQQ\n' > "$CR/run/tc/fleet.tsv"
cat > "$CR/opt/hadoop/bin/hdfs" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_SD}/hdfs.calls"; case "$*" in *" -report"*) [ -f "${FAKE_SD}/dn_up" ] && echo "Name: 10.10.0.2:9866 (10.10.0.2)" ;; esac; exit 0
EOS
printf '#!/usr/bin/env bash\nprintf "Total Nodes:1\\n localhost:1 RUNNING x 0\\n"\n' > "$CR/opt/hadoop/bin/yarn"; printf '#!/usr/bin/env bash\necho "$@" > "${FAKE_SD}/crawl.args"; exit 1\n' > "$CR/opt/tc/nutch/bin/crawl"; chmod +x "$CR"/opt/hadoop/bin/* "$CR/opt/tc/nutch/bin/crawl"
out="$(env TC_ROOT="$CR" TC_MARK="$W/crmark" TC_LOG="$W/crlog" TC_POLL=1 FAKE_SD="$W/crsd" bash "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" 2>&1)"; chk "fault: HDFS answers and a NodeManager runs but NO DataNode is live: the driver waits and gives up (it no longer goes on to fail at the first write)" $([ $? != 0 ] && grep -q "FAILED: HDFS (with a live DataNode per worker) and YARN were not ready" <<<"$out" && ! grep -q "the seeds are in HDFS" <<<"$out"; echo $?)
touch "$W/crsd/dn_up"; : > "$W/crsd/hdfs.calls"; out="$(env TC_ROOT="$CR" TC_MARK="$W/crmark" TC_LOG="$W/crlog" TC_POLL=1 FAKE_SD="$W/crsd" bash "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" 2>&1)"; chk "control: with a live DataNode the driver goes on to put the seeds and run the crawl script (which this stand-in fails on purpose)" $(grep -q "the seeds are in HDFS" <<<"$out" && grep -q "the crawl script failed" <<<"$out"; echo $?)
chk "the driver waits for HDFS to leave safe mode BEFORE the first write (the second fleet run failed on exactly that call)" $(awk '/-safemode wait/ {s=NR} /dfs -put/ {p=NR} END {exit !(s && p && s < p)}' "$W/crsd/hdfs.calls"; echo $?)
grep -q "registration.ip-hostname-check=false" "$I/rootfs/etc/tc/fleet-props/hdfs-site.props"; chk "the fleet's HDFS template turns the DataNode reverse-name check off (the real cause of the first fleet run)" $?
chk "the check's search text for a private key is not contiguous in the check file (a search must not match itself)" $(! grep -q "BEGIN EC PRIVATE KEY" "$I/test/f1-check.sh" && ! grep -q "BEGIN PRIVATE KEY" "$I/test/f1-check.sh"; echo $?)
echo "--- step F2: the wrapped configuration, the key in PKCS#8, and the identity as measured data"
chk "each node sets its host name from the instance name at boot (cloud-init is off): hostnamectl set-hostname tc-f1-m and tc-f1-w, before it joins" $(grep -qx 'hostnamectl set-hostname tc-f1-m' "$W/m/sd/hostname.log" && grep -qx 'hostnamectl set-hostname tc-f1-w' "$W/w/sd/hostname.log"; echo $?)
chk "the node's signing key is PKCS#8 (the form Java reads), and sign.pub is the public key that the announcement and fleet.tsv carry" $([ "$(head -1 $W/m/run/sign.key)" = "-----BEGIN PRIVATE KEY-----" ] && [ "$(cat $W/m/run/sign.pub)" = "$(attrval m sign)" ] && [ "$(openssl ec -in $W/m/run/sign.key -pubout -outform DER 2>/dev/null | base64 -w0)" = "$(cat $W/m/run/sign.pub)" ] && [ "$(stat -c %a $W/m/run/sign.pub)" = 644 ]; echo $?)
chk "the rendered core-site.xml is the wrapped configuration: the attested file system for hdfs:// and for FileContext, and NO setting of the wrapper (it has none, so that no job file can change it)" $(for p in 'org.apache.nutch.attested.AttestedHdfsFileSystem' 'org.apache.nutch.attested.AttestedHdfs<'; do tr -d ' \n' < "$W/m/run/conf/core-site.xml" | grep -qF "$p" || { echo 1; exit; }; done; ! grep -q '<name>attested\.' "$W/m/run/conf/core-site.xml"; echo $?)
CR3="$W/cr3"; rm -rf "$CR3"; cp -r "$CR" "$CR3"; cp "$I/rootfs/etc/tc/crawl/params.env" "$CR3/etc/tc/crawl/params.env"
out="$(env TC_ROOT="$CR3" bash "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" --check-params 2>&1)"; rcv=$?; chk "the baked parameters are valid, and they hold the crawler's identity (name, a https page, the WARC software) with no trace of the old fork" $([ $rcv = 0 ] && grep -q "are valid" <<<"$out" && grep -q '^AGENT_URL=https://github.com/Heron-AI-Security$' "$I/rootfs/etc/tc/crawl/params.env" && ! grep -rqi 'antisource' "$I/rootfs/etc/tc/crawl"; echo $?)
for bad in "AGENT_URL=http://x.org/a|must be a plain https address" "AGENT_URL=https://a.org/b;touch/tmp/f2-pwned|not KEY=VALUE with a plain value" "AGENT_NAME=my bot|not KEY=VALUE with a plain value"; do v="${bad%%|*}"; w="${bad##*|}"; k="${v%%=*}"; grep -v "^$k=" "$I/rootfs/etc/tc/crawl/params.env" > "$CR3/etc/tc/crawl/params.env"; echo "$v" >> "$CR3/etc/tc/crawl/params.env"; out="$(env TC_ROOT="$CR3" bash "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" --check-params 2>&1)"; rcv=$?; chk "fault: $v is refused" $([ $rcv != 0 ] && grep -q "$w" <<<"$out" && [ ! -e /tmp/f2-pwned ]; echo $?); done
grep -v "^AGENT_URL=" "$I/rootfs/etc/tc/crawl/params.env" > "$CR3/etc/tc/crawl/params.env"; out="$(env TC_ROOT="$CR3" bash "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" --check-params 2>&1)"; rcv=$?; chk "fault: a params.env without the identity is refused (params.env lacks AGENT_URL)" $([ $rcv != 0 ] && grep -q "lacks AGENT_URL" <<<"$out"; echo $?)
chk "the driver hands the identity to Nutch with -D (it overrides the job's own configuration), and the crawl script receives it" $(grep -q 'http.agent.url=https://github.com/Heron-AI-Security' "$W/crsd/crawl.args" && grep -q 'warc.export.software=Apache-Nutch-CommonCrawl-fork-training-custody' "$W/crsd/crawl.args" && grep -q 'http.agent.name=training-custody-test-bot' "$W/crsd/crawl.args"; echo $?)
chk "dfsadmin is told to use the plain DistributedFileSystem (it refuses the wrapper), in the driver (twice) and in the check" $(grep -c 'dfsadmin -D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem' "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" | grep -q '^2$' && grep -q 'dfsadmin -D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem' "$I/test/f1-check.sh"; echo $?)
KR="$W/kr"; rm -rf "$KR"; mkdir -p "$KR/etc/ssh" "$KR/var/lib/dbus" "$KR/var/lib/tc-crawl" "$KR/var/lib/tc" "$KR/etc/tc"; echo id > "$KR/etc/machine-id"; echo "crawl done x" > "$KR/var/lib/tc-crawl/done"; echo l > "$KR/etc/tc/measured-paths.txt"
out="$(env TC_ROOT="$KR" TC_SUDO="" bash "$I/build/tc-image-clean.sh" --this-machine-becomes-an-image 2>&1)"; chk "the cleaning removes the crawl marker (a builder that crawled must not make every fleet skip its crawl) and keeps the image's own files" $([ ! -e "$KR/var/lib/tc-crawl" ] && [ -f "$KR/etc/tc/measured-paths.txt" ]; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "REHEARSAL-PASS: two nodes run the real fleet script, the real operator script verifies them, and the bake and the units hold; every fault is refused; $PASS checks"; else echo "REHEARSAL-FAIL"; fi
[ "$FAILN" = 0 ]
REHEARSAL_END_MARK=1
