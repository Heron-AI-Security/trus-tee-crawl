#!/usr/bin/env bash
# Mutual attestation (tc-peer-verify.py) on REAL quotes: the announcements of the two nodes of the debug fleet of 23 October 2026 (testdata/peers: Intel-signed TDX quotes, the
# public keys, the RTMR3 logs and the fleet list). Each node accepts the other; then every check is made to FAIL on purpose. Needs python3 and openssl (as on the image).
#   bash f1-peers-test.sh KITDIR
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; PV="$KIT/ops/image/rootfs/usr/local/lib/tc/tc-peer-verify.py"; TD="$KIT/ops/image/test/testdata/peers"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; echo "${out:-}" | tail -4 | sed "s/^/        | /"; fi; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
M="$TD/announce-tc-f1-m.txt"; WK="$TD/announce-tc-f1-w.txt"; F="$TD/fleet.tsv"
# mut.py IN OUT KIND [ARG]: a changed copy of an announcement. The quote kinds change the quote's bytes (the Intel signatures must then fail); the own-* kinds change THIS node's
# own announcement, which the check reads but does not need to be Intel-signed, to stand for a peer that runs another TD or image
cat > "$W/mut.py" <<'PYEOF'
import base64, hashlib, re, sys
src, dst, kind = sys.argv[1:4]; arg = sys.argv[4] if len(sys.argv) > 4 else ""
d = {}; order = []
for line in open(src).read().splitlines():
    if "=" in line: k, v = line.split("=", 1); d[k] = v; order.append(k)
q = bytearray(base64.b64decode(d["quote_b64"]))
def flip(i): q[i] ^= 1
def pck_span():
    s = bytes(q); a = s.find(b"-----BEGIN CERTIFICATE-----"); return a, s.find(b"-----END CERTIFICATE-----", a)
if kind == "quote-sig": flip(632 + 4 + 10)                       # a byte of the quote's ECDSA signature
elif kind == "debug": q[168] |= 1                                 # the TD debug bit, in the signed body
elif kind == "mrtd": flip(200)                                    # the image measurement, in the signed body
elif kind == "pck-cert": a, b = pck_span(); i = a + 200; q[i] = ord("A") if q[i] != ord("A") else ord("B")   # a character inside the PCK leaf certificate
elif kind == "root":                                              # one character of the chain's last certificate changed: it is no longer Intel's root
    s = bytes(q); last = [m.span() for m in re.finditer(rb"-----BEGIN CERTIFICATE-----.*?-----END CERTIFICATE-----", s, re.S)][-1]; i = last[0] + 100
    q[i] = ord("A") if q[i] != ord("A") else ord("B")
elif kind == "notdx": q = bytearray(b"\0" * 32 + bytes(q[32:]))     # a quote whose header is not a TDX one
elif kind == "short": q = q[:600]
elif kind == "wg": d["wg"] = arg                                  # the announcement names another WireGuard key than its quote binds
elif kind == "log":                                               # the log changed after the quote
    log = base64.b64decode(d["log_b64"]).replace(b"tc-conf", b"tc-cXnf"); d["log_b64"] = base64.b64encode(log).decode()
elif kind in ("own-mrtd", "own-xfam", "own-debug"):              # this node's own TD differs from the peer's
    flip({"own-mrtd": 190, "own-xfam": 177, "own-debug": 168}[kind])
elif kind == "own-event":                                          # this node measured one event differently (another image); its own binding and RTMR3 stay consistent
    rows = [l.split("\t") for l in base64.b64decode(d["log_b64"]).decode().splitlines()]; reg = bytes(48); out = []
    for n, dg, _, _ in rows:
        if n == "tc-conf": dg = hashlib.sha384(b"another image").hexdigest()
        nxt = hashlib.sha384(reg + bytes.fromhex(dg)).digest(); out.append("\t".join([n, dg, reg.hex(), nxt.hex()])); reg = nxt
    log = ("\n".join(out) + "\n").encode(); d["log_b64"] = base64.b64encode(log).decode(); d["log_sha512"] = hashlib.sha512(log).hexdigest(); q[520:568] = reg
    q[568:632] = hashlib.sha512(("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"])).encode()).digest()
else: sys.exit("unknown kind " + kind)
d["quote_b64"] = base64.b64encode(bytes(q)).decode()
open(dst, "w").write("".join("%s=%s\n" % (k, d[k]) for k in order))
PYEOF
quotes() { python3 -c 'import json,sys; json.dump({sys.argv[i]: open(sys.argv[i+1]).read() for i in range(1, len(sys.argv), 2)}, sys.stdout)' "$@"; }
# run OWN QUOTESJSON [FLEET]: the check as node OWN would run it
run() { out="$(python3 "$PV" "$1" "${3:-$F}" "$2" "$W/peers.out" 2>&1)"; rc=$?; }
refused() { [ $rc != 0 ] && grep -q "TC-PEERS-FAIL" <<<"$out" && grep -q "$1" <<<"$out" && [ ! -s "$W/peers.out" ]; }
quotes tc-f1-m "$M" tc-f1-w "$WK" > "$W/q.json"

