#!/usr/bin/env bash
# Rehearsal of step F1 with stand-ins: TWO nodes run the REAL tc-fleet.sh (master and worker) with the REAL tc-extend.sh, hadoop_conf.py, openssl and base64, against a fake register that extends like the hardware, a fake
# metadata server (curl), wg, ip and quote helper; the operator side (f1-fleet.py) then verifies THEIR announcements, builds fleet.tsv from them and verifies their final quotes. The bake script and the unit files are
# tested too. Every check that matters is also made to FAIL on purpose.      bash f1-rehearse.sh KITDIR
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; echo "${out:-}" | grep -v "^      " | tail -5 | sed "s/^/        | /"; fi; }
W="$(mktemp -d)"; STUB="$W/bin"; mkdir -p "$STUB" "$W/lib"
cp "$I"/rootfs/usr/local/lib/tc/tc-extend.sh "$KIT/attest/measure/treehash.sh" "$KIT/ops/rebuild/hadoop_conf.py" "$W/lib/"
# the quotes here are fakes, so the node gets a stand-in for tc-peer-verify.py (the real one is tested on real Intel-signed quotes by f1-peers-test.sh): it records its
# arguments and the announcements it was given, and refuses when the node's fake metadata holds peers-refuse
cat > "$W/lib/tc-peer-verify.py" <<'PYEOF'
import os, shutil, sys
sd = os.environ["FAKE_SD"]; own, fleet, quotes, outp = sys.argv[1:5]
open(sd + "/peers.args", "w").write("\n".join(sys.argv[1:5]) + "\n"); shutil.copy(quotes, sd + "/peers.quotes")
if os.path.exists(sd + "/peers-refuse"): print("peer other: REFUSED: (stand-in)"); print("TC-PEERS-FAIL: 1 of 1 peers refused"); sys.exit(1)
open(outp, "w").write("other\t00\n"); print("TC-PEERS-OK 1")
PYEOF
chmod +x "$W/lib"/*
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
case "$url" in */instance/name) echo "$FAKE_NAME" ;; */instance/attributes/tc-fleet) [ -s "$SD/fleet" ] && cat "$SD/fleet" || exit 22 ;; */instance/attributes/tc-fleet-quotes) [ -s "$SD/quotes" ] && cat "$SD/quotes" || echo "{}" ;; *) exit 22 ;; esac
EOS
cat > "$STUB/hostname" <<'EOS'
#!/usr/bin/env bash
S="${FAKE_SD:?}/hostname.state"; [ -f "$S" ] || echo tc-builder > "$S"   # the image keeps the name of the builder
if [ $# = 0 ]; then cat "$S"; exit 0; fi
echo "hostname-set $1" >> "$FAKE_SD/hostname.log"
case "${FAKE_HOSTNAME:-}" in ro) exit 1 ;; revert) exit 0 ;; esac   # ro: the call is refused; revert: it returns 0 and the name does not change
echo "$1" > "$S"
EOS
cat > "$STUB/hostnamectl" <<'EOS'
#!/usr/bin/env bash
echo "hostnamectl $*" >> "${FAKE_SD}/hostname.log"
case "$*" in *--transient*) exit 0 ;; esac   # what the real one did on the first locked boot: --transient exited 0 and changed nothing
for a in "$@"; do n="$a"; done; echo "$n" > "${FAKE_SD}/hostname.state"   # the static form sets the name
EOS
cat > "$STUB/mount" <<'EOS'
#!/usr/bin/env bash
echo "mount $*" >> "${FAKE_SD:?}/mount.log"; [ -z "${FAKE_MOUNT_FAIL:-}" ]
EOS
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
  printf 'commit cafe0000cafe0000cafe0000cafe0000cafe0000\n' > "$n/src"
  for e in "source src" "tc-lib f1" "tc-conf f2" "nutch-deploy f1"; do set -- $e; env TC_LOG="$n/run/rtmr3-events.tsv" TC_RTMR3="$n/rtmr3.bin" TC_WRITE="python3 $W/fakewrite.py $n/rtmr3.bin" bash "$W/lib/tc-extend.sh" "$1" "$n/$2" >/dev/null; done; date > "$n/run/measure-done"; }
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
for n in m w; do cp "$OUT/fleet-quotes.json" "$W/$n/sd/quotes"; done; cp "$OUT/fleet.tsv" "$W/m/sd/fleet"; cp "$OUT/fleet.tsv" "$W/w/sd/fleet"; wait
chk "both nodes join the fleet and exit 0" $([ "$(cat $W/m/rc)" = 0 ] && [ "$(cat $W/w/rc)" = 0 ] && grep -q 'fleet joined: tc-f1-m is the master at 10.10.0.1' "$W/m/out.txt" && grep -q 'fleet joined: tc-f1-w is the worker at 10.10.0.2' "$W/w/out.txt"; echo $?)
cp "$W/m/sd/put.final" "$OUT/final-tc-f1-m.txt"; cp "$W/w/sd/put.final" "$OUT/final-tc-f1-w.txt"
chk "mutual attestation: each node ran the peer check on its own announcement, the list and the operator's announcements (fleet-quotes.json, which holds both), before wg0" $(ok=0; for n in m w; do [ "$(sed -n 1p $W/$n/sd/peers.args)" = "$W/$n/run/attr-announce.txt" ] && [ "$(sed -n 3p $W/$n/sd/peers.args)" = "$W/$n/run/fleet-quotes.json" ] && cmp -s "$W/$n/sd/peers.quotes" "$OUT/fleet-quotes.json" || ok=1; done; python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if sorted(d) == ["tc-f1-m", "tc-f1-w"] and all(v.startswith("name=") for v in d.values()) else 1)' "$OUT/fleet-quotes.json" || ok=1; echo $ok)
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
# Work item, change 2: an image that differs only in RTMR2 (the root hash), as the debug and the locked image of one commit do once the files are not RTMR3 events any more
rm -rf "$W/opout4"; cp -r "$OUT" "$W/opout4"
python3 - "$W/opout4/final-tc-f1-m.txt" <<'PYX'
import base64, sys
p = sys.argv[1]; o = []
for l in open(p, encoding="utf-8").read().splitlines():
    if l.startswith("quote_b64="):
        q = bytearray(base64.b64decode(l.split("=", 1)[1])); q[472:520] = bytes(b ^ 0x5A for b in q[472:520]); l = "quote_b64=" + base64.b64encode(bytes(q)).decode()
    o.append(l)
