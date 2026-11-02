#!/usr/bin/env bash
# ops/image/test/tamper-rehearse.sh: the offline rehearsal of the tamper cases of step P4 (no Google): ops/tree-lib.sh and the partition lookup of ops/tree-helper.sh with two disks that have the SAME partition id,
# ops/tree-tamper-helper.sh on REAL ext4 files with a dm-verity hash tree like the real root partition (real loop mounts and the real veritysetup: only as root, otherwise skipped), and ops/image/test/tamper-test.sh
# against a fake gcloud, including the clean-up after a success and after every failure and the text of an SSH error.
# Usage:  bash ops/image/test/tamper-rehearse.sh [ROOT]      ROOT is the repository folder (default: three folders above this script).   Ends with  pass: N   fail: M  and TAMPER-REHEARSAL-PASS or TAMPER-REHEARSAL-FAIL.
# shellcheck disable=SC2015,SC2016   # SC2015: the chk lines are written as test && chk ok || chk no (chk never fails); SC2016: some patterns are literal text with a dollar sign
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "TAMPER-REHEARSAL-FAIL: no folder $1"; exit 2; }
W="$(mktemp -d)"; MNTS=(); cleanup() { for m in ${MNTS[@]+"${MNTS[@]}"}; do umount "$m" 2>/dev/null; done; rm -rf "$W"; }; trap cleanup EXIT
pass=0; fail=0; ONLY="${REHEARSE_ONLY:-LHO}"
chk() { if [ "$2" = ok ]; then pass=$((pass+1)); echo "  ok:   $1"; else fail=$((fail+1)); echo "  FAIL: $1"; fi; }
want() { grep -q -- "$1" "$W/out.txt"; }
HAVE_VS=0; command -v veritysetup >/dev/null 2>&1 && HAVE_VS=1
CAN_LOOP=0
if [ "$(id -u)" = 0 ] && [ "$HAVE_VS" = 1 ] && command -v mke2fs >/dev/null 2>&1; then
  truncate -s 4M "$W/t.img" && mke2fs -q -t ext4 -F "$W/t.img" >/dev/null 2>&1 && mkdir "$W/tm" && mount -o loop "$W/t.img" "$W/tm" 2>/dev/null && { umount "$W/tm"; CAN_LOOP=1; }
fi
BLK=2048; SALT="$(python3 -c "import os; print(os.urandom(32).hex())")"; PU=67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8
seal() { veritysetup format --no-superblock --hash=sha256 --data-block-size=4096 --hash-block-size=4096 --data-blocks=$BLK --hash-offset=$((BLK * 4096)) --salt="$SALT" "$1" "$1" 2>&1 | awk '/Root hash:/ {print $3}'; }
# a partition file like the real one: an ext4 file system of exactly $BLK blocks, then (after it) the dm-verity hash tree, in ONE file
mkpart() {   # mkpart FILE FSDIR
  rm -f "$1"; truncate -s $((BLK * 4096 + 1048576)) "$1"; mke2fs -q -t ext4 -b 4096 -F -d "$2" "$1" $BLK >/dev/null 2>&1; seal "$1"
}
if [ "$HAVE_VS" = 1 ]; then
  mkdir -p "$W/fs/etc" "$W/fs/usr/bin" "$W/fs/usr/local/bin" "$W/fs/var/log" "$W/fs/home/user"; echo "Ubuntu 24.04" > "$W/fs/etc/issue"; echo "Ubuntu" > "$W/fs/etc/issue.net"; chmod 644 "$W/fs/etc/issue.net"
  printf '#!/bin/sh\necho cat\n' > "$W/fs/usr/bin/cat"; chmod 755 "$W/fs/usr/bin/cat"; ln -s ../usr/bin/cat "$W/fs/etc/catlink"; for i in 1 2 3; do echo "file $i" > "$W/fs/home/user/f$i"; done
  ROOTH="$(mkpart "$W/orig.img" "$W/fs")"
