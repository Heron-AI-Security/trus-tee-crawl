#!/usr/bin/env bash
# Step P2/P6, part B (no cloud): the boot event table (ops/ccel-table.py) and the release (ops/make-release.py).   bash p2b-rehearse.sh KITDIR
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
long = base(H) + [(3, 0xD, b"grub_cmd: linux /boot/vmlinuz-6.17.0-1022-gcp root=/dev/mapper/vroot ro fsck.mode=skip console=ttyS0,115200 overlayroot=off " + b"x" * 200 + b" tc.verity=" + H + b" END_OF_THE_COMMAND_LINE\x00")]
open(W + "/ccel_long.bin", "wb").write(log(long)); open(W + "/quote_long.bin", "wb").write(quote(long))
open(W + "/ROOT", "w").write(H.decode()); open(W + "/ROOT2", "w").write(H2.decode())
PY
RH="$(cat "$W/ROOT")"
echo "== the boot event table (ops/ccel-table.py)"
mkdir -p "$W/t_ok"; cp "$W/ccel_ok.bin" "$W/t_ok/ccel.bin"; cp "$W/quote_ok.bin" "$W/t_ok/quote.bin"
ct() { COUT="$(python3 "$CT" "$@" 2>&1)"; CRC=$?; }
ct "$W/t_ok" --markdown "$W/t.md"; [ $CRC = 0 ] && grep -q "CCEL-TABLE-OK" <<<"$COUT" && grep -q "replay of RTMR1: equal to the quote" <<<"$COUT" && chk "the replay of RTMR0, RTMR1 and RTMR2 equals the quote (an EV_NO_ACTION event with a digest is NOT extended)" ok || chk "table: $COUT" no
grep -q "events in the log: 9 (RTMR0 3, RTMR1 3, RTMR2 3)" <<<"$COUT" && chk "the events are counted per register" ok || chk "counts: $COUT" no
grep -q "dm-verity root hash in the RTMR2 events: event 1: $RH, event 3: $RH" <<<"$COUT" && chk "the root hash of the kernel command line is found in RTMR2 (events 1 and 3)" ok || chk "verity not found: $COUT" no
grep -q "RTMR2: EV_IPL: grub_cmd linux /boot/vmlinuz" <<<"$COUT" && chk "the events that name the kernel are listed with their register" ok || chk "kernel events: $COUT" no
grep -q "^## The RTMR1 events" "$W/t.md" && grep -q "^## The RTMR2 events" "$W/t.md" && [ "$(grep -c '^| [0-9]' "$W/t.md")" = 6 ] && grep -q "EV_NO_ACTION (not extended)" "$W/t.md" && chk "the markdown holds a table per register with every event, and marks the event that is not extended" ok || chk "markdown: $(cat "$W/t.md" | head -5)" no
mkdir -p "$W/t_long"; cp "$W/ccel_long.bin" "$W/t_long/ccel.bin"; cp "$W/quote_long.bin" "$W/t_long/quote.bin"
ct "$W/t_long" --markdown "$W/long_short.md"; SHORTOUT="$COUT"; ct "$W/t_long" --markdown "$W/long_full.md" --full; FULLOUT="$COUT"; FULLRC=$CRC
[ $FULLRC = 0 ] && ! grep -q "END_OF_THE_COMMAND_LINE" "$W/long_short.md" && grep -q "\.\.\. |" "$W/long_short.md" && chk "without --full a long text is cut with ... (the default tables stay short)" ok || chk "default table not cut: $(grep -c END_OF "$W/long_short.md")" no
grep -q "END_OF_THE_COMMAND_LINE" "$W/long_full.md" && grep -q "tc.verity=$RH END_OF_THE_COMMAND_LINE" "$W/long_full.md" && chk "with --full the complete kernel command line is in the table" ok || chk "--full did not keep the whole text" no
python3 - "$W/long_full.md" "$W/long_short.md" <<'PY' > "$W/fullcheck.txt"
import re, sys
def digests(p): return [m.group(1) for l in open(p) for m in [re.search(r"\| `([0-9a-f.]+)` \|$", l.rstrip())] if m]
f, s = digests(sys.argv[1]), digests(sys.argv[2]); print("full96", len(f) > 0 and all(len(d) == 96 for d in f)); print("short32", len(s) > 0 and all(len(d) == 35 and d.endswith("...") for d in s)); print("same_count", len(f) == len(s))
PY
grep -q "^full96 True" "$W/fullcheck.txt" && grep -q "^short32 True" "$W/fullcheck.txt" && grep -q "^same_count True" "$W/fullcheck.txt" && chk "--full gives every digest as 96 hexadecimal digits, the default as 32 and ..." ok || chk "digest lengths: $(cat "$W/fullcheck.txt" | tr '\n' ' ')" no
grep -q "ccel.bin SHA-256: $(sha256sum < "$W/ccel_long.bin" | cut -d' ' -f1)" <<<"$FULLOUT" && grep -q "quote.bin SHA-256: $(sha256sum < "$W/quote_long.bin" | cut -d' ' -f1)" <<<"$FULLOUT" && grep -q "ccel.bin SHA-256" <<<"$SHORTOUT" && chk "the SHA-256 of ccel.bin and quote.bin is printed, so that a table is tied to its evidence" ok || chk "evidence hashes: $FULLOUT" no
mkdir -p "$W/t_bad"; cp "$W/ccel_ok.bin" "$W/t_bad/ccel.bin"; cp "$W/quote_bad.bin" "$W/t_bad/quote.bin"; ct "$W/t_bad"; [ $CRC = 1 ] && grep -q "replay of RTMR1: DIFFERENT" <<<"$COUT" && grep -q "CCEL-TABLE-FAILED" <<<"$COUT" && chk "a quote whose RTMR1 differs from the replay of the log is rejected" ok || chk "bad quote: $COUT" no
mkdir -p "$W/t_nospec"; cp "$W/ccel_nospec.bin" "$W/t_nospec/ccel.bin"; cp "$W/quote_ok.bin" "$W/t_nospec/quote.bin"; ct "$W/t_nospec"; [ $CRC = 1 ] && grep -q "Spec ID Event03" <<<"$COUT" && chk "a file that is not a boot log is rejected" ok || chk "no spec: $COUT" no
mkdir -p "$W/t_trunc"; cp "$W/ccel_trunc.bin" "$W/t_trunc/ccel.bin"; cp "$W/quote_ok.bin" "$W/t_trunc/quote.bin"; ct "$W/t_trunc"; [ $CRC = 1 ] && chk "a truncated boot log is rejected" ok || chk "truncated log accepted: $COUT" no
mkdir -p "$W/t_none"; ct "$W/t_none"; [ $CRC = 1 ] && grep -q "is missing" <<<"$COUT" && chk "a run folder without ccel.bin says that the image may not publish its log" ok || chk "no ccel.bin: $COUT" no
mkdir -p "$W/bin"
echo "== the release (ops/make-release.py)"
mkdir -p "$W/rel_run"; cp "$W/ann_ok.txt" "$W/rel_run/announce.txt"; cp "$W/settings.json" "$W/image.json" "$W/rel_run/"; cp "$W/annquote_ok.bin" "$W/rel_run/quote.bin"; cp "$W/ccel_ok.bin" "$W/rel_run/ccel.bin"
mr() { MOUT="$(TC_GCLOUD="${GCL:-$W/bin/gcl}" python3 "$MR" --commit "$1" --image "$2" --root-hash "$3" --run "$4" --reference "$5" --out "$W/relout" ${6:-} 2>&1)"; MRC=$?; }
mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_run" "$W/ref_ok.json"; [ $MRC = 0 ] && grep -q "RELEASE-OK commit=0123456789ab" <<<"$MOUT" && chk "a consistent commit, image, run and root hash give RELEASE-OK" ok || chk "release: $MOUT" no
python3 - "$W/relout/release.json" "$W/ref_ok.json" "$RH" <<'PY' > "$W/relcheck.txt"
import hashlib, json, re, sys
r = json.load(open(sys.argv[1])); ref = open(sys.argv[2], "rb").read(); h = sys.argv[3]
print("fields", r["commit"] == "0123456789abcdef0123456789abcdef01234567" and r["image"] == "tc-img-rel-1" and r["verity_root_hash"] == h and r["reference_sha256"] == hashlib.sha256(ref).hexdigest() and r["dummy_run_settings"]["machine_type"] == "c3-standard-4" and r["image_id"] == "123")
print("labels", all(re.fullmatch(r"[a-z0-9_-]{0,63}", v) for v in r["image_labels"].values()) and r["image_labels"]["verity-a"] + r["image_labels"]["verity-b"] == h and len(r["image_labels"]["verity-a"]) == 32)
PY
grep -q "^fields True" "$W/relcheck.txt" && chk "release.json holds the commit, the image, the root hash, the SHA-256 of the reference file and the settings of the run" ok || chk "release.json fields: $(cat "$W/relcheck.txt")" no
grep -q "^labels True" "$W/relcheck.txt" && chk "the label values are valid for GCE (at most 63 characters): the root hash is split in two halves of 32" ok || chk "labels invalid" no
mr 0123456789 tc-img-rel-1 "$(cat "$W/ROOT2")" "$W/rel_run" "$W/ref_ok.json"; [ $MRC = 1 ] && grep -q "carry the root hash" <<<"$MOUT" && chk "another root hash than the kernel command line carries is rejected" ok || chk "wrong root accepted: $MOUT" no
mr 0123456789 tc-img-rel-1 "${RH:0:63}" "$W/rel_run" "$W/ref_ok.json"; [ $MRC = 1 ] && grep -q "64 lowercase" <<<"$MOUT" && chk "a root hash of 63 digits is refused" ok || chk "short root accepted" no
mkdir -p "$W/rel_nov"; cp "$W"/rel_run/* "$W/rel_nov/"; cp "$W/ccel_noverity.bin" "$W/rel_nov/ccel.bin"; mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_nov" "$W/ref_ok.json"; [ $MRC = 1 ] && grep -q "no RTMR2 event carries tc.verity=" <<<"$MOUT" && chk "a boot log without tc.verity= cannot be tied to the root hash" ok || chk "no verity accepted: $MOUT" no
mkdir -p "$W/rel_r1"; cp "$W"/rel_run/* "$W/rel_r1/"; cp "$W/ccel_r1verity.bin" "$W/rel_r1/ccel.bin"; mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_r1" "$W/ref_ok.json"; [ $MRC = 1 ] && grep -q "no RTMR2 event carries tc.verity=" <<<"$MOUT" && chk "tc.verity= in an RTMR1 event does not count (it must be in RTMR2)" ok || chk "RTMR1 verity accepted: $MOUT" no
mkdir -p "$W/rel_nolog"; cp "$W/rel_run/announce.txt" "$W/rel_run/settings.json" "$W/rel_run/image.json" "$W/rel_run/quote.bin" "$W/rel_nolog/"; mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_nolog" "$W/ref_ok.json"; [ $MRC = 1 ] && grep -q "boot event log cannot be read" <<<"$MOUT" && chk "a run without a boot event log is refused" ok || chk "no log accepted: $MOUT" no
mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_run" "$W/ref_othercommit.json"; [ $MRC = 1 ] && grep -q "the reference is of commit" <<<"$MOUT" && chk "a reference of another commit is rejected" ok || chk "other commit accepted: $MOUT" no
mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_run" "$W/ref_badsource.json"; [ $MRC = 1 ] && grep -q "was not built from this commit" <<<"$MOUT" && chk "a source event that is not SHA-384 of 'commit <id>' is rejected" ok || chk "bad source accepted: $MOUT" no
mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_run" "$W/ref_shortcommit.json"; [ $MRC = 1 ] && grep -q "full commit id" <<<"$MOUT" && chk "a reference with a short commit id is rejected" ok || chk "short commit accepted" no
mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_run" "$W/ref_otherimage.json"; [ $MRC = 1 ] && grep -q "the reference is of image" <<<"$MOUT" && chk "a reference of another image is rejected" ok || chk "other image accepted: $MOUT" no
mkdir -p "$W/rel_mrtd"; cp "$W"/rel_run/* "$W/rel_mrtd/"; cp "$W/ann_mrtd.txt" "$W/rel_mrtd/announce.txt"; mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_mrtd" "$W/ref_ok.json"; [ $MRC = 1 ] && grep -q "does not equal the reference" <<<"$MOUT" && chk "a dummy run whose MRTD differs is rejected" ok || chk "mrtd accepted: $MOUT" no
cat > "$W/bin/gcl" <<'GE'
#!/usr/bin/env bash
echo "$*" >> "${P2W:?}/gcl.log"; case "$1 $2 $3" in "compute images add-labels") exit 0;; "compute images describe") if [ -f "${P2W}/wronglabels" ]; then echo '{"labels":{"commit":"x"}}'; else python3 - "${P2W}/gcl.log" <<'PY'
import json, re, sys; l = [x for x in open(sys.argv[1]) if "add-labels" in x][-1]; m = re.search(r"--labels=(\S+)", l); print(json.dumps({"labels": dict(kv.split("=") for kv in m.group(1).split(","))}))
PY
fi;; esac
GE
chmod +x "$W/bin/gcl"; rm -f "$W/gcl.log"; P2W="$W" mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_run" "$W/ref_ok.json" --apply-labels; [ $MRC = 0 ] && grep -q "7. the image is labelled" <<<"$MOUT" && grep -q "add-labels tc-img-rel-1 --labels=commit=0123456789abcdef0123456789abcdef01234567,verity-a=${RH:0:32},verity-b=${RH:32:32}" "$W/gcl.log" && chk "--apply-labels sets commit, verity-a and verity-b on the image and reads them back" ok || chk "labels: $MOUT" no
touch "$W/wronglabels"; P2W="$W" mr 0123456789 tc-img-rel-1 "$RH" "$W/rel_run" "$W/ref_ok.json" --apply-labels; rm -f "$W/wronglabels"; [ $MRC = 1 ] && grep -q "labels of the image are not what was set" <<<"$MOUT" && chk "labels that are not what was set are detected" ok || chk "wrong labels accepted: $MOUT" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "P2B-REHEARSAL-PASS" || { echo "P2B-REHEARSAL-FAIL"; exit 1; }
