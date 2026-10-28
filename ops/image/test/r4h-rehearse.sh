#!/usr/bin/env bash
# Step R4.6 rehearsal (no cloud, seconds): the stage that points apt at a dated copy of the Ubuntu archive.   bash r4h-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$K/ops/image"; SC="$I/build/tc-image-aptpin.sh"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "  pass: $1"; P=$((P+1)); else echo "  FAIL: $1"; F=$((F+1)); fi; }
mkdir -p "$W/bin"
printf '#!/bin/bash\necho "$*" >> "%s/apt.log"\n[ -e "%s/apt_fails" ] && { echo "E: could not reach the archive" >&2; exit 100; }\nexit 0\n' "$W" "$W" > "$W/bin/apt-get"
printf '#!/bin/bash\ncat "%s/policy.txt"\n' "$W" > "$W/bin/apt-cache"; chmod +x "$W/bin/"*
policy() { printf 'openjdk-11-jdk-headless:\n  Installed: (none)\n  Candidate: 11.0.25+9-1ubuntu1~22.04\n  Version table:\n     11.0.25+9-1ubuntu1~22.04 500\n        500 %s jammy-updates/main amd64 Packages\n' "$1" > "$W/policy.txt"; }
mkroot() { rm -rf "$W/r" "$W/apt_fails"; mkdir -p "$W/r/etc/apt/sources.list.d" "$W/r/etc/apt/apt.conf.d"; printf 'VERSION_CODENAME=jammy\n' > "$W/r/etc/os-release"; printf 'deb http://us-central1.gce.archive.ubuntu.com/ubuntu/ jammy main restricted\n' > "$W/r/etc/apt/sources.list"; : > "$W/apt.log"; }
mkrepo() { rm -rf "$W/repo"; mkdir -p "$W/repo/ops/image/build"; [ -n "${1:-}" ] && printf '%s\n' "$1" > "$W/repo/ops/image/build/apt-snapshot.txt"; }
run() { OUT="$(TC_ROOT="$W/r" TC_SUDO="" TC_APT="$W/bin/apt-get" TC_APTCACHE="$W/bin/apt-cache" bash "$SC" "$W/repo" 2>&1)"; RC=$?; }
TS=20261027T000000Z; U=https://snapshot.ubuntu.com/ubuntu
echo "== the pin file of the repository"
python3 - "$I/build/apt-snapshot.txt" <<'PYEOF' && chk "the real pin file holds one date in the form YYYYMMDDTHHMMSSZ that is a real date and not in the future" ok || chk "the real pin file is not a valid date" no
import re, sys, datetime
t = open(sys.argv[1]).read().strip(); assert re.fullmatch(r"\d{8}T\d{6}Z", t), t
d = datetime.datetime.strptime(t, "%Y%m%dT%H%M%SZ"); assert d <= datetime.datetime.utcnow(), "future"
PYEOF
grep -q "https://snapshot.ubuntu.com/ubuntu}" "$SC" && chk "the default source of the dated copy is Canonical's snapshot service" ok || chk "the default URL is not the snapshot service" no
echo; echo "== the happy path"
mkroot; mkrepo $TS; policy "$U/$TS"; cp "$W/r/etc/apt/sources.list" "$W/orig.list"; run
[ $RC = 0 ] && grep -q "^APTPIN-OK snapshot=$TS openjdk-11-jdk-headless=11.0.25" <<<"$OUT" && chk "it ends with APTPIN-OK, the date and the version that apt would install" ok || chk "no APTPIN-OK: $(tail -2 <<<"$OUT" | tr '\n' ' ')" no
SUITES=1; for s in jammy jammy-updates jammy-security; do grep -q "^deb $U/$TS $s main restricted universe multiverse$" "$W/r/etc/apt/sources.list" || SUITES=0; done
[ "$(grep -c '^deb ' "$W/r/etc/apt/sources.list")" = 3 ] && [ $SUITES = 1 ] && ! grep -q "archive.ubuntu.com" <(grep '^deb ' "$W/r/etc/apt/sources.list") && chk "the sources are exactly the three suites of the dated copy, and no live archive line is left" ok || chk "the sources file is wrong: $(grep '^deb' "$W/r/etc/apt/sources.list" | head -4 | tr '\n' '|')" no
cmp -s "$W/r/etc/apt/sources.list.tc-orig" "$W/orig.list" && chk "the original sources are kept as sources.list.tc-orig" ok || chk "the original sources were not kept" no
grep -q 'Check-Valid-Until "false"' "$W/r/etc/apt/apt.conf.d/99tc-snapshot" && grep -q '^update' "$W/apt.log" && chk "apt is told not to expire the dated copy, and apt-get update was run after the change" ok || chk "no apt config or no update" no
echo; echo "== running it twice changes nothing, and does not overwrite the kept original"
cp "$W/r/etc/apt/sources.list" "$W/once.list"; run
[ $RC = 0 ] && cmp -s "$W/r/etc/apt/sources.list" "$W/once.list" && cmp -s "$W/r/etc/apt/sources.list.tc-orig" "$W/orig.list" && chk "the second run gives the same sources and keeps the first original" ok || chk "the second run changed something" no
echo; echo "== refusals (the sources file must be untouched when the date is bad)"
refuse() { # label setup pattern
  mkroot; mkrepo $TS; policy "$U/$TS"; cp "$W/r/etc/apt/sources.list" "$W/b.list"; eval "$2"; run
  [ $RC != 0 ] && grep -q "$3" <<<"$OUT" && chk "$1" ok || chk "$1 (rc=$RC: $(tail -1 <<<"$OUT" | cut -c1-90))" no; }
