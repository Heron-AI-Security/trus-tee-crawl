#!/usr/bin/env bash
# Step F0.3a, the image build part 2: the software layer. JDK 11 and Hadoop 3.4.3 (checksum verified) in root-owned system folders, a service user `hadoop` that cannot log in,
# the plain configuration rendered from its property files, systemd units for the daemons ordered after the measurement, and the longer list of measured paths.
# Run on the builder VM AFTER tc-image-prep.sh (without --with-placeholder), as a user with sudo. It starts nothing and does not reboot.
#   bash tc-image-bake.sh REPO_DIR
# REPO_DIR holds ops/image/ and ops/rebuild/hadoop_conf.py. It replaces the rebuild stages `base` and `hadoop` for the image (nothing in a person's home, nothing started by hand).
# Settings: HADOOP_URL_BASE (the server of the tarball), HADOOP_SUM_BASE (the server of its checksum file: the primary Apache archive), HADOOP_MAX_MINUTES (40), HADOOP_ALLOW_SLOW=1.
# Hooks for the rehearsal only: TC_ROOT (a fake root), TC_SUDO, TC_APT, TC_ANALYZE, TC_CURL, TC_WORK, TC_FREE_KB, TC_SPEED_BPS, TC_RETRY_SLEEP, HADOOP_VERSION.
set -euo pipefail
REPO="${1:?usage: $0 REPO_DIR}"
R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"
HVER="${HADOOP_VERSION:-3.4.3}"; HBASE="${HADOOP_URL_BASE:-https://archive.apache.org/dist/hadoop/common/hadoop-$HVER}"; TAR="hadoop-$HVER.tar.gz"
WORK="${TC_WORK:-$HOME/bake}"; JDK="$R/usr/lib/jvm/java-11-openjdk-amd64"; IMGDIR="$REPO/ops/image/rootfs"
fail() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }

say "pre-flight"
for t in python3 curl sha512sum tar; do command -v "$t" >/dev/null || fail "the tool $t is missing"; done
[ -x "$R/usr/local/lib/tc/tc-measure.sh" ] || fail "the image preparation has not run (no tc-measure.sh): run tc-image-prep.sh first"
FREE_KB="${TC_FREE_KB:-$(df --output=avail / | tail -1 | tr -d ' ')}"
[ "$FREE_KB" -gt 6000000 ] || fail "less than 6 GB free on /"
for f in etc/tc/measured-paths-f03a.txt etc/tc/hadoop-props/core-site.props etc/tc/hadoop-props/hdfs-site.props etc/tc/hadoop-props/mapred-site.props etc/tc/hadoop-props/yarn-site.props usr/local/lib/tc/units/tc-hdfs-format.service usr/local/lib/tc/units/tc-namenode.service usr/local/lib/tc/units/tc-datanode.service usr/local/lib/tc/units/tc-resourcemanager.service usr/local/lib/tc/units/tc-nodemanager.service; do
  [ -f "$IMGDIR/$f" ] || fail "missing in $REPO: ops/image/rootfs/$f"
done
[ -f "$REPO/ops/rebuild/hadoop_conf.py" ] || fail "missing in $REPO: ops/rebuild/hadoop_conf.py"
echo "${FREE_KB} KB free; the preparation is in place"

say "packages (the JDK)"
$SUDO ${TC_APT:-apt-get} update -qq >/dev/null 2>&1 || echo "   note: apt-get update reported a problem; continuing"
$SUDO env DEBIAN_FRONTEND=noninteractive ${TC_APT:-apt-get} install -y --no-install-recommends openjdk-11-jdk-headless ca-certificates >/dev/null 2>&1 || fail "apt-get install of the JDK failed"
[ -d "$JDK" ] || fail "no JDK folder at $JDK after the install"
echo "JDK: $JDK"

say "the service user and the folders (data and logs are the only places that it can write)"
id hadoop >/dev/null 2>&1 || $SUDO useradd --system --home-dir /var/lib/hadoop --shell /usr/sbin/nologin --no-create-home --user-group hadoop
for d in /var/lib/hadoop /var/lib/hadoop/tmp /var/lib/hadoop/namenode /var/lib/hadoop/datanode /var/log/hadoop; do $SUDO mkdir -p "$R$d"; $SUDO chown hadoop:hadoop "$R$d"; $SUDO chmod 0750 "$R$d"; done
echo "user hadoop, shell nologin; data in /var/lib/hadoop, logs in /var/log/hadoop"

