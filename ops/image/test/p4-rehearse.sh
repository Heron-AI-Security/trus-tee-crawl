#!/usr/bin/env bash
# ops/image/test/p4-rehearse.sh: the offline rehearsal of step P4 (no Google, no GitHub): ops/verify-reference.py and ops/verify-reference.sh against a REAL published set (made by ops/ci/publish-ref.sh from synthetic dummy runs),
# attacked in many ways, and against your own dummy runs that differ from the published one in many ways.
# Usage:  bash ops/image/test/p4-rehearse.sh [ROOT]      ROOT is the repository folder (default: three folders above this script).   Ends with  pass: N   fail: M  and P4-REHEARSAL-PASS or P4-REHEARSAL-FAIL.
# shellcheck disable=SC2015   # the chk lines are written as: test && chk ok || chk no (chk never fails, so this is safe)
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "P4-REHEARSAL-FAIL: no folder $1"; exit 2; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0; ONLY="${REHEARSE_ONLY:-ABCIWV}"
chk() { if [ "$2" = ok ]; then pass=$((pass+1)); echo "  ok:   $1"; else fail=$((fail+1)); echo "  FAIL: $1"; fi; }
FULL=16bafb3b19b3ace8c67ff37e8bc50f0463d36453; ROOTH=b80370de63d9c52e355129243f424772ddf7fbeb7c7942fe3c5c6ac7a4a0016c; ROOT2=cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc; IMG=tc-img-rel-1
mkdir -p "$W/bin" "$W/stub"; export STUBDIR="$W/stub" LOG="$W/calls.log"
cat > "$W/mkrun.py" <<'PY'
import base64, hashlib, json, os, struct, sys
out, commit, image, root, mut = sys.argv[1:6]; os.makedirs(out, exist_ok=True)
s384 = lambda b: hashlib.sha384(b).digest()
names = ["source", "tc-lib", "tc-conf", "tc-units", "openssl", "wg", "jdk", "java-settings", "java-ca-fingerprints", "hadoop-code", "hadoop-conf", "nutch-deploy", "crawl-params", "crawl-seeds", "fleet-props"]
ev = [(n, s384(("event " + n).encode()).hex()) for n in names]
ev[0] = ("source", s384(("commit %s\n" % (("b" * 40) if mut == "source" else commit)).encode()).hex())
if mut == "event": ev[3] = (ev[3][0], s384(b"another").hex())
if mut == "extra": ev.append(("fleet", s384(b"fleet").hex()))
reg = bytes(48); lines = []
for n, dg in ev: before = reg; reg = hashlib.sha384(reg + bytes.fromhex(dg)).digest(); lines.append("%s\t%s\t%s\t%s" % (n, dg, before.hex(), reg.hex()))
log = ("\n".join(lines) + "\n").encode(); d = {"name": "tc-ref-test", "sign": "SIGNKEY", "wg": "WGKEY", "log_sha512": hashlib.sha512(log).hexdigest()}
def spec():
    x = b"Spec ID Event03\x00" + struct.pack("<I", 0) + bytes([0, 2, 0, 2]) + struct.pack("<I", 1) + struct.pack("<HH", 0x000C, 48) + bytes([0]); return struct.pack("<II20sI", 0, 3, bytes(20), len(x)) + x
def evt(mr, t, data): return struct.pack("<III", mr, t, 1) + struct.pack("<H", 0x000C) + s384(data) + struct.pack("<I", len(data)) + data
kernel = "vmlinuz-6.18" if mut == "kernel" else "vmlinuz-6.17"; uuid = "11111111-2222-3333-4444-555555555555" if mut == "uuid" else "67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8"
rtmr1 = bytes(range(40)) if mut != "rtmr1" else bytes(range(1, 41))
blocks = "" if mut == "noblocks" else "tc.blocks=2621440 "
es = [(1, 0x80000002, ("BootOrderX" if mut == "rtmr0" else "BootOrder").encode("utf-16-le")), (2, 0x80000003, rtmr1), (3, 0xD, ("grub_cmd: linux /boot/%s root=/dev/mapper/vroot ro tc.verity=%s tc.data=%s %stc.salt=%s" % (kernel, root, uuid, blocks, "ab" * 32)).encode() + b"\x00")]
if mut == "tworoots": es.append((3, 0xD, ("kernel_cmdline: root=/dev/mapper/vroot tc.verity=%s tc.data=%s tc.blocks=2621440 tc.salt=%s" % ("e" * 64, uuid, "ab" * 32)).encode() + b"\x00"))
if mut == "rtmr2extra": es.append((3, 0xD, b"grub_cmd: boot\x00"))
r = {}
for m, t, dd in es: r[m] = s384(r.get(m, bytes(48)) + s384(dd))
q = bytearray(700); q[184:232] = s384(b"other" if mut == "mrtd" else b"mrtd"); q[376:424] = r[1]; q[424:472] = r[2]; q[472:520] = r[3]; q[520:568] = reg
if mut == "debug": q[168] = 1
binding = ("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"])).encode()
q[568:632] = hashlib.sha512(binding + (b"x" if mut == "binding" else b"")).digest()
open(out + "/announce.txt", "w").write("name=%s\nsign=%s\nwg=%s\nlog_sha512=%s\nquote_b64=%s\nlog_b64=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"], base64.b64encode(bytes(q)).decode(), base64.b64encode(log).decode()))
open(out + "/quote.bin", "wb").write(bytes(q)); open(out + "/rtmr3-events.tsv", "wb").write(log); open(out + "/ccel.bin", "wb").write(spec() + b"".join(evt(*e) for e in es))
json.dump({"image": image, "image_id": "123", "machine_type": "c3-standard-4", "memory_mb": 16384, "boot_disk_gb": 30, "scratch_disk_gb": 10, "zone": "us-central1-a", "confidential_instance_type": "TDX", "vm": "tc-ref-test", "run_utc": "2026-10-30T10:00:00Z"}, open(out + "/settings.json", "w"))
lab = {"commit": ("b" * 40) if mut == "labels" else commit, "verity-a": ("d" * 32) if mut == "labelroot" else root[:32], "verity-b": ("d" * 32) if mut == "labelroot" else root[32:]}; json.dump({"id": "123", "name": image, "labels": lab}, open(out + "/image.json", "w")); json.dump({"name": "tc-ref-test"}, open(out + "/instance.json", "w"))
PY
mk() { python3 "$W/mkrun.py" "$1" "$FULL" "$IMG" "${3:-$ROOTH}" "${2:-none}"; }
cat > "$W/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
echo "gcloud $*" >> "$LOG"; S="$STUBDIR"
case "$*" in
  "compute images list"*) a="$*"; f="${a#*labels.commit~^}"; pre="${f%% *}"; while read -r name commit; do case "$commit" in "$pre"*) echo "$name";; esac; done < "$S/images.txt";;
  "compute images describe"*) cat "$S/describe.json";;
  *) echo "stub: unexpected gcloud call: $*" >&2; exit 99;;
