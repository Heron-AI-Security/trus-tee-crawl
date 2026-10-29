#!/usr/bin/env bash
# Step P2/P6, part A (no cloud): the boot event log publisher of the node (ccel() of tc-fleet.sh) and its collection by the dummy-run script.   bash p2a-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; FL="$K/ops/image/rootfs/usr/local/lib/tc/tc-fleet.sh"; RR="$K/ops/reference-run.sh"; CT="$K/ops/ccel-table.py"; MR="$K/ops/make-release.py"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "  pass: $1"; P=$((P+1)); else echo "  FAIL: $1"; F=$((F+1)); fi; }
python3 - "$W" <<'PY'
import base64, hashlib, json, os, struct, sys
W = sys.argv[1]; s384 = lambda b: hashlib.sha384(b).digest(); H = hashlib.sha256(b"root").hexdigest().encode(); H2 = hashlib.sha256(b"other root").hexdigest().encode()
def spec(): d = b"Spec ID Event03\x00" + struct.pack("<I", 0) + bytes([0, 2, 0, 2]) + struct.pack("<I", 1) + struct.pack("<HH", 0x000C, 48) + bytes([0]); return struct.pack("<II20sI", 0, 3, bytes(20), len(d)) + d
def ev(mr, t, data, dg=None): return struct.pack("<III", mr, t, 1) + struct.pack("<H", 0x000C) + (dg or s384(data)) + struct.pack("<I", len(data)) + data
def log(es): return spec() + b"".join(ev(*e) for e in es)
def regs(es):
    r = {}
    for e in es:
        if e[1] == 3: continue
        r[e[0]] = s384(r.get(e[0], bytes(48)) + (e[3] if len(e) > 3 else s384(e[2])))
    return r
def quote(es, bad=False):
    q = bytearray(700); r = regs(es)
    for m, (a, b) in {1: (376, 424), 2: (424, 472), 3: (472, 520)}.items(): q[a:b] = r.get(m, bytes(48))
    if bad: q[424] ^= 1
    return bytes(q)
def base(h): return [(1, 0x80000002, "BootOrder".encode("utf-16-le")), (1, 4, bytes(4)), (1, 0x80000002, "Boot0001".encode("utf-16-le")), (2, 0x80000003, bytes(range(40))), (2, 3, b"NoActionEvent", s384(b"must not be extended")), (2, 4, bytes(4)),
                  (3, 0xD, b"grub_cmd linux /boot/vmlinuz-6.17.0-1022-gcp root=/dev/mapper/tc-root ro tc.verity=" + h + b"\x00"), (3, 0xD, b"grub_cmd initrd /boot/initrd.img-tc\x00"), (3, 0xD, b"grub_kernel_cmdline /boot/vmlinuz-6.17.0-1022-gcp tc.verity=" + h + b" console=ttyS0\x00")]
ok = base(H); open(W + "/ccel_ok.bin", "wb").write(log(ok)); open(W + "/quote_ok.bin", "wb").write(quote(ok)); open(W + "/quote_bad.bin", "wb").write(quote(ok, True))
open(W + "/ccel_wrongverity.bin", "wb").write(log(base(H2))); nov = [e for e in ok if b"tc.verity" not in e[2]]; open(W + "/ccel_noverity.bin", "wb").write(log(nov))
r1 = [e for e in nov] + [(2, 0xD, b"only in rtmr1 tc.verity=" + H + b"\x00")]; open(W + "/ccel_r1verity.bin", "wb").write(log(r1)); open(W + "/ccel_nospec.bin", "wb").write(b"not a boot log at all, but long enough to pass the length test........")
full = log(ok); open(W + "/ccel_trunc.bin", "wb").write(full[:len(full) - 150]); open(W + "/ccel_big.bin", "wb").write(bytes((i * 7 + 3) % 251 for i in range(30000)))
# the announcement and the reference for the release tests
names = ["source", "tc-lib", "tc-conf", "jdk"]; commit = "0123456789abcdef0123456789abcdef01234567"; ev_ = [(n, hashlib.sha384(("commit %s\n" % commit).encode()).hexdigest() if n == "source" else hashlib.sha384(("event " + n).encode()).hexdigest()) for n in names]
def announce(tag, mrtd_other=False):
    reg = bytes(48); lines = []
    for n, dg in ev_: b0 = reg; reg = hashlib.sha384(reg + bytes.fromhex(dg)).digest(); lines.append("%s\t%s\t%s\t%s" % (n, dg, b0.hex(), reg.hex()))
    lg = ("\n".join(lines) + "\n").encode(); d = {"name": "tc-ref-x", "sign": "S", "wg": "G", "log_sha512": hashlib.sha512(lg).hexdigest()}
    regs_ = {k: hashlib.sha384((k + "-value").encode()).digest() for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2")}; ref = dict(regs_)
    if mrtd_other: regs_["mrtd"] = hashlib.sha384(b"other").digest()
    q = bytearray(700)
    for k, (a, b) in {"mrtd": (184, 232), "rtmr0": (376, 424), "rtmr1": (424, 472), "rtmr2": (472, 520)}.items(): q[a:b] = regs_[k]
    q[520:568] = reg; q[568:632] = hashlib.sha512(("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"])).encode()).digest()
    open("%s/ann_%s.txt" % (W, tag), "w").write("name=%s\nsign=S\nwg=G\nlog_sha512=%s\nquote_b64=%s\nlog_b64=%s\n" % (d["name"], d["log_sha512"], base64.b64encode(bytes(q)).decode(), base64.b64encode(lg).decode()))
    open("%s/annquote_%s.bin" % (W, tag), "wb").write(bytes(q)); open("%s/log_%s.tsv" % (W, tag), "wb").write(lg); return ref
