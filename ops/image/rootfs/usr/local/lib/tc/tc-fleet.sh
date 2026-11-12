#!/usr/bin/env bash
# Step F1, the boot flow of a fleet node. Runs once per boot as tc-fleet.service, as root, after the measurement and BEFORE any Hadoop daemon:
#  1. make the signing key (P-256, PKCS#8 PEM, the form FleetKeys reads) and the WireGuard key IN MEMORY (/run/tc, a RAM file system): no private key is ever written to disk;
#  2. make ONE TDX quote whose REPORTDATA is the SHA-512 of a binding text (node name, both public keys, SHA-512 of the RTMR3 event log), and publish it as the guest attribute tc/announce;
#  3. wait for the fleet list `tc-fleet` (instance metadata, set by the operator), check its format, and check that THIS node's own two keys are in it (else stop: the daemons do not start);
#     then mutual attestation: wait for the other nodes' announcements `tc-fleet-quotes` (set by the operator next to tc-fleet) and verify each one with tc-peer-verify.py (Intel chain,
#     its keys equal its row, the same TD and image as this node); one that fails stops this node before WireGuard and Hadoop, so a peer on wg0 is an attested node of this image;
#  4. extend RTMR3 with the event `fleet` (SHA-384 of fleet.tsv), bring up wg0 with the other nodes as peers, render the Hadoop configuration from fleet.tsv into /run/tc/conf (bound to the wg0 address),
#     and extend RTMR3 with the event `fleet-conf`;
#  5. mark the role (/run/tc/role-master or role-worker) for the units, and publish a second, final quote as tc/final.
# fleet.tsv: a line `# tc-fleet v1`, then one line per node, tab-separated: name, role (master|worker), wg address, endpoint (ip:port), signing public key (base64 DER), WireGuard public key.
# Hooks for the rehearsal only: TC_ROOT, TC_RUN, TC_LIB, TC_META, TC_QUOTE, TC_FLEET_WAIT, TC_POLL.
set -uo pipefail
R="${TC_ROOT:-}"; RUN="${TC_RUN:-$R/run/tc}"; LIB="${TC_LIB:-$R/usr/local/lib/tc}"; META="${TC_META:-http://169.254.169.254/computeMetadata/v1}"; QUOTE="${TC_QUOTE:-$LIB/tc-quote.sh}"
WAIT="${TC_FLEET_WAIT:-1800}"; POLL="${TC_POLL:-5}"; LOG="$RUN/rtmr3-events.tsv"
fail() { echo "TC-FLEET-FAIL: $*" >&2; exit 1; }
md() { curl -sf -H 'Metadata-Flavor: Google' "$META/$1"; }
put() { curl -sf -X PUT -H 'Metadata-Flavor: Google' --data-binary @"$2" "$META/instance/guest-attributes/tc/$1" >/dev/null; }
NAME="$(md instance/name)" || fail "no instance name from the metadata server"
# cloud-init is off, so nothing else gives this VM its name: the image keeps the builder's (tc-builder), systemd's static /etc/hostname beats the name that DHCP offers, and Hadoop
# then binds its ports to the VPC address instead of wg0 (found in the first debug fleet run). The instance name from the metadata is the only reliable source.
if [ "$(hostname 2>/dev/null)" != "$NAME" ]; then hostnamectl set-hostname "$NAME" 2>/dev/null || hostname "$NAME" 2>/dev/null || fail "could not set the host name to $NAME"; fi
# The guest agent is what writes this machine's own name into /etc/hosts, and the locked image has no guest agent; Hadoop's daemons look their own name up.
HN="$(hostname 2>/dev/null || true)"; if [ -n "$HN" ] && ! getent hosts "$HN" >/dev/null 2>&1; then printf '127.0.1.1 %s\n' "$HN" >> "$R/etc/hosts"; fi
[ -f "$RUN/measure-done" ] && [ -s "$LOG" ] || fail "the measurement has not finished (no $RUN/measure-done)"
# BENCHMARK ONLY (branch bench/layer-flag, never an approved custody image): which custody layers this fleet runs, for the per-layer performance
# measurements (docs/bench-layers.md). The settings are cumulative, each one the previous one plus one layer:
#   fleet                    the sealed fleet: Intel TDX VMs, the sealed and measured image (dm-verity), the encrypted scratch disk, attestation and mutual
#                            attestation, and the crawl with source receipts; NO WireGuard (Hadoop on the VPC addresses) and NO signing wrapper;
#   fleet-wireguard          fleet + the WireGuard mesh;
#   fleet-wireguard-signing  fleet-wireguard + the signing wrapper (sign on write, verify on read): every layer, as without this switch.
# and the ISOLATED settings (branch bench/isolated-flag), each the sealed fleet (TDX, dm-verity, the encrypted scratch disk, attestation and mutual attestation)
# with at most ONE of the three switchable layers on:
#   all-off                  no receipts, no WireGuard, no signing wrapper;
#   receipts-only            the crawl with source receipts; no WireGuard, no signing (the same layers as fleet, under its own name);
#   wireguard-only           the WireGuard mesh; no receipts, no signing;
#   signing-only             the signing wrapper; no receipts, no WireGuard.
# The encrypted scratch disk is set up in the initramfs, before this switch is read, so it is on in every setting.
# Read ONCE, here, from the instance metadata tc-bench-layers, and kept in /run/tc/bench-layers for the later steps. Absent or fleet-wireguard-signing: nothing
# else happens, and the node does exactly what it does without this switch (no event). fleet or fleet-wireguard is extended into RTMR3 as the event
# bench-layers BEFORE the announcement: every quote and every export of that run names it, and mutual attestation (the same measured events on every node)
# refuses a fleet whose nodes differ. A run whose log holds a bench-layers event is a benchmark, never a custody run.
LAYERS="$(md instance/attributes/tc-bench-layers 2>/dev/null)" || LAYERS=fleet-wireguard-signing
case "$LAYERS" in fleet|fleet-wireguard|fleet-wireguard-signing|all-off|receipts-only|wireguard-only|signing-only) ;; *) fail "unknown tc-bench-layers '$LAYERS' (fleet, fleet-wireguard, fleet-wireguard-signing, all-off, receipts-only, wireguard-only or signing-only)" ;; esac
printf '%s\n' "$LAYERS" > "$RUN/bench-layers"; chmod 0644 "$RUN/bench-layers"
if [ "$LAYERS" != fleet-wireguard-signing ]; then TC_LOG="$LOG" "$LIB/tc-extend.sh" bench-layers "$RUN/bench-layers" >/dev/null || fail "could not extend RTMR3 with the event bench-layers"; fi
WG=1; SIGN=1; case "$LAYERS" in fleet-wireguard|wireguard-only) SIGN=0 ;; fleet|all-off|receipts-only) WG=0; SIGN=0 ;; signing-only) WG=0 ;; esac   # receipts: tc-crawl.sh reads $RUN/bench-layers
umask 077
{ openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null | openssl pkcs8 -topk8 -nocrypt -out "$RUN/sign.key" 2>/dev/null; } || fail "could not make the signing key (PKCS#8, the form that the wrapper reads)"
SIGN_PUB="$(openssl ec -in "$RUN/sign.key" -pubout -outform DER 2>/dev/null | base64 -w0)"; [ -n "$SIGN_PUB" ] || fail "could not read the signing public key"
wg genkey > "$RUN/wg.key" 2>/dev/null || fail "could not make the WireGuard key"; WG_PUB="$(wg pubkey < "$RUN/wg.key" 2>/dev/null)"; [ -n "$WG_PUB" ] || fail "could not read the WireGuard public key"
printf '%s' "$SIGN_PUB" > "$RUN/sign.pub"; chmod 0644 "$RUN/sign.pub"   # the public half, for FleetKeys (the wrapper in every JVM)
chgrp hadoop "$RUN/sign.key" 2>/dev/null && chmod 0640 "$RUN/sign.key"
ccel() { # step P2/P6: the firmware boot event log (CCEL), published as guest attributes tc/ccel-0 ... tc/ccel-N, tc/ccel-sha256 and (last) tc/ccel-count, so that a verifier can read it without a login; never fatal
  local src="${TC_CCEL:-/sys/firmware/acpi/tables/data/CCEL}" n=0 f
  [ -r "$src" ] && [ -s "$src" ] || { echo "note: no boot event log at $src: it is not published" >&2; return 0; }
  rm -rf "$RUN/ccel"; mkdir -p "$RUN/ccel" || return 0
  split -b 12288 -d -a 3 "$src" "$RUN/ccel/part-" || { echo "note: could not split the boot event log" >&2; return 0; }
  for f in "$RUN"/ccel/part-*; do base64 -w0 "$f" > "$f.b64" && put "ccel-$n" "$f.b64" || { echo "note: could not publish the boot event log (chunk $n)" >&2; return 0; }; n=$((n+1)); done
  sha256sum < "$src" | cut -d' ' -f1 | tr -d '\n' > "$RUN/ccel/sha256" && put ccel-sha256 "$RUN/ccel/sha256"
  printf '%s' "$n" > "$RUN/ccel/count" && put ccel-count "$RUN/ccel/count"
  echo "published the boot event log: $(stat -c %s "$src") bytes in $n chunks (tc/ccel-count)"
}
announce() { # TAG: one quote that binds the name, both public keys and the log, published as a guest attribute
  local logsha; logsha="$(sha512sum "$LOG" | cut -d' ' -f1)"
  printf 'tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n' "$NAME" "$SIGN_PUB" "$WG_PUB" "$logsha" > "$RUN/binding-$1.txt"
  "$QUOTE" "$RUN/binding-$1.txt" "$RUN/quote-$1.bin" >/dev/null 2>&1 || fail "could not make the quote ($1)"
  { printf 'name=%s\nsign=%s\nwg=%s\nlog_sha512=%s\n' "$NAME" "$SIGN_PUB" "$WG_PUB" "$logsha"; printf 'quote_b64=%s\n' "$(base64 -w0 "$RUN/quote-$1.bin")"; printf 'log_b64=%s\n' "$(base64 -w0 "$LOG")"; } > "$RUN/attr-$1.txt"
  put "$1" "$RUN/attr-$1.txt" || echo "note: could not publish $1 to the guest attributes" >&2
}
announce announce; ccel; echo "announced: keys made in memory, one quote published (tc/announce)"
t=0; FLEET=""
until FLEET="$(md instance/attributes/tc-fleet)" && [ -n "$FLEET" ]; do t=$((t+POLL)); [ "$t" -lt "$WAIT" ] || fail "no fleet list (instance metadata tc-fleet) within $WAIT seconds"; sleep "$POLL"; done
printf '%s\n' "$FLEET" > "$RUN/fleet.tsv"; chmod 0644 "$RUN/fleet.tsv"
head -1 "$RUN/fleet.tsv" | grep -qx '# tc-fleet v1' || fail "fleet.tsv does not start with '# tc-fleet v1'"
ROWS="$(grep -v '^#' "$RUN/fleet.tsv" | grep -v '^$')"; NR="$(printf '%s\n' "$ROWS" | grep -c .)"; [ "$NR" -ge 2 ] || fail "fleet.tsv has fewer than two nodes"
printf '%s\n' "$ROWS" | awk -F'\t' 'NF!=6 {bad=1} $2!="master" && $2!="worker" {bad=1} $3 !~ /^10\.10\.0\.[0-9]+$/ {bad=1} $4 !~ /^[0-9.]+:[0-9]+$/ {bad=1} $5 !~ /^[A-Za-z0-9+\/=]+$/ || $6 !~ /^[A-Za-z0-9+\/=]+$/ {bad=1} END {exit bad}' || fail "a line of fleet.tsv is malformed (6 tab-separated fields, a role, a 10.10.0.x address, an ip:port, two base64 keys)"
[ "$(printf '%s\n' "$ROWS" | awk -F'\t' '$2=="master"' | wc -l)" = 1 ] || fail "fleet.tsv must have exactly one master"
[ "$(printf '%s\n' "$ROWS" | cut -f1 | sort -u | wc -l)" = "$NR" ] && [ "$(printf '%s\n' "$ROWS" | cut -f3 | sort -u | wc -l)" = "$NR" ] || fail "a name or an address appears twice in fleet.tsv"
OWN="$(printf '%s\n' "$ROWS" | awk -F'\t' -v n="$NAME" '$1==n')"; [ -n "$OWN" ] || fail "this node ($NAME) is not in fleet.tsv"
[ "$(printf '%s\n' "$OWN" | cut -f5)" = "$SIGN_PUB" ] && [ "$(printf '%s\n' "$OWN" | cut -f6)" = "$WG_PUB" ] || fail "this node's keys are not the keys listed for $NAME in fleet.tsv (a rebooted node makes new keys): stopping before Hadoop starts"
ROLE="$(printf '%s\n' "$OWN" | cut -f2)"; OWN_IP="$(printf '%s\n' "$OWN" | cut -f3)"; MASTER_IP="$(printf '%s\n' "$ROWS" | awk -F'\t' '$2=="master" {print $3}')"; NW="$(printf '%s\n' "$ROWS" | awk -F'\t' '$2=="worker"' | wc -l)"
# Mutual attestation: the operator only carries the announcements, it cannot make one, so it cannot slip in a node that is not an attested TDX VM of this image.
t=0; until md instance/attributes/tc-fleet-quotes > "$RUN/fleet-quotes.json" && [ -s "$RUN/fleet-quotes.json" ]; do t=$((t+POLL)); [ "$t" -lt "$WAIT" ] || fail "no peer announcements (instance metadata tc-fleet-quotes) within $WAIT seconds"; sleep "$POLL"; done
python3 "$LIB/tc-peer-verify.py" "$RUN/attr-announce.txt" "$RUN/fleet.tsv" "$RUN/fleet-quotes.json" "$RUN/peers.tsv" || fail "a node of fleet.tsv is not an attested TDX VM of this image: stopping before WireGuard and Hadoop"
TC_LOG="$LOG" "$LIB/tc-extend.sh" fleet "$RUN/fleet.tsv" >/dev/null || fail "could not extend RTMR3 with the fleet list"
if [ "$WG" = 1 ]; then
ip link add wg0 type wireguard 2>/dev/null; wg set wg0 private-key "$RUN/wg.key" listen-port 51820 || fail "could not configure wg0"
ip addr add "$OWN_IP/24" dev wg0 2>/dev/null; ip link set wg0 up || fail "could not bring wg0 up"
printf '%s\n' "$ROWS" | awk -F'\t' -v n="$NAME" '$1!=n' | while IFS=$'\t' read -r pn pr pip pep psign pwg; do wg set wg0 peer "$pwg" allowed-ips "$pip/32" endpoint "$pep" persistent-keepalive 10 || exit 1; done || fail "could not add the peers to wg0"
else
  # BENCHMARK ONLY (fleet), no mesh: Hadoop is bound to the VPC addresses (the endpoint column of fleet.tsv) instead of the wg0 ones, and the host firewall, which accepts
  # only wg0, is opened to the other nodes of fleet.tsv by their VPC address, and to nothing else.
  OWN_IP="$(printf '%s\n' "$OWN" | cut -f4 | cut -d: -f1)"; MASTER_IP="$(printf '%s\n' "$ROWS" | awk -F'\t' '$2=="master" {split($4, a, ":"); print a[1]}')"
  PEERS="$(printf '%s\n' "$ROWS" | awk -F'\t' -v n="$NAME" '$1!=n {split($4, a, ":"); printf "%s%s", s, a[1]; s = ", "}')"
  [ -n "$OWN_IP" ] && [ -n "$MASTER_IP" ] && [ -n "$PEERS" ] || fail "no VPC addresses in the endpoint column of fleet.tsv"
  # the host firewall (table inet tc, chain input) exists only in an image that the lock step made; without it nothing is filtered here and nothing needs opening
  if nft list chain inet tc input >/dev/null 2>&1; then nft add rule inet tc input ip saddr "{ $PEERS }" accept || fail "could not open the host firewall to the other fleet nodes"
  else echo "note: no host firewall (table inet tc) on this node: nothing to open for the other fleet nodes"; fi
