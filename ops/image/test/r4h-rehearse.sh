#!/usr/bin/env bash
# Rehearsal (no cloud, seconds) of the stage that makes the COMMITTED packages (ops/image/debs) the only apt source: tc-image-debs.sh.
# It uses REAL apt-get and dpkg-deb in a fake root with small fake packages, and it runs the stage with the NETWORK BLOCKED (unshare -n, with sudo -n when this is not root), after a control that proves the block works.   bash r4h-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$K/ops/image"; SC="$I/build/tc-image-debs.sh"; LIST="$I/build/apt-installs.txt"; W="$(mktemp -d)"; trap 'rm -rf "$W" 2>/dev/null || sudo -n rm -rf "$W" 2>/dev/null' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "  pass: $1"; P=$((P+1)); else echo "  FAIL: $1"; F=$((F+1)); fi; }
if ! command -v apt-get >/dev/null 2>&1 || ! command -v dpkg-deb >/dev/null 2>&1; then echo "  FAIL: this rehearsal needs apt-get and dpkg-deb (an Ubuntu or Debian machine)"; echo; echo "pass: 0   fail: 1"; echo "R4H-REHEARSAL-FAIL"; exit 1; fi
if [ "$(id -u)" = 0 ]; then NB=(unshare -n); else NB=(sudo -n unshare -n runuser -u "$(id -un)" --); fi; "${NB[@]}" true 2>/dev/null && CANBLOCK=1 || CANBLOCK=0   # not root: the blocked step still runs as THIS user (inside the namespace), so no file in the fake root becomes root-owned
mkdir -p "$W/bin" "$W/pk" "$W/master"
mkdeb() { local n="$1" v="${2:-1.0}" dep="${3:-}" rec="${4:-}" arch="${5:-amd64}"; local d="$W/pk/$n-$v"; rm -rf "$d"; mkdir -p "$d/DEBIAN"; { echo "Package: $n"; echo "Version: $v"; echo "Architecture: $arch"; echo "Maintainer: rehearsal <r@example.invalid>"; [ -n "$dep" ] && echo "Depends: $dep"; [ -n "$rec" ] && echo "Recommends: $rec"; echo "Description: fake $n for the rehearsal"; } > "$d/DEBIAN/control"; dpkg-deb --root-owner-group --build "$d" "${OUTDIR:-$W/master}/${n}_${v}_${arch}.deb" > /dev/null 2>&1; }
sums() { (cd "$1" && sha256sum *.deb > SHA256SUMS); }
# the set mimics the five install commands of apt-installs.txt with their dependency chains (wireguard-tools recommends a package, and the two commands with --no-install-recommends do not need it)
mkdeb xxd; mkdeb libwg-fake; mkdeb tc-resolvconf; mkdeb wireguard-tools 1.0 libwg-fake tc-resolvconf; mkdeb openjdk-11-jre-headless; mkdeb openjdk-11-jdk-headless 1.0 openjdk-11-jre-headless; mkdeb ca-certificates
mkdeb ant-lib; mkdeb ant 1.0 ant-lib; mkdeb maven-lib; mkdeb maven 1.0 maven-lib; mkdeb git; mkdeb libcld2-0; mkdeb libnftables-fake; mkdeb nftables 1.0 libnftables-fake
sums "$W/master"; printf 'snapshot_date: 20261027T000000Z\nsnapshot_url: https://snapshot.example.invalid/ubuntu/20261027T000000Z\n' > "$W/master/SOURCE.txt"; NPK="$(ls "$W/master"/*.deb | wc -l)"
fresh() { rm -rf "$W/d"; cp -a "$W/master" "$W/d"; }
mkroot() { local r="${1:-$W/r}"; rm -rf "$r"; mkdir -p "$r/etc/apt/sources.list.d" "$r/etc/apt/apt.conf.d" "$r/etc/apt/preferences.d" "$r/var/lib/apt/lists/partial" "$r/var/cache/apt/archives/partial" "$r/var/lib/dpkg"; : > "$r/var/lib/dpkg/status"
  printf 'VERSION_CODENAME=jammy\n' > "$r/etc/os-release"; printf 'deb http://us-central1.gce.archive.ubuntu.com/ubuntu/ jammy main restricted\n' > "$r/etc/apt/sources.list"; printf 'deb https://packages.cloud.google.com/apt cloud-sdk main\n' > "$r/etc/apt/sources.list.d/google-cloud-sdk.list"; printf 'Acquire::Check-Valid-Until "false";\n' > "$r/etc/apt/apt.conf.d/99tc-snapshot"; }
