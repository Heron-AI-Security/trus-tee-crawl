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
echo "== 8. the CI check of the committed packages (ops/ci/debs-sums.sh, run by the workflow debs-sums)"
CIS="$T/ops/ci/debs-sums.sh"
mkd() { rm -rf "$W/ci"; mkdir -p "$W/ci/ops/image/debs"; ( cd "$W/ci/ops/image/debs" && python3 -c "
import random; random.seed(5); b = bytearray(random.randrange(256) for _ in range(4000)); b[100:102] = b'\r\n'; open('a_1_amd64.deb', 'wb').write(bytes(b)); open('b_2_all.deb', 'wb').write(bytes(random.randrange(256) for _ in range(3000)))"; sha256sum *.deb > SHA256SUMS; printf 'snapshot_date: 20261027T000000Z\nbase_image: ubuntu-2204-jammy-v20261105\nkernel_signature: signed: the SHA-256 pinned in tc-image-prep.sh equal those of the signed noble indexes of the dated archive\n' > SOURCE.txt); }
ci() { bash "$CIS" "$W/ci" 2>&1; }
mkd; out="$(ci)"; [ $? = 0 ] && grep -q "^DEBS-SUMS-OK files=2" <<<"$out" && chk "the good folder passes" ok || chk "the good folder failed: $(tail -2 <<<"$out" | tr '\n' ' ')" no
mkd; printf X >> "$W/ci/ops/image/debs/b_2_all.deb"; out="$(ci)"; [ $? != 0 ] && grep -q "sha256sum -c failed" <<<"$out" && chk "refused: a package whose bytes changed" ok || chk "a changed package passed" no
mkd; python3 -c "
p = '$W/ci/ops/image/debs/a_1_amd64.deb'; b = open(p, 'rb').read(); assert b'\r\n' in b; open(p, 'wb').write(b.replace(b'\r\n', b'\n'))"; out="$(ci)"; [ $? != 0 ] && grep -q "sha256sum -c failed" <<<"$out" && chk "refused: the corruption of the first commit (the bytes 0D 0A rewritten to 0A) is caught" ok || chk "the CRLF corruption passed" no
mkd; head -c 500 /dev/urandom > "$W/ci/ops/image/debs/c_3_all.deb"; out="$(ci)"; [ $? != 0 ] && grep -q "differ" <<<"$out" && chk "refused: a package that is in the folder but not in SHA256SUMS" ok || chk "an unlisted package passed" no
mkd; rm "$W/ci/ops/image/debs/b_2_all.deb"; out="$(ci)"; [ $? != 0 ] && chk "refused: a listed package that is missing" ok || chk "a missing package passed" no
mkd; echo x > "$W/ci/ops/image/debs/evil.sh"; out="$(ci)"; [ $? != 0 ] && grep -q "do not belong" <<<"$out" && chk "refused: a stray file in the folder" ok || chk "a stray file passed" no
mkd; rm "$W/ci/ops/image/debs/SOURCE.txt"; out="$(ci)"; [ $? != 0 ] && grep -q "SOURCE.txt is missing" <<<"$out" && chk "refused: no SOURCE.txt" ok || chk "no SOURCE.txt passed" no
mkd; sed -i 's/^kernel_signature: signed/kernel_signature: unsigned/' "$W/ci/ops/image/debs/SOURCE.txt"; out="$(ci)"; [ $? != 0 ] && grep -q "kernel_signature: signed" <<<"$out" && chk "refused: kernel files that are not chained to the signed index" ok || chk "an unsigned kernel record passed" no
mkd; sed -i 's/^base_image:.*/base_image: ubuntu-2204-lts/' "$W/ci/ops/image/debs/SOURCE.txt"; out="$(ci)"; [ $? != 0 ] && grep -q "no dated base image" <<<"$out" && chk "refused: the moving image family as the base image" ok || chk "a family base image passed" no
mkd; truncate -s 96M "$W/ci/ops/image/debs/big_1_all.deb"; ( cd "$W/ci/ops/image/debs" && sha256sum *.deb > SHA256SUMS ); out="$(ci)"; [ $? != 0 ] && grep -q "over 95 MB" <<<"$out" && chk "refused: a file over 95 MB (GitHub refuses 100 MB)" ok || chk "a 96 MB file passed" no
rm -rf "$W/ci2"; mkdir -p "$W/ci2/ops/image"; out="$(bash "$CIS" "$W/ci2" 2>&1)"; [ $? != 0 ] && grep -q "does not exist" <<<"$out" && chk "refused: no ops/image/debs folder at all" ok || chk "a missing folder passed" no
mkd; : > "$W/ci/ops/image/debs/SHA256SUMS"; out="$(ci)"; [ $? != 0 ] && chk "refused: an empty SHA256SUMS" ok || chk "an empty SHA256SUMS passed" no
[ -f "$T/.github/workflows/debs-sums.yml" ] && grep -q 'run: bash ops/ci/debs-sums.sh' "$T/.github/workflows/debs-sums.yml" && ! grep -q 'secrets\.' "$T/.github/workflows/debs-sums.yml" && grep -q 'persist-credentials: false' "$T/.github/workflows/debs-sums.yml" && chk "the workflow runs the script, uses no secret and keeps no credentials" ok || chk "the workflow is missing or wrong" no
echo; echo "pass: $P   fail: $F"; [ $F = 0 ] && echo "DEBS-KITS-REHEARSAL-PASS" || echo "DEBS-KITS-REHEARSAL-FAIL"; [ $F = 0 ]