echo "=== the real fleet: each node accepts the other"
rm -f "$W/peers.out"; run "$M" "$W/q.json"; chk "the master accepts the worker (Intel chain, keys, binding, log, same TD and image) and writes the worker's quote hash" $([ $rc = 0 ] && grep -q "TC-PEERS-OK 1" <<<"$out" && grep -qP "^tc-f1-w\t[0-9a-f]{64}$" "$W/peers.out"; echo $?)
rm -f "$W/peers.out"; run "$WK" "$W/q.json"; chk "the worker accepts the master" $([ $rc = 0 ] && grep -q "TC-PEERS-OK 1" <<<"$out" && grep -qP "^tc-f1-m\t" "$W/peers.out"; echo $?)

echo "=== P0: a quote that Intel did not sign is refused"
for c in "quote-sig|attestation key|a changed byte of the quote's signature" "debug|attestation key|the debug bit set in a genuine quote (the signature breaks)" \
         "mrtd|attestation key|another MRTD written into a genuine quote" "pck-cert|PCK chain does not verify|a changed PCK certificate" "root|does not end at the Intel SGX Root CA|a chain that does not end at Intel's root (one character of the root changed)" \
         "notdx|not a TDX v4|a quote that is not a TDX quote (a VM without TDX)" "short|too short|a truncated quote"; do
  IFS='|' read -r kind want label <<<"$c"; rm -f "$W/w.txt"; python3 "$W/mut.py" "$WK" "$W/w.txt" "$kind"; quotes tc-f1-m "$M" tc-f1-w "$W/w.txt" > "$W/qq.json"; rm -f "$W/peers.out"; run "$M" "$W/qq.json"
  chk "fault: $label" $(refused "$want"; echo $?)
done

echo "=== P1 and P2: the announcement must be the row's and must match its quote"
python3 - "$F" "$W/f-wg.tsv" <<'PYEOF'
import sys
rows = open(sys.argv[1]).read().splitlines(); out = []
for l in rows:
    c = l.split("\t")
    if len(c) == 6 and c[0] == "tc-f1-w": c[5] = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
    out.append("\t".join(c))
open(sys.argv[2], "w").write("\n".join(out) + "\n")
PYEOF
rm -f "$W/peers.out"; run "$M" "$W/q.json" "$W/f-wg.tsv"; chk "fault: the operator lists another WireGuard key for the worker than its quote binds (a machine the operator controls)" $(refused "not the ones of its row"; echo $?)
python3 "$W/mut.py" "$WK" "$W/w.txt" wg "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="; quotes tc-f1-m "$M" tc-f1-w "$W/w.txt" > "$W/qq.json"; rm -f "$W/peers.out"; run "$M" "$W/qq.json" "$W/f-wg.tsv"
chk "fault: ... and also rewrites the announcement to name that key (REPORTDATA no longer matches)" $(refused "REPORTDATA"; echo $?)
python3 "$W/mut.py" "$WK" "$W/w.txt" log; quotes tc-f1-m "$M" tc-f1-w "$W/w.txt" > "$W/qq.json"; rm -f "$W/peers.out"; run "$M" "$W/qq.json"
chk "fault: a log changed after the quote" $(refused "the log is not the one hashed"; echo $?)
sed 's/^tc-f1-w\t/tc-f1-x\t/' "$F" > "$W/f-x.tsv"; quotes tc-f1-m "$M" tc-f1-x "$WK" > "$W/qq.json"; rm -f "$W/peers.out"; run "$M" "$W/qq.json" "$W/f-x.tsv"
chk "fault: a genuine quote replayed for a node of another name" $(refused "not the ones of its row"; echo $?)
quotes tc-f1-m "$M" > "$W/qq.json"; rm -f "$W/peers.out"; run "$M" "$W/qq.json"; chk "fault: no announcement for a row (a node that never announced, like the ghost of F4)" $(refused "no announcement for it"; echo $?)
printf '[1, 2]' > "$W/qq.json"; rm -f "$W/peers.out"; run "$M" "$W/qq.json"; chk "fault: tc-fleet-quotes that is not an object of announcements" $(refused "not an object"; echo $?)
printf 'not json' > "$W/qq.json"; rm -f "$W/peers.out"; run "$M" "$W/qq.json"; chk "fault: tc-fleet-quotes that is not JSON" $(refused "cannot be read as JSON"; echo $?)

echo "=== P3: a genuine quote of ANOTHER TD or image is refused (this node's own announcement is changed to stand for the difference)"
for c in "own-mrtd|mrtd|another MRTD (another firmware or image)" "own-xfam|xfam|other TD features (XFAM)" "own-debug|tdattr|other TD attributes (here: this node has the debug bit and the peer not)" \
         "own-event|measured events differ|one measured event differs (another image: tc-conf)"; do
  IFS='|' read -r kind want label <<<"$c"; rm -f "$W/m.txt"; python3 "$W/mut.py" "$M" "$W/m.txt" "$kind"; rm -f "$W/peers.out"; run "$W/m.txt" "$W/q.json"
  chk "fault: $label" $(refused "$want"; echo $?)
done

echo "f1-peers-test: $PASS passed, $FAILN failed"
[ "$FAILN" = 0 ] && echo "F1-PEERS-TEST-OK" || { echo "F1-PEERS-TEST-FAILED ($FAILN)"; exit 1; }
