#!/usr/bin/env bash
# Step P1 rehearsal (no cloud, about a minute): the dummy-run script and the comparison tool.   bash p1-rehearse.sh KITDIR      (KITDIR holds ops/reference-run.sh, ops/reference-compare.py and ops/image/test/f1-drive.sh)
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; RR="$K/ops/reference-run.sh"; RC="$K/ops/reference-compare.py"; FD="$K/ops/image/test/f1-drive.sh"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "  pass: $1"; P=$((P+1)); else echo "  FAIL: $1"; F=$((F+1)); fi; }
mkdir -p "$W/bin"
cat > "$W/bin/gcloud" <<'GE'
#!/usr/bin/env bash
W="${P1W:?}"; echo "$*" >> "$W/calls.log"
case "$1 $2 $3" in
 "compute instances create") [ -f "$W/create_fails" ] && { echo "ERROR: stockout" >&2; exit 1; }; touch "$W/vm_exists"; echo "created";;
 "compute instances get-guest-attributes") [ -f "$W/no_announce" ] && exit 0; if [ -f "$W/slow" ] && [ ! -f "$W/polled" ]; then touch "$W/polled"; exit 0; fi; cat "$W/ann.txt";;
 "compute instances describe") cat "$W/instance.json";;
 "compute images describe") cat "$W/image.json";;
 "compute machine-types describe") echo 16384;;
 "compute instances delete") if [ -f "$W/delete_fails_once" ] && [ ! -f "$W/delete_failed" ]; then touch "$W/delete_failed"; exit 1; fi; rm -f "$W/vm_exists"; echo "deleted";;
esac; exit 0
GE
chmod +x "$W/bin/gcloud"
python3 - "$W" <<'PY'
import base64, hashlib, json, sys
W = sys.argv[1]; names = ["source", "tc-lib", "tc-conf", "tc-units", "openssl", "wg", "jdk", "java-settings", "java-ca-fingerprints", "hadoop-code", "hadoop-conf", "nutch-deploy", "crawl-params", "crawl-seeds", "fleet-props"]
h = lambda s: hashlib.sha384(s.encode()).hexdigest()
def build(tag, **m):
    ev = [(n, h("event " + n)) for n in names]
    if "digest" in m: ev[m["digest"]] = (ev[m["digest"]][0], h("another"))
    if "drop" in m: del ev[m["drop"]]
    if "add" in m: ev.append(("extra-event", h("extra")))
    reg = bytes(48); lines = []
    for n, dg in ev: before = reg; reg = hashlib.sha384(reg + bytes.fromhex(dg)).digest(); lines.append("%s\t%s\t%s\t%s" % (n, dg, before.hex(), reg.hex()))
    log = ("\n".join(lines) + "\n").encode(); d = {"name": "tc-ref-test", "sign": "SIGNKEY", "wg": "WGKEY", "log_sha512": hashlib.sha512(log).hexdigest()}
    regs = {k: hashlib.sha384((k + "-value").encode()).digest() for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2")}; ref = dict(regs)
    for k in ("mrtd", "rtmr0", "rtmr1", "rtmr2"):
        if m.get("reg") == k: regs[k] = hashlib.sha384(b"other").digest()
    q = bytearray(700)
    for k, (a, b) in {"mrtd": (184, 232), "rtmr0": (376, 424), "rtmr1": (424, 472), "rtmr2": (472, 520)}.items(): q[a:b] = regs[k]
    q[520:568] = bytes(48) if m.get("rtmr3_wrong") else reg
    if m.get("debug"): q[168] = 1
    binding = ("tc-bind-v1\nname=%s\nsign=%s\nwg=%s\nlog=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"])).encode()
    q[568:632] = hashlib.sha512(binding + (b"x" if m.get("binding") else b"")).digest()
    open("%s/%s.txt" % (W, tag), "w").write("name=%s\nsign=%s\nwg=%s\nlog_sha512=%s\nquote_b64=%s\nlog_b64=%s\n" % (d["name"], d["sign"], d["wg"], d["log_sha512"], base64.b64encode(bytes(q)).decode(), base64.b64encode(log).decode()))
    r = {"commit": "abcdef0123456789", "events_in_order": names + ["fleet", "fleet-conf"], "stable_events": {n: h("event " + n) for n in names}, "per_run_events": ["fleet", "fleet-conf"], "image": "tc-img-test-1", "machine_type": "c3-standard-4"}
    r.update({k: v.hex() for k, v in ref.items()}); json.dump(r, open("%s/%s-ref.json" % (W, tag), "w"))
