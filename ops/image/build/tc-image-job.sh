#!/usr/bin/env bash
# Step F0.3b, the image build part 3: the job and the wrapper jar. On the builder, after tc-image-bake.sh: build the two libraries that the crawler needs at pinned commits, unpack a PINNED source tree
# (made in Cloud Shell by `git archive`), run `ant runtime` (the source tree already holds the teammate's receipt code since step R1, so there is no patch step), build the wrapper jar from the job's classes (deterministic, by ops/attested/wrapper-jar.sh), install the jar
# in Hadoop's library folder and the whole deploy folder (the job and the launcher scripts) in /opt/tc/nutch, both owned by root, add the deploy folder to the measured list (11 events), record every
# fingerprint in /etc/tc/job-versions.txt, and then REMOVE the build tools and caches: the image keeps only the artifacts. It starts nothing and does not reboot.
#   bash tc-image-job.sh KITDIR SRC_TGZ SRC_SHA256
# It replaces the rebuild stages `deps`, `build` and `jar` of ops/rebuild/node-wrapper.sh for the image (built once, from pinned inputs, not on each node).
# Hooks for the rehearsal only: TC_ROOT, TC_SUDO, TC_APT, TC_WORK, TC_FREE_KB. Settings: CC_COMMIT, CLD2_COMMIT.
set -uo pipefail
KIT="${1:?usage: $0 KITDIR SRC_TGZ SRC_SHA256}"; SRC_TGZ="${2:?}"; SRC_SHA="${3:?}"
R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"; WORK="${TC_WORK:-$HOME/build}"; JDKHOME=/usr/lib/jvm/java-11-openjdk-amd64
CC_REPO=https://github.com/crawler-commons/crawler-commons.git; CC_COMMIT="${CC_COMMIT:-13118882ddfe}"
CLD2_REPO=https://github.com/commoncrawl/language-detection-cld2.git; CLD2_COMMIT="${CLD2_COMMIT:-38efccdc1ec1}"
fail() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }
fp() { sha256sum "$1" | cut -d' ' -f1; }
HB=""; beat_on() { ( while sleep "${TC_BEAT:-30}"; do echo "   still working: $1"; done ) & HB=$!; }; beat_off() { [ -n "$HB" ] && { kill "$HB" 2>/dev/null; wait "$HB" 2>/dev/null; HB=""; }; return 0; }

say "pre-flight"
[ -x "$R/opt/hadoop/bin/hdfs" ] && [ -f "$R/etc/tc/measured-paths.txt" ] || fail "the software layer is not in place: run tc-image-bake.sh first"
FREE_KB="${TC_FREE_KB:-$(df --output=avail / | tail -1 | tr -d ' ')}"; [ "$FREE_KB" -gt 8000000 ] || fail "less than 8 GB free on /"
for f in ops/attested/wrapper-jar.sh ops/image/rootfs/etc/tc/measured-paths-f03b.txt; do [ -f "$KIT/$f" ] || fail "missing in $KIT: $f"; done
[ -f "$SRC_TGZ" ] || fail "the source archive is missing: $SRC_TGZ"
[[ "$SRC_SHA" =~ ^[0-9a-f]{64}$ ]] || fail "give the full 64-digit SHA-256 of the archive"
[ "$(fp "$SRC_TGZ")" = "$SRC_SHA" ] || fail "the source archive is not the pinned one (SHA-256 $(fp "$SRC_TGZ" | cut -c1-16)..., pinned ${SRC_SHA:0:16}...)"
echo "the source archive ${SRC_SHA:0:16}... is the pinned one; ${FREE_KB} KB free"

say "the build tools (they are removed again at the end) and the runtime library of the job"
$SUDO ${TC_APT:-apt-get} update -qq >/dev/null 2>&1 || echo "   note: apt-get update reported a problem; continuing"
$SUDO env DEBIAN_FRONTEND=noninteractive ${TC_APT:-apt-get} install -y --no-install-recommends ant maven git libcld2-0 >/dev/null 2>&1 || fail "apt-get install of the build tools failed"
for t in ant mvn git; do command -v "$t" >/dev/null || fail "the tool $t is missing after the install"; done
TOOLV="$(${TC_DPKGQ:-dpkg-query} -W -f='${Package} ${Version}\n' ant maven git libcld2-0 2>/dev/null | tr '\n' ';' || true)"; echo "tools: $TOOLV"

