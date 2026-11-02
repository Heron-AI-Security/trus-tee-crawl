#!/usr/bin/env bash
# ops/image/test/tamper-test.sh: step P4, the tamper cases ("it fails on an image with one changed file, one added file, and one changed mode"), on REAL disks.
# Usage:   bash ops/image/test/tamper-test.sh IMAGE --verity "ROOTHASH BLOCKS SALT PARTUUID" [--work DIR]
#   IMAGE     an image of your project (or PROJECT/IMAGE) whose root disk is sealed with dm-verity; the SPEC is its dm-verity parameters (python3 ops/verify-reference.py --verity-of FOLDER prints it)
# ONE ordinary helper VM gets the disk of the image (read-only, the original) and five copies of it (read-write). On the copies ops/tree-tamper-helper.sh makes ONE change each (a changed file, an added file, a changed
# mode, an added file capability; the fifth is left alone), RESEALS them (new hash tree, new root hash), and makes the manifest of every disk through dm-verity. Here each copy is compared with the original
# (ops/tree-diff.py --require-verity) and must give EXACTLY the expected result:  control: identical, and its resealed root hash equals the original's;  the four changes: one difference each, named.
# It takes about 25 minutes and costs a few cents; the VM and the disks are always deleted. Ends with TAMPER-TEST-OK or TAMPER-TEST-FAILED (n).
# Settings: ZONE, HELPER_TYPE, HELPER_FAMILY, HELPER_IMAGE_PROJECT, TREE_HB, TREE_SSH_TRIES (24), TREE_SSH_WAIT (15), TC_GCLOUD.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; OPS="$(cd "$HERE/../.." && pwd)"
GC="${TC_GCLOUD:-gcloud}"; Z="${ZONE:-us-central1-a}"; HT="${HELPER_TYPE:-e2-standard-4}"; HF="${HELPER_FAMILY:-ubuntu-2404-lts-amd64}"; HP="${HELPER_IMAGE_PROJECT:-ubuntu-os-cloud}"
usage() { awk 'NR>1 && /^#/ {sub(/^# ?/, ""); print; next} NR>1 {exit}' "${BASH_SOURCE[0]}" >&2; exit 64; }
die() { echo "TAMPER-TEST-FAILED: $*" >&2; exit 2; }
IMG="${1:-}"; [ -n "$IMG" ] || usage; shift; SPEC=""; WORK="tamper-work"
while [ $# -gt 0 ]; do
  case "$1" in
    --verity) [ $# -ge 2 ] || usage; SPEC="$2"; shift 2;;
    --work) [ $# -ge 2 ] || usage; WORK="$2"; shift 2;;
    *) echo "unknown option: $1" >&2; usage;;
  esac