mkroot; rm -rf "$W/repo"; mkdir -p "$W/repo/ops/image/build"; policy "$U/$TS"; run; [ $RC != 0 ] && grep -q "no archive date" <<<"$OUT" && chk "refused: there is no pin file" ok || chk "no pin file not refused" no
refuse "refused: a date in the wrong form (2026-10-27)" 'mkrepo 2026-10-27' "not in the form"
refuse "refused: a date that does not exist (20261340T000000Z)" 'mkrepo 20261340T000000Z' "not a real date"
refuse "refused: a date in the future (20991231T000000Z)" 'mkrepo 20991231T000000Z' "in the future"
refuse "refused: a machine that is not Ubuntu 22.04" 'printf "VERSION_CODENAME=noble\n" > "$W/r/etc/os-release"' "22.04"
refuse "refused: there is no sources file" 'rm -f "$W/r/etc/apt/sources.list"' "no .*sources.list"
refuse "refused: apt-get update fails on the dated copy, and says why" ': > "$W/apt_fails"' "update failed"
refuse "refused: the package lists do not come from the dated copy" 'policy "http://us-central1.gce.archive.ubuntu.com/ubuntu"' "do not come from the dated copy"
refuse "refused: apt knows no JDK after the update" 'printf "openjdk-11-jdk-headless:\n  Installed: (none)\n  Candidate: (none)\n" > "$W/policy.txt"' "knows no openjdk"
for t in "bad date: the sources are untouched" ; do mkroot; mkrepo 2026-10-27; policy "$U/$TS"; cp "$W/r/etc/apt/sources.list" "$W/b.list"; run; cmp -s "$W/r/etc/apt/sources.list" "$W/b.list" && [ ! -e "$W/r/etc/apt/sources.list.tc-orig" ] && chk "$t" ok || chk "$t" no; done
echo; echo "== the driver and the kit"
python3 - "$I/test/f03-drive.sh" <<'PYEOF' && chk "the driver has the stage aptpin, and it comes before the preparation (prep installs wireguard-tools, the measured event wg)" ok || chk "the stage aptpin is missing or after prep" no
import sys; s = open(sys.argv[1]).read(); a = s.index("    aptpin)\n"); p = s.index("    prep)\n"); assert a < p and "tc-image-aptpin.sh" in s[a:p]
PYEOF
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4H-REHEARSAL-PASS" || { echo "R4H-REHEARSAL-FAIL"; exit 1; }