say "the two libraries of the crawler, at pinned commits"
rm -rf "$WORK"; mkdir -p "$WORK/logs" "$WORK/deps"
for spec in "crawler-commons|$CC_REPO|$CC_COMMIT" "language-detection-cld2|$CLD2_REPO|$CLD2_COMMIT"; do
  IFS='|' read -r name url commit <<< "$spec"
  git clone -q "$url" "$WORK/deps/$name" >"$WORK/logs/git-$name.log" 2>&1 || fail "could not clone $url"
  git -C "$WORK/deps/$name" checkout -q "$commit" >>"$WORK/logs/git-$name.log" 2>&1 || fail "$name has no commit $commit"
  head="$(git -C "$WORK/deps/$name" rev-parse HEAD)"; [[ "$head" == "$commit"* ]] || fail "$name is at $head, not at $commit"
  beat_on "building $name"; (cd "$WORK/deps/$name" && mvn -q -B install -DskipTests >"$WORK/logs/mvn-$name.log" 2>&1); mrc=$?; beat_off
  [ $mrc = 0 ] || { tail -8 "$WORK/logs/mvn-$name.log" >&2; fail "mvn install failed for $name"; }
  echo "$name at ${head:0:12} installed in ~/.m2"
done

say "the pinned source tree (with the teammate's receipt code)"
mkdir -p "$WORK/src"; tar xzf "$SRC_TGZ" -C "$WORK/src" || fail "could not unpack the source archive"
[ -f "$WORK/src/build.xml" ] || fail "no build.xml at the top of the unpacked source (was it made by git archive without a prefix?)"
for f in src/java/org/commoncrawl/util/CustodyReceipt.java src/java/org/commoncrawl/util/TcCanonical.java; do [ -f "$WORK/src/$f" ] || fail "the source tree has no receipt code ($f is missing): since step R1 the tree must hold the teammate's receipt code"; done
echo "the source tree holds the receipt code (CustodyReceipt.java and TcCanonical.java)"

say "ant runtime (the job)"
beat_on "ant runtime (about 7 minutes with a cold cache)"; (cd "$WORK/src" && ant runtime >"$WORK/logs/ant.log" 2>&1); beat_off
grep -q "BUILD SUCCESSFUL" "$WORK/logs/ant.log" || { tail -8 "$WORK/logs/ant.log" >&2; fail "ant runtime failed (log: $WORK/logs/ant.log)"; }
DEPLOY="$WORK/src/runtime/deploy"; JOB="$DEPLOY/apache-nutch-1.22.job"
[ -f "$JOB" ] && [ -f "$DEPLOY/bin/nutch" ] || fail "no job or no bin/nutch under $DEPLOY after the build"
JOBFACTS="$(python3 - "$JOB" <<'PYEOF'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); n = z.namelist()
w = [x for x in n if x.startswith("org/apache/nutch/attested/") and x.endswith(".class")]
p = [x for x in n if x == "org/commoncrawl/util/CustodyReceipt.class"]
print(len(n), len(w), len(p))
PYEOF
)" || fail "could not read the job file"
read -r NENT NWRAP NPATCHED <<< "$JOBFACTS"
[ "${NWRAP:-0}" -gt 0 ] || fail "the job holds no wrapper classes (org/apache/nutch/attested/)"
[ "${NPATCHED:-0}" -gt 0 ] || fail "the job lacks the receipt class org/commoncrawl/util/CustodyReceipt (is the receipt code in the source tree?)"
echo "job: $(fp "$JOB" | cut -c1-16)..., $(stat -c %s "$JOB") bytes, $NENT entries, $NWRAP wrapper classes, the receipt class CustodyReceipt is in it"