open(p, "w", encoding="utf-8").write("\n".join(o) + "\n")
PYX
out="$(python3 "$I/test/f1-fleet.py" images "$OUT" "$W/opout4" tc-f1-m rtmr2 2>&1)"; chk "two images with the SAME RTMR3 but a different RTMR2 are told apart, and rtmr2 can be named as the register that must differ (IMAGES-DIFFER)" $([ $? = 0 ] && grep -q 'IMAGES-DIFFER' <<<"$out" && grep -q '^RTMR2 (the root hash' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" images "$OUT" "$W/opout4" tc-f1-m 2>&1)"; chk "... and with no name at all a different RTMR2 is enough (IMAGES-DIFFER)" $([ $? = 0 ] && grep -q 'IMAGES-DIFFER' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" images "$OUT" "$OUT" tc-f1-m rtmr2 2>&1)"; chk "fault: one image against itself is refused even when rtmr2 is named (equal RTMR2 and equal RTMR3: not told apart)" $([ $? != 0 ] && grep -q 'not told apart' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" images "$OUT" "$W/opout4" tc-f1-m tc-conf 2>&1)"; chk "fault: a different RTMR2 does not make an event differ: the named event tc-conf must differ and does not, so the check refuses" $([ $? != 0 ] && grep -q 'must differ' <<<"$out"; echo $?)
FS="$(sha384sum $OUT/fleet.tsv | cut -d' ' -f1)"
mkrep() { # name role kind: a report that says what that kind of image must say
  { echo "name=$1"; echo "hostname=${HOSTFAKE:-$1}"; echo "image=tc-img-test-1"; echo "mode=$3"; echo "input_policy=policy drop"; echo "nft_rules_sha=0123456789abcdef"; echo "failed_units="; echo "unit_tc-measure=active/success"; echo "unit_tc-fleet=active/success"; echo "fleet_done=2026-10-21T00:00:00Z"; echo "fleet_event=$FS"; echo "wg_peers=1"
    if [ "$3" = locked ]; then echo "openssh_server_installed=no"; echo "guest_agent_installed=no"; echo "oslogin_installed=no"; echo "port22_listening=0"; echo "serial_getty=masked"; for d in usr etc opt boot root; do echo "tree_$d=ro"; done; else echo "openssh_server_installed=yes"; echo "port22_listening=1"; echo "serial_getty=enabled"; for d in usr etc opt boot root; do echo "tree_$d=rw"; done; fi
    if [ "$2" = master ]; then echo "unit_tc-namenode=active/success"; echo "unit_tc-resourcemanager=active/success"; echo "crawl_marker=crawl done 2026-10-21T00:00:00Z fetched=8 segments=3"; else echo "unit_tc-datanode=active/success"; echo "unit_tc-nodemanager=active/success"; fi; } > "$W/rep/report-$1.txt"; }
rm -rf "$W/rep"; mkdir -p "$W/rep"; cp "$OUT/fleet.tsv" "$W/rep/"
mkrep tc-f1-m master locked; mkrep tc-f1-w worker locked; out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "a locked image's reports (no sshd, no guest agent, no OS Login, nothing on port 22, serial login masked, firewall dropping, daemons of the role, the crawl done) are accepted (REPORT-OK)" $([ $? = 0 ] && grep -q 'REPORT-OK' <<<"$out"; echo $?)
for fault in "openssh_server_installed=no|openssh_server_installed=yes|sshd" "port22_listening=0|port22_listening=1|port22_listening" "guest_agent_installed=no|guest_agent_installed=yes|guest_agent_installed" "serial_getty=masked|serial_getty=enabled|serial_getty" "input_policy=policy drop|input_policy=policy accept|input_policy" "fleet_event=$FS|fleet_event=0000|fleet_event" "failed_units=|failed_units=tc-crawl.service,|failed_units" "crawl_marker=crawl done|crawl_marker=crawl running|crawl_marker"; do
  from="${fault%%|*}"; r="${fault#*|}"; to="${r%%|*}"; what="${r##*|}"; mkrep tc-f1-m master locked; mkrep tc-f1-w worker locked; sed -i "s#^$from#$to#" "$W/rep/report-tc-f1-m.txt"
  out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "fault: a locked image whose report has $to is refused ($what)" $([ $? != 0 ] && grep -q "$what" <<<"$out"; echo $?); done
# Work item, change 1: a locked image must report all five code trees as read-only mounts
for fault in "tree_usr=ro|tree_usr=rw|tree_usr" "tree_etc=ro|tree_etc=unknown|tree_etc" "tree_root=ro|tree_root=rw|tree_root"; do
  from="${fault%%|*}"; r="${fault#*|}"; to="${r%%|*}"; what="${r##*|}"; mkrep tc-f1-m master locked; mkrep tc-f1-w worker locked; sed -i "s#^$from#$to#" "$W/rep/report-tc-f1-m.txt"
  out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "fault: a locked image whose report has $to (a code tree that is not a read-only mount, or not known to be) is refused ($what)" $([ $? != 0 ] && grep -q "$what" <<<"$out"; echo $?); done
mkrep tc-f1-m master locked; mkrep tc-f1-w worker locked; sed -i '/^tree_boot=/d' "$W/rep/report-tc-f1-w.txt"
out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "fault: a locked image whose report has no tree_boot line (an image made before the lock) is refused, and the check says the line is missing" $([ $? != 0 ] && grep -q 'tree_boot' <<<"$out" && grep -q 'missing' <<<"$out"; echo $?)
HOSTFAKE=tc-builder mkrep tc-f1-m master locked; mkrep tc-f1-w worker locked; out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "fault: a node that still has the builder's host name is refused (hostname)" $([ $? != 0 ] && grep -q 'hostname' <<<"$out"; echo $?)
mkrep tc-f1-m master debug; mkrep tc-f1-w worker debug; out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w debug tc-img-test-1 2>&1)"; chk "a debug image's reports (sshd installed and listening, otherwise the same) are accepted as DEBUG" $([ $? = 0 ] && grep -q 'REPORT-OK' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" tc-f1-m tc-f1-w locked tc-img-test-1 2>&1)"; chk "fault: the debug image's reports are NOT accepted as a locked image" $([ $? != 0 ] && grep -q 'openssh_server_installed' <<<"$out"; echo $?)
echo "=== A3. the reference values of an image, from the final quotes of both nodes"
out="$(python3 "$I/test/f1-fleet.py" reference "$OUT2" tc-img-test-1 c3-standard-4 tc-f1-m tc-f1-w 2>&1)"; rcr=$?
chk "the reference values are written (REFERENCE-OK): MRTD, RTMR0 to RTMR2 and the stable events, with the per-run events named" $([ $rcr = 0 ] && grep -q 'REFERENCE-OK' <<<"$out" && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); assert d["image"]=="tc-img-test-1" and all(len(d[k])==96 for k in ("mrtd","rtmr0","rtmr1","rtmr2")) and "fleet" not in d["stable_events"] and "tc-conf" in d["stable_events"] and d["per_run_events"]==["fleet","fleet-conf"]' "$OUT2/reference-values.json"; echo $?)
rm -rf "$W/opout4"; cp -r "$OUT2" "$W/opout4"; python3 - "$W/opout4/final-tc-f1-w.txt" <<'PY'
import sys, base64
p = sys.argv[1]; L = open(p, encoding="utf-8").read().splitlines(); o = []
for l in L:
    if l.startswith("quote_b64="):
        q = bytearray(base64.b64decode(l.split("=", 1)[1])); q[184] ^= 1; l = "quote_b64=" + base64.b64encode(bytes(q)).decode()
    o.append(l)
open(p, "w", encoding="utf-8").write("\n".join(o) + "\n")
PY
out="$(python3 "$I/test/f1-fleet.py" reference "$W/opout4" tc-img-test-1 c3-standard-4 tc-f1-m tc-f1-w 2>&1)"; chk "fault: two nodes that disagree on MRTD give no reference values" $([ $? != 0 ] && grep -q 'disagree on mrtd' <<<"$out"; echo $?)
echo "=== A4. decision 1 (R2): every row of fleet.tsv has a quote A and a quote B that match the reference values exactly"
rm -rf "$W/opout5"; mkdir "$W/opout5"; for f in announce-tc-f1-m announce-tc-f1-w final-tc-f1-m final-tc-f1-w; do cp "$OUT/$f.txt" "$W/opout5/"; done; cp "$W/m/sd/fleet" "$W/opout5/fleet.tsv"
out="$(python3 "$I/test/f1-fleet.py" reference "$W/opout5" tc-img-test-1 c3-standard-4 tc-f1-m tc-f1-w 2>&1)"; REF="$W/opout5/reference-values.json"
chk "the reference values carry the image and the machine type, and are made from any number of nodes" $(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["machine_type"]=="c3-standard-4" and d["image"]=="tc-img-test-1" else 1)' "$REF"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$REF" 2>&1)"; chk "control: both nodes of the real fleet list, with their real quotes A and B, are accepted (ENFORCE-OK)" $([ $? = 0 ] && grep -q 'ENFORCE-OK: all 2 nodes' <<<"$out"; echo $?)
mkref() { python3 - "$REF" "$1" "$2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); k = sys.argv[2]
if k == "mrtd": d["mrtd"] = "ff" * 48
elif k == "event": d["stable_events"]["tc-conf"] = "11" * 48
elif k == "nomachine": del d["machine_type"]
json.dump(d, open(sys.argv[3], "w"))
PY
}
mkref mrtd "$W/ref-mrtd.json"; out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-mrtd.json" 2>&1)"; chk "fault: a node whose MRTD is not the reference's is REFUSED (E4), and the rules are printed" $([ $? != 0 ] && grep -q 'E4 tc-f1-m' <<<"$out" && grep -q 'E0  (the verifier' <<<"$out"; echo $?)
mkref event "$W/ref-event.json"; out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-event.json" 2>&1)"; chk "fault: a node booted from another image (one measured event, tc-conf, differs) is REFUSED in quote A (E5) and in quote B (E6)" $([ $? != 0 ] && grep -q 'E5 tc-f1-m' <<<"$out" && grep -q 'E6 tc-f1-m' <<<"$out"; echo $?)
mkref nomachine "$W/ref-nomachine.json"; out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-nomachine.json" 2>&1)"; chk "fault: reference values without the machine type are not accepted" $([ $? != 0 ] && grep -q 'lack machine_type' <<<"$out"; echo $?)
rm -rf "$W/opout6"; cp -r "$W/opout5" "$W/opout6"; rm "$W/opout6/final-tc-f1-w.txt"; out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout6" "$REF" 2>&1)"; chk "fault: a row without its quote B is REFUSED (E1)" $([ $? != 0 ] && grep -q 'E1 tc-f1-w: there is no quote B' <<<"$out"; echo $?)
rm -rf "$W/opout6"; cp -r "$W/opout5" "$W/opout6"; printf 'ghost\tworker\t10.10.0.3\t10.128.0.250:51820\tQUJD\tQUJD\n' >> "$W/opout6/fleet.tsv"; out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout6" "$REF" 2>&1)"; chk "fault: a node added to fleet.tsv without any quote (an insider's row) is REFUSED (E1 for the new row), and so is the changed list (E7)" $([ $? != 0 ] && grep -q 'E1 ghost: there is no quote A' <<<"$out" && grep -q 'E7 tc-f1-m' <<<"$out"; echo $?)
rm -rf "$W/opout6"; cp -r "$W/opout5" "$W/opout6"; python3 - "$W/opout6/fleet.tsv" <<'PY'
import sys
L = open(sys.argv[1]).read().split("\n"); i = [k for k, l in enumerate(L) if l.startswith("tc-f1-w")][0]; c = L[i].split("\t"); c[4] = c[4][:-4] + "AAAA"; L[i] = "\t".join(c); open(sys.argv[1], "w").write("\n".join(L))
PY
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout6" "$REF" 2>&1)"; chk "fault: a row whose signing key is not the key of the node's quotes is REFUSED (E2)" $([ $? != 0 ] && grep -q 'E2 tc-f1-w' <<<"$out"; echo $?)
rm -rf "$W/opout7"; mkdir "$W/opout7"; cp "$W/opout5/announce-tc-f1-m.txt" "$W/opout5/announce-tc-f1-w.txt" "$W/opout7/"; out="$(python3 "$I/test/f1-fleet.py" build "$W/opout7" tc-f1-m 10.128.0.2 tc-f1-w 10.128.0.3 "$REF" 2>&1)"; chk "building a fleet with the reference: the nodes that match it are admitted (ANNOUNCEMENTS-VERIFIED)" $([ $? = 0 ] && grep -q 'ANNOUNCEMENTS-VERIFIED' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" build "$W/opout7" tc-f1-m 10.128.0.2 tc-f1-w 10.128.0.3 "$W/ref-event.json" 2>&1)"; chk "fault: building a fleet with the reference REFUSES a node that does not match it, before it can enter fleet.tsv (a debug node added to a locked fleet)" $([ $? != 0 ] && grep -q 'is refused, it does not match the reference values' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/nonexistent" "$REF" 2>&1)"; chk "fault: enforce on a folder that is not a run's says so in one line (no traceback)" $([ $? != 0 ] && grep -q 'there is no fleet.tsv' <<<"$out" && ! grep -q Traceback <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/no-such-reference.json" 2>&1)"; chk "fault: enforce without a reference values file says so in one line" $([ $? != 0 ] && grep -q 'there is no reference values file' <<<"$out" && ! grep -q Traceback <<<"$out"; echo $?)
echo "=== A4b. step R4.4: the run is pinned to a commit (rule E9)"
CM=cafe0000cafe0000cafe0000cafe0000cafe0000; OTHERC=1234567890123456789012345678901234567890
mkcommit() { python3 - "$REF" "$1" "$2" "$CM" "$OTHERC" <<'PY'
import hashlib, json, sys
d = json.load(open(sys.argv[1])); v, out, c, o = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
h = lambda x: hashlib.sha384(("commit %s\n" % x).encode()).hexdigest()
if v == "ok": d["commit"] = c
elif v == "badsource": d["commit"] = c; d["stable_events"]["source"] = "22" * 48
elif v == "none": d["commit"] = "none"
elif v == "other": d["commit"] = o; d["stable_events"]["source"] = h(o)
json.dump(d, open(out, "w"))
PY
}
python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if "source" in d["stable_events"] else 1)' "$REF"; chk "the fake fleet measures the source event (the commit line), so the reference values hold it" $?
mkcommit ok "$W/ref-c.json"; out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-c.json" "$CM" 2>&1)"; chk "step R4.4: reference values that name the commit, enforced with the right pin, are accepted and the pin is reported (ENFORCE-OK and PINNED)" $([ $? = 0 ] && grep -q 'ENFORCE-OK' <<<"$out" && grep -q "PINNED (rule E9): every node was built from commit $CM" <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-c.json" "${CM:0:9}" 2>&1)"; chk "step R4.4: the pin may be the first 9 characters of the commit, as git log shows it" $([ $? = 0 ] && grep -q 'ENFORCE-OK' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-c.json" "$OTHERC" 2>&1)"; chk "fault (E9): a pin for another commit than the reference's is REFUSED, and both commits are named" $([ $? != 0 ] && grep -q 'E9 the run is pinned to commit 123456789012' <<<"$out" && grep -q 'reference values are for commit cafe0000cafe' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-c.json" 2>&1)"; chk "fault (E9): reference values that name a commit are NOT enforced without a pin" $([ $? != 0 ] && grep -q 'E9 the reference values are for commit cafe0000cafe...: the run must be pinned' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$REF" "$CM" 2>&1)"; chk "fault (E9): a pin for reference values that name no commit is REFUSED (a pin must not be silently ignored)" $([ $? != 0 ] && grep -q 'E9 the run is pinned to commit cafe0000cafe... but the reference values are not for any commit' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$REF" 2>&1)"; chk "control: the old way (reference values without a commit, no pin) still works" $([ $? = 0 ] && grep -q 'ENFORCE-OK' <<<"$out" && ! grep -q PINNED <<<"$out"; echo $?)
mkcommit badsource "$W/ref-bs.json"; out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-bs.json" "$CM" 2>&1)"; chk "fault: reference values whose source event is not the hash of the commit that they name are refused as inconsistent (a tampered reference)" $([ $? != 0 ] && grep -q 'STOP: the reference values are inconsistent' <<<"$out"; echo $?)
mkcommit none "$W/ref-none.json"; out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-none.json" "$CM" 2>&1)"; chk "fault: 'commit none' (a development image) is never a reference" $([ $? != 0 ] && grep -q 'is not a commit id' <<<"$out"; echo $?)
mkcommit other "$W/ref-o.json"; out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout5" "$W/ref-o.json" "$OTHERC" 2>&1)"; chk "fault (E9): nodes that were built from another commit than the pinned one are REFUSED by name, with the explicit message" $([ $? != 0 ] && grep -q 'E9 a node was not built from the pinned commit 123456789012' <<<"$out" && grep -q 'E5 tc-f1-m: the event source has digest' <<<"$out"; echo $?)
rm -rf "$W/opout5r"; cp -r "$W/opout5" "$W/opout5r"; rm -f "$W/opout5r/reference-values.json"; out="$(TC_REF_COMMIT="$CM" python3 "$I/test/f1-fleet.py" reference "$W/opout5r" tc-img-test-1 c3-standard-4 tc-f1-m tc-f1-w 2>&1)"; chk "step R4.4: the reference mode records the commit when the nodes really measured it" $([ $? = 0 ] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("commit")==sys.argv[2] else 1)' "$W/opout5r/reference-values.json" "$CM"; echo $?)
# the reference of the real-looking run, with its commit (made above), and two fake independent builds that measured what the fake nodes measured
TC_REF_COMMIT="$CM" python3 "$I/test/f1-fleet.py" reference "$W/opout5r" tc-img-test-1 c3-standard-4 tc-f1-m tc-f1-w >/dev/null 2>&1
mkbuildfrom() { python3 - "$W/opout5r/reference-values.json" "$1" "$CM" "$2" <<'PY'
import json, os, sys
d = json.load(open(sys.argv[1])); out, c, bad = sys.argv[2], sys.argv[3], sys.argv[4]; os.makedirs(out, exist_ok=True)
open(out + "/source.txt", "w").write("commit %s\n" % c)
names = [n for n in d["events_in_order"] if n not in d["per_run_events"]]
open(out + "/events.tsv", "w").write("".join("%s\t%s\t1\tfile\t/x\t\n" % (n, ("00" + d["stable_events"][n][2:]) if (bad == n) else d["stable_events"][n]) for n in names))
PY
}
mkbuildfrom "$W/fb1" none; mkbuildfrom "$W/fb2" none; mkbuildfrom "$W/fb3" tc-lib
out="$(bash "$I/test/r4-accept.sh" "$W/opout5r" "$CM" "$W/fb1" "$W/fb2" 2>&1)"; chk "step R4.5: the acceptance script accepts a fleet whose stable events two independent builds recomputed (R4-ACCEPT-OK), with the wrong and the missing pin refused" $([ $? = 0 ] && grep -q 'R4-REFERENCE-OK' <<<"$out" && grep -q '^PINNED (rule E9)' <<<"$out" && grep -q 'ok: a pin for another commit' <<<"$out" && grep -q 'ok: no pin at all is refused' <<<"$out" && grep -q '^R4-ACCEPT-OK' <<<"$out"; echo $?)
out="$(bash "$I/test/r4-accept.sh" "$W/opout5r" "$CM" "$W/fb1" "$W/fb3" 2>&1)"; chk "fault: two builds that disagree on one event give no acceptance, and the event is named" $([ $? != 0 ] && grep -q 'R4-ACCEPT-FAILED: the builds and the real run do not agree' <<<"$out" && grep -q 'disagree on the event tc-lib' <<<"$out"; echo $?)
out="$(bash "$I/test/r4-accept.sh" "$W/opout5r" "$CM" "$W/fb1" 2>&1)"; chk "fault: one build is refused (it proves nothing about reproducibility)" $([ $? != 0 ] && grep -q 'R4-ACCEPT-FAILED: at least two build folders' <<<"$out"; echo $?)
out="$(bash "$I/test/r4-accept.sh" "$W/opout5" "$CM" "$W/fb1" "$W/fb2" 2>&1)"; chk "fault: a reference of the real run that does not name the commit is refused with the instruction to set PIN_COMMIT" $([ $? != 0 ] && grep -q 'do not name the commit' <<<"$out" && grep -q 'PIN_COMMIT' <<<"$out"; echo $?)
out="$(bash "$I/test/r4-accept.sh" "$W/opout5r" "$OTHERC" "$W/fb1" "$W/fb2" 2>&1)"; chk "fault: another commit than the one of the real run is refused" $([ $? != 0 ] && grep -q 'R4-ACCEPT-FAILED' <<<"$out"; echo $?)
python3 - "$W/opout5r/reference-values.json" "$W/fb1" "$W/fb2" <<'PY'
import json, sys
d = json.load(open(sys.argv[1])); d["stable_events"]["tc-conf"] = "11" * 48; json.dump(d, open(sys.argv[1], "w"))
PY
out="$(bash "$I/test/r4-accept.sh" "$W/opout5r" "$CM" "$W/fb1" "$W/fb2" 2>&1)"; chk "fault: a real run that measured an event differently from the independent builds is refused (the running image is not the commit's image)" $([ $? != 0 ] && grep -q 'the real run measured the event tc-conf' <<<"$out"; echo $?)
TC_REF_COMMIT="$CM" python3 "$I/test/f1-fleet.py" reference "$W/opout5r" tc-img-test-1 c3-standard-4 tc-f1-m tc-f1-w >/dev/null 2>&1
rm -rf "$W/kmut"; mkdir -p "$W/kmut"; cp "$I/test/r4-accept.sh" "$I/test/r4-reference.py" "$I/test/f1-fleet.py" "$W/kmut/"
python3 - "$W/kmut/f1-fleet.py" <<'PY'
import sys
s = open(sys.argv[1]).read(); o = 'elif not ref["commit"].startswith(pin): bad.append'; assert o in s; open(sys.argv[1], "w").write(s.replace(o, "elif False: bad.append", 1))
PY
out="$(bash "$W/kmut/r4-accept.sh" "$W/opout5r" "$CM" "$W/fb1" "$W/fb2" 2>&1)"; chk "the acceptance script CHECKS that the wrong pin is refused: with a verifier that ignores the pin (a deliberately broken copy) it fails loudly instead of reporting success" $([ $? != 0 ] && grep -q 'R4-ACCEPT-FAILED: a pin for another commit was NOT refused' <<<"$out" && ! grep -q '^R4-ACCEPT-OK' <<<"$out"; echo $?)
out="$(TC_REF_COMMIT="$OTHERC" python3 "$I/test/f1-fleet.py" reference "$W/opout5r" tc-img-test-1 c3-standard-4 tc-f1-m tc-f1-w 2>&1)"; chk "fault: the reference mode refuses a commit that the nodes did not measure, and names it" $([ $? != 0 ] && grep -q 'STOP: the nodes did not measure the commit 123456789012' <<<"$out"; echo $?)
out="$(TC_REF_COMMIT="not-hex" python3 "$I/test/f1-fleet.py" reference "$W/opout5r" tc-img-test-1 c3-standard-4 tc-f1-m tc-f1-w 2>&1)"; chk "fault: the reference mode refuses a commit that is not a full commit id" $([ $? != 0 ] && grep -q 'TC_REF_COMMIT must be a full commit id' <<<"$out"; echo $?)
cp "$OUT2/final-tc-f1-m.txt" "$W/opout5/final-n3.txt"; out="$(python3 "$I/test/f1-fleet.py" reference "$W/opout5" tc-img-test-1 c3-standard-4 tc-f1-m tc-f1-w n3 2>&1)"; chk "the reference tool takes three nodes (no two-node assumption) and checks that all agree" $([ $? = 0 ] && grep -q 'all 3 nodes agree' <<<"$out"; echo $?)
echo "=== A5. step R1: a fleet of THREE (a master and two workers) with the real node script: no two-node assumption in the nodes, the operator tool or the reference values"
OUT9="$W/opout9"; rm -rf "$OUT9"; mkdir -p "$OUT9"; mknode m3; mknode w3; mknode x3; startnode m3 tc-r1-m; startnode w3 tc-r1-w; startnode x3 tc-r1-w2
waitfile "$W/m3/sd/put.announce"; waitfile "$W/w3/sd/put.announce"; waitfile "$W/x3/sd/put.announce"
cp "$W/m3/sd/put.announce" "$OUT9/announce-tc-r1-m.txt"; cp "$W/w3/sd/put.announce" "$OUT9/announce-tc-r1-w.txt"; cp "$W/x3/sd/put.announce" "$OUT9/announce-tc-r1-w2.txt"
out="$(python3 "$I/test/f1-fleet.py" build "$OUT9" - master:tc-r1-m:10.128.0.2 worker:tc-r1-w:10.128.0.3 worker:tc-r1-w2:10.128.0.4 2>&1)"; rcb=$?
chk "the operator builds a fleet list of three nodes from three announcements: the master first, the wg addresses 10.10.0.1 to 10.10.0.3" $([ $rcb = 0 ] && grep -q 'fleet.tsv written (3 nodes' <<<"$out" && [ "$(grep -c . "$OUT9/fleet.tsv")" = 4 ] && grep -qP "^tc-r1-w2\tworker\t10\.10\.0\.3\t" "$OUT9/fleet.tsv"; echo $?)
for n in m3 w3 x3; do cp "$OUT9/fleet.tsv" "$W/$n/sd/fleet"; done; wait
chk "all three nodes join the fleet and exit 0" $([ "$(cat $W/m3/rc)" = 0 ] && [ "$(cat $W/w3/rc)" = 0 ] && [ "$(cat $W/x3/rc)" = 0 ]; echo $?)
chk "the master knows two workers, and each node has the TWO others as wg0 peers" $(ok=0; [ "$(cat $W/m3/run/workers)" = 2 ] || ok=1; for n in m3 w3 x3; do [ "$(grep -c ' allowed-ips ' $W/$n/sd/net.log)" = 2 ] || ok=1; done; echo $ok)
chk "with two workers the replication is two (min(workers, 2))" $(python3 -c 'import sys,xml.etree.ElementTree as E; p={(x.findtext("name") or "").strip():(x.findtext("value") or "").strip() for x in E.parse(sys.argv[1]).getroot().findall("property")}; sys.exit(0 if p.get("dfs.replication")=="2" else 1)' "$W/m3/run/conf/hdfs-site.xml"; echo $?)
for n in "m3 tc-r1-m" "w3 tc-r1-w" "x3 tc-r1-w2"; do set -- $n; cp "$W/$1/sd/put.final" "$OUT9/final-$2.txt"; done
out="$(python3 "$I/test/f1-fleet.py" final "$OUT9" tc-r1-m tc-r1-w tc-r1-w2 2>&1)"; chk "the operator verifies the three final quotes: the same fleet event in all three logs" $([ $? = 0 ] && grep -q 'FLEET-DIGEST-EQUAL: all 3 nodes' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" final "$OUT9" tc-r1-m tc-r1-w 2>&1)"; chk "fault: the final quotes of only two of the three nodes are NOT accepted (every node of fleet.tsv is checked)" $([ $? != 0 ] && grep -q 'every node of the fleet must be checked' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" build "$W/opout9" - worker:tc-r1-w:10.128.0.3 master:tc-r1-m:10.128.0.2 2>&1)"; chk "fault: a fleet list whose first node is not the master is refused" $([ $? != 0 ] && grep -q 'exactly one master' <<<"$out"; echo $?)
out="$(python3 "$I/test/f1-fleet.py" reference "$OUT9" tc-img-test-3 c3-standard-4 tc-r1-m tc-r1-w tc-r1-w2 2>&1)"; REF9="$OUT9/reference-values.json"
out="$(python3 "$I/test/f1-fleet.py" enforce "$OUT9" "$REF9" 2>&1)"; chk "the reference values of the three nodes enforce all three (ENFORCE-OK: all 3 nodes)" $([ $? = 0 ] && grep -q 'ENFORCE-OK: all 3 nodes' <<<"$out"; echo $?)
rm -rf "$W/opout10"; cp -r "$OUT9" "$W/opout10"; rm "$W/opout10/final-tc-r1-w2.txt"
out="$(python3 "$I/test/f1-fleet.py" enforce "$W/opout10" "$REF9" 2>&1)"; chk "fault: the third node without its quote B is refused by name (E1)" $([ $? != 0 ] && grep -q 'E1 tc-r1-w2' <<<"$out"; echo $?)
python3 - "$REF9" "$W/ref9-bad.json" <<'PYX'
import json, sys
d = json.load(open(sys.argv[1])); d["stable_events"]["tc-conf"] = "11" * 48; json.dump(d, open(sys.argv[2], "w"))
PYX
rm -rf "$W/opout11"; mkdir "$W/opout11"; cp "$OUT9"/announce-*.txt "$W/opout11/"
out="$(python3 "$I/test/f1-fleet.py" build "$W/opout11" "$W/ref9-bad.json" master:tc-r1-m:10.128.0.2 worker:tc-r1-w:10.128.0.3 worker:tc-r1-w2:10.128.0.4 2>&1)"; chk "fault: building the three-node fleet against reference values that do not match is refused, naming the first node" $([ $? != 0 ] && grep -q 'is refused, it does not match the reference values' <<<"$out" && [ ! -f "$W/opout11/fleet.tsv" ]; echo $?)
FS_KEEP="$FS"; FS="$(sha384sum $OUT9/fleet.tsv | cut -d' ' -f1)"; rm -rf "$W/rep"; mkdir -p "$W/rep"; cp "$OUT9/fleet.tsv" "$W/rep/"
mkrep tc-r1-m master locked; mkrep tc-r1-w worker locked; mkrep tc-r1-w2 worker locked; sed -i 's/^wg_peers=1/wg_peers=2/' "$W"/rep/report-tc-r1-*.txt
out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" locked tc-img-test-1 tc-r1-m tc-r1-w tc-r1-w2 2>&1)"; chk "the reports of three nodes are accepted: each has the two others as peers (REPORT-OK: all 3 nodes)" $([ $? = 0 ] && grep -q 'REPORT-OK: all 3 nodes' <<<"$out"; echo $?)
sed -i 's/^wg_peers=2/wg_peers=1/' "$W/rep/report-tc-r1-w2.txt"; out="$(python3 "$I/test/f1-fleet.py" report "$W/rep" locked tc-img-test-1 tc-r1-m tc-r1-w tc-r1-w2 2>&1)"; chk "fault: a worker that has only one peer in a fleet of three is refused (the mesh is incomplete)" $([ $? != 0 ] && grep -q 'tc-r1-w2: wg_peers' <<<"$out"; echo $?)
FS="$FS_KEEP"
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
mknode x; touch "$W/x/sd/peers-refuse"; startnode x tc-f1-x; waitfile "$W/x/sd/put.announce"; fleetwith good x tc-f1-x > "$W/x/sd/fleet"; wait; out="$(cat $W/x/out.txt)"
chk "fault: a peer whose quote the check refuses stops this node before WireGuard and Hadoop (no wg0 peer, no fleet event, no final quote)" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "TC-FLEET-FAIL: a node of fleet.tsv is not an attested TDX VM of this image" <<<"$out" && ! grep -q ' allowed-ips ' "$W/x/sd/net.log" 2>/dev/null && ! grep -q "^fleet" "$W/x/run/rtmr3-events.tsv" && [ ! -e "$W/x/sd/put.final" ]; echo $?)
refuse "the list has no header line" noheader "does not start with"
refuse "the list has fewer than two nodes" onenode "fewer than two"
refuse "the list has two masters" twomasters "exactly one master"
refuse "a name appears twice" dupname "appears twice"
refuse "a role is neither master nor worker" badrole "malformed"
refuse "an address is not a 10.10.0.x address" badaddr "malformed"
refuse "a key field is not plain base64 (a command in it is refused and NOT run)" badkey "malformed"; chk "control: nothing in the key field was executed" $([ ! -e /tmp/f1-pwned ]; echo $?)
mknode x; FWAIT=2 startnode x tc-f1-x; wait; out="$(cat $W/x/out.txt)"; chk "fault: no fleet list within the wait: the node stops" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "no fleet list" <<<"$out"; echo $?)
mknode x; rm -f "$W/x/run/measure-done"; startnode x tc-f1-x; wait; out="$(cat $W/x/out.txt)"; chk "fault: the measurement has not finished: the node does not even make keys" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "measurement has not finished" <<<"$out" && [ ! -f "$W/x/run/sign.key" ]; echo $?)
mknode x; rm -f "$W/x/run/measure-done"; FAKE_NOHOST=1 startnode x tc-f1-x; wait; NH=tc-f1-x
chk "a machine whose own name does not resolve (no guest agent) gets it into /etc/hosts at boot, by tc-fleet.sh, before any Hadoop daemon" $(grep -qx "127.0.1.1 $NH" "$W/x/root/etc/hosts" 2>/dev/null; echo $?)
mknode x; rm -f "$W/x/run/measure-done"; startnode x tc-f1-x; wait
chk "control: a machine whose name resolves is left alone (no line is added)" $(! grep -q "127.0.1.1" "$W/x/root/etc/hosts" 2>/dev/null; echo $?)
# Work item, change 1: the host name and /etc/hosts of a node whose /etc is read-only (a locked image)
chk "control: with a writable /etc nothing is mounted (the line is appended)" $([ ! -e "$W/x/sd/mount.log" ]; echo $?)
mknode x; FAKE_HOSTNAME=ro startnode x tc-f1-x; wait; out="$(cat $W/x/out.txt)"; chk "fault: the kernel call for the host name is refused: the node stops and says so, and does not go on under the old name" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "could not set the host name to tc-f1-x" <<<"$out"; echo $?)
mknode x; FAKE_HOSTNAME=revert startnode x tc-f1-x; wait; out="$(cat $W/x/out.txt)"; chk "fault: the call returns 0 but the name does not change (what hostnamectl --transient did): the node stops, and the message names the name it has" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "the host name is tc-builder after it was set to tc-f1-x" <<<"$out"; echo $?)
mknode x; printf '127.0.0.1 localhost\n' > "$W/x/root/etc/hosts"; FAKE_NOHOST=1 TC_ETC_READONLY=1 startnode x tc-f1-x; wait
chk "a read-only /etc/hosts: the file is made in the run folder (the old lines and the 127.0.1.1 line for this node) and bound over /etc/hosts, and the file in /etc is not changed" $(grep -qx "mount --bind $W/x/run/hosts $W/x/root/etc/hosts" "$W/x/sd/mount.log" && grep -qx "127.0.1.1 tc-f1-x" "$W/x/run/hosts" && grep -qx "127.0.0.1 localhost" "$W/x/run/hosts" && ! grep -q "127.0.1.1" "$W/x/root/etc/hosts"; echo $?)
mknode x; printf '127.0.0.1 localhost\n' > "$W/x/root/etc/hosts"; FAKE_NOHOST=1 TC_ETC_READONLY=1 FAKE_MOUNT_FAIL=1 startnode x tc-f1-x; wait; out="$(cat $W/x/out.txt)"; chk "fault: the bind of /etc/hosts fails: the node stops and says so" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "could not add tc-f1-x to /etc/hosts, which is read-only" <<<"$out"; echo $?)
mknode x; ( env TC_ROOT="$W/x/root" TC_RUN="$W/x/run" TC_LIB="$W/lib" TC_META=http://meta TC_QUOTE=/bin/false TC_POLL=1 FAKE_SD="$W/x/sd" FAKE_NAME=tc-f1-x TC_RTMR3="$W/x/rtmr3.bin" bash "$I/rootfs/usr/local/lib/tc/tc-fleet.sh" > "$W/x/out.txt" 2>&1; echo $? > "$W/x/rc" ); out="$(cat $W/x/out.txt)"; chk "fault: no quote can be made: the node stops" $([ "$(cat $W/x/rc)" != 0 ] && grep -q "could not make the quote" <<<"$out"; echo $?)
# ---------------------------------------------------------------- C. the bake and the unit files
echo "=== C. the bake script and the unit files"
SD="$W/bsd"; mkdir -p "$SD"; cat > "$STUB/systemctl" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; case "$1" in daemon-reload) echo reload >> "$SD/sc.log" ;; enable) [ -f "$SD/enable_fails" ] && exit 1; echo "enable $2" >> "$SD/sc.log" ;; esac
EOS
printf '#!/usr/bin/env bash\n[ -f "${FAKE_SD:?}/analyze_warns" ] && echo "/usr/local/lib/tc/units/tc-fleet.service:5: Unknown key name '"'"'ConditionPathExists'"'"' in section '"'"'Service'"'"', ignoring."\nexit 0\n' > "$STUB/systemd-analyze"; chmod +x "$STUB/systemctl" "$STUB/systemd-analyze"
BK="$W/bk"; rm -rf "$BK"; mkdir -p "$BK"; cp -r "$KIT/ops" "$KIT/attest" "$BK/"; printf 'cafe0000cafe0000cafe0000cafe0000cafe0000\n' > "$BK/COMMIT"   # a kit that is built from a named commit (step R4.2): the bake refuses a kit without one
mkbake() { rm -rf "$W/br" "$SD"; mkdir -p "$SD"; BR="$W/br"; for d in usr/local/lib/tc/units etc/tc/crawl etc/systemd/system usr/bin usr/lib/jvm/java-11-openjdk-amd64 etc/java-11-openjdk opt/hadoop/etc/hadoop opt/tc/nutch; do mkdir -p "$BR/$d"; done
  cp "$I"/rootfs/usr/local/lib/tc/tc-measure.sh "$I"/rootfs/usr/local/lib/tc/tc-extend.sh "$KIT/attest/measure/treehash.sh" "$KIT/attest/measure/rtmr3_replay.py" "$BR/usr/local/lib/tc/"; cp "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" "$BR/usr/local/lib/tc/"; chmod +x "$BR"/usr/local/lib/tc/*
  cp "$I/rootfs/etc/tc/measured-paths-f03c.txt" "$BR/etc/tc/measured-paths.txt"; cp "$I/rootfs/etc/tc/crawl/"* "$BR/etc/tc/crawl/"; cp "$I/rootfs/etc/systemd/system/tc-measure.service" "$BR/etc/systemd/system/"
  echo o > "$BR/usr/bin/openssl"; echo w > "$BR/usr/bin/wg"; echo j > "$BR/usr/lib/jvm/java-11-openjdk-amd64/release"; echo c > "$BR/etc/java-11-openjdk/jvm.cfg"; echo f > "$BR/etc/tc/java-ca-fingerprints.txt"; echo x > "$BR/opt/hadoop/etc/hadoop/core-site.xml"; echo job > "$BR/opt/tc/nutch/apache-nutch-1.22.job"; }
bake() { out="$(env TC_ROOT="$BR" TC_SUDO="" FAKE_SD="$SD" bash "$I/build/tc-image-fleet.sh" "${BKIT:-$BK}" 2>&1)"; rc=$?; }
mkbake; bake; echo "$out" | tail -1 | cut -c1-100
chk "happy path: exit 0 and READY" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
chk "the fleet script, the export script, the quote helper, the templates and the 8 units are installed, and the units are enabled" $([ -x "$BR/usr/local/lib/tc/tc-fleet.sh" ] && [ -x "$BR/usr/local/lib/tc/tc-export.sh" ] && [ -x "$BR/usr/local/lib/tc/tc-quote.sh" ] && [ -f "$BR/etc/tc/fleet-props/hdfs-site.props" ] && [ "$(grep -c '^enable ' "$SD/sc.log")" = 8 ] && [ -f "$BR/usr/local/lib/tc/units/tc-fleet.service" ] && [ -f "$BR/usr/local/lib/tc/units/tc-export.service" ]; echo $?)
chk "the measured list has 15 entries, starting with source and ending with fleet-props" $(grep -q 'TC-LIST-OK: 15 entries' <<<"$out" && [ "$(awk -F'\t' '!/^#/ && NF>=2 {print $1}' "$BR/etc/tc/measured-paths.txt" | tail -1)" = fleet-props ] && [ "$(awk -F'\t' '!/^#/ && NF>=2 {print $1}' "$BR/etc/tc/measured-paths.txt" | head -1)" = source ]; echo $?)
chk "step R4.2: /etc/tc/source.txt holds the commit of the kit (one line, mode 0644)" $([ "$(cat "$BR/etc/tc/source.txt" 2>/dev/null)" = "commit cafe0000cafe0000cafe0000cafe0000cafe0000" ] && [ "$(stat -c %a "$BR/etc/tc/source.txt")" = 644 ]; echo $?)
abortb() { local label="$1" want="$2"; bake; chk "fault: $label" $([ $rc != 0 ] && grep -q "ABORT: .*$want" <<<"$out"; echo $?); }
mkbake; rm -f "$BR/usr/local/lib/tc/tc-crawl.sh"; abortb "the crawl is not in place" "run tc-image-crawl.sh first"
mkbake; rm -rf "$W/nokit"; cp -r "$BK" "$W/nokit"; rm -f "$W/nokit/COMMIT"; BKIT="$W/nokit" bake; chk "fault (R4.2): a kit with no COMMIT stops the bake, says why, and writes no source.txt" $([ $rc != 0 ] && grep -q 'SOURCE-STOP: no COMMIT file in the kit' <<<"$out" && [ ! -e "$BR/etc/tc/source.txt" ]; echo $?)
mkbake; rm -rf "$W/nokit"; cp -r "$BK" "$W/nokit"; echo "not-a-commit" > "$W/nokit/COMMIT"; BKIT="$W/nokit" bake; chk "fault (R4.2): a COMMIT that is not a commit id (not 40 or 64 hex characters) stops the bake" $([ $rc != 0 ] && grep -q 'is not a commit id' <<<"$out" && [ ! -e "$BR/etc/tc/source.txt" ]; echo $?)
mkbake; rm -rf "$W/nokit"; cp -r "$BK" "$W/nokit"; printf 'cafe0000cafe0000cafe0000cafe0000cafe0000\nextra\n' > "$W/nokit/COMMIT"; BKIT="$W/nokit" bake; chk "fault (R4.2): a COMMIT file with a second line stops the bake" $([ $rc != 0 ] && grep -q 'is not a commit id' <<<"$out"; echo $?)
mkbake; rm -rf "$W/nokit"; cp -r "$BK" "$W/nokit"; rm -f "$W/nokit/COMMIT"; BKIT="$W/nokit" ALLOW_NO_COMMIT=1 bake; chk "development build (R4.2): ALLOW_NO_COMMIT=1 records 'commit none' with a loud warning, so that a verifier that pins a commit refuses it" $([ $rc = 0 ] && grep -q 'WARNING: no COMMIT file' <<<"$out" && [ "$(cat "$BR/etc/tc/source.txt")" = "commit none" ]; echo $?)
mkbake; rm -rf "$W/badkit"; cp -r "$BK" "$W/badkit"; rm -f "$W/badkit/attest/quote.sh"; BKIT="$W/badkit" abortb "the quote helper is missing from the kit" "quote.sh"
mkbake; rm -rf "$W/badkit"; cp -r "$BK" "$W/badkit"; rm -f "$W/badkit/ops/image/rootfs/usr/local/lib/tc/units/tc-fleet.service"; BKIT="$W/badkit" abortb "the fleet unit is missing from the kit" "missing in"
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
U="$I/rootfs/usr/local/lib/tc/units"; ok=0; for u in tc-fleet tc-namenode tc-datanode tc-resourcemanager tc-nodemanager tc-hdfs-format tc-crawl tc-export; do python3 "$UV" "$U/$u.service" > "$W/k.$u" 2>&1 || { ok=1; cat "$W/k.$u"; }; done
chk "every key of the 8 units is in a section where systemd reads it" $ok
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
CR="$W/cr"; rm -rf "$CR"; mkdir -p "$CR/etc/tc/crawl" "$CR/opt/hadoop/bin" "$CR/opt/tc/nutch/bin" "$CR/run/tc" "$W/crsd"; cp "$I/rootfs/etc/tc/crawl/seeds.txt" "$CR/etc/tc/crawl/"; printf '{"version":2}' > "$CR/etc/tc/crawl/collection-policy.json"; sed 's/^WAIT_FOR_CLUSTER_SECONDS=600/WAIT_FOR_CLUSTER_SECONDS=2/' "$I/rootfs/etc/tc/crawl/params.env" > "$CR/etc/tc/crawl/params.env"
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
chk "each node ends with the instance name as its host name (cloud-init is off), set by the kernel call before it joins; hostnamectl --transient is not used, because it exited 0 and changed nothing on the first locked boot" $([ "$(cat "$W/m/sd/hostname.state")" = tc-f1-m ] && [ "$(cat "$W/w/sd/hostname.state")" = tc-f1-w ] && grep -qx 'hostname-set tc-f1-m' "$W/m/sd/hostname.log" && grep -qx 'hostname-set tc-f1-w' "$W/w/sd/hostname.log" && ! grep -q -- '--transient' "$W/m/sd/hostname.log" "$W/w/sd/hostname.log"; echo $?)
chk "the node's signing key is PKCS#8 (the form Java reads), and sign.pub is the public key that the announcement and fleet.tsv carry" $([ "$(head -1 $W/m/run/sign.key)" = "-----BEGIN PRIVATE KEY-----" ] && [ "$(cat $W/m/run/sign.pub)" = "$(attrval m sign)" ] && [ "$(openssl ec -in $W/m/run/sign.key -pubout -outform DER 2>/dev/null | base64 -w0)" = "$(cat $W/m/run/sign.pub)" ] && [ "$(stat -c %a $W/m/run/sign.pub)" = 644 ]; echo $?)
chk "both keys of the wrapper are FINAL in the rendered core-site.xml of every node (a later resource cannot switch the wrapper off), and nothing else is" $(for n in m w; do python3 - "$W/$n/run/conf/core-site.xml" <<'PYX' || { echo 1; exit; }
import sys, xml.etree.ElementTree as ET
fin = sorted((p.findtext("name") or "").strip() for p in ET.parse(sys.argv[1]).getroot().findall("property") if (p.findtext("final") or "").strip() == "true")
sys.exit(0 if fin == ["fs.AbstractFileSystem.hdfs.impl", "fs.hdfs.impl"] else 1)
PYX
done; echo 0)
chk "the rendered core-site.xml is the wrapped configuration: the attested file system for hdfs:// and for FileContext, and NO setting of the wrapper (it has none, so that no job file can change it)" $(for p in 'org.apache.nutch.attested.AttestedHdfsFileSystem' 'org.apache.nutch.attested.AttestedHdfs<'; do tr -d ' \n' < "$W/m/run/conf/core-site.xml" | grep -qF "$p" || { echo 1; exit; }; done; ! grep -q '<name>attested\.' "$W/m/run/conf/core-site.xml"; echo $?)
CR3="$W/cr3"; rm -rf "$CR3"; cp -r "$CR" "$CR3"; cp "$I/rootfs/etc/tc/crawl/params.env" "$CR3/etc/tc/crawl/params.env"
out="$(env TC_ROOT="$CR3" bash "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" --check-params 2>&1)"; rcv=$?; chk "the baked parameters are valid, and they hold the crawler's identity (name, a https page, the WARC software) with no trace of the old fork" $([ $rcv = 0 ] && grep -q "are valid" <<<"$out" && grep -q '^AGENT_URL=https://github.com/Heron-AI-Security$' "$I/rootfs/etc/tc/crawl/params.env" && ! grep -rqi 'antisource' "$I/rootfs/etc/tc/crawl"; echo $?)
for bad in "AGENT_URL=http://x.org/a|must be a plain https address" "AGENT_URL=https://a.org/b;touch/tmp/f2-pwned|not KEY=VALUE with a plain value" "AGENT_NAME=my bot|not KEY=VALUE with a plain value"; do v="${bad%%|*}"; w="${bad##*|}"; k="${v%%=*}"; grep -v "^$k=" "$I/rootfs/etc/tc/crawl/params.env" > "$CR3/etc/tc/crawl/params.env"; echo "$v" >> "$CR3/etc/tc/crawl/params.env"; out="$(env TC_ROOT="$CR3" bash "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" --check-params 2>&1)"; rcv=$?; chk "fault: $v is refused" $([ $rcv != 0 ] && grep -q "$w" <<<"$out" && [ ! -e /tmp/f2-pwned ]; echo $?); done
grep -v "^AGENT_URL=" "$I/rootfs/etc/tc/crawl/params.env" > "$CR3/etc/tc/crawl/params.env"; out="$(env TC_ROOT="$CR3" bash "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" --check-params 2>&1)"; rcv=$?; chk "fault: a params.env without the identity is refused (params.env lacks AGENT_URL)" $([ $rcv != 0 ] && grep -q "lacks AGENT_URL" <<<"$out"; echo $?)
chk "the driver hands the identity to Nutch with -D (it overrides the job's own configuration), and the crawl script receives it" $(grep -q 'http.agent.url=https://github.com/Heron-AI-Security' "$W/crsd/crawl.args" && grep -q 'warc.export.software=Apache-Nutch-CommonCrawl-fork-training-custody' "$W/crsd/crawl.args" && grep -q 'http.agent.name=training-custody-test-bot' "$W/crsd/crawl.args"; echo $?)
chk "dfsadmin is told to use the plain DistributedFileSystem (it refuses the wrapper), in the driver (twice) and in the check" $(grep -c 'dfsadmin -D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem' "$I/rootfs/usr/local/lib/tc/tc-crawl.sh" | grep -q '^2$' && grep -q 'dfsadmin -D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem' "$I/test/f1-check.sh"; echo $?)
KR="$W/kr"; rm -rf "$KR"; mkdir -p "$KR/etc/ssh" "$KR/var/lib/dbus" "$KR/var/lib/tc-crawl" "$KR/var/lib/tc" "$KR/etc/tc"; echo id > "$KR/etc/machine-id"; echo "crawl done x" > "$KR/var/lib/tc-crawl/done"; echo l > "$KR/etc/tc/measured-paths.txt"
out="$(env TC_ROOT="$KR" TC_SUDO="" bash "$I/build/tc-image-clean.sh" --this-machine-becomes-an-image 2>&1)"; chk "the cleaning removes the crawl marker (a builder that crawled must not make every fleet skip its crawl) and keeps the image's own files" $([ ! -e "$KR/var/lib/tc-crawl" ] && [ -f "$KR/etc/tc/measured-paths.txt" ]; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "REHEARSAL-PASS: two and three nodes run the real fleet script, the real operator script verifies them, and the bake and the units hold; every fault is refused; $PASS checks"; else echo "REHEARSAL-FAIL"; fi
[ "$FAILN" = 0 ]
REHEARSAL_END_MARK=1
