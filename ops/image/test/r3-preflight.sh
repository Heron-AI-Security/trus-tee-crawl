#!/usr/bin/env bash
# Preflight of the sealing session (R3.3 and R3.4): READ-ONLY, seconds. Everything that a later, slower stage depends on is looked at here, so that a missing image, a running builder, a leftover disk from an earlier
# attempt, a quota that is too small or a script that does not parse shows up in the first minute and not in the middle of a stage.
#   bash r3-preflight.sh KITDIR
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; Z="${ZONE:-us-central1-a}"; B="${BUILDER:-tc-builder}"; WK="${SEAL_DISK:-tc-seal-work}"; HLP="${SEALER:-tc-sealer}"; ST="${SEAL_TEST:-tc-seal-test}"
IMG="${IMG:-tc-img-seal-1}"; HIMG="${HELPER_IMAGE:-tc-img-dbg-1}"; BASE="${BASE_IMAGE:-tc-img-dbg-5}"; BAD=0
ok() { echo "   ok:   $*"; }; no() { echo "   FAIL: $*"; BAD=$((BAD+1)); }
echo "== the scripts of the kit parse (seconds)"
for f in build/tc-image-sealbake.sh build/tc-image-seal.sh test/r3-seal-check.sh test/f03-drive.sh test/r3-disks.sh; do bash -n "$KIT/ops/image/$f" 2>/dev/null && ok "$f" || no "$f does not parse"; done
if command -v dash >/dev/null; then for f in hooks/tc-seal scripts/local-top/tc-verity scripts/local-top/tc-scratch-dev scripts/init-bottom/tc-scratch-bind; do dash -n "$KIT/ops/image/rootfs/etc/tc/initramfs-tools/$f" 2>/dev/null && ok "initramfs $f (dash)" || no "initramfs $f does not parse under dash"; done; else echo "   note: no dash here: the initramfs scripts are parsed on the builder instead (gate 2)"; fi
for p in ROOTFS_UUID KVER ROOTHASH BLOCKS SALT DATA_PARTUUID; do grep -q "@$p@" "$KIT/ops/image/rootfs/etc/tc/grub-sealed.cfg.in" || no "the GRUB template has no @$p@"; done; ok "the GRUB template has its six placeholders"
echo "== the images (read-only)"
for i in "$HIMG" "$BASE"; do [ "$(gcloud compute images describe "$i" --format='value(status)' 2>/dev/null)" = READY ] && ok "image $i is READY" || no "image $i does not exist or is not READY"; done
echo "== the builder, and leftovers of an earlier attempt that would stop a later stage"
BS="$(gcloud compute instances describe "$B" --zone="$Z" --format='value(status)' 2>/dev/null)"; [ "$BS" = TERMINATED ] && ok "the builder $B exists and is stopped" || no "the builder $B must exist and be stopped (it is: ${BS:-missing})"
for v in "$HLP" "$ST"; do gcloud compute instances describe "$v" --zone="$Z" >/dev/null 2>&1 && no "the VM $v exists already (a stage would refuse): CONFIRM=yes stage seal-delete removes it" || ok "no VM $v yet"; done
gcloud compute disks describe "$WK" --zone="$Z" >/dev/null 2>&1 && no "the disk $WK exists already (a stage would refuse): CONFIRM=yes stage seal-delete removes it" || ok "no disk $WK yet"
gcloud compute images describe "$IMG" >/dev/null 2>&1 && no "the image $IMG exists already: choose another IMG or delete it" || ok "no image $IMG yet"
echo "== the quota of the region (4 vCPUs for the test VM, and the builder's 4 when it runs, plus what runs already)"
QJ="$(gcloud compute regions describe "${Z%-*}" --format=json 2>/dev/null)"
python3 - "$QJ" <<'PYX' && ok "the C3 quota has room for the builder and the test VM (8 vCPUs)" || no "the C3 quota (24) has less than 8 vCPUs free: stop something of OURS first (never the teammate's VMs)"
import json, sys
try: q = {x["metric"]: x for x in json.loads(sys.argv[1])["quotas"]}
except Exception: sys.exit(1)
c = q.get("C3_CPUS"); print("   C3_CPUS %s of %s in use" % (int(c["usage"]), int(c["limit"])) if c else "   (no C3_CPUS metric)"); sys.exit(0 if (c is None or c["limit"] - c["usage"] >= 8) else 1)
PYX
echo; if [ "$BAD" = 0 ]; then echo "PRECHECK-OK"; else echo "PRECHECK-FAILED ($BAD)"; fi
[ "$BAD" = 0 ]