# real apt with explicit directories (not RootDir: apt would chroot there and look for its own method programs): the lists, the cache, the dpkg status and the sources are all in the fake root
wrap() { local r="$1" o; o="-o Dir::Etc::sourcelist=$r/etc/apt/sources.list -o Dir::Etc::sourceparts=$r/etc/apt/sources.list.d -o Dir::Etc::preferences=$r/etc/apt/preferences -o Dir::Etc::preferencesparts=$r/etc/apt/preferences.d -o Dir::State=$r/var/lib/apt -o Dir::State::lists=$r/var/lib/apt/lists -o Dir::State::status=$r/var/lib/dpkg/status -o Dir::Cache=$r/var/cache/apt -o Dir::Cache::pkgcache=pkgcache.bin -o Dir::Cache::srcpkgcache=srcpkgcache.bin -o Debug::NoLocking=1 -o APT::Sandbox::User=$(id -un)"
  printf '#!/bin/bash\nexec apt-get %s "$@"\n' "$o" > "$W/bin/apt-get$2"; printf '#!/bin/bash\nexec apt-cache %s "$@"\n' "$o" > "$W/bin/apt-cache$2"; chmod +x "$W/bin/"*; }
wrap "$W/r" ""
run() { OUT="$(TC_ROOT="$W/r" TC_SUDO="" TC_APT="$W/bin/apt-get" TC_APTCACHE="$W/bin/apt-cache" TC_DEBS_DIR="$W/d" bash "$SC" "$K" 2>&1)"; RC=$?; }
echo "== the install commands of the build: one place, and the stages still use them"
NC="$(grep -vcE '^\s*(#|$)' "$LIST")"; [ "$NC" = 5 ] && chk "apt-installs.txt holds the five install commands of the build" ok || chk "apt-installs.txt has $NC commands (expected 5)" no
i=0; BAD=""; while IFS= read -r L; do case "$L" in ''|'#'*) continue;; esac; i=$((i+1)); case $i in 1|2) S=prep;; 3) S=bake;; 4) S=job;; 5) S=lock;; esac; grep -qF "install -y $L" "$I/build/tc-image-$S.sh" || BAD="$BAD [$S: $L]"; done < "$LIST"
[ -z "$BAD" ] && chk "each line is still the install command of its stage (prep xxd and wireguard-tools, bake, job, lock): the stages did not change" ok || chk "a stage no longer installs exactly what apt-installs.txt says:$BAD" no
! grep -v '^ *#' "$SC" | grep -qE 'https?://' && chk "the stage names no network address (it needs no network)" ok || chk "the stage still names a network address" no
! grep -v '^ *#' "$SC" | grep -q '/tmp/' && chk "the stage keeps its logs in a private temporary folder, with no fixed file name in /tmp (a second run by another user, for example root, would be refused by the system)" ok || chk "the stage uses a fixed file name in /tmp" no
echo; echo "== the folder is kept byte for byte (the repository forces ops/** to text with LF, which corrupted compressed packages that contain the bytes 0D 0A)"
GA="$W/ga"; rm -rf "$GA"; mkdir -p "$GA"; if [ -f "$K/.gitattributes" ] && command -v git >/dev/null 2>&1; then git -C "$GA" init -q 2>/dev/null; cp "$K/.gitattributes" "$GA/"
  CA="$(git -C "$GA" check-attr text -- ops/image/debs/x_1.0_amd64.deb ops/image/debs/SHA256SUMS ops/image/debs/SOURCE.txt 2>/dev/null)"; [ "$(grep -c ': text: unset$' <<<"$CA")" = 3 ] && chk ".gitattributes switches the line-end conversion off for the whole folder (the packages, SHA256SUMS and SOURCE.txt: text is unset)" ok || chk ".gitattributes does not switch the conversion off for ops/image/debs: $(tr '\n' ' ' <<<"$CA" | cut -c1-160)" no
  mkdir -p "$GA/ops/image/debs"; python3 -c "
import random; random.seed(3); b = bytearray(random.randrange(256) for _ in range(20000)); b[500:502] = b'\r\n'; open('$GA/ops/image/debs/x_1.0_amd64.deb', 'wb').write(bytes(b))"; git -C "$GA" -c user.name=t -c user.email=t@x.invalid add -A >/dev/null 2>&1
  [ "$(git -C "$GA" rev-parse :ops/image/debs/x_1.0_amd64.deb 2>/dev/null)" = "$(git -C "$GA" hash-object --no-filters ops/image/debs/x_1.0_amd64.deb 2>/dev/null)" ] && chk "a package that contains the bytes 0D 0A is added to git byte for byte (the blob equals the file)" ok || chk "git changes the bytes of a package that contains 0D 0A: the commit would corrupt the packages" no