say "the wrapper jar, built from the job's own classes and installed in Hadoop's library folder"
HENV="JAVA_HOME=$JDKHOME HADOOP_HOME=$R/opt/hadoop"
env $HENV bash "$KIT/ops/attested/wrapper-jar.sh" build "$JOB" "$WORK/attested-hdfs.jar" >"$WORK/logs/jar-build.log" 2>&1 || { tail -6 "$WORK/logs/jar-build.log" >&2; fail "building the wrapper jar failed"; }
$SUDO env $HENV ATTESTED_FORCE=1 bash "$KIT/ops/attested/wrapper-jar.sh" install "$WORK/attested-hdfs.jar" "$JOB" >"$WORK/logs/jar-install.log" 2>&1 || { tail -6 "$WORK/logs/jar-install.log" >&2; fail "installing the wrapper jar failed"; }
JARLIB="$R/opt/hadoop/share/hadoop/common/lib/attested-hdfs.jar"; $SUDO chown root:root "$JARLIB"; $SUDO chmod 0644 "$JARLIB"
grep -q "on Hadoop's classpath: yes" "$WORK/logs/jar-install.log" || fail "the jar is not on Hadoop's classpath"
echo "attested-hdfs.jar $(fp "$JARLIB" | cut -c1-16)..., $NWRAP classes, on Hadoop's classpath"

say "the deploy folder (the job and the launcher scripts) in /opt/tc/nutch, owned by root"
$SUDO rm -rf "$R/opt/tc/nutch"; $SUDO install -d -m 0755 "$R/opt/tc" "$R/opt/tc/nutch"; $SUDO cp -a "$DEPLOY/." "$R/opt/tc/nutch/" || fail "could not copy the deploy folder"
$SUDO chown -R root:root "$R/opt/tc"; $SUDO chmod -R go-w "$R/opt/tc"
cmp -s "$JOB" "$R/opt/tc/nutch/apache-nutch-1.22.job" || fail "the installed job differs from the built one"; [ -f "$R/opt/tc/nutch/bin/nutch" ] || fail "no bin/nutch in /opt/tc/nutch"
echo "/opt/tc/nutch holds the job and bin/nutch"

say "the fingerprints, and the 11-event measured list"
{ echo "source: $(basename "$SRC_TGZ") sha256 $SRC_SHA"; 
  echo "job: apache-nutch-1.22.job sha256 $(fp "$JOB") bytes $(stat -c %s "$JOB") entries $NENT wrapper-classes $NWRAP";
  echo "jar: attested-hdfs.jar sha256 $(fp "$JARLIB") classes $NWRAP";
  echo "crawler-commons: $CC_COMMIT"; echo "language-detection-cld2: $CLD2_COMMIT"; echo "tools: $TOOLV"; } | $SUDO tee "$R/etc/tc/job-versions.txt" >/dev/null
$SUDO install -m 0644 "$KIT/ops/image/rootfs/etc/tc/measured-paths-f03b.txt" "$R/etc/tc/measured-paths.txt"
TC_ROOT="$R" TC_LIST="$R/etc/tc/measured-paths.txt" TC_LIB="$R/usr/local/lib/tc" "$R/usr/local/lib/tc/tc-measure.sh" --check-list || fail "the measured list does not match this machine"

say "remove the build tools and caches (the image keeps only the artifacts)"
$SUDO env DEBIAN_FRONTEND=noninteractive ${TC_APT:-apt-get} purge -y ant maven git patch >/dev/null 2>&1 || fail "could not remove the build tools"
$SUDO env DEBIAN_FRONTEND=noninteractive ${TC_APT:-apt-get} autoremove -y --purge >/dev/null 2>&1 || echo "   note: autoremove reported a problem; continuing"
rm -rf "$WORK" "$HOME/.m2" "$HOME/.ant" "$HOME/.ivy2"; $SUDO rm -rf "$R/root/.m2" "$R/root/.ant" "$R/root/.ivy2"
hash -r   # the shell remembers where it found a tool; forget that, or a removed tool would still be "found"
for t in ant mvn git patch; do ! command -v "$t" >/dev/null || fail "the tool $t is still installed after the removal"; done
echo "ant, maven, git and patch are gone; the build folder and the caches are removed; libcld2-0 stays (the job needs it at run time)"
echo
echo "READY (nothing was started, nothing was rebooted). Next: tc-image-clean.sh, then stop the builder and make the image."