ref = announce("ok"); announce("mrtd", True)
def refjson(tag, **ov):
    r = {"commit": commit, "events_in_order": names, "stable_events": dict(ev_), "per_run_events": [], "image": "tc-img-rel-1", "machine_type": "c3-standard-4"}; r.update({k: v.hex() for k, v in ref.items()}); r.update(ov); json.dump(r, open("%s/ref_%s.json" % (W, tag), "w"))
refjson("ok"); refjson("othercommit", commit="f" * 40); refjson("badsource", stable_events=dict(ev_, source=hashlib.sha384(b"commit other\n").hexdigest())); refjson("otherimage", image="tc-img-other"); refjson("shortcommit", commit="0123456")
json.dump({"image": "tc-img-rel-1", "machine_type": "c3-standard-4", "memory_mb": 16384, "boot_disk_gb": 30, "scratch_disk_gb": 10, "zone": "us-central1-a", "confidential_instance_type": "TDX", "name": "tc-ref-x"}, open(W + "/settings.json", "w")); json.dump({"id": "123", "name": "tc-img-rel-1"}, open(W + "/image.json", "w"))
open(W + "/ROOT", "w").write(H.decode()); open(W + "/ROOT2", "w").write(H2.decode())
PY
RH="$(cat "$W/ROOT")"
echo "== the node publishes its boot event log (ccel() of tc-fleet.sh)"
cat > "$W/node.sh" <<'NS'
RUN="$W/run"; mkdir -p "$RUN" "$W/attrs"; : > "$W/putlog"
put() { [ -f "$W/put_fails_$1" ] && return 1; cp "$2" "$W/attrs/$1"; echo "$1" >> "$W/putlog"; }
eval "$(sed -n '/^ccel() {/,/^}/p' "$FL")"; ccel; echo "rc=$?"
NS
runnode() { rm -rf "$W/run" "$W/attrs"; NOUT="$(W="$W" FL="$FL" TC_CCEL="$1" bash "$W/node.sh" 2>&1)"; }
runnode "$W/ccel_big.bin"; N=$(cat "$W/attrs/ccel-count" 2>/dev/null)
[ "$N" = 3 ] && grep -q "rc=0" <<<"$NOUT" && grep -q "published the boot event log: 30000 bytes in 3 chunks" <<<"$NOUT" && chk "30000 bytes are published in 3 chunks with a count" ok || chk "publish: $NOUT" no
for i in 0 1 2; do base64 -d "$W/attrs/ccel-$i"; done > "$W/reassembled.bin" 2>/dev/null; cmp -s "$W/reassembled.bin" "$W/ccel_big.bin" && chk "the chunks reassemble to the exact log" ok || chk "reassembly differs" no
[ "$(cat "$W/attrs/ccel-sha256")" = "$(sha256sum < "$W/ccel_big.bin" | cut -d' ' -f1)" ] && chk "the published SHA-256 is the hash of the log" ok || chk "wrong published hash" no
[ "$(tail -1 "$W/putlog")" = "ccel-count" ] && chk "the count is published LAST (a reader that sees it knows that every chunk is there)" ok || chk "the count is not last: $(tail -2 "$W/putlog" | tr '\n' ' ')" no
[ "$(wc -c < "$W/attrs/ccel-0")" = 16384 ] && [ "$(tail -c1 "$W/attrs/ccel-0")" != "=" ] && chk "a full chunk is 16384 base64 characters without padding (so the chunks join into one valid base64 text)" ok || chk "chunk size or padding unexpected" no
runnode "$W/none.bin"; [ ! -d "$W/attrs" ] || [ -z "$(ls "$W/attrs" 2>/dev/null)" ]; grep -q "no boot event log" <<<"$NOUT" && grep -q "rc=0" <<<"$NOUT" && [ -z "$(ls "$W/attrs" 2>/dev/null)" ] && chk "no log: a note, nothing published, not fatal" ok || chk "missing log: $NOUT" no
: > "$W/empty.bin"; runnode "$W/empty.bin"; [ -z "$(ls "$W/attrs" 2>/dev/null)" ] && grep -q "rc=0" <<<"$NOUT" && chk "an empty log is not published" ok || chk "empty log published" no
touch "$W/put_fails_ccel-1"; runnode "$W/ccel_big.bin"; rm -f "$W/put_fails_ccel-1"; [ ! -f "$W/attrs/ccel-count" ] && grep -q "rc=0" <<<"$NOUT" && grep -q "could not publish the boot event log (chunk 1)" <<<"$NOUT" && chk "a failed chunk: no count is published (a reader sees an absent log, never a partial one), and the node goes on" ok || chk "failed chunk: $NOUT" no
grep -q '^announce announce; ccel; echo "announced' "$FL" && [ "$(grep -c '^announce final' "$FL")" = 1 ] && ! grep -q 'announce final; ccel' "$FL" && chk "ccel is called once, after the first announcement and not after the final one" ok || chk "ccel is not wired as intended" no
echo "== the dummy-run script collects it"
mkdir -p "$W/bin"
cat > "$W/bin/gcloud" <<'GE'
#!/usr/bin/env bash
W="${P2W:?}"; echo "$*" >> "$W/calls.log"
case "$1 $2 $3" in
 "compute instances create") touch "$W/vm_exists"; echo created;;
 "compute instances get-guest-attributes") q=""; for a in "$@"; do case "$a" in --query-path=*) q="${a#--query-path=}";; esac; done; case "$q" in
     tc/announce) cat "$W/ann_ok.txt";; tc/ccel-count) [ -f "$W/nolog" ] && exit 0; [ -f "$W/badcount" ] && { echo "abc"; exit 0; }; echo "$(cat "$W/nchunks")";; tc/ccel-sha256) [ -f "$W/wronghash" ] && { echo 0000; exit 0; }; cat "$W/pubhash";; tc/ccel-*) i="${q#tc/ccel-}"; [ -f "$W/missing_$i" ] && exit 0; cat "$W/chunk_$i";; esac;;
 "compute instances describe") cat "$W/instance.json";; "compute images describe") cat "$W/image.json";; "compute machine-types describe") echo 16384;; "compute instances delete") rm -f "$W/vm_exists";; esac; exit 0