fi
# ------------------------------------------------------------------ L. the lookup of the partition and the parameters
if [[ "$ONLY" == *L* ]]; then
echo "== L. ops/tree-lib.sh and the lookup of the partition by ops/tree-helper.sh"
cat > "$W/lsblk-stub" <<'STUB'
#!/usr/bin/env bash
# lsblk -ln -o PATH,PARTUUID DISK: two disks with the SAME partition ids
d="${*: -1}"; f="$LSBLK_ROWS_DIR/$(basename "$d").rows"; [ -f "$f" ] && cat "$f" || exit 1
STUB
chmod +x "$W/lsblk-stub"; mkdir -p "$W/rows"; export LSBLK_ROWS_DIR="$W/rows" TC_LSBLK="$W/lsblk-stub"
printf '%s\n' "/dev/sdb " "/dev/sdb1 67E882D8-F5CF-4A1E-9CBD-6ADB92CB58E8" "/dev/sdb15 baf407ef-3d13-4f53-ac0c-d9cfd0c3e153" > "$W/rows/google-diskA.rows"
printf '%s\n' "/dev/sdc " "/dev/sdc1 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8" "/dev/sdc15 baf407ef-3d13-4f53-ac0c-d9cfd0c3e153" > "$W/rows/google-diskB.rows"
# shellcheck source=ops/tree-lib.sh
. "$ROOT/ops/tree-lib.sh"
[ "$(tc_find_part /dev/disk/google-diskA 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8)" = /dev/sdb1 ] && [ "$(tc_find_part /dev/disk/google-diskB 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8)" = /dev/sdc1 ] && chk "two disks with the SAME partition id: each is looked up on its own disk (sdb1 and sdc1), not in a global list" ok || chk "find_part same id" no
[ "$(tc_find_part /dev/disk/google-diskA 67E882D8-F5CF-4A1E-9CBD-6ADB92CB58E8)" = /dev/sdb1 ] && [ "$(tc_find_part /dev/disk/google-diskB 67E882D8-F5CF-4A1E-9CBD-6ADB92CB58E8)" = /dev/sdc1 ] && chk "the case of the partition id does not matter" ok || chk "find_part case" no
! tc_find_part /dev/disk/google-diskA 00000000-0000-0000-0000-000000000000 >/dev/null && ! tc_find_part /dev/disk/google-nodisk 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8 >/dev/null && ! tc_find_part /dev/disk/google-diskA baf407ef-3d13-4f53-ac0c-d9cfd0c3e15 >/dev/null && chk "an id that is not on the disk, a disk that does not exist, and a prefix of an id are all refused" ok || chk "find_part refused" no
tc_verity_args 2621440 abcd; [ "${VARGS[*]}" = "--no-superblock --hash=sha256 --data-block-size=4096 --hash-block-size=4096 --data-blocks=2621440 --hash-offset=10737418240 --salt=abcd" ] && chk "the verity parameters are the node's own: no superblock, sha256, 4096-byte blocks, 2621440 blocks, the hash tree at 10737418240" ok || chk "verity args: ${VARGS[*]}" no
if [ "$HAVE_VS" = 1 ]; then
  mkdir -p "$W/hd" "$W/disks" "$W/mA" "$W/mB"; cp "$ROOT/ops/tree-manifest.py" "$ROOT/ops/tree-helper.sh" "$ROOT/ops/tree-lib.sh" "$W/hd/"; : > "$W/disks/google-diskA"; : > "$W/disks/google-diskB"
  echo "a" > "$W/mA/a"; echo "b" > "$W/mB/b"; cp "$W/orig.img" "$W/pA.img"; cp "$W/orig.img" "$W/pB.img"
  printf '%s\n' "$W/pA.img 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8" > "$W/rows/google-diskA.rows"; printf '%s\n' "$W/pB.img 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8" > "$W/rows/google-diskB.rows"
  hl() { rm -f "$W/hd/$1.m"; ( cd "$W/hd" && env TC_DISK_DIR="$W/disks" TC_FAKE_MOUNT_"$1"="$W/m${1: -1}" bash tree-helper.sh "$1" "$1.m" "lbl-$1" 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8 "$ROOTH" $BLK "$SALT" ) > "$W/out.txt" 2>&1; echo $?; }
  rcA="$(hl diskA)"; rcB="$(hl diskB)"; [ "$rcA" = 0 ] && [ "$rcB" = 0 ] && grep -q "^# verity: $ROOTH$" "$W/hd/diskA.m" && grep -q "^# verity: $ROOTH$" "$W/hd/diskB.m" && chk "THE REAL LOOKUP PATH of the helper: two disks with the same partition id are each found and each verified (against its own file)" ok || chk "helper two disks: rcA=$rcA rcB=$rcB" no
  python3 - "$W/pB.img" <<'PY'
