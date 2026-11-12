#!/usr/bin/env bash
# BENCHMARK ONLY (branch bench/layer-flag): rehearsal of the tc-bench-layers switch in tc-fleet.sh and tc-export.sh, with the stand-ins of f1-rehearse.sh (read from it,
# not copied, so that both stay the same). Two nodes form a fleet with the REAL tc-fleet.sh for each setting. With an unchanged tc-fleet.sh as the second argument, the
# default setting is also compared with it: the same rendered Hadoop configuration, the same network steps, the same events and the same output.
#   bash bench-flag-rehearse.sh KITDIR [UNCHANGED-tc-fleet.sh]
set -uo pipefail
ORIG="${2:-}"
# the stand-ins of f1-rehearse.sh: its lines from `set -uo pipefail` up to its section A (KIT, I, W, STUB, chk, the fake curl, wg, ip, quote and register, mknode, waitfile, attrval)
eval "$(sed -n '/^set -uo pipefail$/,/^# -* A\. two nodes form a fleet/p' "${1:?usage: $0 KITDIR [UNCHANGED-tc-fleet.sh]}/ops/image/test/f1-rehearse.sh" | sed '1d;$d')"
NEW="$I/rootfs/usr/local/lib/tc/tc-fleet.sh"
# the fake metadata server also answers tc-bench-layers (from the node's sd/bench), and a fake nft records the firewall rule
mv "$STUB/curl" "$STUB/curl.f1"
cat > "$STUB/curl" <<'EOS'
#!/usr/bin/env bash
case "${@: -1}" in */instance/attributes/tc-bench-layers) [ -s "${FAKE_SD:?}/bench" ] && { cat "$FAKE_SD/bench"; exit 0; }; exit 22 ;; esac
exec "$(dirname "$0")/curl.f1" "$@"
EOS
cat > "$STUB/nft" <<'EOS'
#!/usr/bin/env bash
# a node's sd/nofirewall stands for an image without the host firewall (no table inet tc): "nft list chain" fails, as on such a node
[ "$1" = list ] && { [ -e "${FAKE_SD:?}/nofirewall" ] && exit 1; exit 0; }
echo "nft $*" >> "${FAKE_SD:?}/net.log"
EOS
chmod +x "$STUB/curl" "$STUB/nft"
startn() { local n="$W/$1"; ( env TC_ROOT="$n/root" TC_RUN="$n/run" TC_LIB="$W/lib" TC_META=http://meta TC_QUOTE="$W/quote.sh" TC_POLL=1 TC_FLEET_WAIT=30 FAKE_SD="$n/sd" FAKE_NAME="$2" FAKE_REG="$n/rtmr3.bin" TC_RTMR3="$n/rtmr3.bin" TC_WRITE="python3 $W/fakewrite.py $n/rtmr3.bin" bash "$3" > "$n/out.txt" 2>&1; echo $? > "$n/rc" ) & }
fleet2() { # TAG SETTING SCRIPT: a fleet of two, $W/TAG-m (master, VPC 10.128.0.2) and $W/TAG-w (worker, 10.128.0.3); SETTING "" leaves tc-bench-layers unset
  local t="$1" s="$2" sh="$3" OP="$W/op-$1"; rm -rf "$OP"; mkdir -p "$OP"; mknode "$t-m"; mknode "$t-w"
  [ -z "$s" ] || { printf '%s\n' "$s" > "$W/$t-m/sd/bench"; printf '%s\n' "$s" > "$W/$t-w/sd/bench"; }
  startn "$t-m" tc-f1-m "$sh"; startn "$t-w" tc-f1-w "$sh"
  waitfile "$W/$t-m/sd/put.announce" && waitfile "$W/$t-w/sd/put.announce" || { wait; return 1; }
  cp "$W/$t-m/sd/put.announce" "$OP/announce-tc-f1-m.txt"; cp "$W/$t-w/sd/put.announce" "$OP/announce-tc-f1-w.txt"
  python3 "$I/test/f1-fleet.py" build "$OP" tc-f1-m 10.128.0.2 tc-f1-w 10.128.0.3 > "$OP/build.txt" 2>&1 || { wait; return 1; }
  for n in m w; do cp "$OP/fleet-quotes.json" "$W/$t-$n/sd/quotes"; cp "$OP/fleet.tsv" "$W/$t-$n/sd/fleet"; done; wait
}
events() { cut -f1 "$W/$1/run/rtmr3-events.tsv" | tr '\n' ' '; }
digest() { awk -F'\t' -v e="$2" '$1==e {print $2}' "$W/$1/run/rtmr3-events.tsv"; }
sha384() { printf '%s\n' "$1" | sha384sum | cut -d' ' -f1; }
wrapper() { grep -q 'AttestedHdfsFileSystem' "$W/$1/run/conf/core-site.xml"; }

echo "=== 1. default (tc-bench-layers not set): exactly as before, no bench-layers event"
fleet2 def "" "$NEW"; out="$(cat "$W/def-m/out.txt" "$W/def-w/out.txt" "$W/op-def/build.txt" 2>/dev/null)"
chk "both nodes join the fleet and exit 0, with the usual message" $([ "$(cat $W/def-m/rc)" = 0 ] && [ "$(cat $W/def-w/rc)" = 0 ] && grep -q 'nodes, wg0 up, configuration rendered' "$W/def-m/out.txt" && ! grep -q BENCHMARK "$W/def-m/out.txt"; echo $?)
chk "no bench-layers event: the log holds the image's events, fleet and fleet-conf only" $([ "$(events def-m)" = "source tc-lib tc-conf nutch-deploy fleet fleet-conf " ]; echo $?)
chk "wg0 is set up and the wrapper is in the rendered core-site.xml; no firewall rule is added" $(grep -q '^ip addr add 10.10.0.1/24 dev wg0' "$W/def-m/sd/net.log" && wrapper def-m && wrapper def-w && ! grep -q '^nft' "$W/def-m/sd/net.log"; echo $?)

if [ -n "$ORIG" ]; then
  echo "=== 2. default compared with the unchanged tc-fleet.sh ($ORIG)"
  fleet2 org "" "$ORIG"
  chk "the unchanged script forms the same fleet" $([ "$(cat $W/org-m/rc)" = 0 ] && [ "$(cat $W/org-w/rc)" = 0 ]; echo $?)
  chk "the rendered Hadoop configuration is byte for byte the same, on both nodes" $(diff -r "$W/org-m/run/conf" "$W/def-m/run/conf" >/dev/null && diff -r "$W/org-w/run/conf" "$W/def-w/run/conf" >/dev/null; echo $?)
  norm() { sed -E "s|$W/(org|def)-|NODE-|g; s/[A-Za-z0-9+\/]{43}=/KEY/g" "$1"; }
  chk "the network steps are the same (the node's folder and the keys, new on every boot, aside)" $(diff <(norm "$W/org-m/sd/net.log") <(norm "$W/def-m/sd/net.log") >/dev/null && diff <(norm "$W/org-w/sd/net.log") <(norm "$W/def-w/sd/net.log") >/dev/null; echo $?)
  chk "the node's output is the same, line for line" $(diff <(norm "$W/org-m/out.txt") <(norm "$W/def-m/out.txt") >/dev/null && diff <(norm "$W/org-w/out.txt") <(norm "$W/def-w/out.txt") >/dev/null; echo $?)
  chk "the measured events are the same events, and fleet-conf has the same digest" $([ "$(events org-m)" = "$(events def-m)" ] && [ "$(digest org-m fleet-conf)" = "$(digest def-m fleet-conf)" ]; echo $?)
fi

echo "=== 2b. fleet-wireguard-signing set explicitly: the same as not set"
fleet2 exp fleet-wireguard-signing "$NEW"
chk "both nodes join; no bench-layers event; wg0 and the wrapper as in the default; the same rendered configuration" $([ "$(cat $W/exp-m/rc)" = 0 ] && [ "$(cat $W/exp-w/rc)" = 0 ] && [ "$(events exp-m)" = "$(events def-m)" ] && wrapper exp-m && grep -q '^ip addr add 10.10.0.1/24 dev wg0' "$W/exp-m/sd/net.log" && diff -r "$W/exp-m/run/conf" "$W/def-m/run/conf" >/dev/null; echo $?)

echo "=== 3. fleet-wireguard: wg0 as before, the wrapper left out of the rendered configuration only"
fleet2 ns fleet-wireguard "$NEW"
chk "both nodes join the fleet; the event bench-layers (the SHA-384 of 'fleet-wireguard') is measured before the announcement" $([ "$(cat $W/ns-m/rc)" = 0 ] && [ "$(cat $W/ns-w/rc)" = 0 ] && [ "$(events ns-m)" = "source tc-lib tc-conf nutch-deploy bench-layers fleet fleet-conf " ] && [ "$(digest ns-m bench-layers)" = "$(sha384 fleet-wireguard)" ] && grep -q 'bench-layers' <(python3 -c 'import base64,sys; print(base64.b64decode([l for l in open(sys.argv[1]) if l.startswith("log_b64=")][0][8:].strip()).decode())' "$W/ns-m/sd/put.announce") && grep -q 'BENCHMARK bench-layers fleet-wireguard, wg0 up' "$W/ns-m/out.txt"; echo $?)
chk "no wrapper in core-site.xml on either node, wg0 still set up, the measured template unchanged" $(! wrapper ns-m && ! wrapper ns-w && grep -q 'hdfs://10.10.0.1:9000' "$W/ns-m/run/conf/core-site.xml" && grep -q '^ip addr add 10.10.0.1/24 dev wg0' "$W/ns-m/sd/net.log" && grep -q 'AttestedHdfsFileSystem' "$W/ns-m/root/etc/tc/fleet-props/core-site.props"; echo $?)
chk "the rendered configuration is still measured (fleet-conf), and differs from the default's" $([ -n "$(digest ns-m fleet-conf)" ] && [ "$(digest ns-m fleet-conf)" != "$(digest def-m fleet-conf)" ]; echo $?)

echo "=== 4. fleet: no mesh, Hadoop on the VPC addresses, the firewall opened to the other node only"
fleet2 nw fleet "$NEW"
chk "both nodes join the fleet; the event bench-layers is the SHA-384 of 'fleet'" $([ "$(cat $W/nw-m/rc)" = 0 ] && [ "$(cat $W/nw-w/rc)" = 0 ] && [ "$(digest nw-m bench-layers)" = "$(sha384 fleet)" ] && grep -q 'BENCHMARK bench-layers fleet, no wg0' "$W/nw-m/out.txt"; echo $?)
chk "no wg or ip command at all" $(! grep -qE '^(wg set|ip )' "$W/nw-m/sd/net.log" 2>/dev/null && ! grep -qE '^(wg set|ip )' "$W/nw-w/sd/net.log" 2>/dev/null; echo $?)
chk "the firewall accepts the OTHER node's VPC address only" $(grep -qx 'nft add rule inet tc input ip saddr { 10.128.0.3 } accept' "$W/nw-m/sd/net.log" && grep -qx 'nft add rule inet tc input ip saddr { 10.128.0.2 } accept' "$W/nw-w/sd/net.log"; echo $?)
chk "Hadoop: the master's VPC address everywhere, each node bound to its own, no wrapper" $(grep -q 'hdfs://10.128.0.2:9000' "$W/nw-m/run/conf/core-site.xml" && grep -q 'hdfs://10.128.0.2:9000' "$W/nw-w/run/conf/core-site.xml" && grep -q '10.128.0.3:9866' "$W/nw-w/run/conf/hdfs-site.xml" && ! grep -q '10\.10\.0\.' "$W/nw-w/run/conf/hdfs-site.xml" && ! wrapper nw-m; echo $?)

echo "=== 4b. fleet on a node without the host firewall (no table inet tc, as in an image without the lock step)"
mknode nf-m; mknode nf-w; for n in nf-m nf-w; do printf 'fleet\n' > "$W/$n/sd/bench"; touch "$W/$n/sd/nofirewall"; done
OP="$W/op-nf"; rm -rf "$OP"; mkdir -p "$OP"; startn nf-m tc-f1-m "$NEW"; startn nf-w tc-f1-w "$NEW"; waitfile "$W/nf-m/sd/put.announce"; waitfile "$W/nf-w/sd/put.announce"
cp "$W/nf-m/sd/put.announce" "$OP/announce-tc-f1-m.txt"; cp "$W/nf-w/sd/put.announce" "$OP/announce-tc-f1-w.txt"; python3 "$I/test/f1-fleet.py" build "$OP" tc-f1-m 10.128.0.2 tc-f1-w 10.128.0.3 >/dev/null 2>&1
for n in m w; do cp "$OP/fleet-quotes.json" "$W/nf-$n/sd/quotes"; cp "$OP/fleet.tsv" "$W/nf-$n/sd/fleet"; done; wait
chk "both nodes join the fleet, add no rule and say that there is no firewall to open" $([ "$(cat $W/nf-m/rc)" = 0 ] && [ "$(cat $W/nf-w/rc)" = 0 ] && ! grep -q '^nft add' "$W/nf-m/sd/net.log" 2>/dev/null && grep -q 'no host firewall' "$W/nf-m/out.txt" && grep -q 'hdfs://10.128.0.2:9000' "$W/nf-w/run/conf/core-site.xml"; echo $?)

echo "=== 4c. the isolated settings (branch bench/isolated-flag): at most one of receipts, WireGuard, signing"
for st in all-off receipts-only wireguard-only signing-only; do t="is${st%%-*}"; fleet2 "$t" "$st" "$NEW"
  chk "$st: both nodes join the fleet; the event bench-layers is the SHA-384 of '$st'" $([ "$(cat $W/$t-m/rc)" = 0 ] && [ "$(cat $W/$t-w/rc)" = 0 ] && [ "$(digest $t-m bench-layers)" = "$(sha384 $st)" ] && [ "$(cat $W/$t-m/run/bench-layers)" = "$st" ]; echo $?)
  case "$st" in
    wireguard-only) chk "$st: wg0 set up, no wrapper" $(grep -q '^ip addr add 10.10.0.1/24 dev wg0' "$W/$t-m/sd/net.log" && grep -q 'hdfs://10.10.0.1:9000' "$W/$t-m/run/conf/core-site.xml" && ! wrapper $t-m && ! wrapper $t-w; echo $?) ;;
    signing-only)   chk "$st: no wg0, Hadoop on the VPC addresses, the wrapper IN core-site.xml on both nodes" $(! grep -qE '^(wg set|ip )' "$W/$t-m/sd/net.log" 2>/dev/null && grep -q 'hdfs://10.128.0.2:9000' "$W/$t-w/run/conf/core-site.xml" && wrapper $t-m && wrapper $t-w; echo $?) ;;
    *)              chk "$st: no wg0, Hadoop on the VPC addresses, no wrapper (as fleet)" $(! grep -qE '^(wg set|ip )' "$W/$t-m/sd/net.log" 2>/dev/null && grep -q 'hdfs://10.128.0.2:9000' "$W/$t-w/run/conf/core-site.xml" && ! wrapper $t-m && [ "$(cat $W/$t-m/run/conf/core-site.xml)" = "$(cat $W/nw-m/run/conf/core-site.xml)" ]; echo $?) ;;
  esac
