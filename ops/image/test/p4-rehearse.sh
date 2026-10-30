#!/usr/bin/env bash
# ops/image/test/p4-rehearse.sh: the offline rehearsal of step P4 (no Google, no GitHub): ops/verify-reference.py and ops/verify-reference.sh against a REAL published set (made by ops/ci/publish-ref.sh from synthetic dummy runs),
# attacked in many ways, and against your own dummy runs that differ from the published one in many ways.
# Usage:  bash ops/image/test/p4-rehearse.sh [ROOT]      ROOT is the repository folder (default: three folders above this script).   Ends with  pass: N   fail: M  and P4-REHEARSAL-PASS or P4-REHEARSAL-FAIL.
# shellcheck disable=SC2015   # the chk lines are written as: test && chk ok || chk no (chk never fails, so this is safe)
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "P4-REHEARSAL-FAIL: no folder $1"; exit 2; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0; ONLY="${REHEARSE_ONLY:-ABC}"
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
es = [(1, 0x80000002, ("BootOrderX" if mut == "rtmr0" else "BootOrder").encode("utf-16-le")), (2, 0x80000003, rtmr1), (3, 0xD, ("grub_cmd: linux /boot/%s root=/dev/mapper/vroot ro tc.verity=%s tc.data=%s tc.salt=00" % (kernel, root, uuid)).encode() + b"\x00")]
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
json.dump({"id": "123", "name": image, "labels": {"commit": commit}}, open(out + "/image.json", "w")); json.dump({"name": "tc-ref-test"}, open(out + "/instance.json", "w"))
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
n="$(cat "$STUBDIR/counter" 2>/dev/null || echo 0)"; echo "run $* " >> "$LOG"
if [ -f "$STUBDIR/stockout_once" ]; then rm -f "$STUBDIR/stockout_once"; echo "ERROR: ZONE_RESOURCE_POOL_EXHAUSTED"; exit 1; fi
if [ -f "$STUBDIR/runner_error" ]; then echo "ERROR: something else is wrong with the zone"; exit 1; fi
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
echo; echo "pass: $pass   fail: $fail"
if [ "$fail" = 0 ]; then echo "P4-REHEARSAL-PASS"; else echo "P4-REHEARSAL-FAIL"; exit 1; fi