esac
STUB
cat > "$W/runner.sh" <<'STUB'
#!/usr/bin/env bash
# fake reference-run.sh IMAGE OUT: copies the prepared run N
n="$(cat "$STUBDIR/counter" 2>/dev/null || echo 0)"; echo "run $* project=${IMAGE_PROJECT:-}" >> "$LOG"
if [ -f "$STUBDIR/stockout_once" ]; then rm -f "$STUBDIR/stockout_once"; echo "ERROR: ZONE_RESOURCE_POOL_EXHAUSTED"; exit 1; fi
if [ -f "$STUBDIR/runner_error" ]; then echo "ERROR: something else is wrong with the zone"; exit 1; fi
if [ -f "$STUBDIR/runner_error_after1" ] && [ "$n" -ge 1 ]; then echo "ERROR: something else is wrong with the zone"; exit 1; fi
n=$((n+1)); echo "$n" > "$STUBDIR/counter"; rm -rf "$2"; cp -r "$STUBDIR/run$n" "$2" || exit 1; echo "REFERENCE-RUN-OK image=$1 out=$2"
STUB
cat > "$W/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "gh $*" >> "$LOG"; dir=""; while [ $# -gt 0 ]; do [ "$1" = "--dir" ] && dir="$2"; shift; done
mkdir -p "$dir" && cp "$STUBDIR"/published/* "$dir"/
STUB
chmod +x "$W/bin/gcloud" "$W/runner.sh" "$W/bin/gh"
# ---- a REAL published set: the real publication script on synthetic dummy runs
printf '%s %s\n' "$IMG" "$FULL" > "$STUBDIR/images.txt"; python3 -c "import json; print(json.dumps({'labels': {'commit': '$FULL', 'verity-a': '${ROOTH:0:32}', 'verity-b': '${ROOTH:32}'}}))" > "$STUBDIR/describe.json"; mk "$STUBDIR/run1"; mk "$STUBDIR/run2"; : > "$LOG"
( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" PUBLISH_WAIT=0 PUBLISH_HB=0.2 COMMIT=16bafb3b1 bash "$ROOT/ops/ci/publish-ref.sh" "$W/pubout" ) > "$W/pub.txt" 2>&1
PUB="$W/pubout/publish"; grep -q "^PUBLISH-REF-OK" "$W/pub.txt" || { echo "the fixture could not be made:"; tail -5 "$W/pub.txt"; echo "P4-REHEARSAL-FAIL"; exit 1; }
rm -rf "${STUBDIR:?}"/run* "$STUBDIR/counter"
mk "$STUBDIR/run1" noblocks; mk "$STUBDIR/run2" noblocks; ( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" PUBLISH_WAIT=0 PUBLISH_HB=0.2 COMMIT=16bafb3b1 bash "$ROOT/ops/ci/publish-ref.sh" "$W/pubout2" ) > "$W/pub2.txt" 2>&1   # a second published set whose boot log has no tc.blocks=
PUB2="$W/pubout2/publish"; grep -q "^PUBLISH-REF-OK" "$W/pub2.txt" || { echo "the second fixture could not be made:"; tail -5 "$W/pub2.txt"; echo "P4-REHEARSAL-FAIL"; exit 1; }
rm -rf "${STUBDIR:?}"/run* "$STUBDIR/counter"
ver() { python3 "$ROOT/ops/verify-reference.py" "$@" > "$W/out.txt" 2>&1; echo $?; }
resum() { ( cd "$1" && find . -maxdepth 1 -type f ! -name SHA256SUMS -printf '%f\n' | LC_ALL=C sort | xargs sha256sum > ../sums.tmp ) && mv "$1/../sums.tmp" "$1/SHA256SUMS"; }
fresh() { rm -rf "$W/t"; cp -r "$PUB" "$W/t"; }
want() { grep -q -- "$1" "$W/out.txt"; }
# ---------------------------------------------------------------- A. the published evidence
if [[ "$ONLY" == *A* ]]; then
echo "== A. the published evidence (part A, no cloud)"
rc=$(ver --published "$PUB" --commit 16bafb3b1); n_ok=$(grep -c "^  ok:" "$W/out.txt"); [ "$rc" = 0 ] && want "VERIFY-REFERENCE-OK commit=$FULL image=$IMG own=none explained=0" && [ "$n_ok" -ge 18 ] && chk "a real published set passes all $n_ok checks of part A" ok || chk "good set: rc=$rc $(tail -4 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
rc=$(ver --published "$PUB" --commit "$FULL"); [ "$rc" = 0 ] && chk "the full commit id is accepted too" ok || chk "full commit: rc=$rc" no
rc=$(ver --published "$PUB" --commit xyz); [ "$rc" = 1 ] && want "the commit must be 9 to 40 lowercase hexadecimal digits" && chk "refused: a commit that is not hexadecimal" ok || chk "bad commit: rc=$rc" no
rc=$(ver --published "$PUB" --commit aaaaaaaaa); [ "$rc" = 1 ] && want "the release is of commit 16bafb3b19b3, not of aaaaaaaaa" && chk "refused: the release is of another commit than the one you named" ok || chk "other commit: rc=$rc" no
fresh; echo "x" >> "$W/t/reference.json"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "SHA256SUMS does not match the files: reference.json" && chk "refused: a file changed after SHA256SUMS was made" ok || chk "changed file: rc=$rc" no
fresh; rm "$W/t/ccel.bin"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the published files are missing: ccel.bin" && chk "refused: a missing file is named" ok || chk "missing file: rc=$rc" no
fresh; echo "$(printf 'a%.0s' {1..64})  extra.txt" >> "$W/t/SHA256SUMS"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the list of files differs" && chk "refused: SHA256SUMS that lists a file that is not there" ok || chk "extra sum: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import json, sys
p = sys.argv[1] + "/reference.json"; r = json.load(open(p)); r["rtmr2"] = "00" * 48; json.dump(r, open(p, "w"), indent=2)
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the SHA-256 of reference.json is not the one that release.json records" && want "RTMR2: the quotes and the reference do not agree" && chk "an attacker who changes the reference AND recomputes SHA256SUMS is still caught (the release and the quotes disagree)" ok || chk "recomputed sums: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import hashlib, json, sys
d = sys.argv[1]; r = json.load(open(d + "/reference.json")); r["stable_events"]["source"] = "00" * 48; json.dump(r, open(d + "/reference.json", "w"), indent=2)
rel = json.load(open(d + "/release.json")); rel["reference_sha256"] = hashlib.sha256(open(d + "/reference.json", "rb").read()).hexdigest(); json.dump(rel, open(d + "/release.json", "w"), indent=2)
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the \`source\` event is not the SHA-384 of 'commit" && chk "a reference whose source event is not the hash of the commit is refused (even if the release was updated to match)" ok || chk "source event: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import sys
p = sys.argv[1] + "/quote-run2.bin"; b = bytearray(open(p, "rb").read()); b[480] ^= 1; open(p, "wb").write(bytes(b))
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "RTMR2: the quotes and the reference do not agree" && chk "a second quote that differs in RTMR2 is refused" ok || chk "quote 2: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import sys
p = sys.argv[1] + "/quote-run1.bin"; b = bytearray(open(p, "rb").read()); b[168] |= 1; open(p, "wb").write(bytes(b))
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the quote file differs from the quote in the announcement" && chk "a quote file that is not the quote of the announcement is refused" ok || chk "quote file: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import base64, sys
d = sys.argv[1]; lines = open(d + "/announce-run1.txt").read().splitlines(); out = []
for l in lines:
    if l.startswith("quote_b64="):
        b = bytearray(base64.b64decode(l[len("quote_b64="):])); b[168] |= 1; out.append("quote_b64=" + base64.b64encode(bytes(b)).decode()); open(d + "/quote-run1.bin", "wb").write(bytes(b))
    else: out.append(l)
open(d + "/announce-run1.txt", "w").write("\n".join(out) + "\n")
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "run 1: the TD debug bit is ON" && chk "a published quote with the debug bit on is refused" ok || chk "debug bit: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import sys
p = sys.argv[1] + "/ccel.bin"; b = bytearray(open(p, "rb").read()); b[-5] ^= 1; open(p, "wb").write(bytes(b))
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "does not hash to its digest" && chk "an altered command text no longer hashes to its digest" ok || chk "ccel: rc=$rc $(grep FAIL "$W/out.txt" | head -2 | tr '\n' ' ' | cut -c1-160)" no
fresh; python3 - "$W/t" "$ROOTH" <<'PY'
import sys
p = sys.argv[1] + "/ccel.bin"; b = open(p, "rb").read(); old = sys.argv[2].encode(); assert b.count(old) == 1; open(p, "wb").write(b.replace(old, b"e" * 64))
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "does not hash to its digest" && ! want "the boot event log does not replay" && chk "THE ATTACK: a forged root hash in the text of the kernel command line, with the genuine digest, still replays to the quote but is caught" ok || chk "forged root: rc=$rc $(grep FAIL "$W/out.txt" | head -2 | tr '\n' ' ' | cut -c1-160)" no
fresh; echo "| 99 | EV_IPL | forged | \`00\` |" >> "$W/t/boot-tables.md"; resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "boot-tables.md is not what ops/ccel-table.py makes" && chk "altered tables are caught: they must be exactly what the tool makes from the log" ok || chk "tables: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import json, sys
p = sys.argv[1] + "/release.json"; r = json.load(open(p)); r["verity_root_hash"] = "d" * 64; json.dump(r, open(p, "w"), indent=2)
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the root hash of the release is not the tc.verity= value of the authenticated commands" && chk "a release with another root hash than the kernel command line is refused" ok || chk "root hash: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import json, sys
p = sys.argv[1] + "/release.json"; r = json.load(open(p)); r["image_labels"]["verity-a"] = "f" * 32; json.dump(r, open(p, "w"), indent=2)
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the image labels do not match release.json" && chk "image labels that do not match the root hash of the release are refused" ok || chk "labels: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import json, sys
p = sys.argv[1] + "/settings.json"; r = json.load(open(p)); r["image"] = "tc-img-other"; json.dump(r, open(p, "w"))
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the image name differs between settings.json, release.json and reference.json" && chk "settings of another image are refused" ok || chk "settings image: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import json, sys
p = sys.argv[1] + "/settings.json"; r = json.load(open(p)); r["machine_type"] = "c3-standard-8"; json.dump(r, open(p, "w"))
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the settings of the dummy run differ from the reference" && chk "settings of another machine type are refused" ok || chk "settings machine: rc=$rc" no
fresh; sed -i 's/^name=.*/name=someone-else/' "$W/t/announce-run1.txt"; resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "run 1: the REPORTDATA of the quote is not the SHA-512 of its binding" && chk "an announcement whose keys were swapped no longer matches the quote (binding)" ok || chk "binding: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import base64, sys
d = sys.argv[1]; out = []
for l in open(d + "/announce-run1.txt").read().splitlines():
    if l.startswith("quote_b64="):
        b = bytearray(base64.b64decode(l[len("quote_b64="):])); b[530] ^= 1; out.append("quote_b64=" + base64.b64encode(bytes(b)).decode()); open(d + "/quote-run1.bin", "wb").write(bytes(b))
    else: out.append(l)