done

echo "=== 5. what the switch refuses"
mknode bad; printf 'all\n' > "$W/bad/sd/bench"; startn bad tc-f1-m "$NEW"; wait
chk "fault: an unknown setting stops the node before any key or announcement" $([ "$(cat $W/bad/rc)" != 0 ] && grep -q "unknown tc-bench-layers 'all'" "$W/bad/out.txt" && [ ! -e "$W/bad/sd/put.announce" ]; echo $?)

echo "=== 6. the export of a benchmark run"
xp() { mkdir -p "$W/xs-$1"; date > "$W/xs-$1/crawl-done"; touch "$W/$2/run/role-master"
  env TC_ROOT="$W/$2/root" TC_RUN="$W/$2/run" TC_LIB="$W/lib" TC_META=http://meta TC_STATE="$W/xs-$1/state" TC_CRAWL_MARK="$W/xs-$1/crawl-done" TC_EXPORT_LOG="$W/xs-$1/log" TC_AS="" FAKE_SD="$W/$2/sd" bash "$I/rootfs/usr/local/lib/tc/tc-export.sh" 2>&1; }
out="$(xp nw nw-m)"; chk "a benchmark run makes no export and says so (tc/export-skipped), exit 0" $([ $? = 0 ] && grep -q 'TC-EXPORT-SKIPPED: benchmark run (bench-layers fleet): no export' <<<"$out" && [ -s "$W/nw-m/sd/put.export-skipped" ]; echo $?)
out="$(xp isall isall-m)"; chk "an all-off run makes no export either" $(grep -q 'TC-EXPORT-SKIPPED: benchmark run (bench-layers all-off): no export' <<<"$out"; echo $?)
out="$(xp def def-m)"; chk "a run with bench-layers fleet-wireguard-signing goes on to the export (here it stops later, on the missing stand-in crawl)" $(! grep -q 'SKIPPED' <<<"$out" && [ ! -e "$W/def-m/sd/put.export-skipped" ]; echo $?)

echo "bench-flag-rehearse: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ] && echo "BENCH-FLAG-REHEARSE-OK" || { echo "BENCH-FLAG-REHEARSE-FAILED ($FAILN)"; exit 1; }