GE
chmod +x "$W/bin/gcloud"; cp "$W/settings.json" "$W/instance.json"; python3 - "$W" <<'PY'
import json, sys; W = sys.argv[1]; json.dump({"name": "tc-ref-x", "disks": [{"boot": True, "diskSizeGb": "30"}, {"boot": False, "diskSizeGb": "10"}], "confidentialInstanceConfig": {"confidentialInstanceType": "TDX"}}, open(W + "/instance.json", "w"))
PY
runnode "$W/ccel_big.bin"; for i in 0 1 2; do cp "$W/attrs/ccel-$i" "$W/chunk_$i"; done; echo 3 > "$W/nchunks"; cp "$W/attrs/ccel-sha256" "$W/pubhash"
rr() { rm -f "$W/calls.log" "$W/vm_exists"; RO="$(P2W="$W" TC_GCLOUD="$W/bin/gcloud" REF_VM=tc-ref-x POLL_SECONDS=1 WAIT_SECONDS=5 bash "$RR" tc-img-rel-1 "$W/out" 2>&1)"; RRC=$?; }
rr; [ $RRC = 0 ] && cmp -s "$W/out/ccel.bin" "$W/ccel_big.bin" && grep -q "SHA-256 verified" <<<"$RO" && chk "the chunks are collected, joined and verified: ccel.bin equals the log" ok || chk "collect: $RO" no
python3 -c "import json; s=json.load(open('$W/out/settings.json')); print(s.get('boot_event_log_bytes'))" | grep -q "^30000$" && chk "settings.json records the size of the boot event log" ok || chk "settings lacks the log size" no
touch "$W/missing_1"; rr; rm -f "$W/missing_1"; [ $RRC != 0 ] && grep -q "chunk 1 of the boot event log is missing" <<<"$RO" && [ ! -f "$W/vm_exists" ] && chk "a missing chunk fails the run, and the VM is still deleted" ok || chk "missing chunk: $RO" no
touch "$W/wronghash"; rr; rm -f "$W/wronghash"; [ $RRC != 0 ] && grep -q "does not match its published hash" <<<"$RO" && chk "a chunk set that does not match its published hash is refused" ok || chk "wrong hash: $RO" no
touch "$W/nolog"; rr; rm -f "$W/nolog"; [ $RRC = 0 ] && [ ! -f "$W/out/ccel.bin" ] && grep -q "does not publish its boot event log" <<<"$RO" && chk "an older image without tc/ccel-count: the run succeeds and says so" ok || chk "older image: $RO" no
touch "$W/badcount"; rr; rm -f "$W/badcount"; [ $RRC = 0 ] && [ ! -f "$W/out/ccel.bin" ] && chk "a count that is not a number is treated as no log" ok || chk "bad count: $RO" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "P2A-REHEARSAL-PASS" || { echo "P2A-REHEARSAL-FAIL"; exit 1; }
