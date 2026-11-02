#!/usr/bin/env bash
# ops/tree-diff.sh: step P4.2 of the mentor's plan. The file-tree diff of two images: do two root disks, whose root hashes differ, hold the same files?
# Usage:
#   bash ops/tree-diff.sh diff IMAGE_A IMAGE_B [--ignore FILE] [--partuuid-a UUID] [--partuuid-b UUID] [--work DIR]
#   bash ops/tree-diff.sh manifest IMAGE OUTFILE [--partuuid UUID] [--work DIR]
# IMAGE is an image of your Google Cloud project, or PROJECT/IMAGE for an image that another project shares with you. For each image a disk is made, and ONE throwaway helper VM (an ordinary
# Ubuntu VM, not a TDX VM) mounts the disks READ-ONLY and makes the manifest of each file tree (ops/tree-manifest.py); the manifests are fetched, compared (ops/tree-diff.py), and everything that this
# command made (the VM and the disks) is deleted, also when something fails. It takes about 10 to 15 minutes and costs a few cents. The manifests stay in --work (default tree-work) so that they can be compared again offline:
#   python3 ops/tree-diff.py tree-work/a.manifest tree-work/b.manifest
# Settings: ZONE (us-central1-a), HELPER_TYPE (e2-standard-4), HELPER_FAMILY (ubuntu-2404-lts-amd64), HELPER_IMAGE_PROJECT (ubuntu-os-cloud), TREE_HB (heartbeat seconds, 60).
# For diff it ends with the line of tree-diff.py: TREE-DIFF-IDENTICAL (exit 0), TREE-DIFF-DIFFERENT (exit 1) or TREE-DIFF-FAILED (exit 2).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GC="${TC_GCLOUD:-gcloud}"; Z="${ZONE:-us-central1-a}"; HT="${HELPER_TYPE:-e2-standard-4}"; HF="${HELPER_FAMILY:-ubuntu-2404-lts-amd64}"; HP="${HELPER_IMAGE_PROJECT:-ubuntu-os-cloud}"
usage() { sed -n '2,12p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; exit 64; }
die() { echo "TREE-DIFF-FAILED: $*" >&2; exit 2; }
MODE="${1:-}"; [ -n "$MODE" ] || usage; shift
A=""; B=""; OUTF=""; IGN=""; UA=""; UB=""; WORK="tree-work"
case "$MODE" in
  diff) [ $# -ge 2 ] || usage; A="$1"; B="$2"; shift 2;;
  manifest) [ $# -ge 2 ] || usage; A="$1"; OUTF="$2"; shift 2;;
  *) usage;;
esac
while [ $# -gt 0 ]; do
  case "$1" in
    --ignore) [ $# -ge 2 ] || usage; IGN="$2"; shift 2;;
    --partuuid-a|--partuuid) [ $# -ge 2 ] || usage; UA="$2"; shift 2;;
    --partuuid-b) [ $# -ge 2 ] || usage; UB="$2"; shift 2;;
    --work) [ $# -ge 2 ] || usage; WORK="$2"; shift 2;;
    *) echo "unknown option: $1" >&2; usage;;
  esac