fi
mkdir -p "$RUN/props" "$RUN/conf"; cp -a "$R/opt/hadoop/etc/hadoop/." "$RUN/conf/"
REPL=$(( NW > 2 ? 2 : NW )); [ "$REPL" -ge 1 ] || REPL=1
for f in core hdfs mapred yarn; do sed "s/@MASTER_IP@/$MASTER_IP/g; s/@BIND_IP@/$OWN_IP/g; s/@REPLICATION@/$REPL/g" "$R/etc/tc/fleet-props/$f-site.props" > "$RUN/props/$f-site.props" || fail "could not fill in $f-site.props"; done
if [ "$SIGN" = 0 ]; then
  # BENCHMARK ONLY (fleet, fleet-wireguard), no signing: the four lines that put the attested file system on hdfs:// are left out of THIS node's rendered configuration (the measured
  # template keeps them), so Hadoop uses plain HDFS; the rendered configuration is measured below as fleet-conf, as always.
  sed -i '/^fs\.hdfs\.impl=/d; /^fs\.AbstractFileSystem\.hdfs\.impl=/d; /^@final fs\.hdfs\.impl$/d; /^@final fs\.AbstractFileSystem\.hdfs\.impl$/d' "$RUN/props/core-site.props" || fail "could not leave the wrapper out of core-site.props"
  ! grep -q "Attested" "$RUN/props/core-site.props" || fail "the wrapper is still in core-site.props"
fi
python3 "$LIB/hadoop_conf.py" render "$RUN/props" "$RUN/conf" /unused >/dev/null || fail "could not render the Hadoop configuration"
chmod -R a+rX "$RUN/conf"; chmod 0755 "$RUN"
TC_LOG="$LOG" "$LIB/tc-extend.sh" fleet-conf "$RUN/conf" >/dev/null || fail "could not extend RTMR3 with the rendered configuration"
rm -f "$RUN/role-master" "$RUN/role-worker"; touch "$RUN/role-$ROLE"; echo "$NW" > "$RUN/workers"
announce final; date -u +%FT%TZ > "$RUN/fleet-done"
if [ "$LAYERS" = fleet-wireguard-signing ]; then echo "fleet joined: $NAME is the $ROLE at $OWN_IP, $NR nodes, wg0 up, configuration rendered into $RUN/conf, final quote published (tc/final)"
else echo "fleet joined: $NAME is the $ROLE at $OWN_IP, $NR nodes, BENCHMARK bench-layers $LAYERS, $([ "$WG" = 1 ] && echo "wg0 up" || echo "no wg0"), configuration rendered into $RUN/conf, final quote published (tc/final)"; fi