else chk "this rehearsal needs git and the .gitattributes of the repository in the tree (the kit archive must include it)" no; chk "(the byte for byte test did not run)" no; fi
echo; echo "== the happy path, with real apt in a fake root"
mkroot; fresh; cp "$W/r/etc/apt/sources.list" "$W/orig.list"; run
[ $RC = 0 ] && grep -q "^DEBS-OK snapshot=20261027T000000Z packages=$NPK sums=[0-9a-f]\{12\} openjdk-11-jdk-headless=1.0" <<<"$OUT" && chk "it ends with DEBS-OK, the snapshot date of the capture, the number of packages and the version apt would install" ok || chk "no DEBS-OK: $(tail -2 <<<"$OUT" | tr '\n' ' ')" no
[ "$(grep -vc '^#' "$W/r/etc/apt/sources.list")" = 1 ] && grep -qx "deb \[trusted=yes\] file:$W/d ./" "$W/r/etc/apt/sources.list" && ! grep -q 'http' <(grep -v '^#' "$W/r/etc/apt/sources.list") && chk "the sources are exactly one line, the committed folder, and no network source" ok || chk "the sources file is not the one local line" no
cmp -s "$W/r/etc/apt/sources.list.tc-orig" "$W/orig.list" && chk "the original sources are kept as sources.list.tc-orig" ok || chk "the original sources were not kept" no
[ -z "$(ls -A "$W/r/etc/apt/sources.list.d")" ] && [ -f "$W/r/etc/apt/sources.list.d.tc-orig/google-cloud-sdk.list" ] && chk "other source files (here the Google one) are put aside, so that apt never asks the network" ok || chk "another source file is still active" no
[ ! -e "$W/r/etc/apt/apt.conf.d/99tc-snapshot" ] && chk "the old Check-Valid-Until override of the snapshot is removed" ok || chk "99tc-snapshot is still there" no
python3 - "$W/d" <<'PYEOF' && chk "the index has one entry per file, with the Filename, Size and SHA256 of the committed list, and Packages.gz is the same text" ok || chk "the index is wrong" no
import gzip, hashlib, os, sys
d = sys.argv[1]; sums = dict(l.split()[::-1] for l in open(d + "/SHA256SUMS").read().splitlines())
txt = open(d + "/Packages").read(); assert gzip.open(d + "/Packages.gz", "rt").read() == txt
ent = [e for e in txt.split("\n\n") if e.strip()]; assert len(ent) == len(sums), (len(ent), len(sums))
for e in ent:
    f = dict(l.split(": ", 1) for l in e.splitlines() if ": " in l and not l.startswith(" "))
    n = f["Filename"][2:]; assert sums[n] == f["SHA256"] and int(f["Size"]) == os.path.getsize(d + "/" + n), n
PYEOF
(cd "$W/d" && ls -A | grep -vxE 'Packages|Packages.gz') | sort > "$W/a.txt"; (cd "$W/master" && ls -A) | sort > "$W/b.txt"; cmp -s "$W/a.txt" "$W/b.txt" && (cd "$W/d" && sha256sum -c SHA256SUMS >/dev/null 2>&1) && chk "the committed files are untouched: only Packages and Packages.gz were added" ok || chk "the committed folder changed" no
SIM="$("$W/bin/apt-get" install -s -y wireguard-tools 2>&1)"; grep -q "^Inst tc-resolvconf" <<<"$SIM" && SIM2="$("$W/bin/apt-get" install -s -y --no-install-recommends openjdk-11-jdk-headless ca-certificates 2>&1)" && ! grep -q "tc-resolvconf" <<<"$SIM2" && grep -q "^Inst openjdk-11-jre-headless" <<<"$SIM2" && chk "the flags matter and are kept: wireguard-tools brings its recommended package, the --no-install-recommends command brings only the dependencies" ok || chk "apt does not resolve the recommends as expected" no
echo; echo "== running it twice"
cp "$W/r/etc/apt/sources.list" "$W/once.list"; run
[ $RC = 0 ] && cmp -s "$W/r/etc/apt/sources.list" "$W/once.list" && cmp -s "$W/r/etc/apt/sources.list.tc-orig" "$W/orig.list" && [ "$(ls "$W/r/etc/apt/sources.list.d.tc-orig" | wc -l)" = 1 ] && chk "the second run gives the same sources, keeps the first original and puts nothing aside twice" ok || chk "the second run changed something" no
echo; echo "== with the network blocked"
if [ $CANBLOCK = 1 ]; then
  mkroot "$W/r2"; printf 'deb http://archive.example.invalid/ubuntu jammy main\n' > "$W/r2/etc/apt/sources.list"; wrap "$W/r2" "-ctl"
  "${NB[@]}" "$W/bin/apt-get-ctl" -o APT::Update::Error-Mode=any update -qq > /dev/null 2>&1; CR=$?
  [ $CR != 0 ] && chk "control: in the blocked network an apt-get update from a network source FAILS (so the block really blocks)" ok || chk "control: the network block does not block (an http update worked)" no
  mkroot; fresh; OUT="$("${NB[@]}" env TC_ROOT="$W/r" TC_SUDO="" TC_APT="$W/bin/apt-get" TC_APTCACHE="$W/bin/apt-cache" TC_DEBS_DIR="$W/d" bash "$SC" "$K" 2>&1)"; RC=$?
  [ $RC = 0 ] && grep -q '^DEBS-OK ' <<<"$OUT" && chk "the whole stage (index, sources, update, and every install command) passes with the network blocked" ok || chk "the stage needs the network: $(tail -2 <<<"$OUT" | tr '\n' ' ')" no
