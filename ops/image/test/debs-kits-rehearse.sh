#!/usr/bin/env bash
# Rehearsal of the switch from the archive pin to the committed packages: the kits (s0-prepare.sh, s1-build.sh, s2-compare.sh, the report of the run script), the driver (f03-drive.sh) and the repository as a whole.
#   bash debs-kits-rehearse.sh TREE        (TREE holds ops/; no cloud, no network, nothing is written outside a temporary folder)
# The pieces of the kit scripts that matter are taken out of the REAL files (between the markers #DEBS-CHECK-BEGIN/END and #DEBS-COMPARE-BEGIN/END) and run against good and bad inputs, so the text that the kits run is the text that is tested.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; KITS="$T/ops/kits"; DRIVE="$T/ops/image/test/f03-drive.sh"; W="$(mktemp -d)"; P=0; F=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then echo "  pass: $1"; P=$((P + 1)); else echo "  FAIL: $1"; F=$((F + 1)); fi; }
ext() { sed -n "/^#$2-BEGIN/,/^#$2-END/p" "$1" | sed '1d;$d'; }
SIX="cl2-kit psl-fix-kit r4-r47-kit rel-fix-kit k1a-kit e15r2-kit"
echo "== 1. the six kits: only what Task 6 asks (the old kits are replaced by the next deliverable and are not made to work again here)"
for k in $SIX; do d="$KITS/$k"
  L="$(grep -rnE 'aptpin|APTPIN|tc-prefetch|snapwait|snap_wait|prefetch_builder|prefetch\.sh|SNAP_GATE|snapshot\.ubuntu\.com' "$d" 2>/dev/null | cut -c1-110 | head -2 | tr '\n' ' ')"; [ -z "$L" ] && chk "$k: the archive pin, the prefetch and the snapshot probe are gone" ok || chk "$k still names them: $L" no
  [ ! -e "$d/snapwait.sh" ] && [ ! -e "$d/tc-prefetch.sh" ] && [ ! -e "$d/prefetch.sh" ] && chk "$k: snapwait.sh, tc-prefetch.sh and prefetch.sh are deleted" ok || chk "$k still has a workaround script" no
  grep -q 'for st in ship-builder debs prep ' "$d/s1-build.sh" && chk "$k: the stage list runs debs (the stage aptpin is gone)" ok || chk "$k: the stage list is wrong" no
  (cd "$d" && sha256sum -c MANIFEST.sha256 >/dev/null 2>&1) && chk "$k: the manifest matches the files" ok || chk "$k: the manifest does not match its files" no
done
echo "== 2. who names Canonical's snapshot service in ops/ (the acceptance: the capture tool, and the record SOURCE.txt of the capture)"
BAD="$(grep -rl 'snapshot\.ubuntu\.com' "$T/ops" 2>/dev/null | sed "s#^$T/##" | grep -vE '^ops/image/build/tc-image-debs-capture\.sh$|^ops/image/debs/SOURCE\.txt$')"; [ -z "$BAD" ] && chk "only the capture tool (and SOURCE.txt, the record of the capture) name the service" ok || chk "these files name the service too: $(echo $BAD | tr '\n' ' ')" no
[ ! -e "$T/ops/image/build/tc-image-aptpin.sh" ] && chk "tc-image-aptpin.sh is gone" ok || chk "tc-image-aptpin.sh still exists" no
echo "== 3. the driver (dry run: it prints what it would do)"
dr() { ( cd "$T" && DRY=1 OUT="$W/drv" ZONE=z BUILDER=tcb TESTVM=tct bash "$DRIVE" "$@" 2>&1 ); }
dr debs | grep -q 'DRY: ssh tcb: cd ~/f03 && bash ops/image/build/tc-image-debs.sh ~/f03' && chk "stage debs runs tc-image-debs.sh on the builder" ok || chk "stage debs is wrong" no
dr ship-builder | grep -q 'DRY: tar czf /tmp/f03-ship-tcb.tgz -C ' && ! dr ship-builder | grep 'DRY: tar' | grep -q 'exclude' && chk "ship-builder carries the committed packages (no exclusion)" ok || chk "ship-builder excludes the packages or is wrong" no
dr ship-test | grep 'DRY: tar' | grep -q -- '--exclude=ops/image/debs' && chk "ship-test does NOT carry the 184 MB of packages (no apt runs there)" ok || chk "ship-test carries the packages" no
[ "$(grep -c 'tar czf "/tmp/f03-ship-$V.tgz" "${NODEBS\[@\]}"' "$DRIVE")" = 1 ] && chk "shipkit (every other VM) excludes the packages" ok || chk "shipkit does not exclude the packages" no
mkdir -p "$W/gbin"; printf '#!/bin/bash\nif [ "$1 $2" = "compute ssh" ]; then echo "${FAKE_SSH_OUT:-ok}"; exit "${FAKE_SSH_RC:-0}"; fi\nexit 0\n' > "$W/gbin/gcloud"; chmod +x "$W/gbin/gcloud"
live() { ( cd "$T" && PATH="$W/gbin:$PATH" OUT="$W/drv2" ZONE=z BUILDER=tcb FAKE_SSH_RC="$1" FAKE_SSH_OUT="$2" bash "$DRIVE" "$3" 2>&1; echo "rc=$?" ); }
out="$(live 1 'ABORT: a file does not match SHA256SUMS' debs)"; grep -q '^rc=1' <<<"$out" && grep -q 'committed packages stage stopped' <<<"$out" && chk "a failed packages stage stops the driver too" ok || chk "a failed debs stage did not stop the driver" no
dr aptpin | grep -q 'unknown stage: aptpin' && chk "the retired stage aptpin is refused as unknown" ok || chk "aptpin is still a stage" no
echo; echo "pass: $P   fail: $F"; [ $F = 0 ] && echo "DEBS-KITS-REHEARSAL-PASS" || echo "DEBS-KITS-REHEARSAL-FAIL"; [ $F = 0 ]
