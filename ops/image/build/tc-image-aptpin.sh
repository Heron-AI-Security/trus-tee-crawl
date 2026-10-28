#!/usr/bin/env bash
# Step R4.6 (28 October 2026): build from a DATED COPY of the Ubuntu archive (Canonical's snapshot service), so that every package that the build installs has the version of that day and a rebuild a month later gets the same versions.
# Run on a builder as a user with sudo, BEFORE tc-image-prep.sh (the preparation installs xxd and wireguard-tools, and wireguard-tools is the measured event wg).
#   bash tc-image-aptpin.sh REPO_DIR
# The date is the one line of ops/image/build/apt-snapshot.txt (YYYYMMDDTHHMMSSZ, UTC): a build input, like the name of the base image. To change it, change that line and build again.
# Hooks for the rehearsal only: TC_ROOT (a fake root), TC_SUDO, TC_APT (the apt-get command), TC_APTCACHE (the apt-cache command), TC_SNAPSHOT_URL.
set -euo pipefail
REPO="${1:?usage: $0 REPO_DIR}"; R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"; APT="${TC_APT:-apt-get}"; APTC="${TC_APTCACHE:-apt-cache}"; BASE="${TC_SNAPSHOT_URL:-https://snapshot.ubuntu.com/ubuntu}"
fail() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }
say "the date of the archive"
PIN="$REPO/ops/image/build/apt-snapshot.txt"; [ -f "$PIN" ] || fail "there is no $PIN: the build has no archive date"
TS="$(tr -d ' \r\n\t' < "$PIN")"
[[ "$TS" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || fail "the archive date '$TS' is not in the form YYYYMMDDTHHMMSSZ"
WHEN="${TS:0:4}-${TS:4:2}-${TS:6:2} ${TS:9:2}:${TS:11:2}:${TS:13:2}"
EP="$(date -u -d "$WHEN" +%s 2>/dev/null)" || fail "the archive date $TS is not a real date"
[ "$EP" -le "$(date -u +%s)" ] || fail "the archive date $TS is in the future: there is no archive of that day yet"
CODE="$(sed -n 's/^VERSION_CODENAME=//p' "$R/etc/os-release" 2>/dev/null | tr -d '"')"
[ "$CODE" = jammy ] || fail "this pin is for Ubuntu 22.04 (jammy), the machine says '${CODE:-nothing}'"
echo "   the archive of $WHEN UTC ($TS), for jammy"
say "the package sources: the dated copy only (the original file is kept once as sources.list.tc-orig)"
S="$R/etc/apt/sources.list"; [ -f "$S" ] || fail "there is no $S"
[ -e "$S.tc-orig" ] || $SUDO cp -a "$S" "$S.tc-orig"
TMP="$(mktemp)"; trap 'rm -f "$TMP"' EXIT
{ echo "# written by tc-image-aptpin.sh (step R4.6): the Ubuntu archive of $TS; the original is sources.list.tc-orig"
  for suite in jammy jammy-updates jammy-security; do echo "deb $BASE/$TS $suite main restricted universe multiverse"; done; } > "$TMP"
$SUDO install -m 644 "$TMP" "$S"
$SUDO mkdir -p "$R/etc/apt/apt.conf.d"; printf 'Acquire::Check-Valid-Until "false";\n' > "$TMP"; $SUDO install -m 644 "$TMP" "$R/etc/apt/apt.conf.d/99tc-snapshot"
OTHER="$(ls "$R"/etc/apt/sources.list.d/ 2>/dev/null | tr '\n' ' ')"; echo "   other source files (not changed, they carry no Ubuntu package that the build installs): ${OTHER:-none}"
say "apt reads the dated copy"
$SUDO $APT update -qq > /tmp/tc-aptpin.log 2>&1 || { tail -5 /tmp/tc-aptpin.log; fail "apt-get update failed on the dated copy of the archive (is snapshot.ubuntu.com reachable, and is $TS a date that it has?)"; }
POL="$($APTC policy openjdk-11-jdk-headless 2>&1 || true)"
echo "$POL" | grep -q "^  Candidate: [^(]" || fail "apt knows no openjdk-11-jdk-headless after the update"
echo "$POL" | grep -q "$BASE/$TS" || fail "the package lists do not come from the dated copy ($BASE/$TS)"
CAND="$(echo "$POL" | sed -n 's/^  Candidate: //p' | head -1)"
echo "APTPIN-OK snapshot=$TS openjdk-11-jdk-headless=$CAND"
