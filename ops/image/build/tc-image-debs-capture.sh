#!/usr/bin/env bash
# Fills ops/image/debs: the Ubuntu packages that the image build installs, captured ONCE from a dated copy of the archive, through apt's SIGNED path (InRelease verified against Canonical's keyring).
# Run on a builder (the base image that the builds use) as a user with sudo, from a tree that holds ops/image/build. NOT part of a build: a build uses tc-image-debs.sh and the committed result.
#   bash tc-image-debs-capture.sh REPO_DIR OUT_DIR [DEADLINE_MINUTES]      OUT_DIR must be empty or new; the result is the content of ops/image/debs: the .deb files, SHA256SUMS, SOURCE.txt
# The date is the one line of ops/image/build/apt-snapshot.txt (YYYYMMDDTHHMMSSZ, UTC): the INPUT of the capture, no longer of the build. To refresh the packages: change the date, capture again on the base image that the builds use, commit the folder, rebuild.
# What it downloads: every install command of ops/image/build/apt-installs.txt with --download-only (so only what the base image lacks), and the two kernel files of tc-image-prep.sh. The kernel files are not in jammy: their exact versions are in the NOBLE suites, which are read in a separate apt state (dated archive first, the live archive if the dated one lacks them). The SHA-256 pinned in tc-image-prep.sh must equal the SHA-256 in the signed noble index, or the capture stops; the files are taken through apt, and from the pool only if apt cannot (the hash is checked either way). If no noble suite has them, the capture stops, unless TC_ALLOW_UNSIGNED_KERNEL=1 accepts the pool and the pinned SHA-256 alone (SOURCE.txt then says unsigned).
# The signature: the sources use signed-by=<the Ubuntu archive keyring> and never trusted=yes; the InRelease of every suite is verified again with gpgv, and the key is recorded in SOURCE.txt. The committed SHA256SUMS then chains back to Canonical's signing key; from the commit on, the hashes are the trust anchor.
# The indexes are kept plain (Acquire::GzipIndexes=false), so that their hashes can be recorded whatever the apt configuration of the machine is; the downloads run as root (APT::Sandbox::User=root) because the work folder belongs to the user who runs this.
# Patience: the snapshot service has bad periods, so the whole round (update, check, download) repeats with pauses for up to DEADLINE_MINUTES (default 180). Every file that arrived stays in the cache of this run.
# Hooks for the rehearsal only: TC_ROOT, TC_SUDO, TC_APT, TC_APTCACHE, TC_SNAPSHOT_URL, TC_NOBLE_URL, TC_LIVE_URL, TC_KEYRING, TC_DPKG_STATUS, TC_CURL, TC_KERNEL_URL, TC_CAP_SLEEP, TC_CAP_WORK. Inputs from the kit: TC_BASE_IMAGE (the name of the image that the builder was made from), TC_COMMIT.
set -uo pipefail
REPO="${1:?usage: $0 REPO_DIR OUT_DIR [DEADLINE_MINUTES]}"; OUT="${2:?usage: $0 REPO_DIR OUT_DIR [DEADLINE_MINUTES]}"; DEADLINE="${3:-180}"
R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"; APT="${TC_APT:-apt-get}"; APTC="${TC_APTCACHE:-apt-cache}"; BASE="${TC_SNAPSHOT_URL:-https://snapshot.ubuntu.com/ubuntu}"
KEYRING="${TC_KEYRING:-/usr/share/keyrings/ubuntu-archive-keyring.gpg}"; CURL="${TC_CURL:-curl}"; SLEEP="${TC_CAP_SLEEP:-60}"
fail() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }
say "the inputs"
PIN="$REPO/ops/image/build/apt-snapshot.txt"; LIST="$REPO/ops/image/build/apt-installs.txt"; PREP="$REPO/ops/image/build/tc-image-prep.sh"
for f in "$PIN" "$LIST" "$PREP"; do [ -f "$f" ] || fail "there is no $f"; done
TS="$(tr -d ' \r\n\t' < "$PIN")"; [[ "$TS" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || fail "the archive date '$TS' is not in the form YYYYMMDDTHHMMSSZ"
WHEN="${TS:0:4}-${TS:4:2}-${TS:6:2} ${TS:9:2}:${TS:11:2}:${TS:13:2}"; EP="$(date -u -d "$WHEN" +%s 2>/dev/null)" || fail "the archive date $TS is not a real date"
[ "$EP" -le "$(date -u +%s)" ] || fail "the archive date $TS is in the future: there is no archive of that day yet"
CODE="$(sed -n 's/^VERSION_CODENAME=//p' "$R/etc/os-release" 2>/dev/null | tr -d '"')"; [ "$CODE" = jammy ] || fail "the capture is for Ubuntu 22.04 (jammy), the machine says '${CODE:-nothing}'"
[ "$(dpkg --print-architecture 2>/dev/null)" = amd64 ] || fail "the capture is for amd64"
[ -f "$KEYRING" ] || fail "there is no keyring $KEYRING (the Ubuntu archive keyring: the signature of the archive cannot be checked without it)"
command -v gpgv >/dev/null 2>&1 || fail "gpgv is missing (apt needs it to check signatures, so every Ubuntu machine has it)"
{ [ ! -e "$OUT" ] || [ -z "$(ls -A "$OUT" 2>/dev/null)" ]; } || fail "$OUT is not empty: the capture writes a new folder"
echo "   the archive of $WHEN UTC ($TS), for jammy; commands: $(grep -vcE '^\s*(#|$)' "$LIST"); keyring $KEYRING"
kv() { sed -n "s/^$1=\"\(.*\)\"\$/\1/p" "$PREP" | head -1; }
IMG="$(kv IMG)"; MOD="$(kv MOD)"; KURL="${TC_KERNEL_URL:-http://archive.ubuntu.com/ubuntu/pool/main/l}"   # the archive pool: the capture is the only place that still downloads kernel packages (its fallback)
SHA_IMG="$(grep -m1 '^SHA_IMG=' "$PREP" | grep -oE '[0-9a-f]{64}' | head -1)"; SHA_MOD="$(grep -m1 '^SHA_MOD=' "$PREP" | grep -oE '[0-9a-f]{64}' | head -1)"
DIR_IMG=linux-signed-gcp-6.17; DIR_MOD=linux-gcp-6.17   # the pool folders of the source packages of the two files (the Filename field of the signed index names the same)
for v in "$IMG" "$MOD" "$KURL" "$SHA_IMG" "$SHA_MOD" "$DIR_IMG" "$DIR_MOD"; do [ -n "$v" ] || fail "could not read the kernel files (names, SHA-256, address) from $PREP"; done
WORK="${TC_CAP_WORK:-$(mktemp -d)}"; mkdir -p "$WORK/empty.d" "$WORK/lists/partial" "$WORK/archives/partial" "$WORK/kernel"; : > "$WORK/cap.list"
for s in jammy jammy-updates jammy-security; do echo "deb [signed-by=$KEYRING] $BASE/$TS $s main restricted universe multiverse" >> "$WORK/cap.list"; done
OPTS=(-o Dir::Etc::sourcelist="$WORK/cap.list" -o Dir::Etc::sourceparts="$WORK/empty.d" -o Dir::State::lists="$WORK/lists" -o Dir::Cache::archives="$WORK/archives" -o Acquire::Check-Valid-Until=false -o Acquire::AllowInsecureRepositories=false -o Acquire::AllowDowngradeToInsecureRepositories=false -o Acquire::GzipIndexes=false -o APT::Sandbox::User=root -o Acquire::Retries=5 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60 -o APT::Update::Error-Mode=any)
[ -z "${TC_DPKG_STATUS:-}" ] || OPTS+=(-o Dir::State::status="$TC_DPKG_STATUS")
dl() { $SUDO env DEBIAN_FRONTEND=noninteractive $APT install --download-only -y "${OPTS[@]}" "$@"; }
round() {
  $SUDO $APT update -qq "${OPTS[@]}" || { echo "   the update did not complete"; return 1; }
  local pol; pol="$($APTC "${OPTS[@]}" policy openjdk-11-jdk-headless 2>&1)"
  echo "$pol" | grep -q "^  Candidate: [^(]" || { echo "   no candidate for openjdk-11-jdk-headless: the package lists are incomplete"; return 1; }
  echo "$pol" | grep -q "$BASE/$TS" || { echo "   the candidate does not come from the dated copy $BASE/$TS"; return 1; }
  local line; while IFS= read -r line; do case "$line" in ''|'#'*) continue;; esac; dl $line || { echo "   the download of '$line' did not complete"; return 1; }; done < "$LIST"
  return 0
}
say "update and download, patiently (up to $DEADLINE minutes)"
T0=$(date +%s); N=0
while :; do
  N=$((N+1)); echo "[$(date -u +%H:%M:%S)] round $N"
  if round; then break; fi
  EL=$(( $(date +%s) - T0 )); [ "$EL" -lt $((DEADLINE*60)) ] || fail "no complete round in $DEADLINE minutes (the archive of $TS did not answer, or does not have a package; the files that arrived are in $WORK)"
  echo "   pause $SLEEP s, then the next round"; sleep "$SLEEP"
done
say "the signature of every suite is checked again with gpgv, against the Ubuntu archive keyring"
declare -A SIGNED
for s in jammy jammy-updates jammy-security; do
  F="$(ls "$WORK/lists"/*_dists_${s}_InRelease 2>/dev/null | head -1)"; [ -n "$F" ] || fail "no InRelease of $s in the lists: apt read the suite without a signed file"
  FPR="$(gpgv --keyring "$KEYRING" --status-fd 1 "$F" 2>/dev/null | sed -n 's/^\[GNUPG:\] VALIDSIG \([0-9A-F]*\) .*/\1/p' | head -1)"; [ -n "$FPR" ] || fail "the InRelease of $s is NOT signed by a key of $KEYRING"
  SIGNED[$s]="$FPR"; echo "   $s: signed by $FPR"
done
say "the two kernel files: their exact versions are in the NOBLE suites, so apt reads those in a separate state that never mixes with the jammy one"
NOBLE_DATED="${TC_NOBLE_URL:-$BASE/$TS}"; LIVE="${TC_LIVE_URL:-http://archive.ubuntu.com/ubuntu}"
IPKG="${IMG%%_*}"; IVER="${IMG#*_}"; IVER="${IVER%%_*}"; MPKG="${MOD%%_*}"; MVER="${MOD#*_}"; MVER="${MVER%%_*}"
kstate() { KD="$WORK/k-$1"; rm -rf "$KD"; mkdir -p "$KD/lists/partial" "$KD/archives/partial" "$KD/empty.d"; : > "$KD/src.list"; local s; for s in noble noble-updates noble-security; do echo "deb [signed-by=$KEYRING] $2 $s main" >> "$KD/src.list"; done
  KO=(-o Dir::Etc::sourcelist="$KD/src.list" -o Dir::Etc::sourceparts="$KD/empty.d" -o Dir::State::lists="$KD/lists" -o Dir::Cache::archives="$KD/archives" -o Acquire::Check-Valid-Until=false -o Acquire::AllowInsecureRepositories=false -o Acquire::AllowDowngradeToInsecureRepositories=false -o Acquire::GzipIndexes=false -o APT::Sandbox::User=root -o Acquire::Retries=5 -o APT::Update::Error-Mode=any)
  [ -z "${TC_DPKG_STATUS:-}" ] || KO+=(-o Dir::State::status="$TC_DPKG_STATUS"); }
kfind() { $APTC "${KO[@]}" show "$1=$2" 2>/dev/null | sed -n 's/^SHA256: //p' | head -1; }
KIDX=""; SI=""; SM=""
for MODE in dated live; do
  if [ "$MODE" = dated ]; then kstate dated "$NOBLE_DATED"; else kstate live "$LIVE"; fi
  if ! $SUDO $APT update -qq "${KO[@]}" > "$KD/update.log" 2>&1; then echo "   the $MODE noble indexes could not be read ($(tail -1 "$KD/update.log" | cut -c1-110))"; continue; fi
  SI="$(kfind "$IPKG" "$IVER")"; SM="$(kfind "$MPKG" "$MVER")"
  if [ -n "$SI" ] && [ -n "$SM" ]; then KIDX="$MODE"; echo "   both exact versions are in the signed noble indexes of the $MODE archive"; break; fi
  echo "   the $MODE noble suites do not hold both exact versions"
done
declare -A KFPR
if [ -n "$KIDX" ]; then
  [ "$SI" = "$SHA_IMG" ] || fail "the signed index says SHA-256 $SI for $IMG, but tc-image-prep.sh pins $SHA_IMG: the pin is not what Canonical publishes"
  [ "$SM" = "$SHA_MOD" ] || fail "the signed index says SHA-256 $SM for $MOD, but tc-image-prep.sh pins $SHA_MOD: the pin is not what Canonical publishes"
  for s in noble noble-updates noble-security; do
    F="$(ls "$KD/lists"/*_dists_${s}_InRelease 2>/dev/null | head -1)"; [ -n "$F" ] || fail "no InRelease of $s in the lists of the kernel step"
    FPR="$(gpgv --keyring "$KEYRING" --status-fd 1 "$F" 2>/dev/null | sed -n 's/^\[GNUPG:\] VALIDSIG \([0-9A-F]*\) .*/\1/p' | head -1)"; [ -n "$FPR" ] || fail "the InRelease of $s is NOT signed by a key of $KEYRING"
    KFPR[$s]="$(sha256sum "$F" | cut -c1-64) signed_by $FPR"; echo "   $s: signed by $FPR"
  done
  echo "   the SHA-256 pinned in tc-image-prep.sh are the SHA-256 in Canonical's signed index: the chain to the signing key holds"
else
  [ "${TC_ALLOW_UNSIGNED_KERNEL:-0}" = 1 ] || fail "the exact kernel versions are in no noble suite, neither of the dated archive nor of the live one: their pinned SHA-256 cannot be chained to Canonical's signing key (to accept the pool and the pinned SHA-256 alone, set TC_ALLOW_UNSIGNED_KERNEL=1; SOURCE.txt then says unsigned)"
  echo "   NOTE: TC_ALLOW_UNSIGNED_KERNEL=1: the pool and the pinned SHA-256 alone; SOURCE.txt says unsigned"
fi
declare -A KSRC
for K in IMG MOD; do
  if [ $K = IMG ]; then FILE="$IMG"; WANT="$SHA_IMG"; KDIR="$DIR_IMG"; PKG="$IPKG"; VER="$IVER"; else FILE="$MOD"; WANT="$SHA_MOD"; KDIR="$DIR_MOD"; PKG="$MPKG"; VER="$MVER"; fi
  rm -f "$WORK/kernel/"*"$PKG"*.deb; SRC=""
  if [ -n "$KIDX" ] && ( cd "$WORK/kernel" && $SUDO $APT download "${KO[@]}" "$PKG=$VER" > /dev/null 2>&1 ); then
    GOT="$(ls "$WORK/kernel"/${PKG}_*.deb 2>/dev/null | head -1)"; if [ -n "$GOT" ]; then [ "$(basename "$GOT")" = "$FILE" ] || mv -f "$GOT" "$WORK/kernel/$FILE" 2>/dev/null; [ "$(sha256sum "$WORK/kernel/$FILE" | cut -c1-64)" = "$WANT" ] && SRC=apt; fi
  fi
  if [ -z "$SRC" ]; then rm -f "$WORK/kernel/$FILE"; ( cd "$WORK/kernel" && $CURL -fsSO "$KURL/$KDIR/$FILE" ) || fail "could not download $FILE"; SRC=pool; fi
  [ "$(sha256sum "$WORK/kernel/$FILE" | cut -c1-64)" = "$WANT" ] || fail "$FILE does not match the SHA-256 that tc-image-prep.sh pins ($WANT)"
  KSRC[$FILE]="$SRC"; echo "   $FILE: $SRC, matches the pinned SHA-256"
done
say "the result: $OUT"
mkdir -p "$OUT"
for f in "$WORK/archives"/*.deb; do [ -e "$f" ] || continue; B="$(basename "$f")"; P="$(echo "$B" | sed -E 's/_[0-9]+%3[aA]/_/')"; cp -f "$f" "$OUT/$P"; done   # apt keeps an epoch as %3a in the file name; the pool name has none
cp -f "$WORK/kernel/$IMG" "$WORK/kernel/$MOD" "$OUT/"; chmod 644 "$OUT"/*.deb
NPK="$(ls "$OUT"/*.deb | wc -l)"; [ "$NPK" -ge 3 ] || fail "only $NPK packages were captured"
(cd "$OUT" && LC_ALL=C sha256sum *.deb | LC_ALL=C sort -k2 > SHA256SUMS)
BYTES="$(cat "$OUT"/*.deb | wc -c)"; BIG="$(cd "$OUT" && ls -S *.deb | head -1)"; BIGB="$(stat -c %s "$OUT/$BIG")"
{ echo "# SOURCE.txt: where the files of this folder come from (written by tc-image-debs-capture.sh). The trust anchor from the commit on is SHA256SUMS."
  echo "snapshot_date: $TS"; echo "snapshot_url: $BASE/$TS"; echo "suites: jammy jammy-updates jammy-security (main restricted universe multiverse)"
  echo "captured_utc: $(date -u +%FT%TZ)"; echo "capture_tool: ops/image/build/tc-image-debs-capture.sh${TC_COMMIT:+ at commit $TC_COMMIT}"
  echo "base_image: ${TC_BASE_IMAGE:-unknown (the kit passes TC_BASE_IMAGE)}"
  echo "machine: $(sed -n 's/^PRETTY_NAME=//p' "$R/etc/os-release" | tr -d '"'), kernel $(uname -r), $(dpkg --print-architecture)"
  echo "keyring: $KEYRING sha256 $(sha256sum "$KEYRING" | cut -c1-64), ubuntu-keyring $(dpkg-query -W -f='${Version}' ubuntu-keyring 2>/dev/null || echo unknown)"
  for s in jammy jammy-updates jammy-security; do F="$(ls "$WORK/lists"/*_dists_${s}_InRelease | head -1)"; echo "inrelease_sha256_$s: $(sha256sum "$F" | cut -c1-64) signed_by $(printf '%s' "${SIGNED[$s]}")"; done
  for F in "$WORK/lists"/*_dists_*_Packages; do [ -e "$F" ] || continue; K="${F##*_dists_}"; echo "packages_sha256_${K%_Packages}: $(sha256sum "$F" | cut -c1-64)"; done
  if [ -n "$KIDX" ]; then echo "kernel_signature: signed: the SHA-256 pinned in tc-image-prep.sh equal those of the signed noble indexes of the $KIDX archive"; for s in noble noble-updates noble-security; do echo "kernel_inrelease_sha256_$s: ${KFPR[$s]} ($KIDX)"; done; else echo "kernel_signature: unsigned: the pool and the SHA-256 pinned in tc-image-prep.sh alone (TC_ALLOW_UNSIGNED_KERNEL=1)"; fi
  echo "kernel_$IMG: ${KSRC[$IMG]} sha256 $SHA_IMG"; echo "kernel_$MOD: ${KSRC[$MOD]} sha256 $SHA_MOD"
  echo "packages: $NPK, $BYTES bytes"
  for f in "$OUT"/*.deb; do echo "package: $(dpkg-deb -f "$f" Package)=$(dpkg-deb -f "$f" Version)"; done | LC_ALL=C sort
} > "$OUT/SOURCE.txt"
echo "CAPTURE-OK snapshot=$TS packages=$NPK size_mb=$((BYTES/1048576)) largest=$BIG:$((BIGB/1048576))MB kernel=${KSRC[$IMG]},${KSRC[$MOD]} kernel_index=${KIDX:-none} out=$OUT"
