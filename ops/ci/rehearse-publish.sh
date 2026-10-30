#!/usr/bin/env bash
# ops/ci/rehearse-publish.sh: the offline rehearsal of step P3.2 (no Google, no GitHub): ops/make-reference.py and ops/ci/publish-ref.sh against synthetic dummy runs, a fake gcloud and a fake dummy-run script.
# Usage:  bash ops/ci/rehearse-publish.sh [ROOT]      ROOT is the repository folder (default: two folders above this script).    Ends with  pass: N   fail: M  and PUBLISH-REHEARSAL-PASS or PUBLISH-REHEARSAL-FAIL.
# shellcheck disable=SC2015   # the chk lines are written as: test && chk ok || chk no (chk never fails, so this is safe)
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "PUBLISH-REHEARSAL-FAIL: no folder $1"; exit 2; }
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0; ONLY="${REHEARSE_ONLY:-AB}"   # A or B runs only that part (used to test the tests); the default runs both
chk() { if [ "$2" = ok ]; then pass=$((pass+1)); echo "  ok:   $1"; else fail=$((fail+1)); echo "  FAIL: $1"; fi; }
FULL=16bafb3b19b3ace8c67ff37e8bc50f0463d36453; OTHER=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa; ROOTH=b80370de63d9c52e355129243f424772ddf7fbeb7c7942fe3c5c6ac7a4a0016c; IMG=tc-img-rel-1
mkdir -p "$W/bin" "$W/stub"; export STUBDIR="$W/stub" LOG="$W/calls.log"
# ---- the synthetic dummy runs: valid announcement, quote, RTMR3 log, boot log, settings
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
es = [(1, 0x80000002, "BootOrder".encode("utf-16-le")), (2, 0x80000003, bytes(range(40))), (3, 0xD, b"grub_cmd: linux /boot/vmlinuz-6.17 root=/dev/mapper/vroot tc.verity=" + root.encode() + b" tc.salt=00\x00")]
if mut == "rtmr2": es[2] = (3, 0xD, b"grub_cmd: linux /boot/vmlinuz-6.17 root=/dev/mapper/vroot tc.verity=" + root.encode() + b" tc.salt=11\x00")
r = {}
for m, t, dd in es: r[m] = s384(r.get(m, bytes(48)) + s384(dd))
q = bytearray(700); q[184:232] = s384(b"mrtd"); q[376:424] = r[1]; q[424:472] = r[2]; q[472:520] = r[3]; q[520:568] = bytes(48) if mut == "rtmr3" else reg
if mut == "debug": q[168] = 1
binding = ("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"])).encode()
q[568:632] = hashlib.sha512(binding + (b"x" if mut == "binding" else b"")).digest()
open(out + "/announce.txt", "w").write("name=%s\nsign=%s\nwg=%s\nlog_sha512=%s\nquote_b64=%s\nlog_b64=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"], base64.b64encode(bytes(q)).decode(), base64.b64encode(log).decode()))
open(out + "/quote.bin", "wb").write(bytes(q)); open(out + "/rtmr3-events.tsv", "wb").write(log); open(out + "/ccel.bin", "wb").write(spec() + b"".join(evt(*e) for e in es))
st = {"image": "tc-img-other" if mut == "image" else image, "image_id": "123", "machine_type": "c3-standard-8" if mut == "setting" else "c3-standard-4", "memory_mb": 16384, "boot_disk_gb": 30, "scratch_disk_gb": 10, "zone": "us-central1-a", "confidential_instance_type": "TDX", "vm": "tc-ref-test", "run_utc": "2026-10-30T10:00:00Z"}
if mut == "leak": st["note"] = "project training-custody"
json.dump(st, open(out + "/settings.json", "w")); json.dump({"id": "123", "name": image, "labels": {"commit": commit}}, open(out + "/image.json", "w")); json.dump({"name": "tc-ref-test", "selfLink": "https://www.googleapis.com/compute/v1/projects/training-custody/zones/us-central1-a/instances/tc-ref-test"}, open(out + "/instance.json", "w"))
PY
mk() { python3 "$W/mkrun.py" "$1" "$FULL" "$IMG" "$ROOTH" "${2:-none}"; }
# ---- the fake gcloud (images by label) and the fake dummy-run script
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
# fake reference-run.sh IMAGE OUT: copies the prepared run N (the counter counts the calls that were not refused)
n="$(cat "$STUBDIR/counter" 2>/dev/null || echo 0)"; echo "run $* " >> "$LOG"
if [ -f "$STUBDIR/stockout_once" ]; then rm -f "$STUBDIR/stockout_once"; echo "ERROR: ZONE_RESOURCE_POOL_EXHAUSTED"; exit 1; fi
if [ -f "$STUBDIR/runner_error" ]; then echo "ERROR: something else is wrong with the zone"; exit 1; fi
n=$((n+1)); echo "$n" > "$STUBDIR/counter"; rm -rf "$2"; cp -r "$STUBDIR/run$n" "$2" || exit 1; echo "REFERENCE-RUN-OK image=$1 out=$2"
STUB
chmod +x "$W/bin/gcloud" "$W/runner.sh"
setup_images() { printf '%s %s\n' "$IMG" "$FULL" > "$STUBDIR/images.txt"; python3 -c "import json,sys; print(json.dumps({'labels': {'commit': '$FULL', 'verity-a': '${ROOTH:0:32}', 'verity-b': '${ROOTH:32}', 'purpose': 'tc-seal'}}))" > "$STUBDIR/describe.json"; }
fresh() { rm -rf "${STUBDIR:?}"/* "$W/o"; setup_images; mk "$STUBDIR/run1"; mk "$STUBDIR/run2"; : > "$LOG"; }
pub() { ( cd "$W" && env PATH="$W/bin:$PATH" TC_REFERENCE_RUN="$W/runner.sh" PUBLISH_WAIT=0 PUBLISH_HB=0.2 "$@" bash "$ROOT/ops/ci/publish-ref.sh" "$W/o" ) > "$W/out.txt" 2>&1; echo $?; }
mref() { python3 "$ROOT/ops/make-reference.py" --run "$1" --run "$2" --commit "${3:-$FULL}" --image "${4:-$IMG}" --out "$W/ref.json" > "$W/mref.txt" 2>&1; echo $?; }
# ---------------------------------------------------------------- A. ops/make-reference.py
if [[ "$ONLY" == *A* ]]; then
echo "== A. ops/make-reference.py (the reference from two dummy runs)"
rm -rf "$W/r1" "$W/r2"; mk "$W/r1"; mk "$W/r2"
rc=$(mref "$W/r1" "$W/r2"); [ "$rc" = 0 ] && grep -q "^REFERENCE-MADE commit=16bafb3b19b3 image=tc-img-rel-1 registers=4 events=15" "$W/mref.txt" && chk "two equal runs: REFERENCE-MADE with 15 events" ok || chk "good case: rc=$rc $(cat "$W/mref.txt")" no
python3 - "$W/ref.json" "$FULL" <<'PY' > "$W/refcheck.txt"
import json, sys
r = json.load(open(sys.argv[1])); print("fields", all(k in r for k in ("commit", "image", "machine_type", "mrtd", "rtmr0", "rtmr1", "rtmr2", "stable_events", "per_run_events", "events_in_order")))
print("commit", r["commit"] == sys.argv[2]); print("noperrun", r["per_run_events"] == []); print("order", r["events_in_order"] == list(r["stable_events"])); print("source", "source" in r["stable_events"]); print("debug", r["tdattributes_debug_bit"] == "off"); print("two", len(r["runs"]) == 2)
PY
for k in fields:"the reference has the fields that reference-compare.py and make-release.py read" commit:"it names the full commit" noperrun:"a reference from a dummy run has no per-run events" order:"events_in_order is the stable events in order" source:"it holds the source event" debug:"it records that the debug bit is off" two:"it records both runs"; do key="${k%%:*}"; grep -q "^$key True" "$W/refcheck.txt" && chk "${k#*:}" ok || chk "${k#*:}" no; done
for r in 1 2; do python3 "$ROOT/ops/reference-compare.py" "$W/r$r" "$W/ref.json" > "$W/cmp.txt" 2>&1; grep -q "REFERENCE-COMPARE-OK" "$W/cmp.txt" && chk "the existing comparison tool accepts the new reference for run $r (15 of 15 events, debug bit off)" ok || chk "compare run $r: $(tail -2 "$W/cmp.txt")" no; done
for spec in "rtmr2:differ in RTMR2:the two runs differing in RTMR2" "event:differ in the RTMR3 event tc-units:the two runs differing in one RTMR3 event" "extra:different RTMR3 events:an extra event in one run" "setting:differ in the setting machine_type:the two runs differing in the machine type" "debug:TD debug bit is ON:the debug bit on in a run" "binding:REPORTDATA of the quote:a broken REPORTDATA binding" "rtmr3:RTMR3 of the quote is not the replay:an RTMR3 that is not the replay of its log"; do
  mut="${spec%%:*}"; rest="${spec#*:}"; msg="${rest%%:*}"; label="${rest#*:}"; rm -rf "$W/m2"; mk "$W/m2" "$mut"; rc=$(mref "$W/r1" "$W/m2")
  [ "$rc" = 1 ] && grep -q "^REFERENCE-FAILED: .*$msg" "$W/mref.txt" && chk "refused: $label" ok || chk "$label: rc=$rc $(cat "$W/mref.txt" | cut -c1-120)" no
done
rm -rf "$W/m3" "$W/m4"; mk "$W/m3" source; mk "$W/m4" source; rc=$(mref "$W/m3" "$W/m4"); [ "$rc" = 1 ] && grep -q "the image was not built from this commit" "$W/mref.txt" && chk "refused: a source event that is not the hash of the commit" ok || chk "source event: rc=$rc" no
rm -rf "$W/m3" "$W/m4"; mk "$W/m3" image; mk "$W/m4" image; rc=$(mref "$W/m3" "$W/m4"); [ "$rc" = 1 ] && grep -q "the runs are of image tc-img-other, not of tc-img-rel-1" "$W/mref.txt" && chk "refused: runs of another image" ok || chk "other image: rc=$rc" no
rc=$(mref "$W/r1" "$W/r2" 16bafb3b1); [ "$rc" = 1 ] && grep -q "full commit id" "$W/mref.txt" && chk "refused: a short commit id" ok || chk "short commit: rc=$rc" no
rc=$(python3 "$ROOT/ops/make-reference.py" --run "$W/r1" --commit "$FULL" --image "$IMG" --out "$W/ref.json" > "$W/mref.txt" 2>&1; echo $?); [ "$rc" = 1 ] && grep -q "exactly two --run" "$W/mref.txt" && chk "refused: one run only" ok || chk "one run: rc=$rc" no
rc=$(mref "$W/r1" "$W/nonexistent"); [ "$rc" = 1 ] && grep -q "the file is missing" "$W/mref.txt" && chk "refused: a missing run folder, with the file named" ok || chk "missing folder: rc=$rc" no
# ---------------------------------------------------------------- B. ops/ci/publish-ref.sh
fi
if [[ "$ONLY" == *B* ]]; then
echo "== B. ops/ci/publish-ref.sh (the whole publication, with a fake gcloud and a fake dummy run)"
fresh; rc=$(pub COMMIT=16bafb3b1); P="$W/o/publish"
[ "$rc" = 0 ] && grep -q "^PUBLISH-REF-OK commit=$FULL image=$IMG files=11 .* by=local$" "$W/out.txt" && chk "a good run: PUBLISH-REF-OK with the 11 files (by=local outside CI)" ok || chk "good publication: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
want=(SHA256SUMS ccel.bin announce-run1.txt boot-tables.md publication.json quote-run1.bin quote-run2.bin reference.json release.json rtmr3-events.tsv settings.json); got="$(find "$P" -maxdepth 1 -type f -printf '%f\n' 2>/dev/null | LC_ALL=C sort | tr '\n' ' ')"
[ "$(printf '%s\n' "${want[@]}" | LC_ALL=C sort | tr '\n' ' ')" = "$got" ] && chk "the published files are exactly the expected ones" ok || chk "published files: $got" no
{ [ ! -e "$P/instance.json" ] && [ ! -e "$P/image.json" ] && ! grep -r -q -F "training-custody" "$P"; } && chk "nothing that names the project is published (no instance.json, no image.json, no project id)" ok || chk "a file names the project" no
( cd "$P" && sha256sum -c --quiet SHA256SUMS ) >/dev/null 2>&1 && chk "SHA256SUMS verifies every published file" ok || chk "SHA256SUMS does not verify" no
python3 - "$P/publication.json" "$P/release.json" "$FULL" "$ROOTH" <<'PY' > "$W/pubcheck.txt"
import json, sys
p = json.load(open(sys.argv[1])); r = json.load(open(sys.argv[2]))
print("pub", p["image_commit"] == sys.argv[3] and p["image"] == "tc-img-rel-1" and p["published_by_commit"] == "local" and all(v and len(v) == 64 for v in p["tools_sha256"].values()))
print("rel", r["commit"] == sys.argv[3] and r["verity_root_hash"] == sys.argv[4] and r["image"] == "tc-img-rel-1")
PY
grep -q "^pub True" "$W/pubcheck.txt" && chk "publication.json records the image commit and the SHA-256 of every tool used" ok || chk "publication.json: $(cat "$W/pubcheck.txt")" no
grep -q "^rel True" "$W/pubcheck.txt" && chk "release.json has the commit, the image and the root hash from the labels" ok || chk "release.json: $(cat "$W/pubcheck.txt")" no
[ "$(grep -c "^gcloud" "$LOG")" -le 2 ] && ! grep -q -E "gcloud .*(create|delete|update|add-iam|set-iam)" "$LOG" && chk "the script calls gcloud only to read the image (the runner creates the VMs)" ok || chk "gcloud calls: $(grep -c '^gcloud' "$LOG")" no
fresh; rc=$(pub COMMIT=16bafb3b1 GITHUB_SHA=deadbeef GITHUB_REF_NAME=publish-ref-16bafb3b1 GITHUB_RUN_ID=77 GITHUB_REPOSITORY=org/repo GITHUB_SERVER_URL=https://github.com)
python3 -c "import json; p=json.load(open('$W/o/publish/publication.json')); print(p['published_by_commit'], p['tag'], p['run_url'])" > "$W/ctx.txt" 2>&1; [ "$rc" = 0 ] && grep -q "deadbeef publish-ref-16bafb3b1 https://github.com/org/repo/actions/runs/77" "$W/ctx.txt" && grep -q " by=deadbeef$" "$W/out.txt" && chk "in CI, publication.json and the last line record the workflow's commit, the tag and the run URL" ok || chk "CI context: $(cat "$W/ctx.txt")" no
fresh; rc=$(pub COMMIT=xyz); [ "$rc" = 1 ] && grep -q "COMMIT must be 9 to 40 lowercase hexadecimal digits" "$W/out.txt" && chk "refused: a COMMIT that is not hexadecimal" ok || chk "bad COMMIT: rc=$rc" no
fresh; rc=$(pub); [ "$rc" = 1 ] && grep -q "COMMIT must be" "$W/out.txt" && chk "refused: no COMMIT" ok || chk "no COMMIT: rc=$rc" no
fresh; : > "$STUBDIR/images.txt"; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "0 images carry a label commit=16bafb3b1" "$W/out.txt" && chk "refused: no image carries the commit" ok || chk "no image: rc=$rc" no
fresh; printf '%s %s\ntc-img-rel-2 %s\n' "$IMG" "$FULL" "$FULL" > "$STUBDIR/images.txt"; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "2 images carry a label commit=16bafb3b1" "$W/out.txt" && ! grep -q "run " "$LOG" && chk "refused: two images carry the commit (no VM is created)" ok || chk "two images: rc=$rc" no
fresh; python3 -c "import json; print(json.dumps({'labels': {'commit': '$FULL', 'verity-a': 'abc', 'verity-b': 'def'}}))" > "$STUBDIR/describe.json"; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "do not make a 64-digit root hash" "$W/out.txt" && chk "refused: root hash labels that are not 64 digits" ok || chk "bad root labels: rc=$rc" no
fresh; python3 -c "import json; print(json.dumps({'labels': {'commit': '16bafb3b1', 'verity-a': '${ROOTH:0:32}', 'verity-b': '${ROOTH:32}'}}))" > "$STUBDIR/describe.json"; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "not a full commit id" "$W/out.txt" && chk "refused: a label that is not a full commit id" ok || chk "short label: rc=$rc" no
fresh; python3 -c "import json; print(json.dumps({'labels': {'commit': '$OTHER', 'verity-a': '${ROOTH:0:32}', 'verity-b': '${ROOTH:32}'}}))" > "$STUBDIR/describe.json"; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "is of commit $OTHER, not of 16bafb3b1" "$W/out.txt" && chk "refused: an image whose label is of another commit" ok || chk "other commit: rc=$rc" no
fresh; touch "$STUBDIR/stockout_once"; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 0 ] && grep -q "no capacity right now (attempt 1 of 6)" "$W/out.txt" && chk "a stockout is waited out and the run goes on" ok || chk "stockout: rc=$rc" no
fresh; touch "$STUBDIR/runner_error"; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "dummy run 1 did not finish; the end of its output: ERROR: something else" "$W/out.txt" && chk "another error of the dummy run stops with the end of its output" ok || chk "runner error: rc=$rc" no
fresh; rm -rf "$STUBDIR/run2"; mk "$STUBDIR/run2" rtmr2; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "the two runs differ in RTMR2" "$W/out.txt" && grep -q "PUBLISH-REF-FAILED: the reference could not be made" "$W/out.txt" && [ ! -e "$W/o/publish/reference.json" ] && chk "two runs that disagree: the reference step stops the script and nothing is published" ok || chk "disagreeing runs: rc=$rc" no
fresh; rm -rf "$STUBDIR/run1" "$STUBDIR/run2"; mk "$STUBDIR/run1" source; mk "$STUBDIR/run2" source; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "the image was not built from this commit" "$W/out.txt" && chk "an image whose source event is not of its commit label is refused" ok || chk "source mismatch: rc=$rc" no
fresh; python3 -c "import json; print(json.dumps({'labels': {'commit': '$FULL', 'verity-a': 'c' * 32, 'verity-b': 'c' * 32}}))" > "$STUBDIR/describe.json"; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "RELEASE-FAILED" "$W/out.txt" && grep -q "PUBLISH-REF-FAILED: the release checks failed" "$W/out.txt" && [ ! -e "$W/o/publish/release.json" ] && chk "root hash labels that differ from the kernel command line in RTMR2: the release step stops the script" ok || chk "wrong root hash: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-160)" no
fresh; rm -rf "$STUBDIR/run1" "$STUBDIR/run2"; mk "$STUBDIR/run1" leak; mk "$STUBDIR/run2" leak; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && grep -q "contains the project id" "$W/out.txt" && chk "a file that names the project is never published" ok || chk "leak: rc=$rc" no
fresh; rm -f "$STUBDIR/run1/ccel.bin" "$STUBDIR/run2/ccel.bin"; rc=$(pub COMMIT=16bafb3b1); [ "$rc" = 1 ] && chk "an image that does not publish its boot log is refused" ok || chk "no ccel: rc=$rc" no
fi
echo; echo "pass: $pass   fail: $fail"
if [ "$fail" = 0 ]; then echo "PUBLISH-REHEARSAL-PASS"; else echo "PUBLISH-REHEARSAL-FAIL"; exit 1; fi