import sys
p = sys.argv[1]; b = bytearray(open(p, "rb").read()); b[5 * 4096 + 7] ^= 1; open(p, "wb").write(b)
PY
  rcA="$(hl diskA)"; rcB="$(hl diskB)"; [ "$rcA" = 0 ] && [ "$rcB" = 3 ] && want "VERITY CHECK FAILED" && chk "with the SAME partition id on both disks, a flipped byte in disk B's partition is found on B (exit 3) and does not touch disk A (exit 0): the lookup does not mix the disks up" ok || chk "helper tampered B: rcA=$rcA rcB=$rcB" no
  rc="$(hl diskC)"; [ "$rc" = 1 ] && want "is not attached" && chk "a disk that is not attached is named" ok || chk "helper no disk: rc=$rc" no
  printf '%s\n' "$W/pA.img 11111111-2222-3333-4444-555555555555" > "$W/rows/google-diskA.rows"; rc="$(hl diskA)"; [ "$rc" = 1 ] && want "no partition with the PARTUUID 67e882d8-f5cf-4a1e-9cbd-6adb92cb58e8 on the disk diskA" && chk "a partition id that is not on the disk is refused with its own message" ok || chk "helper wrong id: rc=$rc $(head -1 "$W/out.txt")" no
else chk "the lookup path of the helper with real dm-verity checks (skipped: veritysetup is not installed here)" ok; fi
grep -q 'tc_find_part "\$disk" "\$PUID"' "$ROOT/ops/tree-helper.sh" && ! grep -q "by-partuuid" "$ROOT/ops/tree-helper.sh" && chk "the helper no longer uses /dev/disk/by-partuuid anywhere" ok || chk "by-partuuid still used" no
fi
# ------------------------------------------------------------------ H. the tamper helper on real ext4 files
if [[ "$ONLY" == *H* ]]; then
echo "== H. ops/tree-tamper-helper.sh on real ext4 files with a dm-verity hash tree (real loop mounts and the real veritysetup)"
if [ "$CAN_LOOP" != 1 ]; then chk "the tamper helper on real files (skipped: this needs root, loop mounts, mke2fs and veritysetup; the real run on the helper VM covers it)" ok; else
TH="$W/th"; rm -rf "$TH"; mkdir -p "$TH"; cp "$ROOT/ops/tree-manifest.py" "$ROOT/ops/tree-helper.sh" "$ROOT/ops/tree-lib.sh" "$ROOT/ops/tree-tamper-helper.sh" "$TH/"
sha_orig="$(sha256sum "$W/orig.img" | cut -d' ' -f1)"
for k in 1 2 3 4 5; do cp "$W/orig.img" "$TH/c$k.img"; done
thr() { env TC_FAKE_PART_treeo="$W/orig.img" TC_FAKE_PART_tree1="$TH/c1.img" TC_FAKE_PART_tree2="$TH/c2.img" TC_FAKE_PART_tree3="$TH/c3.img" TC_FAKE_PART_tree4="$TH/c4.img" TC_FAKE_PART_tree5="$TH/c5.img" "$@"; }
( cd "$TH" && thr bash tree-tamper-helper.sh "$ROOTH" $BLK "$SALT" "$PU" "$TH/out" control:tree1 changed:tree2 added:tree3 mode:tree4 xattr:tree5 ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 0 ] && want "TREE-TAMPER-JOBS-OK" && [ -s "$TH/out/orig.manifest" ] && [ -s "$TH/out/control.manifest" ] && [ -s "$TH/out/xattr.manifest" ] && chk "all five copies and the original are processed: manifests made, TREE-TAMPER-JOBS-OK" ok || chk "tamper helper: rc=$rc $(tail -4 "$W/out.txt" | tr '\n' ' ' | cut -c1-250)" no
[ "$(sha256sum "$W/orig.img" | cut -d' ' -f1)" = "$sha_orig" ] && chk "THE ORIGINAL IS NEVER WRITTEN: its partition file is byte for byte the same after the run" ok || chk "original changed" no
[ "$(cat "$TH/out/control.root")" = "$ROOTH" ] && chk "the CONTROL (untouched, resealed) has the ORIGINAL root hash: the sealing parameters of the helper are exactly the ones of the sealing" ok || chk "control root $(cat "$TH/out/control.root") != $ROOTH" no
rs="$(cat "$TH/out/changed.root" "$TH/out/added.root" "$TH/out/mode.root" "$TH/out/xattr.root" | sort -u | wc -l)"; ! grep -q "$ROOTH" "$TH/out/changed.root" "$TH/out/added.root" "$TH/out/mode.root" "$TH/out/xattr.root" && [ "$rs" = 4 ] && chk "each of the four changes gives its own NEW root hash, different from the original's and from each other" ok || chk "new roots: $rs distinct" no
td() { python3 "$ROOT/ops/tree-diff.py" "$TH/out/orig.manifest" "$TH/out/$1.manifest" --require-verity --report "$TH/out/$1.rep" > "$W/out.txt" 2>&1; echo $?; }
got() { awk -F'\t' '$1=="DIFF" {print $2 " " $3}' "$TH/out/$1.rep" | sort | tr '\n' ';'; }
rc=$(td control); [ "$rc" = 0 ] && want "TREE-DIFF-IDENTICAL .* verity=checked" && chk "the control against the original: identical, both verity-checked" ok || chk "diff control: rc=$rc" no
rc=$(td changed); [ "$rc" = 1 ] && [ "$(got changed)" = "content differs /etc/issue;" ] && want "verity=checked" && chk "ONE CHANGED FILE: rejected, and the one difference is /etc/issue (content)" ok || chk "diff changed: rc=$rc got '$(got changed)'" no
rc=$(td added); [ "$rc" = 1 ] && [ "$(got added)" = "only in B /usr/local/bin/tc-added-file;" ] && chk "ONE ADDED FILE: rejected, and the one difference is the new file" ok || chk "diff added: rc=$rc got '$(got added)'" no
rc=$(td mode); [ "$rc" = 1 ] && [ "$(got mode)" = "mode differs /etc/issue.net;" ] && want "644 -> 600" && chk "ONE CHANGED MODE: rejected, and the one difference is /etc/issue.net (644 -> 600)" ok || chk "diff mode: rc=$rc got '$(got mode)'" no
rc=$(td xattr); [ "$rc" = 1 ] && [ "$(got xattr)" = "xattrs differ /usr/bin/cat;" ] && want "security.capability: (none) -> 010000020020000000" && chk "ONE ADDED FILE CAPABILITY: rejected, and the one difference is /usr/bin/cat (security.capability)" ok || chk "diff xattr: rc=$rc got '$(got xattr)'" no
# failure cases of the helper
run_h() { ( cd "$TH" && thr bash tree-tamper-helper.sh "$@" ) > "$W/out.txt" 2>&1; echo $?; }
rc=$(run_h "ZZ$ROOTH" $BLK "$SALT" "$PU" "$TH/o2" control:tree1); [ "$rc" = 1 ] && want "the root hash must be 64 lowercase hexadecimal digits" && chk "a root hash that is not 64 hexadecimal digits is refused" ok || chk "bad root: rc=$rc" no
rc=$(run_h "$ROOTH" abc "$SALT" "$PU" "$TH/o2" control:tree1); [ "$rc" = 1 ] && want "BLOCKS must be a positive number" && chk "a block count that is not a number is refused" ok || chk "bad blocks: rc=$rc" no
rc=$(run_h "$ROOTH" $BLK "$SALT" "$PU" "$TH/o2" wipe:tree1); [ "$rc" = 1 ] && want "is not KIND:DEVICE" && chk "an unknown kind of change is refused" ok || chk "bad kind: rc=$rc" no
rc=$(run_h "$ROOTH" $BLK "$SALT" "$PU" "$TH/o2"); [ "$rc" = 1 ] && want "usage" && chk "no copies at all is refused" ok || chk "no jobs: rc=$rc" no
rm -rf "$W/fs2" && cp -a "$W/fs" "$W/fs2" && rm "$W/fs2/etc/issue.net" && mkpart "$TH/nomode.img" "$W/fs2" >/dev/null; mkdir -p "$TH/o3"
( cd "$TH" && env TC_FAKE_PART_treeo="$W/orig.img" TC_FAKE_PART_tree1="$TH/c1.img" TC_FAKE_PART_tree2="$TH/nomode.img" bash tree-tamper-helper.sh "$ROOTH" $BLK "$SALT" "$PU" "$TH/o3" control:tree1 mode:tree2 ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 1 ] && want "there is no /etc/issue.net" && want "TREE-TAMPER-JOBS-FAILED" && want "JOB control rc=0" && chk "a copy that lacks the file to change fails with its own message; the other jobs still finish; the exit code is 1" ok || chk "missing file: rc=$rc $(tail -5 "$W/out.txt" | tr '\n' ' ' | cut -c1-250)" no
head -c 4096 /dev/zero > "$TH/zero.img"; mkdir -p "$TH/o4"; ( cd "$TH" && env TC_FAKE_PART_treeo="$W/orig.img" TC_FAKE_PART_tree1="$TH/zero.img" bash tree-tamper-helper.sh "$ROOTH" $BLK "$SALT" "$PU" "$TH/o4" changed:tree1 ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 1 ] && want "cannot mount" && chk "a copy that cannot be mounted read-write fails with its own message" ok || chk "no mount: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
fi
fi
# ------------------------------------------------------------------ O. ops/image/test/tamper-test.sh with a fake gcloud
if [[ "$ONLY" == *O* ]]; then
echo "== O. ops/image/test/tamper-test.sh (a fake gcloud; the clean-up is checked after every run)"
mkdir -p "$W/bin" "$W/stub"; export STUBDIR="$W/stub" LOG="$W/calls.log"
cat > "$W/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
echo "gcloud $*" >> "$LOG"; S="$STUBDIR"; H="$S/home"
case "$*" in
  "compute disks create"*) [ -f "$S/disk_fail" ] && { echo "ERROR: quota exceeded" >&2; exit 1; }; for a in "${@:4}"; do case "$a" in --*) break;; *) touch "$S/disk_$a";; esac; done;;
  "compute instances create"*) [ -f "$S/vm_fail" ] && { echo "ERROR: no capacity" >&2; exit 1; }; touch "$S/vm";;
  "compute ssh"*) [ -f "$S/vm" ] || { echo "ERROR: no such VM" >&2; exit 1; }
    cmd=""; prev=""; for a in "$@"; do [ "$prev" = "--command" ] && cmd="$a"; prev="$a"; done
    if [ "$cmd" = true ]; then if [ -f "$S/ssh_never" ]; then echo "ssh: connect to host 10.1.2.3 port 22: Connection timed out" >&2; exit 255; fi; exit 0; fi
    case "$cmd" in *tree-tamper-helper.sh*) [ -f "$S/helper_fail" ] && { echo "TREE-TAMPER-FAILED: boom" >&2; exit 1; };; esac
    c="${cmd//sudo /}"; c="${c//\~\//$H/}"; mkdir -p "$H"
    ( cd "$H" && env TC_FAKE_PART_treeo="$PARTS/orig.img" TC_FAKE_PART_tree1="$PARTS/c1.img" TC_FAKE_PART_tree2="$PARTS/c2.img" TC_FAKE_PART_tree3="$PARTS/c3.img" TC_FAKE_PART_tree4="$PARTS/c4.img" TC_FAKE_PART_tree5="$PARTS/c5.img" bash -c "$c" ); r=$?
    case "$cmd" in *tree-tamper-helper.sh*) [ -z "${FAKE_EXTRA:-}" ] || sed -i 's#^\(F\t/etc/issue\t\)644#\1600#' "$H/tt/$FAKE_EXTRA.manifest"; [ -z "${FAKE_SWAP:-}" ] || cp "$H/tt/orig.manifest" "$H/tt/$FAKE_SWAP.manifest"; [ -z "${FAKE_CONTROL_ROOT:-}" ] || echo "$FAKE_CONTROL_ROOT" > "$H/tt/control.root";; esac; exit $r;;
  "compute scp"*) src=(); skip=0; for a in "${@:3}"; do if [ "$skip" = 1 ]; then skip=0; continue; fi; case "$a" in --zone) skip=1;; --*) :;; *) src+=("$a");; esac; done
    dst="${src[-1]}"; unset 'src[-1]'; mkdir -p "$H"
    for s in "${src[@]}"; do case "$s" in *:*) f="${s#*:}"; f="${f/#\~/$H}"; cp "$f" "${dst}";; *) cp "$s" "$H/";; esac; done;;
  "compute instances delete"*) rm -f "$S/vm";;
  "compute disks delete"*) rm -f "$S/disk_$4";;
  *) echo "stub: unexpected gcloud call: $*" >&2; exit 99;;