done
[ -z "$IGN" ] || [ -f "$IGN" ] || die "the ignore file $IGN does not exist"
split() { case "$1" in */*) IMGP="${1%%/*}"; IMGN="${1#*/}";; *) IMGP=""; IMGN="$1";; esac; }
ID="$(date -u +%m%d-%H%M%S)"; VM="tc-tree-$ID"; DISKS=(); VMMADE=0
# shellcheck disable=SC2329   # cleanup is called by the traps below
cleanup() {
  trap - EXIT
  [ "$VMMADE" = 1 ] && { echo "== cleaning up: deleting the helper VM $VM"; "$GC" compute instances delete "$VM" --zone "$Z" --quiet >/dev/null 2>&1 || echo "   warning: the VM $VM could not be deleted: delete it by hand"; }
  for d in ${DISKS[@]+"${DISKS[@]}"}; do echo "== cleaning up: deleting the disk $d"; "$GC" compute disks delete "$d" --zone "$Z" --quiet >/dev/null 2>&1 || echo "   warning: the disk $d could not be deleted: delete it by hand"; done
}
trap cleanup EXIT; trap 'exit 130' INT TERM
mkdir -p "$WORK" || die "cannot make the folder $WORK"
mkdisk() {   # mkdisk NAME IMAGE-SPEC
  split "$2"; local extra=(); [ -z "$IMGP" ] || extra=(--image-project "$IMGP")
  "$GC" compute disks create "$1" --zone "$Z" --image "$IMGN" ${extra[@]+"${extra[@]}"} --labels purpose=tc-tree-diff --quiet >"$WORK/$1.log" 2>&1 || die "the disk $1 could not be made from the image $2: $(tail -3 "$WORK/$1.log" | tr '\n' ' ' | cut -c1-300)"
  DISKS+=("$1")
}
rssh() { "$GC" compute ssh "$VM" --zone "$Z" --quiet --strict-host-key-checking=no --command "$1"; }
runhelper() {   # runhelper DEVICE LABEL PARTUUID OUTNAME
  rssh "sudo bash ~/tree-helper.sh $1 ~/$4 '$2' $3" > "$WORK/$4.log" 2>&1 &
  local pid=$!; while kill -0 "$pid" 2>/dev/null; do sleep "${TREE_HB:-60}"; echo "   ... making the manifest $4 ($(date -u +%H:%M) UTC)"; done; wait "$pid"; local rc=$?
  [ "$rc" = 0 ] || { echo "--- the output of the helper (its partition list helps to find the cause):" >&2; tail -25 "$WORK/$4.log" >&2; die "the manifest $4 could not be made (exit code $rc): $(tail -3 "$WORK/$4.log" | tr '\n' ' ' | cut -c1-400)"; }
  tail -2 "$WORK/$4.log" | sed 's/^/   /'
}
echo "== 1. the disk(s) made from the image(s)"
DA="tc-tree-$ID-a"; mkdisk "$DA" "$A"; echo "   $DA from $A"
ATT=(--disk "name=$DA,device-name=treea,mode=ro,boot=no")
if [ "$MODE" = diff ]; then DB="tc-tree-$ID-b"; mkdisk "$DB" "$B"; echo "   $DB from $B"; ATT+=(--disk "name=$DB,device-name=treeb,mode=ro,boot=no"); fi
echo "== 2. the helper VM $VM (an ordinary VM; the disks are attached read-only)"
"$GC" compute instances create "$VM" --zone "$Z" --machine-type "$HT" --image-family "$HF" --image-project "$HP" --no-service-account --no-scopes --labels purpose=tc-tree-diff "${ATT[@]}" --quiet >"$WORK/vm.log" 2>&1 || die "the helper VM could not be made: $(tail -3 "$WORK/vm.log" | tr '\n' ' ' | cut -c1-300)"
VMMADE=1
echo "== 3. waiting for the VM to accept SSH"
up=0; for t in 1 2 3 4 5 6 7 8 9 10 11 12; do if rssh true >/dev/null 2>&1; then up=1; break; fi; echo "   not yet (attempt $t of 12)"; sleep "${TREE_SSH_WAIT:-15}"; done
[ "$up" = 1 ] || die "the helper VM does not accept SSH after 12 attempts"
"$GC" compute scp --zone "$Z" --quiet --strict-host-key-checking=no "$HERE/tree-manifest.py" "$HERE/tree-helper.sh" "$VM":~ >"$WORK/scp.log" 2>&1 || die "the tools could not be copied to the VM: $(tail -3 "$WORK/scp.log" | tr '\n' ' ' | cut -c1-300)"
echo "== 4. the manifests (the helper mounts each disk read-only and hashes every file)"
runhelper treea "$A" "$UA" a.manifest
[ "$MODE" = diff ] && runhelper treeb "$B" "$UB" b.manifest
echo "== 5. fetching the manifests"
"$GC" compute scp --zone "$Z" --quiet --strict-host-key-checking=no "$VM":~/a.manifest "$WORK/" >"$WORK/scp.log" 2>&1 || die "the manifest could not be fetched: $(tail -3 "$WORK/scp.log" | tr '\n' ' ' | cut -c1-300)"
[ "$MODE" = diff ] && { "$GC" compute scp --zone "$Z" --quiet --strict-host-key-checking=no "$VM":~/b.manifest "$WORK/" >"$WORK/scp.log" 2>&1 || die "the manifest b could not be fetched"; }
if [ "$MODE" = manifest ]; then cp "$WORK/a.manifest" "$OUTF" || die "cannot write $OUTF"; echo "the manifest of $A is in $OUTF ($(grep -c . "$OUTF") lines)"; echo "TREE-MANIFEST-OK image=$A out=$OUTF"; exit 0; fi
echo "== 6. the comparison"
ARGS=("$WORK/a.manifest" "$WORK/b.manifest" --report "$WORK/differences.tsv"); [ -z "$IGN" ] || ARGS+=(--ignore "$IGN")
python3 "$HERE/tree-diff.py" "${ARGS[@]}"; rc=$?
exit "$rc"