build("ok"); build("mrtd", reg="mrtd"); build("rtmr0", reg="rtmr0"); build("rtmr1", reg="rtmr1"); build("rtmr2", reg="rtmr2"); build("digest", digest=3); build("drop", drop=5); build("add", add=1); build("debug", debug=1); build("binding", binding=1); build("rtmr3", rtmr3_wrong=1)
json.dump({"name": "tc-ref-test", "disks": [{"boot": True, "diskSizeGb": "30"}, {"boot": False, "diskSizeGb": "10"}], "confidentialInstanceConfig": {"confidentialInstanceType": "TDX"}}, open(W + "/instance.json", "w")); json.dump({"id": "123", "name": "tc-img-test-1", "labels": {"commit": "abc"}}, open(W + "/image.json", "w"))
PY
cp "$W/ok.txt" "$W/ann.txt"
run() { rm -f "$W/calls.log" "$W/vm_exists" "$W/polled" "$W/delete_failed"; OUTS="$(P1W="$W" TC_GCLOUD="$W/bin/gcloud" REF_VM=tc-ref-test POLL_SECONDS=1 WAIT_SECONDS=${WS:-6} bash "$RR" "$@" 2>&1)"; RCS=$?; }
echo "== the dummy-run script"
run tc-img-test-1 "$W/out"; [ $RCS = 0 ] && grep -q "REFERENCE-RUN-OK" <<<"$OUTS" && chk "a normal run ends with REFERENCE-RUN-OK" ok || chk "normal run: $OUTS" no
python3 - "$FD" "$W" > "$W/drift.txt" <<'PY'
import re, shlex, sys
fd = open(sys.argv[1]).read(); W = sys.argv[2]; tdx = re.search(r"^TDX=\((.*?)\)", fd, re.M).group(1); want = [a.replace('"$Z"', "us-central1-a").replace("$Z", "us-central1-a") for a in shlex.split(tdx.replace('"$Z"', "ZONEX"))]
want = [a.replace("ZONEX", "us-central1-a") for a in want]; want.append("--create-disk=name=tc-ref-test-scratch,size=10GB,type=pd-balanced,device-name=tcscratch,auto-delete=yes")
call = [l for l in open(W + "/calls.log") if l.startswith("compute instances create")][0].split()[4:]
call = [a for a in call if not a.startswith("--image=") and not a.startswith("--labels=")]
print("same_flags", sorted(want) == sorted(call)); print("no_tc_fleet", not any("tc-fleet" in a for a in call)); print("no_metadata_file", not any("metadata-from-file" in a for a in call))
print("flags", len(call))
PY
grep -q "^same_flags True" "$W/drift.txt" && chk "the creation flags equal the fleet driver's TDX array (read from f1-drive.sh) plus the scratch disk" ok || chk "the flags differ from the fleet's: $(cat "$W/drift.txt" | tr '\n' ' ')" no
grep -q "^no_tc_fleet True" "$W/drift.txt" && grep -q "^no_metadata_file True" "$W/drift.txt" && chk "no tc-fleet metadata and no metadata file (a node booted so makes its quote and stops before Hadoop)" ok || chk "tc-fleet is passed" no
[ "$(grep -o -- '--metadata=[^ ]*' "$W/calls.log" | sort -u)" = "--metadata=enable-guest-attributes=TRUE" ] && ! grep -qi "cmdline\|kernel-command" "$W/calls.log" && chk "the only metadata is the guest-attributes switch, and nothing is put on the kernel command line" ok || chk "other metadata or a kernel command line is passed: $(grep -o -- '--metadata=[^ ]*' "$W/calls.log" | sort -u | tr '\n' ' ')" no
[ ! -f "$W/vm_exists" ] && grep -q "instances delete tc-ref-test" "$W/calls.log" && chk "the VM is deleted after a successful run" ok || chk "the VM was not deleted" no
python3 - "$W/out" <<'PY' > "$W/saved.txt"
import json, os, sys
o = sys.argv[1]; s = json.load(open(o + "/settings.json"))
print("files", all(os.path.isfile(o + "/" + f) for f in ("announce.txt", "quote.bin", "rtmr3-events.tsv", "settings.json", "instance.json", "image.json")))
print("quote", os.path.getsize(o + "/quote.bin") == 700); print("events", len(open(o + "/rtmr3-events.tsv").read().splitlines()) == 15)
print("settings", s["machine_type"] == "c3-standard-4" and s["memory_mb"] == 16384 and s["boot_disk_gb"] == 30 and s["scratch_disk_gb"] == 10 and s["zone"] == "us-central1-a" and s["image"] == "tc-img-test-1" and s["confidential_instance_type"] == "TDX")
PY
for k in files quote events settings; do grep -q "^$k True" "$W/saved.txt" && chk "saved: $k" ok || chk "saved: $k" no; done
touch "$W/slow"; run tc-img-test-1 "$W/out2"; [ $RCS = 0 ] && [ "$(grep -c get-guest-attributes "$W/calls.log")" -ge 2 ] && chk "it keeps polling until the announcement appears" ok || chk "polling failed" no; rm -f "$W/slow"
touch "$W/no_announce"; WS=3 run tc-img-test-1 "$W/out3"; [ $RCS != 0 ] && grep -q "no announcement" <<<"$OUTS" && [ ! -f "$W/vm_exists" ] && chk "no announcement in time: it fails and the VM is deleted" ok || chk "timeout case: $OUTS" no; rm -f "$W/no_announce"
touch "$W/create_fails"; run tc-img-test-1 "$W/out4"; [ $RCS != 0 ] && grep -q "instances delete tc-ref-test" "$W/calls.log" && chk "the VM creation fails: it fails and still tries to delete (a half-created VM would cost money)" ok || chk "create failure: $OUTS" no; rm -f "$W/create_fails"
touch "$W/delete_fails_once"; run tc-img-test-1 "$W/out5"; [ $RCS = 0 ] && [ "$(grep -c 'instances delete' "$W/calls.log")" = 2 ] && [ ! -f "$W/vm_exists" ] && chk "a failed delete is tried again and succeeds" ok || chk "delete retry: $(grep -c 'instances delete' "$W/calls.log")" no; rm -f "$W/delete_fails_once"
run "Bad_Name" "$W/out6"; [ $RCS = 2 ] && grep -q "usage" <<<"$OUTS" && [ ! -f "$W/calls.log" ] && chk "a bad image name is refused before any cloud call" ok || chk "bad name accepted" no
SCRATCH_GB=abc run tc-img-test-1 "$W/out7"; [ $RCS != 0 ] && [ ! -f "$W/calls.log" ] && chk "a setting that is not a number is refused before any cloud call" ok || chk "bad setting accepted" no
SCRATCH_GB=0 run tc-img-test-1 "$W/out8"; ! grep -q "create-disk" "$W/calls.log" && chk "SCRATCH_GB=0 leaves out the scratch disk" ok || chk "scratch disk present with 0" no
echo "== the comparison tool"
cmp1() { OUTC="$(python3 "$RC" "$1" "$2" 2>&1)"; RCC=$?; }
mkdir -p "$W/r_ok"; cp "$W/ok.txt" "$W/r_ok/announce.txt"; cp "$W/out/settings.json" "$W/r_ok/settings.json"
cmp1 "$W/r_ok" "$W/ok-ref.json"; [ $RCC = 0 ] && grep -q "REFERENCE-COMPARE-OK" <<<"$OUTC" && grep -q "TDATTRIBUTES debug bit: off" <<<"$OUTC" && chk "equal registers and events: REFERENCE-COMPARE-OK, the settings are printed and the debug bit is off" ok || chk "equal case: $OUTC" no
grep -q "settings of the run: image=tc-img-test-1, machine_type=c3-standard-4, memory_mb=16384, boot_disk_gb=30, scratch_disk_gb=10" <<<"$OUTC" && chk "the settings used are printed" ok || chk "settings not printed" no
for v in mrtd rtmr0 rtmr1 rtmr2; do mkdir -p "$W/r_$v"; cp "$W/$v.txt" "$W/r_$v/announce.txt"; cmp1 "$W/r_$v" "$W/${v}-ref.json"; U=$(echo $v | tr a-z A-Z); [ $RCC = 1 ] && grep -q "$U differs" <<<"$OUTC" && chk "a different $U is rejected" ok || chk "$U difference not caught: $OUTC" no; done
mkdir -p "$W/r_dg"; cp "$W/digest.txt" "$W/r_dg/announce.txt"; cmp1 "$W/r_dg" "$W/digest-ref.json"; [ $RCC = 1 ] && grep -q "has another digest" <<<"$OUTC" && chk "a changed digest of a stable event is rejected" ok || chk "digest not caught: $OUTC" no
mkdir -p "$W/r_drop"; cp "$W/drop.txt" "$W/r_drop/announce.txt"; cmp1 "$W/r_drop" "$W/drop-ref.json"; [ $RCC = 1 ] && grep -q "is missing" <<<"$OUTC" && chk "a missing stable event is rejected" ok || chk "missing event not caught: $OUTC" no
mkdir -p "$W/r_add"; cp "$W/add.txt" "$W/r_add/announce.txt"; cmp1 "$W/r_add" "$W/add-ref.json"; [ $RCC = 1 ] && grep -q "events that the reference does not know" <<<"$OUTC" && chk "an extra event (a service added to the image) is rejected" ok || chk "extra event not caught: $OUTC" no
mkdir -p "$W/r_dbg"; cp "$W/debug.txt" "$W/r_dbg/announce.txt"; cmp1 "$W/r_dbg" "$W/debug-ref.json"; [ $RCC = 1 ] && grep -q "debug bit is ON" <<<"$OUTC" && chk "a TD with the debug bit on is rejected" ok || chk "debug bit not caught: $OUTC" no
mkdir -p "$W/r_bind"; cp "$W/binding.txt" "$W/r_bind/announce.txt"; cmp1 "$W/r_bind" "$W/binding-ref.json"; [ $RCC = 1 ] && grep -q "REPORTDATA" <<<"$OUTC" && chk "a quote whose REPORTDATA does not bind the announcement is rejected" ok || chk "binding not caught: $OUTC" no
mkdir -p "$W/r_r3"; cp "$W/rtmr3.txt" "$W/r_r3/announce.txt"; cmp1 "$W/r_r3" "$W/rtmr3-ref.json"; [ $RCC = 1 ] && grep -q "RTMR3 of the quote is not the replay" <<<"$OUTC" && chk "an RTMR3 that is not the replay of its log is rejected" ok || chk "rtmr3 not caught: $OUTC" no
mkdir -p "$W/r_img"; cp "$W/ok.txt" "$W/r_img/announce.txt"; python3 -c "
import json,sys; s=json.load(open('$W/out/settings.json')); s['image']='tc-img-other'; json.dump(s, open('$W/r_img/settings.json','w'))"; cmp1 "$W/r_img" "$W/ok-ref.json"; [ $RCC = 1 ] && grep -q "the run is of image tc-img-other" <<<"$OUTC" && chk "a run of another image than the reference is rejected" ok || chk "image mismatch not caught: $OUTC" no
cmp1 "$W/r_ok" "$W/none.json"; [ $RCC = 1 ] && grep -q "the file is missing" <<<"$OUTC" && chk "a missing reference file is refused" ok || chk "missing file not refused" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "P1-REHEARSAL-PASS" || { echo "P1-REHEARSAL-FAIL"; exit 1; }
