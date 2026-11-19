#!/usr/bin/env bash
# Rehearsal (no cloud, about a minute) of tc-image-debs-capture.sh with REAL apt against a small fake Ubuntu archive that is SIGNED and served on 127.0.0.1 (so apt downloads over http and copies the files, as from the snapshot service).
# It checks the capture (the packages, the epoch in a file name, SHA256SUMS, SOURCE.txt), that the real stage tc-image-debs.sh accepts the result, and that the SIGNED path is enforced: a tampered InRelease, a signature by another key and an unsigned archive are all refused.   bash debs-capture-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$K/ops/image"; CAP="$I/build/tc-image-debs-capture.sh"; STAGE="$I/build/tc-image-debs.sh"; W="$(mktemp -d)"; PORT=$((20000 + RANDOM % 20000)); P=0; F=0; SRV=""; export TC_LIVE_URL="http://127.0.0.1:$PORT/live"
trap '[ -z "$SRV" ] || kill "$SRV" 2>/dev/null; rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then echo "  pass: $1"; P=$((P+1)); else echo "  FAIL: $1"; F=$((F+1)); fi; }
for t in apt-get dpkg-deb gpg gpgv python3 curl; do command -v $t >/dev/null 2>&1 || { echo "  FAIL: this rehearsal needs $t"; echo; echo "pass: 0   fail: 1"; echo "DEBS-CAPTURE-REHEARSAL-FAIL"; exit 1; }; done
export TC_LIVE_URL="http://127.0.0.1:$PORT/live"; mkdir -p "$W/pk" "$W/www" "$W/repo/ops/image/build" "$W/bin"   # $W/www is the root of the local web server: the fake archive (ubuntu) and the fake pool for the kernel files (kpool)
mkdeb() { local n="$1" v="${2:-1.0}" dep="${3:-}" rec="${4:-}" out="$5" fn="${6:-}"; local d="$W/pk/$n-$v"; rm -rf "$d"; mkdir -p "$d/DEBIAN" "$out"; { echo "Package: $n"; echo "Version: $v"; echo "Architecture: amd64"; echo "Maintainer: rehearsal <r@example.invalid>"; [ -n "$dep" ] && echo "Depends: $dep"; [ -n "$rec" ] && echo "Recommends: $rec"; echo "Description: fake $n for the rehearsal"; } > "$d/DEBIAN/control"; [ -n "$fn" ] || fn="${n}_${v}_amd64.deb"; dpkg-deb --root-owner-group --build "$d" "$out/$fn" > /dev/null 2>&1; }
# the keys: a good one (its keyring is the one that the capture trusts) and another one
export GNUPGHOME="$W/gh"; mkdir -m 700 "$GNUPGHOME"; GB="$W/gb"; mkdir -m 700 "$GB"
for h in "$GNUPGHOME" "$GB"; do printf '%%no-protection\nKey-Type: RSA\nKey-Length: 2048\nName-Real: Fake %s\nName-Email: f@example.invalid\nExpire-Date: 0\n%%commit\n' "$(basename "$h")" > "$W/k.batch"; GNUPGHOME="$h" gpg --batch --gen-key "$W/k.batch" > /dev/null 2>&1; done
gpg --export > "$W/keyring.gpg" 2>/dev/null; FPR="$(gpg --list-keys --with-colons 2>/dev/null | sed -n 's/^fpr:::::::::\([0-9A-F]*\):$/\1/p' | head -1)"
# the kernel files and the fake prep script: the real lines of tc-image-prep.sh, with the hashes of the fake kernel files
IMGF="$(sed -n 's/^IMG="\(.*\)"$/\1/p' "$I/build/tc-image-prep.sh" | head -1)"; MODF="$(sed -n 's/^MOD="\(.*\)"$/\1/p' "$I/build/tc-image-prep.sh" | head -1)"
KVER="${IMGF#*_}"; KVER="${KVER%%_*}"; mkdir -p "$W/www/kpool/linux-signed-gcp-6.17" "$W/www/kpool/linux-gcp-6.17"
mkdeb "${IMGF%%_*}" "$KVER" "" "" "$W/www/kpool/linux-signed-gcp-6.17" "$IMGF"; mkdeb "${MODF%%_*}" "$KVER" "" "" "$W/www/kpool/linux-gcp-6.17" "$MODF"
HI="$(sha256sum "$W/www/kpool/linux-signed-gcp-6.17/$IMGF" | cut -c1-64)"; HM="$(sha256sum "$W/www/kpool/linux-gcp-6.17/$MODF" | cut -c1-64)"
mkprep() { grep -E '^(IMG|MOD|SHA_IMG|SHA_MOD)=' "$I/build/tc-image-prep.sh" | sed -E "/^SHA_IMG=/s/[0-9a-f]{64}/${1:-$HI}/; /^SHA_MOD=/s/[0-9a-f]{64}/$HM/" > "$W/repo/ops/image/build/tc-image-prep.sh"; }
mkprep; cp "$I/build/apt-installs.txt" "$W/repo/ops/image/build/"; printf '20261027T000000Z\n' > "$W/repo/ops/image/build/apt-snapshot.txt"
# the base image of the fake builder already has ca-certificates installed (so the capture must NOT take it)
printf 'Package: ca-certificates\nStatus: install ok installed\nPriority: optional\nArchitecture: amd64\nVersion: 1.0\nMaintainer: rehearsal <r@example.invalid>\nDescription: in the base image\n\n' > "$W/status"
# the archive: three jammy suites, signed. mode: good | tamper | wrongkey | unsigned | missingdep.   The kernel files are in the NOBLE suites: KIN=dated (default) | live | none, KBAD=1 (a wrong SHA-256 in the index), NTAMPER=1 (a tampered dated noble InRelease)
mkarchive() {
  local mode="${1:-good}" T="$W/www/ubuntu/20261027T000000Z" s c; rm -rf "$W/www/ubuntu" "$W/pool" "$W/poolu"; mkdir -p "$W/pool" "$W/poolu"; local O="$W/pool"
  mkdeb xxd 1.0 "" "" $O; mkdeb libwg-fake 1.0 "" "" $O; mkdeb tc-resolvconf 1.0 "" "" $O; mkdeb wireguard-tools 1.0 libwg-fake tc-resolvconf $O; mkdeb openjdk-11-jre-headless 1.0 "" "" $O; mkdeb openjdk-11-jdk-headless 1.0 openjdk-11-jre-headless "" $O
  mkdeb ca-certificates 1.0 "" "" $O; mkdeb ant-lib 1.0 "" "" $O; mkdeb ant 1.0 ant-lib "" $O; mkdeb maven-lib 1.0 "" "" $O; mkdeb maven 1.0 maven-lib "" $O; mkdeb git 1:1.0 "" "" $O git_1.0_amd64.deb; mkdeb libcld2-0 1.0 "" "" $O; mkdeb nftables 1.0 libnftables-fake "" $O
  [ "$mode" = missingdep ] || mkdeb libnftables-fake 1.0 "" "" $O
  mkdeb openjdk-11-jdk-headless 1.1 openjdk-11-jre-headless "" "$W/poolu"
  for s in jammy jammy-updates jammy-security; do
    local D="$T/dists/$s"; mkdir -p "$D"; local rel="Origin: Fake\nSuite: $s\nCodename: $s\nArchitectures: amd64\nComponents: main restricted universe multiverse\nDate: Thu, 27 Oct 2026 00:00:00 UTC\nSHA256:\n"
    for c in main restricted universe multiverse; do
      mkdir -p "$D/$c/binary-amd64"; : > "$D/$c/binary-amd64/Packages"
      if [ "$c" = main ]; then
        local src="$O"; [ "$s" = jammy-updates ] && src="$W/poolu"; [ "$s" = jammy-security ] && src=""
        if [ -n "$src" ]; then for f in "$src"/*.deb; do [ -e "$f" ] || continue; mkdir -p "$T/pool/main"; cp -f "$f" "$T/pool/main/"; { dpkg-deb -f "$f"; printf 'Filename: pool/main/%s\nSize: %s\nSHA256: %s\n\n' "$(basename "$f")" "$(stat -c %s "$f")" "$(sha256sum "$f" | cut -c1-64)"; } >> "$D/$c/binary-amd64/Packages"; done; fi
      fi
      rel="$rel $(sha256sum "$D/$c/binary-amd64/Packages" | cut -c1-64) $(stat -c %s "$D/$c/binary-amd64/Packages") $c/binary-amd64/Packages\n"
    done
    printf "$rel" > "$D/Release"
    case "$mode" in
      unsigned) ;;
      wrongkey) GNUPGHOME="$GB" gpg --batch --yes --clearsign -o "$D/InRelease" "$D/Release" 2>/dev/null;;
      *) gpg --batch --yes --clearsign -o "$D/InRelease" "$D/Release" 2>/dev/null;;
    esac
    [ "$mode" != tamper ] || sed -i 's/Origin: Fake/Origin: Fakf/' "$D/InRelease"
  done
  mknoble_all
}
mknoble() { local R="$1" has="$2" tamper="$3" s D rel f sha; rm -rf "$R/dists/noble" "$R/dists/noble-updates" "$R/dists/noble-security"   # only the noble suites: the jammy ones are in the same folder
  for s in noble noble-updates noble-security; do D="$R/dists/$s"; mkdir -p "$D/main/binary-amd64"; : > "$D/main/binary-amd64/Packages"
    if [ "$has" = yes ] && [ "$s" = noble-updates ]; then mkdir -p "$R/pool/main"; for f in "$W/www/kpool/linux-signed-gcp-6.17/$IMGF" "$W/www/kpool/linux-gcp-6.17/$MODF"; do cp -f "$f" "$R/pool/main/"; sha="$(sha256sum "$f" | cut -c1-64)"; { [ "${KBAD:-0}" = 1 ] || { [ "${KBAD:-0}" = mod ] && [ "$f" = "$W/www/kpool/linux-gcp-6.17/$MODF" ]; }; } && sha=0000000000000000000000000000000000000000000000000000000000000000; { dpkg-deb -f "$f"; printf 'Filename: pool/main/%s\nSize: %s\nSHA256: %s\n\n' "$(basename "$f")" "$(stat -c %s "$f")" "$sha"; } >> "$D/main/binary-amd64/Packages"; done; fi
    rel="Origin: Fake\nSuite: $s\nCodename: $s\nArchitectures: amd64\nComponents: main\nDate: Thu, 27 Oct 2026 00:00:00 UTC\nSHA256:\n $(sha256sum "$D/main/binary-amd64/Packages" | cut -c1-64) $(stat -c %s "$D/main/binary-amd64/Packages") main/binary-amd64/Packages\n"
    printf "$rel" > "$D/Release"; gpg --batch --yes --clearsign -o "$D/InRelease" "$D/Release" 2>/dev/null
    [ "$tamper" != 1 ] || sed -i 's/Origin: Fake/Origin: Fakf/' "$D/InRelease"
  done; }
mknoble_all() { local kin="${KIN:-dated}"; rm -rf "$W/www/live"; mknoble "$W/www/ubuntu/20261027T000000Z" "$([ "$kin" = dated ] && echo yes || echo no)" "${NTAMPER:-0}"; mknoble "$W/www/live" "$([ "$kin" = live ] && echo yes || echo no)" 0; }
( cd "$W/www" && exec python3 -m http.server "$PORT" --bind 127.0.0.1 > "$W/http.log" 2>&1 ) & SRV=$!; for i in 1 2 3 4 5 6 7 8 9 10; do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.3; done
cap() { local out="$1" dl="${2:-0}"; rm -rf "$W/work"; OUT="$(TC_ROOT="$W/root" TC_SUDO="" TC_SNAPSHOT_URL="http://127.0.0.1:$PORT/ubuntu" TC_KEYRING="$W/keyring.gpg" TC_DPKG_STATUS="$W/status" TC_CAP_SLEEP=0 TC_CAP_WORK="$W/work" TC_KERNEL_URL="http://127.0.0.1:$PORT/kpool" TC_BASE_IMAGE=ubuntu-2204-jammy-v20260101 TC_COMMIT=abc1234 bash "$CAP" "$W/repo" "$out" "$dl" 2>&1)"; RC=$?; }
mkdir -p "$W/root/etc"; printf 'VERSION_CODENAME=jammy\nPRETTY_NAME="Ubuntu 22.04.5 LTS"\n' > "$W/root/etc/os-release"
echo "== the capture tool and the real files that it reads"
! grep -v '^ *#' "$CAP" | grep -qE 'trusted=yes|allow-insecure|AllowInsecureRepositories=true|--allow-unauthenticated' && grep -q 'signed-by=\$KEYRING' "$CAP" && chk "the sources of the capture use signed-by with the Ubuntu keyring, and never trusted=yes or an insecure option" ok || chk "the capture weakens the signature check" no
[[ "$IMGF" =~ ^linux-image-.*_amd64\.deb$ && "$MODF" =~ ^linux-modules-.*_amd64\.deb$ && "$(grep -m1 '^SHA_IMG=' "$I/build/tc-image-prep.sh" | grep -cE '[0-9a-f]{64}')" = 1 && "$(grep -m1 '^SHA_MOD=' "$I/build/tc-image-prep.sh" | grep -cE '[0-9a-f]{64}')" = 1 ]] && chk "the real tc-image-prep.sh still has the kernel names and the two pinned hashes in the form that the capture reads" ok || chk "the kernel lines of tc-image-prep.sh are not in the form that the capture reads" no
echo; echo "== the capture: the kernel files through apt, from the signed NOBLE index of the dated archive"
mkarchive good; cap "$W/o1"
[ $RC = 0 ] && grep -q "^CAPTURE-OK snapshot=20261027T000000Z packages=16 .*kernel=apt,apt kernel_index=dated" <<<"$OUT" && chk "it ends with CAPTURE-OK, the date, 16 packages (14 from the archive, the base image's ca-certificates left out, plus 2 kernel files) and the kernel source" ok || chk "no CAPTURE-OK: $(tail -2 <<<"$OUT" | tr '\n' ' ' | cut -c1-200)" no
ls "$W/o1"/*.deb 2>/dev/null | xargs -n1 basename 2>/dev/null | sort > "$W/got.txt"
grep -q '^git_1.0_amd64.deb$' "$W/got.txt" && ! grep -q '%' "$W/got.txt" && chk "a package with an epoch gets its pool name (git_1.0_amd64.deb), no file name has a %3a" ok || chk "the epoch is still in a file name: $(grep % "$W/got.txt" | head -2 | tr '\n' ' ')" no
! grep -q '^ca-certificates' "$W/got.txt" && grep -q '^openjdk-11-jdk-headless_1.1_amd64.deb$' "$W/got.txt" && ! grep -q '^openjdk-11-jdk-headless_1.0_' "$W/got.txt" && grep -q '^tc-resolvconf' "$W/got.txt" && chk "only what the base image lacks (no ca-certificates), the candidate of jammy-updates (1.1, not 1.0), and the recommended package of wireguard-tools" ok || chk "the package set is wrong: $(tr '\n' ' ' < "$W/got.txt" | cut -c1-200)" no
(cd "$W/o1" && sha256sum --strict -c SHA256SUMS > /dev/null 2>&1) && [ "$(wc -l < "$W/o1/SHA256SUMS")" = 16 ] && LC_ALL=C sort -k2 -c "$W/o1/SHA256SUMS" 2>/dev/null && chk "SHA256SUMS lists exactly the 16 files, sorted by name, and every hash is right" ok || chk "SHA256SUMS is wrong" no
S="$W/o1/SOURCE.txt"; MISS=""; for k in snapshot_date snapshot_url captured_utc capture_tool base_image machine keyring inrelease_sha256_jammy inrelease_sha256_jammy-updates inrelease_sha256_jammy-security packages_sha256_jammy_main_binary-amd64 packages_sha256_jammy-updates_main_binary-amd64 packages package; do grep -q "^$k: " "$S" || MISS="$MISS $k"; done
grep -q '^snapshot_date: 20261027T000000Z$' "$S" && grep -q '^base_image: ubuntu-2204-jammy-v20260101$' "$S" && grep -q 'at commit abc1234' "$S" && [ -z "$MISS" ] && chk "SOURCE.txt records the date, the URL, the base image, the commit of the tool, the keyring, the InRelease and Packages hashes and the package list" ok || chk "SOURCE.txt lacks:$MISS" no
python3 - "$W" "$FPR" <<'PYEOF' && chk "SOURCE.txt holds the true SHA-256 of each InRelease (the file that apt read) and the fingerprint of the key that signed it" ok || chk "an InRelease hash or key in SOURCE.txt is wrong" no
import glob, hashlib, re, sys
w, fpr = sys.argv[1:3]; s = open(w + "/o1/SOURCE.txt").read()
for suite in ("jammy", "jammy-updates", "jammy-security"):
    m = re.search(r"^inrelease_sha256_%s: ([0-9a-f]{64}) signed_by ([0-9A-F]{40})$" % suite, s, re.M); assert m, suite
    f = open(w + "/www/ubuntu/20261027T000000Z/dists/%s/InRelease" % suite, "rb").read(); assert hashlib.sha256(f).hexdigest() == m.group(1), suite; assert m.group(2) == fpr, (m.group(2), fpr)
PYEOF
grep -q "^kernel_$IMGF: apt sha256 $HI$" "$S" && grep -q "^kernel_$MODF: apt sha256 $HM$" "$S" && grep -q '^kernel_signature: signed: ' "$S" && chk "SOURCE.txt says that the kernel files came through apt, that their pinned SHA-256 equal the signed noble index, and the pinned hashes" ok || chk "the kernel lines of SOURCE.txt are wrong" no
python3 - "$W" "$FPR" <<'PYEOF2' && chk "SOURCE.txt holds the true SHA-256 of each noble InRelease and the fingerprint of the key that signed it (the chain to Canonical's key, for the kernel files too)" ok || chk "a noble InRelease hash or key in SOURCE.txt is wrong" no
import hashlib, re, sys
w, fpr = sys.argv[1:3]; s = open(w + "/o1/SOURCE.txt").read()
for suite in ("noble", "noble-updates", "noble-security"):
    m = re.search(r"^kernel_inrelease_sha256_%s: ([0-9a-f]{64}) signed_by ([0-9A-F]{40}) \(dated\)$" % suite, s, re.M); assert m, suite
    f = open(w + "/www/ubuntu/20261027T000000Z/dists/%s/InRelease" % suite, "rb").read(); assert hashlib.sha256(f).hexdigest() == m.group(1), suite; assert m.group(2) == fpr, suite
PYEOF2
echo; echo "== the real stage accepts what the capture wrote (the contract), on a fake builder whose base image has ca-certificates"
SR="$W/sr"; rm -rf "$SR"; mkdir -p "$SR/etc/apt/sources.list.d" "$SR/etc/apt/apt.conf.d" "$SR/var/lib/apt/lists/partial" "$SR/var/cache/apt/archives/partial" "$SR/var/lib/dpkg"; cp "$W/status" "$SR/var/lib/dpkg/status"; printf 'VERSION_CODENAME=jammy\n' > "$SR/etc/os-release"; printf 'deb http://x.invalid/ubuntu jammy main\n' > "$SR/etc/apt/sources.list"
o="-o Dir::Etc::sourcelist=$SR/etc/apt/sources.list -o Dir::Etc::sourceparts=$SR/etc/apt/sources.list.d -o Dir::State=$SR/var/lib/apt -o Dir::State::lists=$SR/var/lib/apt/lists -o Dir::State::status=$SR/var/lib/dpkg/status -o Dir::Cache=$SR/var/cache/apt -o Dir::Cache::pkgcache=pkgcache.bin -o Dir::Cache::srcpkgcache=srcpkgcache.bin -o Debug::NoLocking=1 -o APT::Sandbox::User=$(id -un)"
printf '#!/bin/bash\nexec apt-get %s "$@"\n' "$o" > "$W/bin/apt-get"; printf '#!/bin/bash\nexec apt-cache %s "$@"\n' "$o" > "$W/bin/apt-cache"; chmod +x "$W/bin/"*; rm -rf "$W/stage"; mkdir -p "$W/stage"; cp -a "$W/o1/." "$W/stage/"
SOUT="$(TC_ROOT="$SR" TC_SUDO="" TC_APT="$W/bin/apt-get" TC_APTCACHE="$W/bin/apt-cache" TC_DEBS_DIR="$W/stage" bash "$STAGE" "$K" 2>&1)"; SRC=$?
[ $SRC = 0 ] && grep -q "^DEBS-OK snapshot=20261027T000000Z packages=16 " <<<"$SOUT" && chk "tc-image-debs.sh ends with DEBS-OK on the folder that the capture wrote (the files, the names, SHA256SUMS and SOURCE.txt fit together)" ok || chk "the stage does not accept the capture: $(tail -2 <<<"$SOUT" | tr '\n' ' ' | cut -c1-220)" no
echo; echo "== the kernel files when the dated archive lacks them: the live archive, then nothing"
KIN=live mkarchive good; cap "$W/o2"; [ $RC = 0 ] && grep -q "kernel=apt,apt kernel_index=live" <<<"$OUT" && grep -q '^kernel_signature: signed: .* the live archive' "$W/o2/SOURCE.txt" && chk "if the dated archive lacks the kernel files, the signed noble index of the live archive is used, and SOURCE.txt says live" ok || chk "the live fallback did not work: $(tail -2 <<<"$OUT" | tr '\n' ' ' | cut -c1-200)" no
KIN=none mkarchive good; rm -rf "$W/o7"; cap "$W/o7"; [ $RC != 0 ] && grep -q "no noble suite" <<<"$OUT" && { [ ! -e "$W/o7" ] || [ -z "$(ls -A "$W/o7")" ]; } && chk "refused: the exact kernel versions are in no noble suite, dated or live (their pinned hash cannot be chained to Canonical's key), and the output folder stays empty" ok || chk "no refusal when no noble suite has the kernel files (rc=$RC: $(tail -1 <<<"$OUT" | cut -c1-120))" no
KIN=none mkarchive good; rm -rf "$W/o8"; TC_ALLOW_UNSIGNED_KERNEL=1 cap "$W/o8"; [ $RC = 0 ] && grep -q "kernel=pool,pool kernel_index=none" <<<"$OUT" && grep -q '^kernel_signature: unsigned' "$W/o8/SOURCE.txt" && chk "with TC_ALLOW_UNSIGNED_KERNEL=1 the pool and the pinned hash alone are accepted, and SOURCE.txt says unsigned" ok || chk "the unsigned switch did not work: $(tail -2 <<<"$OUT" | tr '\n' ' ' | cut -c1-200)" no
KBAD=1 mkarchive good; rm -rf "$W/o10"; cap "$W/o10"; [ $RC != 0 ] && grep -q "the pin is not what Canonical publishes" <<<"$OUT" && chk "refused: the SHA-256 pinned in tc-image-prep.sh is not the one in the signed index (the pin is checked against Canonical's data)" ok || chk "a pin that differs from the signed index was accepted (rc=$RC)" no
# a corrupted copy: apt checks every download against the signed index and refuses it; the pool copy (also checked against the pin) takes over; if both are corrupted the capture stops
mkdir -p "$W/kbak"; cp -a "$W/www/kpool" "$W/kbak/"
KIN=dated mkarchive good; printf X | dd of="$W/www/ubuntu/20261027T000000Z/pool/main/$IMGF" bs=1 seek=100 conv=notrunc 2>/dev/null; rm -rf "$W/o12"; cap "$W/o12"
[ $RC = 0 ] && grep -q "kernel=pool,apt kernel_index=dated" <<<"$OUT" && chk "a corrupted kernel file in the dated archive is refused by apt (its hash is in the signed index), and the pool copy, checked against the pin, takes over" ok || chk "the corrupted archive copy was not handled (rc=$RC: $(tail -2 <<<"$OUT" | tr '\n' ' ' | cut -c1-160))" no
printf X | dd of="$W/www/kpool/linux-signed-gcp-6.17/$IMGF" bs=1 seek=100 conv=notrunc 2>/dev/null; rm -rf "$W/o13"; cap "$W/o13"
[ $RC != 0 ] && grep -q "does not match the SHA-256 that tc-image-prep.sh pins" <<<"$OUT" && { [ ! -e "$W/o13" ] || [ -z "$(ls -A "$W/o13")" ]; } && chk "refused: the kernel file is corrupted in the dated archive AND in the pool (nothing is written)" ok || chk "two corrupted copies were accepted (rc=$RC)" no
rm -rf "$W/www/kpool"; cp -a "$W/kbak/kpool" "$W/www/kpool"
KBAD=mod mkarchive good; rm -rf "$W/o14"; cap "$W/o14"; [ $RC != 0 ] && grep -q "for $MODF, but tc-image-prep.sh pins" <<<"$OUT" && chk "refused: only the MODULES file has a pin that differs from the signed index (each of the two pins is compared)" ok || chk "a modules pin that differs from the signed index was accepted (rc=$RC: $(tail -1 <<<"$OUT" | cut -c1-120))" no
NTAMPER=1 mkarchive good; rm -rf "$W/o11"; TC_LIVE_URL="http://127.0.0.1:9/live" cap "$W/o11"; [ $RC != 0 ] && { [ ! -e "$W/o11" ] || [ -z "$(ls -A "$W/o11")" ]; } && chk "refused: a tampered noble InRelease, and no live archive to fall back to" ok || chk "a tampered noble InRelease was accepted (rc=$RC)" no
echo; echo "== the SIGNED path is enforced (each case: the capture stops and the output folder stays empty)"
refuse() { mkarchive "$2"; rm -rf "$W/o9"; cap "$W/o9" 0; if [ $RC != 0 ] && [ ! -e "$W/o9" -o -z "$(ls -A "$W/o9" 2>/dev/null)" ]; then chk "$1" ok; else chk "$1 (rc=$RC, the output has $(ls "$W/o9" 2>/dev/null | wc -l) files: $(tail -1 <<<"$OUT" | cut -c1-100))" no; fi; }
refuse "refused: an InRelease that was changed after it was signed" tamper
refuse "refused: an archive signed by another key than the one in the Ubuntu keyring" wrongkey
refuse "refused: an archive without a signed InRelease" unsigned
refuse "refused: a package that the archive lacks (a dependency is missing), with a deadline of 0 minutes" missingdep
echo; echo "== the inputs"
mkarchive good; cap "$W/o3" 0; rm -rf "$W/o3"
bad() { # label, setup, pattern
  mkarchive good; rm -rf "$W/o4" "$W/repo2"; cp -a "$W/repo" "$W/repo2"; eval "$2"; rm -rf "$W/work"; OUT="$(TC_ROOT="${ROOTX:-$W/root}" TC_SUDO="" TC_SNAPSHOT_URL="http://127.0.0.1:$PORT/ubuntu" TC_KEYRING="${KEYX:-$W/keyring.gpg}" TC_DPKG_STATUS="$W/status" TC_CAP_SLEEP=0 TC_CAP_WORK="$W/work" TC_KERNEL_URL="http://127.0.0.1:$PORT/kpool" bash "$CAP" "$W/repo2" "${OUTX:-$W/o4}" 0 2>&1)"; RC=$?; ROOTX=""; KEYX=""; OUTX=""
  [ $RC != 0 ] && grep -q "$3" <<<"$OUT" && chk "$1" ok || chk "$1 (rc=$RC: $(tail -1 <<<"$OUT" | cut -c1-110))" no; }
bad "refused: a machine that is not Ubuntu 22.04" 'mkdir -p "$W/rootn/etc"; printf "VERSION_CODENAME=noble\n" > "$W/rootn/etc/os-release"; ROOTX="$W/rootn"' "22.04"
bad "refused: a date in the wrong form" 'printf "2026-10-27\n" > "$W/repo2/ops/image/build/apt-snapshot.txt"' "not in the form"
bad "refused: a date that does not exist" 'printf "20261340T000000Z\n" > "$W/repo2/ops/image/build/apt-snapshot.txt"' "not a real date"
bad "refused: a date in the future" 'printf "20991231T000000Z\n" > "$W/repo2/ops/image/build/apt-snapshot.txt"' "in the future"
bad "refused: no Ubuntu archive keyring on the machine" 'KEYX="$W/no-such-keyring.gpg"' "no keyring"
bad "refused: an output folder that is not empty" 'mkdir -p "$W/o5"; echo x > "$W/o5/x"; OUTX="$W/o5"' "is not empty"
bad "refused: a pinned kernel hash that differs from the signed index (checked before anything is downloaded)" 'mkprep 0000000000000000000000000000000000000000000000000000000000000000; cp "$W/repo/ops/image/build/tc-image-prep.sh" "$W/repo2/ops/image/build/"; mkprep' "the pin is not what Canonical publishes"
echo; echo "== patience: the first round fails, the next one succeeds"
mkarchive good; rm -rf "$W/work" "$W/o6" "$W/cnt"; printf '#!/bin/bash\nif [ "$1" = update ] && [ ! -e "%s/cnt" ]; then : > "%s/cnt"; echo "E: the archive did not answer" >&2; exit 100; fi\nexec apt-get "$@"\n' "$W" "$W" > "$W/bin/apt-flaky"; chmod +x "$W/bin/apt-flaky"
OUT="$(TC_APT="$W/bin/apt-flaky" TC_ROOT="$W/root" TC_SUDO="" TC_SNAPSHOT_URL="http://127.0.0.1:$PORT/ubuntu" TC_KEYRING="$W/keyring.gpg" TC_DPKG_STATUS="$W/status" TC_CAP_SLEEP=0 TC_CAP_WORK="$W/work" TC_KERNEL_URL="http://127.0.0.1:$PORT/kpool" bash "$CAP" "$W/repo" "$W/o6" 2 2>&1)"; RC=$?
[ $RC = 0 ] && grep -q "round 2" <<<"$OUT" && grep -q "^CAPTURE-OK" <<<"$OUT" && chk "a failed first round is repeated after a pause, and the second round completes the capture" ok || chk "no second round: $(tail -2 <<<"$OUT" | tr '\n' ' ' | cut -c1-160)" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "DEBS-CAPTURE-REHEARSAL-PASS" || { echo "DEBS-CAPTURE-REHEARSAL-FAIL"; exit 1; }