say "download and verify Hadoop $HVER"
mkdir -p "$WORK"; cd "$WORK"
SUMBASE="${HADOOP_SUM_BASE:-https://archive.apache.org/dist/hadoop/common/hadoop-$HVER}"   # the small checksum file always comes from the primary archive, whichever server the tarball comes from
${TC_CURL:-curl} -fsSL -o "$TAR.sha512" "$SUMBASE/$TAR.sha512" || fail "could not download the checksum file $SUMBASE/$TAR.sha512"
size="$(${TC_CURL:-curl} -sIL "$HBASE/$TAR" | grep -i '^content-length' | tail -1 | tr -dc 0-9 || true)"
[ -n "$size" ] && [ "$size" -gt 100 ] || fail "could not read the size of $HBASE/$TAR (is the address right?)"
have_size="$(stat -c %s "$TAR" 2>/dev/null || echo 0)"
if [ "$have_size" -ne "$size" ]; then
  # a speed check first (guide rule 35): 4 MB are measured, and a download that would take too long is refused
  bps="${TC_SPEED_BPS:-$(${TC_CURL:-curl} -sL -r 0-4194303 -o /dev/null -w '%{speed_download}' --max-time 30 "$HBASE/$TAR" | cut -d. -f1)}"; bps="${bps:-0}"; [ "$bps" -gt 0 ] || bps=1
  left=$(( size - have_size )); mins=$(( left / bps / 60 ))
  echo "the server gives about $(( bps / 1024 )) KB/s; $(( left / 1048576 )) MB are left: about $mins minutes"
  [ "$mins" -le "${HADOOP_MAX_MINUTES:-40}" ] || [ "${HADOOP_ALLOW_SLOW:-0}" = 1 ] || fail "this server is too slow ($mins minutes). Set HADOOP_URL_BASE to a faster mirror of the same folder (the checksum file still comes from $SUMBASE), or HADOOP_ALLOW_SLOW=1 to wait"
  ( while sleep 15; do echo "   downloaded $(( $(stat -c %s "$TAR" 2>/dev/null || echo 0) / 1048576 )) MB of $(( size / 1048576 )) MB"; done ) & MON=$!
  for try in 1 2 3 4 5 6; do ${TC_CURL:-curl} -fL -C - --connect-timeout 20 --retry 3 -o "$TAR" "$HBASE/$TAR" 2>/dev/null && break; sleep "${TC_RETRY_SLEEP:-5}"; done
  kill "$MON" 2>/dev/null || true; wait "$MON" 2>/dev/null || true
fi
got_size="$(stat -c %s "$TAR" 2>/dev/null || echo 0)"
[ "$got_size" -eq "$size" ] || fail "the download is incomplete after 6 tries ($got_size of $size bytes): run the bake again to resume it"
want="$(grep -o -E '[0-9a-fA-F]{128}' "$TAR.sha512" | head -1 | tr 'A-F' 'a-f' || true)"; have="$(sha512sum "$TAR" | cut -d' ' -f1)"   # '|| true': an empty result must reach the message below, not end the script silently
[ -n "$want" ] && [ "$want" = "$have" ] || fail "checksum mismatch for $TAR (want ${want:0:16}..., have ${have:0:16}...)"
echo "sha512 ${have:0:16}... equals the checksum file of $SUMBASE"

say "install Hadoop in /opt/hadoop (owned by root: the service user cannot change it)"
for u in tc-nodemanager tc-resourcemanager tc-datanode tc-namenode; do $SUDO systemctl stop "$u.service" >/dev/null 2>&1 || true; done   # a builder that has booted since an earlier bake ran the daemons: they must not run from a folder that is replaced
echo "any daemons of an earlier boot of this builder were stopped"
$SUDO rm -rf "$R/opt/hadoop"; $SUDO mkdir -p "$R/opt/hadoop"
$SUDO tar -xzf "$TAR" --strip-components=1 -C "$R/opt/hadoop" || fail "could not unpack $TAR"
$SUDO rm -rf "$R/opt/hadoop/share/doc"
$SUDO chown -R root:root "$R/opt/hadoop"; $SUDO chmod -R go-w "$R/opt/hadoop"
[ -x "$R/opt/hadoop/bin/hdfs" ] || fail "no bin/hdfs in the unpacked Hadoop"
cd - >/dev/null

