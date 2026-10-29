#!/usr/bin/env bash
# Rehearsal of step F0.3b with stand-ins: the REAL tc-image-job.sh, f03b-check.sh, wrapper-jar.sh, tc-measure.sh and tc-image-clean.sh, against a fake root, a pinned source archive made here,
# and fake apt-get, git, mvn, ant (which writes a job file), hadoop, hdfs and nutch. The source archive already holds the receipt code. Every check that matters is also made to FAIL on purpose.
#   bash f03b-rehearse.sh KITDIR      KITDIR holds ops/image, attest, ops/rebuild/hadoop_conf.py and ops/attested/wrapper-jar.sh
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; PASS=0; FAILN=0; REALPATCH="$(command -v patch)"
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; echo "${out:-}" | grep -v "^      " | tail -6 | sed "s/^/        | /"; fi; }
W="$(mktemp -d)"; STUB="$W/bin"; SS="$W/stubsrc"; RB="$W/realbin"; SD="$W/sd"; mkdir -p "$STUB" "$SS" "$RB" "$SD" "$W/home"
for c in flock gzip gunzip zcat bash sh python3 sha256sum stat cmp tar install cp rm mkdir tee cat grep sed awk tr cut head tail ls wc date sleep env chmod touch mktemp find basename dirname kill wait dd id seq timeout sort uniq xargs readlink df mv ln cmp diff; do p="$(command -v $c 2>/dev/null)" && ln -sf "$p" "$RB/$c"; done
export PATH="$STUB:$RB" HOME="$W/home" FAKE_SD="$SD"
# ---------------------------------------------------------------- stand-ins (the build tools exist only after the fake apt-get has "installed" them, and vanish when it "purges" them)
cat > "$SS/git" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; echo "git $*" >> "$SD/git.log"
if [ "$1" = clone ]; then [ -f "$SD/git_clone_fails" ] && exit 128; mkdir -p "$4/.git"; echo "$3" > "$4/.git/url"; exit 0; fi
if [ "$1" = -C ]; then d="$2"; case "$3" in checkout) echo "$5" > "$d/.git/commit" ;; rev-parse) c="$(cat "$d/.git/commit")"; [ -f "$SD/git_wrong_head" ] && c="ffffffffff"; printf '%s%s\n' "$c" "0000000000000000000000000000000000000000" | cut -c1-40 ;; esac; fi
exit 0
EOS
cat > "$SS/mvn" <<'EOS'
#!/usr/bin/env bash
[ -f "${FAKE_SD:?}/mvn_fails" ] && { echo "[ERROR] stand-in failure"; exit 1; }
mkdir -p "$HOME/.m2/repository"; touch "$HOME/.m2/repository/$(basename "$PWD")"
if [ "$(basename "$PWD")" = crawler-commons ] && [ ! -f "${FAKE_SD:?}/mvn_nojar" ]; then J="$HOME/.m2/repository/com/github/crawler-commons/crawler-commons/1.7-SNAPSHOT"; mkdir -p "$J"; python3 -c "import zipfile,sys; z=zipfile.ZipFile(sys.argv[1],'w',zipfile.ZIP_DEFLATED); z.writestr('META-INF/MANIFEST.MF','Manifest-Version: 1.0\n'); z.writestr('effective_tld_names.dat','// a list downloaded while the library is built\ncom\n'); z.writestr('a/B.class','x'*50); z.close()" "$J/crawler-commons-1.7-SNAPSHOT.jar"; fi
EOS
cat > "$SS/ant" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; [ -f "$SD/ant_fails" ] && { echo "BUILD FAILED"; exit 1; }; [ -f "$SD/ant_deletes_work" ] && { rm -rf "$(dirname "$PWD")"; exit 0; }
[ -f "$SD/slow" ] && sleep 3
mkdir -p runtime/deploy/bin; printf '#!/bin/sh\necho nutch launcher\n' > runtime/deploy/bin/nutch; printf '#!/bin/sh\necho crawl launcher\n' > runtime/deploy/bin/crawl; chmod +x runtime/deploy/bin/*
CUSTODY=0; [ -f src/java/org/commoncrawl/util/CustodyReceipt.java ] && CUSTODY=1
SD="$SD" CUSTODY="$CUSTODY" python3 - <<'PYEOF'
import os, zipfile
z = zipfile.ZipFile("runtime/deploy/apache-nutch-1.22.job", "w", zipfile.ZIP_DEFLATED)
z.writestr("nutch-site.xml", "<configuration/>")
if not os.path.exists(os.environ["SD"] + "/job_no_wrapper"):
    z.writestr("org/apache/nutch/attested/AttestedHdfs.class", b"stand-in class one"); z.writestr("org/apache/nutch/attested/AttestedHdfsFileSystem.class", b"stand-in class two")
if os.environ["CUSTODY"] == "1": z.writestr("org/commoncrawl/util/CustodyReceipt.class", b"custody")
z.close()
PYEOF
echo "BUILD SUCCESSFUL"
EOS
printf '#!/usr/bin/env bash\nexec %s "$@"\n' "$REALPATCH" > "$SS/patch"
cat > "$STUB/apt-get" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; echo "$*" >> "$SD/apt.log"; SS="$(dirname "$0")/../stubsrc"; B="$(dirname "$0")"
case "$1" in
  install) [ -f "$SD/apt_install_fails" ] && exit 1; for t in git mvn ant patch; do cp "$SS/$t" "$B/$t"; chmod +x "$B/$t"; done ;;
  purge) [ -f "$SD/apt_purge_fails" ] && exit 1; [ -f "$SD/purge_keeps" ] || rm -f "$B/git" "$B/mvn" "$B/ant" "$B/patch" ;;
esac
exit 0
EOS
printf '#!/usr/bin/env bash\nprintf "ant 1.10.12-1;maven 3.6.3-5;git 1:2.34.1-1ubuntu1.99;patch 2.7.6-7;libcld2-0 0.0~git20150806-4build1\\n" | tr ";" "\\n"\n' > "$STUB/dpkg-query"
printf '#!/usr/bin/env bash\necho "chown $*" >> "${FAKE_SD:?}/chown.log"\n' > "$STUB/chown"
printf '#!/usr/bin/env bash\necho "$*" >> "${FAKE_SD:?}/runuser.log"\nshift 3; exec "$@"\n' > "$STUB/runuser"
chmod +x "$STUB"/*
# ---------------------------------------------------------------- the pinned inputs: a tiny source tree that holds the receipt code, and variants
SRC="$W/srcgen"; mkdir -p "$SRC/a/src/java/org/apache/nutch" "$SRC/a/conf"; printf 'line1\nline2\nline3\n' > "$SRC/a/src/java/org/apache/nutch/Foo.java"; echo "<project/>" > "$SRC/a/build.xml"; echo "<configuration/>" > "$SRC/a/conf/nutch-site.xml"
cp -r "$SRC/a" "$SRC/b"; sed -i 's/line2/line2-changed/' "$SRC/b/src/java/org/apache/nutch/Foo.java"; mkdir -p "$SRC/b/src/java/org/commoncrawl/util"; printf 'class CustodyReceipt {}\n' > "$SRC/b/src/java/org/commoncrawl/util/CustodyReceipt.java"
printf 'class TcCanonical {}\n' > "$SRC/b/src/java/org/commoncrawl/util/TcCanonical.java"
(cd "$SRC/b" && tar czf "$W/src.tgz" .); (cd "$SRC/a" && tar czf "$W/nocustody.tgz" .)   # b holds the receipt code; a (a tree without it) is the variant that must be refused
mkdir -p "$SRC/nb" && cp "$SRC/a/conf/nutch-site.xml" "$SRC/nb/" && (cd "$SRC/nb" && tar czf "$W/nobuildxml.tgz" .)
SSHA="$(sha256sum "$W/src.tgz" | cut -c1-64)"
# ---------------------------------------------------------------- the fake builder, after the F0.3a bake
mkroot() { hash -r; rm -rf "$W/fr" "$SD" "$W/work" "$W/home/.m2" "$W/home/.ant" "$W/home/.ivy2"; mkdir -p "$SD"; rm -f "$STUB/git" "$STUB/mvn" "$STUB/ant" "$STUB/patch"; FR="$W/fr"
  for d in usr/local/lib/tc etc/tc etc/systemd/system usr/bin usr/lib/jvm/java-11-openjdk-amd64 etc/java-11-openjdk opt/hadoop/bin opt/hadoop/etc/hadoop opt/hadoop/share/hadoop/common/lib opt/hadoop/share/hadoop/mapreduce root; do mkdir -p "$FR/$d"; done
  cp "$I"/rootfs/usr/local/lib/tc/*.sh "$FR/usr/local/lib/tc/"; cp "$KIT/attest/measure/treehash.sh" "$KIT/attest/measure/rtmr3_replay.py" "$FR/usr/local/lib/tc/"; chmod +x "$FR"/usr/local/lib/tc/*
  cp "$I/rootfs/etc/tc/measured-paths-f03a.txt" "$FR/etc/tc/measured-paths.txt"; cp "$I/rootfs/etc/systemd/system/tc-measure.service" "$FR/etc/systemd/system/"; echo openssl > "$FR/usr/bin/openssl"; echo wg > "$FR/usr/bin/wg"
  echo jdk > "$FR/usr/lib/jvm/java-11-openjdk-amd64/release"; echo jvm > "$FR/etc/java-11-openjdk/jvm.cfg"; echo "fingerprint" > "$FR/etc/tc/java-ca-fingerprints.txt"; echo conf > "$FR/opt/hadoop/etc/hadoop/core-site.xml"
  printf '#!/bin/sh\necho hdfs\n' > "$FR/opt/hadoop/bin/hdfs"; python3 -c 'import zipfile; zipfile.ZipFile("'"$FR"'/opt/hadoop/share/hadoop/mapreduce/hadoop-mapreduce-examples-3.4.3.jar","w").writestr("x","y")'
  cat > "$FR/opt/hadoop/bin/hadoop" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; H="$(cd "$(dirname "$0")/.." && pwd)"
case "$1" in
  classpath) printf '%s/etc/hadoop:%s/share/hadoop/common/lib/guava.jar' "$H" "$H"; [ -f "$H/share/hadoop/common/lib/attested-hdfs.jar" ] && printf ':%s/share/hadoop/common/lib/attested-hdfs.jar' "$H"; echo ;;
  jar) [ -f "$SD/pi_fails" ] && { echo "stand-in failure"; exit 1; }; echo "Estimated value of Pi is 3.80000000000000000000" ;;
esac
EOS
  chmod +x "$FR"/opt/hadoop/bin/*; }
job() { out="$(env TC_ROOT="$FR" TC_SUDO="" TC_WORK="$W/work" TC_FREE_KB="${JFREE:-12000000}" TC_BEAT=1 bash "$I/build/tc-image-job.sh" "${JKIT:-$KIT}" "${JSRC:-$W/src.tgz}" "${JSSHA:-$SSHA}" 2>&1)"; rc=$?; }
echo "=== A. the job script against a fake builder"
mkroot; job; echo "$out" | tail -2 | cut -c1-110
chk "happy path: exit 0 and READY" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
chk "the pinned archive was checked, and the source tree holds the receipt code (no patch step)" $(grep -q 'is the pinned one' <<<"$out" && grep -q 'the source tree holds the receipt code' <<<"$out" && ! grep -q 'patch applied\|pinned patch' <<<"$out"; echo $?)
chk "the two libraries were built at their pinned commits" $(grep -q 'crawler-commons at 13118882ddfe installed' <<<"$out" && grep -q 'language-detection-cld2 at 38efccdc1ec1 installed' <<<"$out"; echo $?)
chk "the Public Suffix List is pinned in the library jar (the helper ran) and the versions file records its hash from the pin" $(grep -q 'Public Suffix List pinned in crawler-commons-1.7-SNAPSHOT.jar' <<<"$out" && grep -q "^public-suffix-list: sha256 $(sed -n 's/^PSL_SHA256=//p' "$I/build/psl/PIN") bytes $(stat -c %s "$I/build/psl/public_suffix_list.dat")" "$FR/etc/tc/job-versions.txt"; echo $?)
chk "the job holds the wrapper classes and the receipt class CustodyReceipt" $(grep -q 'wrapper classes, the receipt class CustodyReceipt is in it' <<<"$out"; echo $?)
chk "the wrapper jar was built from the job and installed in Hadoop's library folder, on the classpath" $([ -f "$FR/opt/hadoop/share/hadoop/common/lib/attested-hdfs.jar" ] && grep -q "on Hadoop's classpath" <<<"$out"; echo $?)
chk "the deploy folder (job and bin/nutch) is installed in /opt/tc/nutch and equals the built job" $([ -f "$FR/opt/tc/nutch/apache-nutch-1.22.job" ] && [ -f "$FR/opt/tc/nutch/bin/nutch" ] && [ -f "$FR/opt/tc/nutch/bin/crawl" ]; echo $?)
chk "every fingerprint is recorded (source, job, jar, the two commits, the tools), and there is no patch line" $(grep -q "^source: src.tgz sha256 $SSHA" "$FR/etc/tc/job-versions.txt" && ! grep -q '^patch' "$FR/etc/tc/job-versions.txt" && grep -q '^job: apache-nutch-1.22.job sha256 [0-9a-f]\{64\} bytes' "$FR/etc/tc/job-versions.txt" && grep -q '^jar: attested-hdfs.jar sha256 [0-9a-f]\{64\} classes 2' "$FR/etc/tc/job-versions.txt" && grep -q '^crawler-commons: 13118882ddfe' "$FR/etc/tc/job-versions.txt" && grep -q '^tools: ant ' "$FR/etc/tc/job-versions.txt"; echo $?)
chk "the measured list has 11 entries and the last one is nutch-deploy" $(grep -q 'TC-LIST-OK: 11 entries' <<<"$out" && [ "$(awk -F'\t' '!/^#/ && NF>=2' "$FR/etc/tc/measured-paths.txt" | tail -1 | cut -f1)" = nutch-deploy ]; echo $?)
chk "the build tools were purged, the build folder and the caches are gone, and libcld2-0 was installed to stay" $(! command -v ant >/dev/null && ! command -v git >/dev/null && [ ! -d "$W/work" ] && [ ! -d "$W/home/.m2" ] && grep -q '^purge -y ant maven git patch' "$SD/apt.log" && grep -q 'libcld2-0' "$SD/apt.log" && ! grep -q 'purge.*libcld2' "$SD/apt.log"; echo $?)
chk "the installed tree was handed to root (chown -R root:root /opt/tc)" $(grep -q 'root:root' "$SD/chown.log"; echo $?)
mkroot; touch "$SD/slow"; job; chk "a heartbeat line is printed while a long build runs (and the job still finishes)" $([ $rc = 0 ] && grep -q "still working: ant runtime" <<<"$out"; echo $?)
mkroot; job
echo "--- faults of the job script"
abort() { local label="$1" want="$2"; job; chk "fault: $label" $([ $rc != 0 ] && grep -q "ABORT: .*$want" <<<"$out"; echo $?); }
mkroot; rm -f "$FR/opt/hadoop/bin/hdfs"; abort "the software layer of F0.3a is not in place" "run tc-image-bake.sh first"
mkroot; JFREE=1000 abort "too little disk space" "less than 8 GB"
mkroot; JSSHA="$(printf '0%.0s' $(seq 64))" abort "the source archive is not the pinned one" "source archive is not the pinned one"
mkroot; JSSHA="61dbff2e" abort "a short fingerprint is refused (the full 64 digits are required)" "full 64-digit"
mkroot; JSRC="$W/nobuildxml.tgz" JSSHA="$(sha256sum "$W/nobuildxml.tgz" | cut -c1-64)" abort "the archive has no build.xml at its top" "no build.xml"
mkroot; touch "$SD/apt_install_fails"; abort "the build tools cannot be installed" "apt-get install of the build tools failed"
mkroot; touch "$SD/git_clone_fails"; abort "a library cannot be cloned" "could not clone"
mkroot; touch "$SD/git_wrong_head"; abort "a library is not at its pinned commit" "not at 13118882ddfe\|is at ffffffffff"
mkroot; touch "$SD/mvn_fails"; abort "a library does not build" "mvn install failed"
mkroot; touch "$SD/mvn_nojar"; abort "the library jar is not in the maven cache" "crawler-commons jar is not in ~/.m2 exactly once"
mkroot; touch "$SD/ant_fails"; abort "ant runtime fails" "ant runtime failed"
mkroot; touch "$SD/ant_deletes_work"; job
chk "step R4: when the ant log is missing after the build (it happened once, the cause is not known), the stage stops AND prints the diagnostic: the state of the work folder, disk, memory, processes, kernel messages" $([ $rc != 0 ] && grep -q "DIAGNOSTIC: the ant log" <<<"$out" && grep -q "/work: does not exist" <<<"$out" && grep -q "ABORT: ant runtime failed" <<<"$out" && grep -q "^disk:" <<<"$out"; echo $?)
mkroot; touch "$SD/job_no_wrapper"; abort "the job holds no wrapper classes" "no wrapper classes"
mkroot; JSRC="$W/nocustody.tgz" JSSHA="$(sha256sum "$W/nocustody.tgz" | cut -c1-64)" abort "the source tree has no receipt code" "has no receipt code"
mkroot; touch "$SD/apt_purge_fails"; abort "the build tools cannot be removed" "could not remove the build tools"
mkroot; touch "$SD/purge_keeps"; abort "a build tool is still installed after the removal" "still installed"
mkroot; job; out2="$out"; rc2=$rc; job; chk "a second run on the same machine is harmless" $([ $rc2 = 0 ] && [ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
# ---------------------------------------------------------------- the check script, on the artifacts that the job script just made
echo "=== B. the check after a boot"
mkroot; job; [ $rc = 0 ] || { echo "  (the base for the check tests could not be built)"; echo "$out" | tail -5; }
mkdir -p "$W/state" "$W/outd"; echo 1 > "$W/state/bootcount"
printf '#!/usr/bin/env bash\nif [ -f "${FAKE_SD:?}/f03a_fail" ]; then echo "   FAIL: stand-in failure of the F0.3a checks"; echo "F03A-CHECK-FAILED (1) boot=1"; exit 1; fi\necho "   info: the measurement took 11 s"\necho "   note: java also listens on 0.0.0.0:13562 (to be bound or closed in step F0.5)"\necho "F03A-CHECK-OK boot=1"\n' > "$W/f03a-stub.sh"
cat > "$W/wj.sh" <<EOS
#!/usr/bin/env bash
case "\$1" in
  verify) exec bash "$KIT/ops/attested/wrapper-jar.sh" "\$@" ;;
  selftest) [ -f "${SD}/self_fails" ] && { echo "JAR-SELFTEST-FAILED" >&2; exit 1; }; echo "JAR-LOADS-FROM-LIB-OK: stand-in" ;;
esac
EOS
cat > "$FR/opt/hadoop/bin/hdfs" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; shift
case "$1" in
  -rm) rm -f "$SD/crawldb_made" ;;
  -mkdir) ;;
  -put) cat > /dev/null ;;
  -test) [ -f "$SD/crawldb_made" ] || exit 1 ;;
esac
exit 0
EOS
cat > "$FR/opt/tc/nutch/bin/nutch.new" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"
[ -f "$SD/inject_fails" ] && { echo "stand-in failure"; exit 1; }
if [ -f "$SD/inject_wrong" ]; then echo "Injector: Total new urls injected: 0"; else echo "Injector: Total new urls injected: 2"; fi
[ -f "$SD/no_crawldb" ] || touch "$SD/crawldb_made"
EOS
mv "$FR/opt/tc/nutch/bin/nutch.new" "$FR/opt/tc/nutch/bin/nutch"; chmod 755 "$FR/opt/tc/nutch/bin/nutch" "$FR/opt/hadoop/bin/hdfs"
# the recorded job sha must still match: the stand-in launcher is not part of it (only the job file is recorded)
check() { out="$(env TC_ROOT="$FR" TC_STATE="$W/state" TC_OUT="$W/outd" TC_F03A="$W/f03a-stub.sh" TC_WRAPJAR="$W/wj.sh" TC_TIMEOUT=20 FAKE_SD="$SD" bash "$I/test/f03b-check.sh" 2>&1)"; rc=$?; }
check; echo "$out" | tail -2 | cut -c1-100
chk "happy path: exit 0 and F03B-CHECK-OK" $([ $rc = 0 ] && grep -q '^F03B-CHECK-OK boot=1' <<<"$out"; echo $?)
chk "the report names the recorded job and jar, the Pi value and the 2 injected urls" $(grep -q 'the installed job equals the recorded one' <<<"$out" && grep -q 'the installed wrapper jar equals the recorded one' <<<"$out" && grep -q 'Estimated value of Pi is 3.8' <<<"$out" && grep -q 'injected the 2 seed urls' <<<"$out"; echo $?)
chk "the info and note lines of the F0.3a part are shown (the measurement time is not hidden)" $(grep -q "info: the measurement took 11 s" <<<"$out" && grep -q "note: java also listens on 0.0.0.0:13562" <<<"$out"; echo $?)
chk "the wrapper self-test runs a COPY of the helper from /tmp (the user hadoop cannot read a home folder), and the copy is removed again" $(grep -q "^-u hadoop -- env .* bash /tmp/tc-wrapper-jar\." "$SD/runuser.log" && ! grep -q "^-u hadoop -- env .* bash $W/wj.sh" "$SD/runuser.log" && [ -z "$(ls /tmp/tc-wrapper-jar.* 2>/dev/null)" ]; echo $?)
chk "evidence files are left behind (pi, inject, job versions)" $([ -s "$W/outd/f03b-boot1-pi.txt" ] && [ -s "$W/outd/f03b-boot1-inject.txt" ] && [ -s "$W/outd/f03b-boot1-job-versions.txt" ]; echo $?)
out="$(env TC_ROOT="$FR" TC_STATE="$W/state" TC_OUT="$W/outd" TC_F03A="$W/f03a-stub.sh" TC_WRAPJAR="$W/wj.sh" TC_SKIP_JOBS=1 FAKE_SD="$SD" bash "$I/test/f03b-check.sh" 2>&1)"; rc=$?
chk "TC_SKIP_JOBS=1 skips the two YARN jobs and still passes" $([ $rc = 0 ] && grep -q 'the two YARN jobs were skipped' <<<"$out"; echo $?)
fault() { local label="$1" want="$2"; check; chk "fault: $label" $([ $rc != 0 ] && grep -q "FAIL: .*$want" <<<"$out" && grep -q '^F03B-CHECK-FAILED' <<<"$out"; echo $?); rm -f "$SD"/*_fails "$SD"/inject_wrong "$SD"/no_crawldb "$SD/f03a_fail"; }
touch "$SD/f03a_fail"; fault "the checks of step F0.3a fail" "did not pass"
cp "$FR/opt/tc/nutch/apache-nutch-1.22.job" "$W/job.keep"; echo tamper >> "$FR/opt/tc/nutch/apache-nutch-1.22.job"; fault "the installed job was changed after the build" "installed job"; cp "$W/job.keep" "$FR/opt/tc/nutch/apache-nutch-1.22.job"
cp "$FR/opt/hadoop/share/hadoop/common/lib/attested-hdfs.jar" "$W/jar.keep"; echo tamper >> "$FR/opt/hadoop/share/hadoop/common/lib/attested-hdfs.jar"; fault "the installed wrapper jar was changed after the build" "wrapper jar"; cp "$W/jar.keep" "$FR/opt/hadoop/share/hadoop/common/lib/attested-hdfs.jar"
chmod 775 "$FR/opt/tc/nutch"; fault "the deploy folder is writable by its group" "/opt/tc/nutch: owner"; chmod 755 "$FR/opt/tc/nutch"
mv "$FR/opt/hadoop/share/hadoop/common/lib/attested-hdfs.jar" "$W/jar.moved"; fault "the jar is missing from the library folder (not on the classpath)" "wrapper jar"; mv "$W/jar.moved" "$FR/opt/hadoop/share/hadoop/common/lib/attested-hdfs.jar"
touch "$SD/self_fails"; fault "the wrapper does not load or initialize" "wrapper self-test failed"
touch "$SD/pi_fails"; fault "Hadoop's Pi example does not finish" "Pi example did not finish"
touch "$SD/inject_fails"; fault "the Nutch inject job fails" "did not report 2 new urls"
touch "$SD/inject_wrong"; fault "the Nutch inject job reports the wrong number of urls" "did not report 2 new urls"
touch "$SD/no_crawldb"; fault "no crawl database is left in HDFS" "no crawl database"
# ---------------------------------------------------------------- the cleaning now also removes build caches
echo "=== C. the cleaning of build caches"
KR="$W/kr"; rm -rf "$KR"; mkdir -p "$KR/etc/ssh" "$KR/var/lib/dbus" "$KR/var/lib/apt/lists" "$KR/var/log" "$KR/home/u1/build" "$KR/home/u1/.m2/repository" "$KR/home/u1/.ant" "$KR/home/u1/.ivy2" "$KR/root/.m2" "$KR/opt/tc/nutch" "$KR/etc/tc"
echo id > "$KR/etc/machine-id"; echo keep > "$KR/home/u1/keep.txt"; echo job > "$KR/opt/tc/nutch/apache-nutch-1.22.job"; echo list > "$KR/etc/tc/measured-paths.txt"
out="$(env TC_ROOT="$KR" TC_SUDO="" bash "$I/build/tc-image-clean.sh" --this-machine-becomes-an-image 2>&1)"; rc=$?
chk "the cleaning removes the build folder and the maven, ant and ivy caches (home and root)" $([ $rc = 0 ] && [ ! -e "$KR/home/u1/build" ] && [ ! -e "$KR/home/u1/.m2" ] && [ ! -e "$KR/home/u1/.ant" ] && [ ! -e "$KR/home/u1/.ivy2" ] && [ ! -e "$KR/root/.m2" ]; echo $?)
chk "control: the baked job, the measured list and a user's own file are untouched" $([ -f "$KR/opt/tc/nutch/apache-nutch-1.22.job" ] && [ -f "$KR/etc/tc/measured-paths.txt" ] && [ -f "$KR/home/u1/keep.txt" ]; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"
if [ "$FAILN" = 0 ]; then echo "REHEARSAL-PASS: the real job script, check script and cleaning of step F0.3b pass against stand-ins, and every fault is refused; $PASS checks"; else echo "REHEARSAL-FAIL"; fi
[ "$FAILN" = 0 ]
REHEARSAL_END_MARK=1