open(d + "/announce-run1.txt", "w").write("\n".join(out) + "\n")
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "run 1: the RTMR3 log does not replay to the RTMR3 of the quote" && chk "an RTMR3 that is not the replay of its log is refused" ok || chk "rtmr3 replay: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import hashlib, json, sys
d = sys.argv[1]; r = json.load(open(d + "/reference.json")); r["stable_events"]["tc-lib"] = "00" * 48; json.dump(r, open(d + "/reference.json", "w"), indent=2)
rel = json.load(open(d + "/release.json")); rel["reference_sha256"] = hashlib.sha256(open(d + "/reference.json", "rb").read()).hexdigest(); json.dump(rel, open(d + "/release.json", "w"), indent=2)
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the RTMR3 events of run 1 are not the stable events of the reference" && chk "a reference whose stable events are not the ones of the quote is refused" ok || chk "stable events: rc=$rc" no
fresh; python3 - "$W/t" <<'PY'
import hashlib, sys
p = sys.argv[1] + "/ccel.bin"; b = open(p, "rb").read(); old = hashlib.sha384("BootOrder".encode("utf-16-le")).digest(); assert b.count(old) == 1; open(p, "wb").write(b.replace(old, b"\x11" * 48))
PY
resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "the boot event log does not replay to the quote" && chk "a changed digest in the boot event log no longer replays to the quote" ok || chk "ccel digest: rc=$rc $(grep FAIL "$W/out.txt" | head -2 | tr '\n' ' ' | cut -c1-140)" no
fresh; sed -i 's/^name=.*/&/' "$W/t/rtmr3-events.tsv"; printf 'x' >> "$W/t/rtmr3-events.tsv"; resum "$W/t"; rc=$(ver --published "$W/t" --commit 16bafb3b1); [ "$rc" = 1 ] && want "rtmr3-events.tsv is not the RTMR3 log of the announcement" && chk "rtmr3-events.tsv that differs from the log of the announcement is refused" ok || chk "tsv: rc=$rc" no
fi
# ---------------------------------------------------------------- B. your own dummy run
if [[ "$ONLY" == *B* ]]; then
echo "== B. your own build (part B)"
own() { rm -rf "$W/own"; mk "$W/own" "${1:-none}" "${2:-$ROOTH}"; ver --published "$PUB" --commit 16bafb3b1 --own-run "$W/own"; }
rc=$(own none); [ "$rc" = 0 ] && want "RTMR2 equals the published value" && want "VERIFY-REFERENCE-OK .* own=yes explained=0" && chk "your build equals the published one: all equal, RTMR2 included" ok || chk "own equal: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
rc=$(own none "$ROOT2"); [ "$rc" = 0 ] && want "RTMR2 event 1 differs only in the root hash or a UUID (explained)" && want "explained=1" && want "whether they hold the same files is the file-tree diff" && chk "another root hash: RTMR2 differs only in the event that carries it, and that event is named" ok || chk "own root: rc=$rc $(grep -E 'FAIL|RTMR2' "$W/out.txt" | head -3 | tr '\n' ' ' | cut -c1-200)" no
rc=$(own uuid); [ "$rc" = 0 ] && want "explained=1" && chk "another partition UUID is explained too (it is on the same command line)" ok || chk "own uuid: rc=$rc" no
rc=$(own kernel); [ "$rc" = 1 ] && want "RTMR2 events that differ for another reason than the root hash or a UUID: 1" && chk "a different kernel is NOT explained away: it fails" ok || chk "own kernel: rc=$rc" no
rc=$(own source); [ "$rc" = 1 ] && want "your \`source\` event differs: your image was not built from commit" && chk "an image built from another commit is refused" ok || chk "own source: rc=$rc" no
rc=$(own mrtd); [ "$rc" = 1 ] && want "MRTD differs from the published value" && chk "a different MRTD is refused" ok || chk "own mrtd: rc=$rc" no
rc=$(own rtmr1); [ "$rc" = 1 ] && want "RTMR1 differs from the published value" && chk "a different RTMR1 is refused" ok || chk "own rtmr1: rc=$rc" no
rc=$(own event); [ "$rc" = 1 ] && want "RTMR3 events with another digest: tc-units" && chk "an RTMR3 event with another digest is named and refused" ok || chk "own event: rc=$rc" no
rc=$(own extra); [ "$rc" = 1 ] && want "your RTMR3 events are not the stable events of the reference" && chk "an extra RTMR3 event is refused" ok || chk "own extra: rc=$rc" no
rc=$(own debug); [ "$rc" = 1 ] && want "your run: the TD debug bit is ON" && chk "your own run with the debug bit on is refused" ok || chk "own debug: rc=$rc" no
rc=$(own binding); [ "$rc" = 1 ] && want "your run: the REPORTDATA of the quote is not the SHA-512 of its binding" && chk "your own run with a broken binding is refused" ok || chk "own binding: rc=$rc" no
rm -rf "$W/own"; mk "$W/own" none "$ROOT2"; rm "$W/own/ccel.bin"; rc=$(ver --published "$PUB" --commit 16bafb3b1 --own-run "$W/own"); [ "$rc" = 1 ] && want "your run has no boot event log (ccel.bin), so the difference cannot be explained" && chk "an RTMR2 difference without a boot event log of yours cannot be explained: it fails" ok || chk "no ccel, differs: rc=$rc" no
rm -rf "$W/own"; mk "$W/own" none; rm "$W/own/ccel.bin"; rc=$(ver --published "$PUB" --commit 16bafb3b1 --own-run "$W/own"); [ "$rc" = 0 ] && chk "an RTMR2 that is equal needs no boot event log of yours" ok || chk "no ccel, equal: rc=$rc" no
rm -rf "$W/own"; mk "$W/own"; rm "$W/own/announce.txt"; rc=$(ver --published "$PUB" --commit 16bafb3b1 --own-run "$W/own"); [ "$rc" = 1 ] && want "the file is missing: $W/own/announce.txt" && chk "a missing file of your run is named" ok || chk "own missing: rc=$rc" no
rc=$(own rtmr0); [ "$rc" = 1 ] && want "RTMR0 differs from the published value" && chk "a different RTMR0 is refused" ok || chk "own rtmr0: rc=$rc" no
rc=$(own rtmr2extra); [ "$rc" = 1 ] && want "RTMR2 has 2 events in your run and 1 in the published log" && chk "an extra RTMR2 event in your run is refused" ok || chk "own rtmr2extra: rc=$rc $(grep -E 'FAIL' "$W/out.txt" | head -2 | tr '\n' ' ' | cut -c1-160)" no
fi
# ---------------------------------------------------------------- C. the command
if [[ "$ONLY" == *C* ]]; then
echo "== C. ops/verify-reference.sh"
cmd() { : > "$LOG"; rm -rf "${STUBDIR:?}"/run* "$STUBDIR/counter" "$STUBDIR/stockout_once" "$STUBDIR/runner_error" "$STUBDIR/published"; mk "$STUBDIR/run1" none "$ROOT2"; mkdir -p "$STUBDIR/published"; cp "$PUB"/* "$STUBDIR/published/"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" VERIFY_WAIT=0 VERIFY_HB=0.2 "$@" ) > "$W/out.txt" 2>&1; echo $?; }
rc=$(cmd bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --published "$PUB" --own-image tc-img-own --work "$W/w1"); [ "$rc" = 0 ] && want "VERIFY-REFERENCE-OK .* own=yes explained=1" && [ "$(grep -c '^run ' "$LOG")" = 1 ] && grep -q "^run tc-img-own " "$LOG" && chk "with --own-image: one dummy run of your image, then the verdict" ok || chk "wrapper own: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
rc=$(cmd bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --published "$PUB" --work "$W/w2"); [ "$rc" = 0 ] && want "own=none" && [ "$(grep -c '^run ' "$LOG")" = 0 ] && chk "without --own-image no VM is made (part A only)" ok || chk "wrapper no own: rc=$rc" no
: > "$LOG"; rm -rf "${STUBDIR:?}"/run* "$STUBDIR/counter"; mk "$STUBDIR/run1" none "$ROOT2"; touch "$STUBDIR/stockout_once"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" VERIFY_WAIT=0 VERIFY_HB=0.2 bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --published "$PUB" --own-image tc-img-own --work "$W/w3" ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 0 ] && want "no capacity right now (attempt 1 of 6)" && chk "a stockout is waited out and the run goes on" ok || chk "wrapper stockout: rc=$rc" no
: > "$LOG"; rm -rf "${STUBDIR:?}"/run* "$STUBDIR/counter"; touch "$STUBDIR/runner_error"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" VERIFY_WAIT=0 VERIFY_HB=0.2 bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --published "$PUB" --own-image tc-img-own --work "$W/w4" ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 1 ] && want "your own dummy run did not finish; the end of its output: ERROR: something else" && chk "another error of your dummy run stops with the end of its output" ok || chk "wrapper error: rc=$rc" no
rc=$(cmd bash "$ROOT/ops/verify-reference.sh"); [ "$rc" = 2 ] && want "Usage:" && chk "no arguments: the usage, exit code 2" ok || chk "no args: rc=$rc" no
rc=$(cmd bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --nonsense x); [ "$rc" = 2 ] && want "unknown option: --nonsense" && chk "an unknown option is refused" ok || chk "unknown option: rc=$rc" no
rc=$(cmd bash "$ROOT/ops/verify-reference.sh" 16bafb3b1); [ "$rc" = 2 ] && want "give exactly one of --published and --release" && chk "neither --published nor --release is refused" ok || chk "no source: rc=$rc" no
rc=$(cmd bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --published "$PUB" --release publish-ref-16bafb3b1); [ "$rc" = 2 ] && want "give exactly one of" && chk "both --published and --release are refused" ok || chk "both sources: rc=$rc" no
rc=$(cmd bash "$ROOT/ops/verify-reference.sh" XYZ --published "$PUB"); [ "$rc" = 2 ] && want "COMMIT must be 9 to 40 lowercase hexadecimal digits" && chk "a commit that is not hexadecimal is refused by the command" ok || chk "bad commit: rc=$rc" no
rc=$(cmd bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --release publish-ref-16bafb3b1 --work "$W/w5"); [ "$rc" = 0 ] && grep -q "^gh release download publish-ref-16bafb3b1 --repo Heron-AI-Security/nutch-private --dir $W/w5/published" "$LOG" && chk "--release downloads the release with gh and verifies it" ok || chk "wrapper release: rc=$rc $(tail -2 "$W/out.txt" | tr '\n' ' ' | cut -c1-150)" no
: > "$LOG"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GH=gh-does-not-exist bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --release publish-ref-16bafb3b1 --work "$W/w6" ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 1 ] && want "the gh CLI is needed for --release" && chk "--release without gh says what to do" ok || chk "no gh: rc=$rc" no
fi
# ---------------------------------------------------------------- I. the published image and the file trees (ops/verify-reference.py)
if [[ "$ONLY" == *I* ]]; then
echo "== I. the published image and the file trees (part B1 and C)"
img() { rm -rf "$W/img"; mk "$W/img" "${1:-none}" "${2:-$ROOTH}"; }
# shellcheck disable=SC2119,SC2120   # the helpers take extra arguments only in some calls
vi() { ver --published "$PUB" --commit 16bafb3b1 --image-run "$W/img" "$@"; }
printf 'TREE-DIFF-IDENTICAL files=10 dirs=3 symlinks=1 ignored=0 verity=checked\n== cleaning up: deleting the helper VM x\n' > "$W/tv-ok.txt"; printf 'TREE-DIFF-IDENTICAL files=10 dirs=3 symlinks=1 ignored=0 verity=unchecked\n' > "$W/tv-unchecked.txt"; printf 'TREE-DIFF-DIFFERENT differences=3 ignored=0\n' > "$W/tv-diff.txt"; printf 'TREE-DIFF-FAILED: the helper VM could not be made\n' > "$W/tv-fail.txt"; printf '== nothing useful\n' > "$W/tv-none.txt"
img none; rc=$(vi); [ "$rc" = 0 ] && want "the published image is the image of the release" && want "image-run=exact" && chk "a dummy run of the published image that reproduces the reference exactly is accepted" ok || chk "image ok: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
img none "$ROOT2"; rc=$(vi); [ "$rc" = 1 ] && want "RTMR2 of the published image differs from the published value" && chk "for the PUBLISHED image another root hash is NOT an explained difference: it fails" ok || chk "image root: rc=$rc" no
img kernel; rc=$(vi); [ "$rc" = 1 ] && want "RTMR2 of the published image differs" && chk "a published image with another kernel is refused" ok || chk "image kernel: rc=$rc" no
img source; rc=$(vi); [ "$rc" = 1 ] && want "its RTMR3 events are not exactly the published ones" && chk "a published image built from another commit is refused (source event)" ok || chk "image source: rc=$rc" no
img mrtd; rc=$(vi); [ "$rc" = 1 ] && want "MRTD of the published image differs" && chk "a published image with another MRTD is refused" ok || chk "image mrtd: rc=$rc" no
img rtmr1; rc=$(vi); [ "$rc" = 1 ] && want "RTMR1 of the published image differs" && chk "a published image with another RTMR1 is refused" ok || chk "image rtmr1: rc=$rc" no
img rtmr0; rc=$(vi); [ "$rc" = 1 ] && want "RTMR0 of the published image differs" && chk "a published image with another RTMR0 is refused" ok || chk "image rtmr0: rc=$rc" no
img event; rc=$(vi); [ "$rc" = 1 ] && want "its RTMR3 events are not exactly the published ones" && chk "a published image with another RTMR3 event is refused" ok || chk "image event: rc=$rc" no
img extra; rc=$(vi); [ "$rc" = 1 ] && want "its RTMR3 events are not exactly the published ones" && chk "a published image with an extra RTMR3 event is refused" ok || chk "image extra: rc=$rc" no
img debug; rc=$(vi); [ "$rc" = 1 ] && want "image run: the TD debug bit is ON" && chk "a run of the published image with the debug bit on is refused" ok || chk "image debug: rc=$rc" no
img binding; rc=$(vi); [ "$rc" = 1 ] && want "image run: the REPORTDATA of the quote is not the SHA-512 of its binding" && chk "a run of the published image with a broken binding is refused" ok || chk "image binding: rc=$rc" no
img labels; rc=$(vi); [ "$rc" = 1 ] && want "the image labels name commit bbbbbbbbbbbb, not 16bafb3b19b3" && chk "an image whose labels name another commit is refused" ok || chk "image labels: rc=$rc" no
img labelroot; rc=$(vi); [ "$rc" = 1 ] && want "the image labels do not carry the root hash of the release" && chk "an image whose labels carry another root hash is refused" ok || chk "image labelroot: rc=$rc" no
rm -rf "$W/img"; mk "$W/img"; rm "$W/img/announce.txt"; rc=$(vi); [ "$rc" = 1 ] && want "the file is missing: $W/img/announce.txt" && chk "a missing file of the image run is named" ok || chk "image missing: rc=$rc" no
rm -rf "$W/img"; mk "$W/img"; rm "$W/img/image.json"; rc=$(vi); [ "$rc" = 0 ] && chk "a run without image.json is still accepted (the labels are only an extra check)" ok || chk "no image.json: rc=$rc" no
own() { rm -rf "$W/own"; mk "$W/own" "${1:-none}" "${2:-$ROOTH}"; }
vo() { ver --published "$PUB" --commit 16bafb3b1 --own-run "$W/own" "$@"; }
own none "$ROOT2"; rc=$(vo --tree-result "$W/tv-ok.txt"); [ "$rc" = 0 ] && want "the two file trees are identical, and both disks were opened through dm-verity against their root hash: TREE-DIFF-IDENTICAL" && want "explained=1 trees=identical image-run=none" && ! want "it was NOT run here" && chk "a root hash difference that is explained, and identical file trees: OK, trees=identical" ok || chk "tree ok: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
own none "$ROOT2"; rc=$(vo --tree-result "$W/tv-unchecked.txt"); [ "$rc" = 1 ] && want "identical but at least one disk was NOT checked against its root hash" && chk "identical trees from disks that were NOT verity-checked do not count" ok || chk "unchecked: rc=$rc" no
rc=$(vo --tree-result "$W/tv-diff.txt"); [ "$rc" = 1 ] && want "the two file trees are NOT shown to be identical: TREE-DIFF-DIFFERENT differences=3" && chk "file trees that differ make the verdict FAIL" ok || chk "tree diff: rc=$rc" no
rc=$(vo --tree-result "$W/tv-fail.txt"); [ "$rc" = 1 ] && want "TREE-DIFF-FAILED: the helper VM could not be made" && chk "a failed file-tree comparison makes the verdict FAIL" ok || chk "tree failed: rc=$rc" no
rc=$(vo --tree-result "$W/tv-none.txt"); [ "$rc" = 1 ] && want "(no TREE-DIFF verdict line)" && chk "a result without a verdict line makes the verdict FAIL" ok || chk "tree none: rc=$rc" no
rc=$(vo --tree-result "$W/does-not-exist.txt"); [ "$rc" = 1 ] && want "(no TREE-DIFF verdict line)" && chk "a missing tree result file makes the verdict FAIL" ok || chk "tree missing: rc=$rc" no
rc=$(vo); [ "$rc" = 0 ] && want "explained=1 trees=not-compared" && want "it was NOT run here" && chk "an explained difference without a tree result is OK but says trees=not-compared and that the files were not compared" ok || chk "not compared: rc=$rc" no
own none; rc=$(vo); [ "$rc" = 0 ] && want "explained=0 trees=not-needed" && chk "an equal RTMR2 needs no file trees (trees=not-needed)" ok || chk "not needed: rc=$rc" no
own none; rc=$(vo --tree-result "$W/tv-ok.txt"); [ "$rc" = 0 ] && want "trees=identical" && chk "an equal RTMR2 with a tree result that is identical also says trees=identical" ok || chk "equal+tree: rc=$rc" no
own source "$ROOT2"; rc=$(vo --tree-result "$W/tv-ok.txt"); [ "$rc" = 1 ] && want "your \`source\` event differs" && chk "identical file trees do NOT rescue a build from another commit" ok || chk "source+tree: rc=$rc" no
own kernel "$ROOT2"; rc=$(vo --tree-result "$W/tv-ok.txt"); [ "$rc" = 1 ] && want "RTMR2 events that differ for another reason" && chk "identical file trees do NOT rescue a different kernel" ok || chk "kernel+tree: rc=$rc" no
img none; own none "$ROOT2"; rc=$(ver --published "$PUB" --commit 16bafb3b1 --image-run "$W/img" --own-run "$W/own" --tree-result "$W/tv-ok.txt"); [ "$rc" = 0 ] && want "explained=1 trees=identical image-run=exact" && chk "everything together: the published image reproduces the reference, your build differs only in the root hash, the trees are identical: OK" ok || chk "all together: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
fi
if [[ "$ONLY" == *V* ]]; then
echo "== V. the dm-verity parameters of an image (--verity-of)"
vv() { python3 "$ROOT/ops/verify-reference.py" --verity-of "$1" > "$W/out.txt" 2>&1; echo $?; }
SALT64=abababababababababababababababababababababababababababababababab; UU1=67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8
rc=$(vv "$PUB"); [ "$rc" = 0 ] && [ "$(cat "$W/out.txt")" = "$ROOTH 2621440 $SALT64 $UU1" ] && chk "a published set gives root hash, blocks, salt and partition id of its image (from the authenticated command events)" ok || chk "verity-of published: rc=$rc $(cat "$W/out.txt" | head -2 | tr '\n' ' ' | cut -c1-200)" no
rm -rf "$W/vr"; mk "$W/vr" none "$ROOT2"; rc=$(vv "$W/vr"); [ "$rc" = 0 ] && [ "$(cat "$W/out.txt")" = "$ROOT2 2621440 $SALT64 $UU1" ] && chk "a folder of a dummy run (quote.bin) gives the parameters of ITS image" ok || chk "verity-of run: rc=$rc" no
rm -rf "$W/vr"; mk "$W/vr" uuid; rc=$(vv "$W/vr"); [ "$rc" = 0 ] && grep -q "11111111-2222-3333-4444-555555555555$" "$W/out.txt" && chk "another partition id is read as it is" ok || chk "verity-of uuid: rc=$rc" no
rm -rf "$W/vr"; mk "$W/vr"; rm "$W/vr/ccel.bin"; rc=$(vv "$W/vr"); [ "$rc" = 1 ] && grep -q "does not publish one" "$W/out.txt" && chk "no boot event log: refused, with the reason" ok || chk "verity-of no ccel: rc=$rc" no
rm -rf "$W/vr"; mk "$W/vr"; python3 - "$W/vr" "$ROOTH" <<'PY'
import sys
p = sys.argv[1] + "/ccel.bin"; b = open(p, "rb").read(); old = sys.argv[2].encode(); assert b.count(old) == 1; open(p, "wb").write(b.replace(old, b"e" * 64))
PY
rc=$(vv "$W/vr"); [ "$rc" = 1 ] && grep -q "does not hash to its digest" "$W/out.txt" && chk "THE ATTACK again: a forged root hash in the text of a command event is not accepted as a parameter" ok || chk "verity-of forged: rc=$rc $(head -1 "$W/out.txt" | cut -c1-120)" no
rm -rf "$W/vr"; mk "$W/vr"; python3 - "$W/vr" <<'PY'
import hashlib, sys
p = sys.argv[1] + "/ccel.bin"; b = open(p, "rb").read(); old = hashlib.sha384("BootOrder".encode("utf-16-le")).digest(); assert b.count(old) == 1; open(p, "wb").write(b.replace(old, b"\x11" * 48))
PY
rc=$(vv "$W/vr"); [ "$rc" = 1 ] && grep -q "does not replay to its quote" "$W/out.txt" && chk "a boot event log that does not replay to its quote gives no parameters" ok || chk "verity-of replay: rc=$rc" no
rm -rf "$W/vr"; mk "$W/vr" tworoots; rc=$(vv "$W/vr"); [ "$rc" = 1 ] && grep -q "tc.verity= has 2 different values" "$W/out.txt" && chk "two different root hashes in the authenticated events: refused" ok || chk "verity-of two roots: rc=$rc $(head -1 "$W/out.txt" | cut -c1-120)" no
rm -rf "$W/vr"; mk "$W/vr" noblocks; rc=$(vv "$W/vr"); [ "$rc" = 1 ] && grep -q "tc.blocks= has 0 different values" "$W/out.txt" && chk "a missing block count: refused, with the name of the parameter" ok || chk "verity-of noblocks: rc=$rc" no

fi
# ---------------------------------------------------------------- W. ops/verify-reference.sh with the published image and the trees
if [[ "$ONLY" == *W* ]]; then
echo "== W. ops/verify-reference.sh: the published image, the file trees, the order"
mkdir -p "$W/bin" "$W/stub"; export STUBDIR="$W/stub" LOG="$W/calls.log"
cat > "$W/treediff.sh" <<'STUB'
#!/usr/bin/env bash
echo "treediff $*" >> "$LOG"; mode="$(cat "$STUBDIR/tree_mode" 2>/dev/null || echo identical)"
echo "== 1. the disk(s) made from the image(s)"
case "$mode" in identical) echo "TREE-DIFF-IDENTICAL files=10 dirs=3 symlinks=1 ignored=0 verity=checked"; rc=0;; different) echo "TREE-DIFF-DIFFERENT differences=3 ignored=0"; rc=1;; failed) echo "TREE-DIFF-FAILED: the helper VM could not be made"; rc=2;; *) rc=2;; esac
echo "== cleaning up: deleting the helper VM tc-tree-x"; exit $rc
STUB
chmod +x "$W/treediff.sh"
w() { local pm="$1" om="$2" orr="$3" tm="$4"; shift 4
  : > "$LOG"; rm -rf "${STUBDIR:?}"/run* "$STUBDIR/counter" "$STUBDIR/stockout_once" "$STUBDIR/runner_error" "$STUBDIR/published" "$STUBDIR/tree_mode"; mk "$STUBDIR/run1" "$pm"; mk "$STUBDIR/run2" "$om" "$orr"; mkdir -p "$STUBDIR/published"; cp "$PUB"/* "$STUBDIR/published/"; echo "$tm" > "$STUBDIR/tree_mode"
  ( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" TC_TREE_DIFF="$W/treediff.sh" VERIFY_WAIT=0 VERIFY_HB=0.2 "$@" ) > "$W/out.txt" 2>&1; echo $?; }
V=(bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --published "$PUB")
rc=$(w none none "$ROOT2" identical "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --work "$W/x1"); [ "$rc" = 0 ] && want "VERIFY-REFERENCE-OK .* explained=1 trees=identical image-run=exact" && [ "$(grep -c '^run ' "$LOG")" = 2 ] && [ "$(grep '^run ' "$LOG" | sed -n 1p | cut -d' ' -f2)" = tc-img-pub ] && [ "$(grep '^run ' "$LOG" | sed -n 2p | cut -d' ' -f2)" = tc-img-own ] && grep -q "^treediff diff tc-img-pub tc-img-own --verity-a $ROOTH 2621440 abababababababababababababababababababababababababababababababab 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8 --verity-b $ROOT2 2621440 abababababababababababababababababababababababababababababababab 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8 --work $W/x1/trees$" "$LOG" && chk "the full flow: your run of the published image FIRST, then your own run, then the tree diff WITH the dm-verity parameters of both images (read from their authenticated boot logs), then OK" ok || chk "full flow: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
rc=$(w none none "$ROOT2" different "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --work "$W/x2"); [ "$rc" = 1 ] && want "the two file trees are NOT shown to be identical: TREE-DIFF-DIFFERENT" && chk "file trees that differ: the command fails" ok || chk "trees differ: rc=$rc" no
rc=$(w none none "$ROOT2" failed "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --work "$W/x3"); [ "$rc" = 1 ] && want "TREE-DIFF-FAILED: the helper VM could not be made" && chk "a failed tree diff: the command fails and shows why (the verdict is found although clean-up lines follow it)" ok || chk "trees failed: rc=$rc" no
rc=$(w none none "$ROOT2" none "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --work "$W/x4"); [ "$rc" = 1 ] && want "TREE-DIFF-FAILED: no verdict (see $W/x4/trees.log)" && chk "a tree diff that printed no verdict at all: the command fails and points to its log" ok || chk "trees none: rc=$rc" no
rc=$(w none none "$ROOT2" identical "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --no-trees --work "$W/x5"); [ "$rc" = 0 ] && want "trees=not-compared" && ! grep -q "^treediff" "$LOG" && chk "--no-trees leaves the tree diff out, and the verdict says trees=not-compared" ok || chk "no-trees: rc=$rc" no
rc=$(w none none "$ROOT2" identical "${V[@]}" --published-image proj-x/tc-img-pub --own-image tc-img-own --work "$W/x6"); [ "$rc" = 0 ] && grep -q "^run tc-img-pub .* project=proj-x$" "$LOG" && grep -q "^run tc-img-own .* project=$" "$LOG" && grep -q "^treediff diff proj-x/tc-img-pub tc-img-own --verity-a " "$LOG" && chk "PROJECT/IMAGE: the dummy run gets IMAGE_PROJECT only for the published image, and the tree diff gets the full name" ok || chk "project: rc=$rc $(grep -E '^run|^treediff' "$LOG" | tr '\n' '|' | cut -c1-250)" no
rc=$(w none none "$ROOT2" identical "${V[@]}" --published-image tc-img-pub --work "$W/x7"); [ "$rc" = 0 ] && want "own=none explained=0 trees=n/a image-run=exact" && [ "$(grep -c '^run ' "$LOG")" = 1 ] && ! grep -q "^treediff" "$LOG" && chk "only the published image: one dummy run, no tree diff, image-run=exact" ok || chk "only published image: rc=$rc" no
printf '/var/log/*\n' > "$W/ign.txt"; rc=$(w none none "$ROOT2" identical "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --ignore "$W/ign.txt" --work "$W/x8"); [ "$rc" = 0 ] && grep -q "^treediff diff tc-img-pub tc-img-own --verity-a .* --verity-b .* --work $W/x8/trees --ignore $W/ign.txt$" "$LOG" && chk "--ignore FILE is handed to the tree diff" ok || chk "ignore: rc=$rc" no
rc=$(w none none "$ROOT2" identical "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --ignore "$W/nonexistent" --work "$W/x9"); [ "$rc" = 1 ] && want "the ignore file $W/nonexistent does not exist" && [ "$(grep -c '^run ' "$LOG")" = 0 ] && chk "a missing ignore file is refused before any VM is made" ok || chk "no ignore file: rc=$rc" no
: > "$LOG"; rm -rf "${STUBDIR:?}"/run* "$STUBDIR/counter"; touch "$STUBDIR/runner_error"; mkdir -p "$STUBDIR/published"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" TC_TREE_DIFF="$W/treediff.sh" VERIFY_WAIT=0 VERIFY_HB=0.2 "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --work "$W/x10" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 1 ] && want "your dummy run of the published image did not finish; the end of its output: ERROR: something else" && [ "$(grep -c '^run ' "$LOG")" = 1 ] && ! grep -q "^treediff" "$LOG" && chk "a failure of the dummy run of the published image stops everything: no own run, no tree diff" ok || chk "image run fails: rc=$rc" no
rc=$(w kernel none "$ROOT2" identical "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --work "$W/x11"); [ "$rc" = 1 ] && want "RTMR2 of the published image differs" && want "stopped before the other steps" && [ "$(grep -c '^run ' "$LOG")" = 1 ] && ! grep -q "^treediff" "$LOG" && chk "a published image that does not reproduce the reference stops the command EARLY: no own run, no tree diff (it saves time and money)" ok || chk "early stop: rc=$rc $(grep -c '^run ' "$LOG") runs" no
: > "$LOG"; rm -rf "${STUBDIR:?}"/run* "$STUBDIR/counter" "$STUBDIR/runner_error"; mk "$STUBDIR/run1" none; mk "$STUBDIR/run2" none "$ROOT2"; touch "$STUBDIR/stockout_once"; echo identical > "$STUBDIR/tree_mode"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" TC_TREE_DIFF="$W/treediff.sh" VERIFY_WAIT=0 VERIFY_HB=0.2 "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --work "$W/x12" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 0 ] && want "no capacity right now (attempt 1 of 6)" && want "trees=identical image-run=exact" && chk "a stockout during the run of the published image is waited out too" ok || chk "stockout published: rc=$rc" no
rm -rf "${STUBDIR:?}"/run* "$STUBDIR/counter" "$STUBDIR/stockout_once" "$STUBDIR/runner_error" "$STUBDIR/published"; : > "$LOG"; mk "$STUBDIR/run1" none; mkdir -p "$STUBDIR/published"; cp "$PUB"/* "$STUBDIR/published/"; echo identical > "$STUBDIR/tree_mode"; touch "$STUBDIR/runner_error_after1"
( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" TC_TREE_DIFF="$W/treediff.sh" VERIFY_WAIT=0 VERIFY_HB=0.2 "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --work "$W/x13" ) > "$W/out.txt" 2>&1; rc=$?; rm -f "$STUBDIR/runner_error_after1"
[ "$rc" = 1 ] && want "your own dummy run did not finish; the end of its output: ERROR: something else" && [ "$(grep -c '^run ' "$LOG")" = 2 ] && ! grep -q "^treediff" "$LOG" && chk "the published image is fine but YOUR OWN run fails: the command stops, the helper VM of the tree diff is never started" ok || chk "own run fails after the published run: rc=$rc runs=$(grep -c '^run ' "$LOG")" no
rc=$(w none noblocks "$ROOT2" identical "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --work "$W/x14"); [ "$rc" = 1 ] && want "the dm-verity parameters of your own image cannot be read from the authenticated boot log of your dummy run" && want "tc.blocks= has 0 different values" && [ "$(grep -c '^run ' "$LOG")" = 2 ] && ! grep -q "^treediff" "$LOG" && chk "your image without readable dm-verity parameters: the command stops before the tree diff and says why" ok || chk "own params: rc=$rc" no
rc=$(w none none "$ROOT2" identical "${V[@]}" --published-image tc-img-pub --own-image tc-img-own --no-trees --work "$W/x16"); [ "$rc" = 0 ] && ! grep -q "verity-of" "$W/out.txt" && chk "--no-trees does not need the dm-verity parameters" ok || chk "no-trees verity: rc=$rc" no
rc=$(w none none "$ROOT2" identical bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --published "$PUB2" --published-image tc-img-pub --own-image tc-img-own --work "$W/x17"); [ "$rc" = 1 ] && want "the dm-verity parameters of the published image cannot be read from its authenticated boot log" && want "tc.blocks= has 0 different values" && [ "$(grep -c '^run ' "$LOG")" = 0 ] && ! grep -q "^treediff" "$LOG" && chk "a published release whose boot log has no dm-verity parameters: the command stops BEFORE any VM is made" ok || chk "published params: rc=$rc runs=$(grep -c '^run ' "$LOG")" no
rc=$(w none none "$ROOT2" identical bash "$ROOT/ops/verify-reference.sh" 16bafb3b1 --published-image x); [ "$rc" = 2 ] && want "give exactly one of --published and --release" && chk "--published-image does not replace --published or --release" ok || chk "no published: rc=$rc" no
fi
echo; echo "pass: $pass   fail: $fail"
if [ "$fail" = 0 ]; then echo "P4-REHEARSAL-PASS"; else echo "P4-REHEARSAL-FAIL"; exit 1; fi
