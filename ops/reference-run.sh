#!/usr/bin/env bash
# Step P1 of the mentor's plan of 28 October 2026 (US time): the DUMMY RUN.   bash ops/reference-run.sh IMAGE [OUTDIR]
# One VM is created from IMAGE exactly like a fleet node (same machine type, memory, boot disk and scratch disk, TDX, no service account), but WITHOUT the instance metadata tc-fleet. A node booted like that already makes its keys, publishes one quote as the
# guest attribute tc/announce and waits for a fleet list that never comes (tc-fleet.sh), so no new mode and nothing on the kernel command line (it would change RTMR2). The script saves the announcement, the quote, the RTMR3 event log and the settings, and deletes the VM even when a step fails.
# Settings (environment, defaults are the fleet's): ZONE=us-central1-a MACHINE_TYPE=c3-standard-4 BOOT_DISK_GB=30 SCRATCH_GB=10 WAIT_SECONDS=900 POLL_SECONDS=10 IMAGE_PROJECT (only when the image is in another project) REF_VM (the name of the VM).
set -uo pipefail
GC="${TC_GCLOUD:-gcloud}"
fail() { echo "REFERENCE-RUN-FAILED: $*" >&2; exit 1; }
IMAGE="${1:-}"; [[ "$IMAGE" =~ ^[a-z]([-a-z0-9]{0,61}[a-z0-9])?$ ]] || { echo "usage: reference-run.sh IMAGE [OUTDIR]   (IMAGE is the name of a GCE image)" >&2; exit 2; }
OUT="${2:-$HOME/reference-run-$IMAGE}"
Z="${ZONE:-us-central1-a}"; MT="${MACHINE_TYPE:-c3-standard-4}"; DISK="${BOOT_DISK_GB:-30}"; SCRATCH="${SCRATCH_GB:-10}"; WAIT="${WAIT_SECONDS:-900}"; POLL="${POLL_SECONDS:-10}"; VM="${REF_VM:-tc-ref-$(date -u +%m%d-%H%M%S)}"
[[ "$DISK" =~ ^[0-9]+$ && "$SCRATCH" =~ ^[0-9]+$ && "$WAIT" =~ ^[0-9]+$ && "$POLL" =~ ^[0-9]+$ ]] || fail "BOOT_DISK_GB, SCRATCH_GB, WAIT_SECONDS and POLL_SECONDS must be numbers"
CREATED=0
cleanup() { local rc=$?; if [ "$CREATED" = 1 ]; then local i; for i in 1 2 3; do "$GC" compute instances delete "$VM" --zone="$Z" --quiet >/dev/null 2>&1 && { echo "the dummy-run VM $VM is deleted"; break; }; sleep 5; done; fi; exit $rc; }
trap cleanup EXIT; trap 'exit 130' INT TERM
mkdir -p "$OUT" || fail "cannot make $OUT"
# the creation flags are the fleet's (ops/image/test/f1-drive.sh, the array TDX and the scratch disk); the rehearsal p1-rehearse.sh checks that they have not drifted apart
ARGS=(--zone="$Z" --machine-type="$MT" --confidential-compute-type=TDX --maintenance-policy=TERMINATE --boot-disk-size="${DISK}GB" --boot-disk-type=pd-balanced --no-service-account --no-scopes --metadata=enable-guest-attributes=TRUE)
[ "$SCRATCH" = 0 ] || ARGS+=(--create-disk="name=$VM-scratch,size=${SCRATCH}GB,type=pd-balanced,device-name=tcscratch,auto-delete=yes")
ARGS+=(--image="$IMAGE" --labels=purpose=tc-reference-run); [ -z "${IMAGE_PROJECT:-}" ] || ARGS+=(--image-project="$IMAGE_PROJECT")
echo "== the dummy run of image $IMAGE: one VM $VM ($MT, ${DISK} GB boot disk, ${SCRATCH} GB scratch disk, TDX) in $Z, without a fleet list"
CREATED=1; "$GC" compute instances create "$VM" "${ARGS[@]}" < /dev/null || fail "the VM could not be created (the error is above; a capacity stockout can be tried again later)"
echo "== waiting for the announcement (guest attribute tc/announce), at most $WAIT seconds"
t=0; ANN=""
while [ "$t" -lt "$WAIT" ]; do ANN="$("$GC" compute instances get-guest-attributes "$VM" --zone="$Z" --query-path=tc/announce --format='value(value)' 2>/dev/null)"; [ -n "$ANN" ] && break; sleep "$POLL"; t=$((t+POLL)); done
[ -n "$ANN" ] || fail "no announcement (tc/announce) from $VM within $WAIT seconds"
printf '%s\n' "$ANN" > "$OUT/announce.txt"
DESC="$("$GC" compute instances describe "$VM" --zone="$Z" --format=json 2>/dev/null)" || fail "could not describe $VM"
IMGD="$("$GC" compute images describe "$IMAGE" --format=json 2>/dev/null)" || fail "could not describe the image $IMAGE"
MEM="$("$GC" compute machine-types describe "$MT" --zone="$Z" --format='value(memoryMb)' 2>/dev/null)" || fail "could not describe the machine type $MT"
printf '%s\n' "$DESC" > "$OUT/instance.json"; printf '%s\n' "$IMGD" > "$OUT/image.json"
python3 - "$OUT" "$IMAGE" "$MT" "$MEM" "$Z" <<'PY' || fail "the announcement could not be unpacked"
import base64, json, sys, time
out, image, mt, mem, zone = sys.argv[1:6]; desc = json.load(open(out + "/instance.json")); imgd = json.load(open(out + "/image.json"))
d = {}
for line in open(out + "/announce.txt", encoding="utf-8").read().splitlines():
    if "=" in line: k, v = line.split("=", 1); d[k] = v
for k in ("name", "sign", "wg", "log_sha512", "quote_b64", "log_b64"):
    if k not in d: sys.exit("the announcement lacks " + k)
open(out + "/quote.bin", "wb").write(base64.b64decode(d["quote_b64"])); open(out + "/rtmr3-events.tsv", "wb").write(base64.b64decode(d["log_b64"]))
disks = desc.get("disks", []); boot = [x for x in disks if x.get("boot")]; other = [x for x in disks if not x.get("boot")]
settings = {"image": image, "image_id": imgd.get("id"), "image_labels": imgd.get("labels", {}), "machine_type": mt, "memory_mb": int(mem) if mem.isdigit() else mem, "boot_disk_gb": int(boot[0]["diskSizeGb"]) if boot else None, "scratch_disk_gb": int(other[0]["diskSizeGb"]) if other else 0,
            "zone": zone, "confidential_instance_type": (desc.get("confidentialInstanceConfig") or {}).get("confidentialInstanceType"), "vm": desc.get("name"), "run_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
open(out + "/settings.json", "w").write(json.dumps(settings, indent=2) + "\n")
print("saved: announce.txt, quote.bin (%d bytes), rtmr3-events.tsv (%d events), settings.json, instance.json, image.json" % (len(open(out + "/quote.bin", "rb").read()), len(open(out + "/rtmr3-events.tsv").read().splitlines())))
PY
echo "REFERENCE-RUN-OK image=$IMAGE out=$OUT"
