#!/usr/bin/env bash
# Step F1, the check on ONE fleet node after the fleet has formed (run as root over ssh):  sudo bash f1-check.sh master|worker
# Keys only in memory; the fleet event equals the SHA-384 of fleet.tsv; the log replays to the register of the final quote, which binds the node's keys and the log; wg0 has every other node as a peer and
# reaches it; the daemons of the role run and listen on the wg0 address; and on the master HDFS sees every worker and the crawl runs by itself and succeeds.
set -uo pipefail
ROLE="${1:?usage: $0 master|worker}"; HERE="$(cd "$(dirname "$0")" && pwd)"; RUN=/run/tc; REPLAY="$HERE/../../../attest/measure/rtmr3_replay.py"
bad=0; ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; bad=$((bad+1)); }
echo "f1-check: $(date -u +%FT%TZ) on $(hostname), role $ROLE"
echo "== the fleet unit and the keys"
[ "$(systemctl show tc-fleet.service -p Result --value)" = success ] && [ -f $RUN/fleet-done ] && ok "tc-fleet.service ended with success and the fleet is joined ($(cat $RUN/fleet-done))" || no "tc-fleet.service did not end with success (result '$(systemctl show tc-fleet.service -p Result --value)')"
[ "$(findmnt -n -o FSTYPE -T $RUN/sign.key 2>/dev/null)" = tmpfs ] && ok "the signing key and the WireGuard key are on a memory file system (tmpfs)" || no "the keys are not on tmpfs"
BODY="$(sed -n 2p $RUN/sign.key)"; WGK="$(cat $RUN/wg.key)"
# the patterns are built from two pieces so that THIS file never contains them (a search must not match itself), and the kit's own folder is left out
P1='BEGIN EC PRIV''ATE KEY'; P2='BEGIN PRIV''ATE KEY'
HITS="$( { grep -rIl --exclude-dir=f03 -e "$P1" -e "$P2" /etc /var /opt /home /root /usr/local /boot /srv 2>/dev/null; grep -rIlF --exclude-dir=f03 -e "$BODY" -e "$WGK" /etc /var /opt /home /root /usr/local /boot /srv 2>/dev/null; } | sort -u | head -5)"
[ -z "$HITS" ] && ok "a search of the disk (/etc /var /opt /home /root /usr/local /boot /srv) finds no private key and neither of this boot's key values" || no "private key material found on disk: $HITS"
echo "== the log, the fleet event and the final quote"
FD="$(awk -F'\t' '$1=="fleet" {print $2}' $RUN/rtmr3-events.tsv)"; [ -n "$FD" ] && [ "$FD" = "$(sha384sum $RUN/fleet.tsv | cut -d' ' -f1)" ] && ok "the event fleet equals the SHA-384 of fleet.tsv (${FD:0:16}...)" || no "the fleet event does not equal the SHA-384 of fleet.tsv"
[ "$(cut -f1 $RUN/rtmr3-events.tsv | tail -2 | tr '\n' ' ')" = "fleet fleet-conf " ] && ok "the last two events of the log are fleet and fleet-conf ($(wc -l < $RUN/rtmr3-events.tsv) events)" || no "the log does not end with fleet and fleet-conf"
RP="$(python3 "$REPLAY" $RUN/rtmr3-events.tsv $RUN/quote-final.bin 2>&1)"; printf '%s\n' "$RP" | grep -q 'chain consistent: True' && printf '%s\n' "$RP" | grep -q 'RTMR3 in quote: .* -> MATCH' && ok "the log's chain is consistent and replays to the RTMR3 of the final quote" || { printf '%s\n' "$RP" | tail -3 | sed 's/^/      /'; no "the log does not replay to the final quote's RTMR3"; }
python3 - "$RUN" <<'PYEOF' && ok "the final quote's REPORTDATA is the SHA-512 of a binding text that holds this node's two public keys and the SHA-512 of this log" || no "the final quote does not bind the keys and the log"
import hashlib, subprocess, sys
run = sys.argv[1]; q = open(run + "/quote-final.bin", "rb").read(); b = open(run + "/binding-final.txt", "rb").read()
assert q[568:632] == hashlib.sha512(b).digest(), "REPORTDATA differs"
d = dict(l.split("=", 1) for l in b.decode().splitlines()[1:])
pub = subprocess.run(["openssl", "ec", "-in", run + "/sign.key", "-pubout", "-outform", "DER"], capture_output=True).stdout
import base64
assert d["sign"] == base64.b64encode(pub).decode(), "signing key differs"
assert d["wg"] == subprocess.run(["wg", "pubkey"], input=open(run + "/wg.key", "rb").read(), capture_output=True).stdout.decode().strip(), "wg key differs"
assert d["log"] == hashlib.sha512(open(run + "/rtmr3-events.tsv", "rb").read()).hexdigest(), "log hash differs"
PYEOF
echo "== the mesh"
NP="$(wg show wg0 peers 2>/dev/null | wc -l)"; NN="$(grep -v '^#' $RUN/fleet.tsv | grep -c .)"; [ "$NP" = $((NN-1)) ] && ok "wg0 has $NP peer(s), every other node of the fleet" || no "wg0 has $NP peers, expected $((NN-1))"
for ip in $(grep -v '^#' $RUN/fleet.tsv | cut -f3); do [ "$ip" = "$(ip -4 -o addr show wg0 | awk '{print $4}' | cut -d/ -f1)" ] && continue; ping -c 2 -W 3 "$ip" >/dev/null 2>&1 && ok "ping over wg0 to $ip works" || no "no ping over wg0 to $ip"; done
BOOTE="$(date -d "$(uptime -s)" +%s)"; if [ "$ROLE" = master ]; then VF=/var/lib/hadoop/namenode/current/VERSION; WHAT="NameNode namespace"; else VF=/var/lib/hadoop/datanode/current/VERSION; WHAT="DataNode storage"; fi
VT="$(stat -c %Y "$VF" 2>/dev/null)"; [ -n "$VT" ] && [ "$VT" -ge "$BOOTE" ] && ok "the $WHAT was created during THIS boot ($(date -d @$VT +%T)), not inherited from the image" || no "the $WHAT is older than this boot (created $(date -d @${VT:-0} +%FT%T)): the image carries HDFS state of the builder"
echo "== the daemons of the role, bound to the wg0 address"
WGIP="$(ip -4 -o addr show wg0 | awk '{print $4}' | cut -d/ -f1)"
if [ "$ROLE" = master ]; then UNITS="tc-namenode tc-resourcemanager"; PORTS="9000 9870 8030 8031 8032 8033 8088"; else UNITS="tc-datanode tc-nodemanager"; PORTS="9866 9864 9867 8042 8040"; fi
for u in $UNITS; do [ "$(systemctl is-active $u.service)" = active ] && ok "$u is active" || no "$u is not active"; done
SS="$(ss -H -lntp 2>/dev/null)"; for p in $PORTS; do A="$(printf '%s\n' "$SS" | awk -v p=":$p" '$4 ~ (p "$") {print $4}' | head -1)"; [ -n "$A" ] && [ "${A%:*}" = "$WGIP" ] && ok "port $p listens on the wg0 address $WGIP" || no "port $p: '$A' (expected $WGIP)"; done
printf '%s\n' "$SS" | grep java | awk '{print $4}' | grep -v "^$WGIP:" | sort -u | sed 's/^/   note: java also listens on /; s/$/ (for the firewall of phase 4)/'
if [ "$ROLE" = master ]; then
  echo "== the master: HDFS sees every worker, and the crawl runs by itself"
  NW="$(cat $RUN/workers)"; ENVV=(JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64 HADOOP_HOME=/opt/hadoop HADOOP_CONF_DIR=/run/tc/conf HADOOP_LOG_DIR=/var/log/hadoop NUTCH_LOG_DIR=/var/log/hadoop PATH=/opt/hadoop/bin:/usr/bin:/bin)
  t=0; until [ "$(runuser -u hadoop -- env "${ENVV[@]}" /opt/hadoop/bin/hdfs dfsadmin -D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem -report 2>/dev/null | grep -c '^Name:')" -ge "$NW" ]; do t=$((t+10)); [ $t -lt 300 ] || break; sleep 10; done
  LIVE="$(runuser -u hadoop -- env "${ENVV[@]}" /opt/hadoop/bin/hdfs dfsadmin -D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem -report 2>/dev/null | grep -c '^Name:')"; [ "$LIVE" -ge "$NW" ] && ok "HDFS reports $LIVE live DataNode(s) (the fleet has $NW worker(s))" || no "HDFS reports $LIVE live DataNodes, expected $NW"
  t=0; while [ "$(systemctl show tc-crawl.service -p ActiveState --value)" = activating ] || [ "$(systemctl show tc-crawl.service -p ActiveState --value)" = active ]; do t=$((t+30)); [ $t -lt 1800 ] || break; [ $((t % 60)) -eq 0 ] && echo "   still waiting for the crawl ($t s)"; sleep 30; done
  [ "$(systemctl show tc-crawl.service -p Result --value)" = success ] && [ -s /var/lib/tc-crawl/done ] && ok "the crawl ran by itself and ended with success: $(head -c 120 /var/lib/tc-crawl/done)" || { no "the crawl did not end with success (result '$(systemctl show tc-crawl.service -p Result --value)')"; tail -5 /var/log/hadoop/tc-crawl.log 2>/dev/null | cut -c1-220 | sed 's/^/      /'; }
fi
if [ $bad -eq 0 ]; then echo "F1-CHECK-OK role=$ROLE"; else echo "F1-CHECK-FAILED ($bad) role=$ROLE"; fi
[ $bad -eq 0 ]