esac
STUB
chmod +x "$W/bin/gcloud"
export PARTS="$W/parts"; mkdir -p "$PARTS"
if [ "$CAN_LOOP" = 1 ]; then cp "$W/orig.img" "$PARTS/orig.img"; fi
SPEC="${ROOTH:-$(printf 'a%.0s' {1..64})} $BLK ${SALT} $PU"
prep() { if [ "$CAN_LOOP" = 1 ]; then for k in 1 2 3 4 5; do cp "$W/orig.img" "$PARTS/c$k.img"; done; fi; }
run() { rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; prep; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 "$@" ) > "$W/out.txt" 2>&1; echo $?; }
nothing_left() { [ ! -e "$STUBDIR/vm" ] && ! ls "$STUBDIR"/disk_* >/dev/null 2>&1; }
made() { grep -c -E "^gcloud compute instances create" "$LOG"; }; deleted_vm() { grep -c -E "^gcloud compute instances delete" "$LOG"; }; deleted_disks() { grep -c -E "^gcloud compute disks delete" "$LOG"; }
T=(bash "$ROOT/ops/image/test/tamper-test.sh")
if [ "$CAN_LOOP" = 1 ]; then
  rc=$(run "${T[@]}" tc-img-A --verity "$SPEC" --work "$W/work"); [ "$rc" = 0 ] && want "^TAMPER-TEST-OK image=tc-img-A cases=5" && [ "$(grep -c '^  ok:' "$W/out.txt")" = 10 ] && nothing_left && [ "$(deleted_vm)" = 1 ] && [ "$(deleted_disks)" = 6 ] && chk "the whole experiment: five copies, ten checks ok (identical control, resealed root = original, four rejections, four new roots), the VM and all 6 disks deleted" ok || chk "full: rc=$rc $(grep -E 'FAIL|TAMPER' "$W/out.txt" | tr '\n' ' ' | cut -c1-300)" no
  grep -q -- "--disk name=tc-tamper-.*-0,device-name=treeo,mode=ro,boot=no --disk name=tc-tamper-.*-1,device-name=tree1,mode=rw,boot=no" "$LOG" && grep -q -- "--no-service-account --no-scopes" "$LOG" && grep -q -- "--labels purpose=tc-tamper-test" "$LOG" && chk "the original is attached READ-ONLY (treeo), the five copies read-write, no service account, no scopes, labelled for clean-up" ok || chk "attach flags" no
  grep -q "tree-tamper-helper.sh $ROOTH $BLK $SALT $PU ~/tt control:tree1 changed:tree2 added:tree3 mode:tree4 xattr:tree5" "$LOG" && chk "the helper is told the root hash, block count, salt, partition id and which copy gets which change" ok || chk "helper command: $(grep tamper-helper "$LOG" | cut -c1-250)" no
  rc=$(FAKE_SWAP=changed run "${T[@]}" tc-img-A --verity "$SPEC" --work "$W/work"); [ "$rc" = 1 ] && want "FAIL: changed: expected exit code 1 and 'content differs /etc/issue;', got exit code 0 and 'no difference'" && want "^TAMPER-TEST-FAILED (1)" && nothing_left && chk "a tampered copy that the comparison does NOT reject makes the experiment FAIL, with the expected and the actual result" ok || chk "swap: rc=$rc $(grep -E 'FAIL|TAMPER' "$W/out.txt" | tr '\n' ' ' | cut -c1-300)" no
  grep -q "compute ssh .*tree-tamper-helper.sh.* -- -o ServerAliveInterval=30 -o ServerAliveCountMax=60" "$LOG" && chk "the long helper call keeps its SSH session alive (ServerAliveInterval)" ok || chk "keepalive: $(grep 'tamper-helper' "$LOG" | grep ssh | cut -c1-200)" no
  rc=$(FAKE_EXTRA=mode run "${T[@]}" tc-img-A --verity "$SPEC" --work "$W/work"); [ "$rc" = 1 ] && want "FAIL: mode: expected exit code 1 and 'mode differs /etc/issue.net;', got exit code 1 and 'mode differs /etc/issue;mode differs /etc/issue.net;'" && chk "a copy with the expected difference AND ONE MORE is rejected by the experiment: the result must be EXACTLY the one difference" ok || chk "extra difference: rc=$rc $(grep -E 'FAIL' "$W/out.txt" | tr '\n' ' ' | cut -c1-300)" no
  rc=$(FAKE_CONTROL_ROOT=0000000000000000000000000000000000000000000000000000000000000000 run "${T[@]}" tc-img-A --verity "$SPEC" --work "$W/work"); [ "$rc" = 1 ] && want "FAIL: control: the resealed copy has the root hash '0000000000000000', not the original" && chk "a control whose resealed root hash is not the original makes the experiment FAIL: the sealing parameters would be wrong" ok || chk "control root: rc=$rc" no