done
read -r ROOTH BLOCKS SALT PUID EXTRA <<<"$SPEC"
{ [[ "$ROOTH" =~ ^[0-9a-f]{64}$ ]] && [[ "$BLOCKS" =~ ^[0-9]{1,12}$ ]] && [[ "$SALT" =~ ^[0-9a-f]{2,128}$ ]] && [[ "$PUID" =~ ^[0-9A-Fa-f-]{8,40}$ ]] && [ -z "$EXTRA" ]; } || die "--verity must be one word in quotes: ROOTHASH BLOCKS SALT PARTUUID (see the usage); got '$SPEC'"
case "$IMG" in */*) IMGP="${IMG%%/*}"; IMGN="${IMG#*/}";; *) IMGP=""; IMGN="$IMG";; esac
ID="$(date -u +%m%d-%H%M%S)"; VM="tc-tamper-$ID"; DISKS=(); VMMADE=0
# shellcheck disable=SC2329   # cleanup is called by the traps below
cleanup() {
  trap - EXIT
  [ "$VMMADE" = 1 ] && { echo "== cleaning up: deleting the helper VM $VM"; "$GC" compute instances delete "$VM" --zone "$Z" --quiet >/dev/null 2>&1 || echo "   warning: the VM $VM could not be deleted: delete it by hand"; }
  for d in ${DISKS[@]+"${DISKS[@]}"}; do echo "== cleaning up: deleting the disk $d"; "$GC" compute disks delete "$d" --zone "$Z" --quiet >/dev/null 2>&1 || echo "   warning: the disk $d could not be deleted (it may never have been made): check with gcloud compute disks list"; done
}
trap cleanup EXIT; trap 'exit 130' INT TERM
mkdir -p "$WORK" || die "cannot make the folder $WORK"
rssh() { "$GC" compute ssh "$VM" --zone "$Z" --quiet --strict-host-key-checking=no --command "$1" -- -o ServerAliveInterval=30 -o ServerAliveCountMax=60; }   # keep-alive: the helper works for about 20 minutes without any output
echo "== 1. the disks: the original and five copies, made from $IMG"
for k in 0 1 2 3 4 5; do DISKS+=("$VM-$k"); done
extra=(); [ -z "$IMGP" ] || extra=(--image-project "$IMGP")
"$GC" compute disks create "${DISKS[@]}" --zone "$Z" --image "$IMGN" ${extra[@]+"${extra[@]}"} --labels purpose=tc-tamper-test --quiet >"$WORK/disks.log" 2>&1 || die "the disks could not be made from the image $IMG: $(tail -3 "$WORK/disks.log" | tr '\n' ' ' | cut -c1-300)"
echo "   ${#DISKS[@]} disks"
echo "== 2. the helper VM $VM (an ordinary VM; the original is attached read-only, the five copies read-write)"
ATT=(--disk "name=$VM-0,device-name=treeo,mode=ro,boot=no"); for k in 1 2 3 4 5; do ATT+=(--disk "name=$VM-$k,device-name=tree$k,mode=rw,boot=no"); done
"$GC" compute instances create "$VM" --zone "$Z" --machine-type "$HT" --image-family "$HF" --image-project "$HP" --no-service-account --no-scopes --labels purpose=tc-tamper-test "${ATT[@]}" --quiet >"$WORK/vm.log" 2>&1 || die "the helper VM could not be made: $(tail -3 "$WORK/vm.log" | tr '\n' ' ' | cut -c1-300)"
VMMADE=1
echo "== 3. waiting for the VM to accept SSH"
TRIES="${TREE_SSH_TRIES:-24}"; up=0; for ((t = 1; t <= TRIES; t++)); do if rssh true >"$WORK/ssh-last.log" 2>&1; then up=1; break; fi; echo "   not yet (attempt $t of $TRIES)"; sleep "${TREE_SSH_WAIT:-15}"; done
[ "$up" = 1 ] || die "the helper VM does not accept SSH after $TRIES attempts (the last SSH error: $(tail -3 "$WORK/ssh-last.log" 2>/dev/null | tr '\n' ' ' | cut -c1-300))"
"$GC" compute scp --zone "$Z" --quiet --strict-host-key-checking=no "$OPS/tree-manifest.py" "$OPS/tree-helper.sh" "$OPS/tree-lib.sh" "$OPS/tree-tamper-helper.sh" "$VM":~ >"$WORK/scp.log" 2>&1 || die "the tools could not be copied to the VM: $(tail -3 "$WORK/scp.log" | tr '\n' ' ' | cut -c1-300)"
echo "== 4. on the VM: the original and the five copies are changed, resealed and read at the same time (about 20 minutes)"
rssh "sudo bash ~/tree-tamper-helper.sh $ROOTH $BLOCKS $SALT $PUID ~/tt control:tree1 changed:tree2 added:tree3 mode:tree4 xattr:tree5" > "$WORK/helper.log" 2>&1 &
pid=$!; while kill -0 "$pid" 2>/dev/null; do sleep "${TREE_HB:-60}"; echo "   ... the helper is working ($(date -u +%H:%M) UTC)"; done; wait "$pid"; rc=$?
tail -8 "$WORK/helper.log" | sed 's/^/   /'
[ "$rc" = 0 ] || { echo "--- the output of the helper:" >&2; tail -30 "$WORK/helper.log" >&2; die "the tamper helper did not finish (exit code $rc)"; }
echo "== 5. fetching the manifests"
rssh "sudo tar -C ~/tt -czf ~/tt.tgz . && sudo chmod 644 ~/tt.tgz" >"$WORK/tar.log" 2>&1 || die "the results could not be packed on the VM: $(tail -3 "$WORK/tar.log" | tr '\n' ' ' | cut -c1-300)"
"$GC" compute scp --zone "$Z" --quiet --strict-host-key-checking=no "$VM":~/tt.tgz "$WORK/" >"$WORK/scp.log" 2>&1 || die "the results could not be fetched: $(tail -3 "$WORK/scp.log" | tr '\n' ' ' | cut -c1-300)"
T="$WORK/tt"; rm -rf "$T"; mkdir -p "$T"; tar -xzf "$WORK/tt.tgz" -C "$T" || die "the results could not be unpacked"
echo "== 6. each copy against the original, through ops/tree-diff.py --require-verity (both disks were opened through dm-verity against their own root hash)"
fails=0
ok() { echo "  ok:   $1"; }
no() { fails=$((fails + 1)); echo "  FAIL: $1"; }
check() {   # check KIND WANTRC WANTLINES
  local kind="$1" wrc="$2" want="$3" out rc got
  out="$(python3 "$OPS/tree-diff.py" "$T/orig.manifest" "$T/$kind.manifest" --require-verity --report "$T/$kind.report" 2>&1)"; rc=$?
  got="$(awk -F'\t' '$1=="DIFF" {print $2 " " $3}' "$T/$kind.report" 2>/dev/null | sort | tr '\n' ';')"
  if [ "$rc" = "$wrc" ] && [ "$got" = "$want" ] && grep -q "verity=checked" <<<"$out"; then ok "$kind: $( [ -n "$want" ] && echo "rejected, with exactly this one difference: ${want%;}" || echo "identical (verity=checked)")"
  else no "$kind: expected exit code $wrc and '${want:-no difference}', got exit code $rc and '${got:-no difference}' ($(tail -1 <<<"$out" | cut -c1-100))"; fi
}
check control 0 ""
check changed 1 "content differs /etc/issue;"
check added 1 "only in B /usr/local/bin/tc-added-file;"
check mode 1 "mode differs /etc/issue.net;"
check xattr 1 "xattrs differ /usr/bin/cat;"
newroot="$(cat "$T/control.root" 2>/dev/null)"
if [ "$newroot" = "$ROOTH" ]; then ok "control: the resealed copy has the ORIGINAL root hash (${ROOTH:0:16}...): our sealing parameters are exactly those of the real sealing"; else no "control: the resealed copy has the root hash '${newroot:0:16}', not the original ${ROOTH:0:16}: the sealing parameters differ"; fi
for k in changed added mode xattr; do nr="$(cat "$T/$k.root" 2>/dev/null)"; if [ -n "$nr" ] && [ "$nr" != "$ROOTH" ]; then ok "$k: its root hash changed (${nr:0:16}...), so a verifier that knows the original root hash cannot mistake it"; else no "$k: its resealed root hash is missing or equal to the original"; fi; done
echo
if [ "$fails" = 0 ]; then echo "TAMPER-TEST-OK image=$IMG cases=5 original-root=${ROOTH:0:16}"; exit 0; fi
echo "TAMPER-TEST-FAILED ($fails)"; exit 1