else chk "this machine cannot block the network (run as root, or with passwordless sudo): the no-network proof did not run" no; chk "(the stage under a blocked network did not run)" no; fi
echo; echo "== refusals (the committed folder must be exactly right; the sources file stays untouched when the folder is wrong)"
refuse() { mkroot; fresh; cp "$W/r/etc/apt/sources.list" "$W/b.list"; eval "$2"; run; if [ $RC != 0 ] && grep -q "$3" <<<"$OUT"; then if [ "${4:-keep}" = keep ] && ! cmp -s "$W/r/etc/apt/sources.list" "$W/b.list"; then chk "$1 (but the sources file was changed)" no; else chk "$1" ok; fi; else chk "$1 (rc=$RC: $(tail -1 <<<"$OUT" | cut -c1-110))" no; fi; }
refuse "refused: a machine that is not Ubuntu 22.04" 'printf "VERSION_CODENAME=noble\n" > "$W/r/etc/os-release"' "22.04"
refuse "refused: there is no committed folder" 'rm -rf "$W/d"' "no committed packages"
refuse "refused: there is no SHA256SUMS" 'rm -f "$W/d/SHA256SUMS"' "no SHA256SUMS"
refuse "refused: there is no SOURCE.txt (the provenance)" 'rm -f "$W/d/SOURCE.txt"' "no SOURCE.txt"
refuse "refused: SOURCE.txt has no snapshot date in the right form" 'printf "snapshot_date: 2026-10-27\n" > "$W/d/SOURCE.txt"' "snapshot_date"
refuse "refused: a line of SHA256SUMS that is not a hash and a name" 'echo garbage >> "$W/d/SHA256SUMS"' "not '<sha256>"
refuse "refused: one changed byte in one package, and the file is named" 'printf X | dd of="$W/d/git_1.0_amd64.deb" bs=1 seek=100 conv=notrunc 2>/dev/null' "git_1.0_amd64.deb: FAILED"
refuse "refused: a .deb in the folder that SHA256SUMS does not list" 'OUTDIR="$W/d" mkdeb evil' "not in SHA256SUMS"
refuse "refused: a package that SHA256SUMS lists and the folder lacks" 'rm -f "$W/d/xxd_1.0_amd64.deb"' "missing or is not a plain file"
refuse "refused: a file that does not belong in the folder" 'echo x > "$W/d/evil.sh"' "do not belong there"
refuse "refused: a symbolic link in place of a package" 'rm -f "$W/d/git_1.0_amd64.deb"; ln -s "$W/master/git_1.0_amd64.deb" "$W/d/git_1.0_amd64.deb"' "not a plain file"
refuse "refused: two versions of one package (a build installs one)" 'OUTDIR="$W/d" mkdeb xxd 2.0; sums "$W/d"' "twice"
refuse "refused: a package for another architecture" 'OUTDIR="$W/d" mkdeb foreign 1.0 "" "" i386; sums "$W/d"' "architecture 'i386'"
refuse "refused: a SHA256SUMS that names a file twice" 'head -1 "$W/d/SHA256SUMS" >> "$W/d/SHA256SUMS"' "twice"
refuse "refused: a machine without sources.list" 'rm -f "$W/r/etc/apt/sources.list"' "no .*sources.list" change
refuse "refused: the captured set does not resolve here (a dependency is missing, as after a base image that changed), and it says so" 'rm -f "$W/d/libnftables-fake_1.0_amd64.deb"; sums "$W/d"' "base image of this machine" change
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4H-REHEARSAL-PASS" || { echo "R4H-REHEARSAL-FAIL"; exit 1; }