else chk "the whole experiment against the fake gcloud (skipped: this needs root, loop mounts, mke2fs and veritysetup)" ok; fi
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; touch "$STUBDIR/helper_fail"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 "${T[@]}" tc-img-A --verity "$SPEC" --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 2 ] && want "the tamper helper did not finish (exit code 1)" && want "TREE-TAMPER-FAILED: boom" && ! want "== 5. fetching the manifests" && nothing_left && [ "$(deleted_disks)" = 6 ] && chk "a failure of the helper STOPS there (the next step never starts), with its message, and the VM and all 6 disks are still deleted" ok || chk "helper fail: rc=$rc" no
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; touch "$STUBDIR/ssh_never"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 TREE_SSH_TRIES=3 "${T[@]}" tc-img-A --verity "$SPEC" --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 2 ] && want "does not accept SSH after 3 attempts (the last SSH error: ssh: connect to host 10.1.2.3 port 22: Connection timed out" && want "not yet (attempt 3 of 3)" && nothing_left && chk "a VM that never accepts SSH: the REAL SSH error text is in the message, and everything is deleted" ok || chk "ssh never: rc=$rc $(tail -2 "$W/out.txt" | tr '\n' ' ' | cut -c1-250)" no
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; touch "$STUBDIR/ssh_never"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 "${T[@]}" tc-img-A --verity "$SPEC" --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 2 ] && want "does not accept SSH after 24 attempts" && chk "the default is 24 attempts to reach the VM by SSH (6 minutes at 15 seconds), not 12" ok || chk "default tries: rc=$rc" no
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; touch "$STUBDIR/disk_fail"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 "${T[@]}" tc-img-A --verity "$SPEC" --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 2 ] && want "the disks could not be made from the image tc-img-A: ERROR: quota exceeded" && [ "$(made)" = 0 ] && chk "disks that cannot be made stop everything before a VM is made" ok || chk "disk fail: rc=$rc" no
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; touch "$STUBDIR/vm_fail"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 "${T[@]}" tc-img-A --verity "$SPEC" --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?
[ "$rc" = 2 ] && want "the helper VM could not be made: ERROR: no capacity" && nothing_left && [ "$(deleted_disks)" = 6 ] && [ "$(deleted_vm)" = 0 ] && chk "a VM that cannot be made: the 6 disks are deleted and no VM delete is attempted" ok || chk "vm fail: rc=$rc" no
rm -rf "${STUBDIR:?}"/* "$W/work"; : > "$LOG"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" TREE_HB=0.2 TREE_SSH_WAIT=0 TREE_SSH_TRIES=1 "${T[@]}" proj-x/tc-img-A --verity "$SPEC" --work "$W/work" ) > "$W/out.txt" 2>&1; grep -q -- "--image tc-img-A --image-project proj-x" "$LOG" && chk "PROJECT/IMAGE uses the image of another project" ok || chk "image project" no
rm -rf "${STUBDIR:?}"/*; : > "$LOG"; ( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" "${T[@]}" tc-img-A --verity "not valid" --work "$W/work" ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 2 ] && want "--verity must be one word in quotes" && [ ! -s "$LOG" ] && chk "malformed dm-verity parameters are refused before any cloud call" ok || chk "bad spec: rc=$rc" no
( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" "${T[@]}" ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 64 ] && want "Usage:" && chk "no arguments: the usage, exit code 64" ok || chk "usage: rc=$rc" no
( cd "$W" && env PATH="$W/bin:$PATH" TC_GCLOUD="$W/bin/gcloud" "${T[@]}" tc-img-A --nonsense ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 64 ] && want "unknown option: --nonsense" && chk "an unknown option is refused" ok || chk "unknown option: rc=$rc" no
fi
echo; echo "pass: $pass   fail: $fail"
if [ "$fail" = 0 ]; then echo "TAMPER-REHEARSAL-PASS"; else echo "TAMPER-REHEARSAL-FAIL"; exit 1; fi
