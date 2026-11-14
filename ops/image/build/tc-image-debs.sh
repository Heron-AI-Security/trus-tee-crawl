#!/usr/bin/env bash
# Build from the Ubuntu packages that are COMMITTED in this repository (ops/image/debs), not from a snapshot service: the apt stages need no network, and two builds of one commit install byte-identical packages.
# Run on a builder as a user with sudo, BEFORE tc-image-prep.sh (the preparation installs xxd and wireguard-tools, and wireguard-tools is the measured event wg).
#   bash tc-image-debs.sh REPO_DIR
# The trust anchor is SHA256SUMS in ops/image/debs (committed with the files); SOURCE.txt records where the capture came from. To refresh the folder: change ops/image/build/apt-snapshot.txt, run tc-image-debs-capture.sh on a builder, commit the result.
# What it does: 1. checks the folder (only the files that belong there, every file against SHA256SUMS, one version of each package, only amd64 and all);  2. writes the index (Packages, Packages.gz: generated here, never committed);
#   3. makes the committed folder the ONLY package source (the original sources.list is kept once as sources.list.tc-orig, other source files are put aside once in sources.list.d.tc-orig, the old Check-Valid-Until override is removed);
#   4. runs apt-get update (no network is needed) and simulates every install command of apt-installs.txt: a captured set resolves only against the base image that it was captured on, and this is where a base image that changed shows.
# Hooks for the rehearsal only: TC_ROOT (a fake root), TC_SUDO, TC_APT (the apt-get command), TC_APTCACHE (the apt-cache command), TC_DEBS_DIR.
set -euo pipefail
REPO="${1:?usage: $0 REPO_DIR}"; R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"; APT="${TC_APT:-apt-get}"; APTC="${TC_APTCACHE:-apt-cache}"
DEBS="${TC_DEBS_DIR:-$REPO/ops/image/debs}"; LIST="$REPO/ops/image/build/apt-installs.txt"
fail() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }
LOGD="$(mktemp -d)"; INDEX=""; TMP=""; trap 'rm -rf "$LOGD"; [ -z "$INDEX" ] || rm -f "$INDEX"; [ -z "$TMP" ] || rm -f "$TMP"' EXIT   # private logs: fixed names in /tmp would block a second run by another user (a normal user and root)
CODE="$(sed -n 's/^VERSION_CODENAME=//p' "$R/etc/os-release" 2>/dev/null | tr -d '"')"
[ "$CODE" = jammy ] || fail "this stage is for Ubuntu 22.04 (jammy), the machine says '${CODE:-nothing}'"
command -v dpkg-deb >/dev/null 2>&1 || fail "dpkg-deb is missing (it is part of dpkg, which every Ubuntu machine has)"
say "the committed packages ($DEBS)"
[ -d "$DEBS" ] || fail "there is no $DEBS: the build has no committed packages"
DEBS="$(cd "$DEBS" && pwd)"
[ -f "$DEBS/SHA256SUMS" ] || fail "there is no SHA256SUMS in $DEBS"
[ -f "$DEBS/SOURCE.txt" ] || fail "there is no SOURCE.txt in $DEBS (it records where the files come from)"
SNAP="$(sed -n 's/^snapshot_date: *//p' "$DEBS/SOURCE.txt" | head -1 | tr -d ' \r')"
[[ "$SNAP" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || fail "SOURCE.txt has no line 'snapshot_date: YYYYMMDDTHHMMSSZ'"
BADLINES="$(grep -vcE '^[0-9a-f]{64}  [A-Za-z0-9][A-Za-z0-9._+~-]*\.deb$' "$DEBS/SHA256SUMS" || true)"
[ "$BADLINES" = 0 ] || fail "SHA256SUMS has $BADLINES line(s) that are not '<sha256>  <name>.deb'"
LISTED="$(awk '{print $2}' "$DEBS/SHA256SUMS" | sort)"; [ -n "$LISTED" ] || fail "SHA256SUMS is empty"
[ -z "$(echo "$LISTED" | uniq -d)" ] || fail "SHA256SUMS names a file twice: $(echo "$LISTED" | uniq -d | tr '\n' ' ')"
OTHER="$(cd "$DEBS" && ls -A | { grep -vxE 'SHA256SUMS|SOURCE.txt|Packages|Packages.gz|.*\.deb' || true; } | tr '\n' ' ')"
[ -z "$OTHER" ] || fail "the folder holds files that do not belong there: $OTHER"
for n in $LISTED; do [ -f "$DEBS/$n" ] && [ ! -L "$DEBS/$n" ] || fail "$n of SHA256SUMS is missing or is not a plain file"; done
EXTRA="$(cd "$DEBS" && ls -A | { grep '\.deb$' || true; } | sort | comm -13 <(echo "$LISTED") - | tr '\n' ' ')"
[ -z "$EXTRA" ] || fail "these .deb files are not in SHA256SUMS: $EXTRA"
(cd "$DEBS" && sha256sum --strict -c SHA256SUMS > $LOGD/sums.log 2>&1) || { grep -v ': OK$' $LOGD/sums.log | head -5; fail "a file does not match SHA256SUMS (the committed hash is the trust anchor)"; }
N=0; BYTES=0; SEEN=""; INDEX="$(mktemp)"; TMP="$(mktemp)"
while read -r HASH NAME; do
  F="$DEBS/$NAME"; META="$(dpkg-deb -f "$F" Package Version Architecture 2>/dev/null)" || fail "$NAME is not a Debian package"
  P="$(sed -n 's/^Package: //p' <<<"$META")"; A="$(sed -n 's/^Architecture: //p' <<<"$META")"
  case "$A" in amd64|all) ;; *) fail "$NAME has the architecture '$A' (only amd64 and all)";; esac
  case " $SEEN " in *" $P "*) fail "the package $P is in the folder twice (two versions): a build installs one";; esac; SEEN="$SEEN $P"
  dpkg-deb -f "$F" >> "$INDEX"; SZ="$(stat -c %s "$F")"; printf 'Filename: ./%s\nSize: %s\nSHA256: %s\n\n' "$NAME" "$SZ" "$HASH" >> "$INDEX"; N=$((N+1)); BYTES=$((BYTES+SZ))