say "the configuration: rendered from the property files, then checked against them"
$SUDO install -d -m 0755 "$R/etc/tc/hadoop-props" "$R/usr/local/lib/tc/units"
for f in core hdfs mapred yarn; do $SUDO install -m 0644 "$IMGDIR/etc/tc/hadoop-props/$f-site.props" "$R/etc/tc/hadoop-props/$f-site.props"; done
$SUDO install -m 0755 "$REPO/ops/rebuild/hadoop_conf.py" "$R/usr/local/lib/tc/hadoop_conf.py"
$SUDO python3 "$R/usr/local/lib/tc/hadoop_conf.py" render "$R/etc/tc/hadoop-props" "$R/opt/hadoop/etc/hadoop" /unused >/dev/null || fail "could not render the configuration"
$SUDO python3 "$R/usr/local/lib/tc/hadoop_conf.py" check "$R/etc/tc/hadoop-props" "$R/opt/hadoop/etc/hadoop" /unused >/dev/null || fail "the rendered configuration differs from its specification"
echo "core-site, hdfs-site, yarn-site and mapred-site equal their property files"

say "the CA fingerprints of the JDK (one of the measured items)"
FPR="$("$JDK/bin/keytool" -list -cacerts -storepass changeit 2>/dev/null | grep 'Certificate fingerprint' | sort || true)"
[ -n "$FPR" ] || fail "no CA fingerprints were listed"
printf '%s\n' "$FPR" | $SUDO tee "$R/etc/tc/java-ca-fingerprints.txt" >/dev/null
echo "$(wc -l < "$R/etc/tc/java-ca-fingerprints.txt") fingerprints"

say "the units (in the measured folder, then enabled), without the test-only stand-in"
if [ -e "$R/etc/systemd/system/tc-placeholder.service" ]; then $SUDO systemctl disable tc-placeholder.service >/dev/null 2>&1 || true; $SUDO rm -f "$R/etc/systemd/system/tc-placeholder.service"; echo "the stand-in unit was removed"; fi
for u in tc-hdfs-format tc-namenode tc-datanode tc-resourcemanager tc-nodemanager; do $SUDO install -m 0644 "$IMGDIR/usr/local/lib/tc/units/$u.service" "$R/usr/local/lib/tc/units/$u.service"; done
$SUDO systemctl daemon-reload
for u in tc-hdfs-format tc-namenode tc-datanode tc-resourcemanager tc-nodemanager; do $SUDO systemctl enable "$R/usr/local/lib/tc/units/$u.service" >/dev/null 2>&1 || fail "could not enable $u"; done
AOUT="$($SUDO ${TC_ANALYZE:-systemd-analyze} verify "$R"/usr/local/lib/tc/units/*.service 2>&1 || true)"
if printf '%s\n' "$AOUT" | grep -i 'unknown' | grep -q 'tc-[a-z-]*\.service'; then printf '%s\n' "$AOUT" | grep -i 'unknown' | grep 'tc-[a-z-]*\.service' | sed 's/^/   /'; fail "systemd does not understand part of a unit file (a key in the wrong section?)"; fi
echo "enabled: the format unit, the NameNode, the DataNode, the ResourceManager and the NodeManager; systemd reads them without an unknown key or section"

say "the role, the versions and the longer measured list"
echo single | $SUDO tee "$R/etc/tc/role" >/dev/null
{ echo "hadoop: $TAR sha512 $have"; ${TC_DPKGQ:-dpkg-query} -W -f='${Package} ${Version}\n' openjdk-11-jdk-headless ca-certificates 2>/dev/null || true; } | $SUDO tee "$R/etc/tc/bake-versions.txt" >/dev/null
$SUDO install -m 0644 "$IMGDIR/etc/tc/measured-paths-f03a.txt" "$R/etc/tc/measured-paths.txt"
TC_ROOT="$R" TC_LIST="$R/etc/tc/measured-paths.txt" TC_LIB="$R/usr/local/lib/tc" "$R/usr/local/lib/tc/tc-measure.sh" --check-list || fail "the measured list does not match this machine"
echo
echo "READY (nothing was started, nothing was rebooted). Next: tc-image-clean.sh, then stop the builder and make the image."