done < <(sort -k2 "$DEBS/SHA256SUMS")
install -m 644 "$INDEX" "$DEBS/Packages"; gzip -9nc "$INDEX" > "$TMP"; install -m 644 "$TMP" "$DEBS/Packages.gz"
echo "   $N packages, $((BYTES/1048576)) MB, every file matches SHA256SUMS; the capture is of the archive of $SNAP"
say "the package sources: the committed folder only (the original file is kept once as sources.list.tc-orig)"
S="$R/etc/apt/sources.list"; [ -f "$S" ] || fail "there is no $S"
[ -e "$S.tc-orig" ] || $SUDO cp -a "$S" "$S.tc-orig"
SD="$R/etc/apt/sources.list.d"
if [ -d "$SD" ] && [ -n "$(ls -A "$SD" 2>/dev/null)" ]; then $SUDO mkdir -p "$SD.tc-orig"; for f in "$SD"/*; do $SUDO mv -n "$f" "$SD.tc-orig/"; done; echo "   other source files put aside in $(basename "$SD").tc-orig, so that apt never asks the network"; fi
{ echo "# written by tc-image-debs.sh: the packages committed in ops/image/debs (captured from the Ubuntu archive of $SNAP); the original is sources.list.tc-orig"; echo "deb [trusted=yes] file:$DEBS ./"; } > "$TMP"
$SUDO install -m 644 "$TMP" "$S"
$SUDO rm -f "$R/etc/apt/apt.conf.d/99tc-snapshot"
say "apt reads the committed packages (no network is needed)"
$SUDO $APT update -qq > $LOGD/update.log 2>&1 || { tail -5 $LOGD/update.log; fail "apt-get update failed on the committed packages"; }
POL="$($APTC policy openjdk-11-jdk-headless 2>&1 || true)"
echo "$POL" | grep -q "^  Candidate: [^(]" || fail "apt knows no openjdk-11-jdk-headless after the update"
echo "$POL" | grep -q "file:$DEBS" || fail "the package lists do not come from the committed folder (file:$DEBS)"
CAND="$(echo "$POL" | sed -n 's/^  Candidate: //p' | head -1)"
say "every install command of the build resolves from the committed packages on this machine"
while IFS= read -r LINE; do
  case "$LINE" in ''|'#'*) continue;; esac
  $SUDO env DEBIAN_FRONTEND=noninteractive $APT install -s -y $LINE > $LOGD/sim.log 2>&1 || { tail -6 $LOGD/sim.log; fail "'apt-get install $LINE' does not resolve from the committed packages: the base image of this machine is not the one that they were captured on, or the capture is incomplete (capture again on this base image)"; }
  echo "   ok: install $LINE"
done < "$LIST"
echo "DEBS-OK snapshot=$SNAP packages=$N sums=$(sha256sum "$DEBS/SHA256SUMS" | cut -c1-12) openjdk-11-jdk-headless=$CAND"
