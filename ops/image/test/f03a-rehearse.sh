#!/usr/bin/env bash
# Rehearsal of step F0.3a with stand-ins: the REAL bake, clean and check scripts, the real tc-measure.sh and the real hadoop_conf.py, against a fake root, a fake Hadoop tarball and fake apt, curl, systemctl,
# ps, ss, runuser, getent and hdfs. Every check that matters is also made to FAIL on purpose.
#   bash f03a-rehearse.sh KITDIR      KITDIR holds ops/image, attest and ops/rebuild/hadoop_conf.py
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; echo "${out:-}" | grep -v "^      " | tail -6 | sed "s/^/        | /"; fi; }
W="$(mktemp -d)"; STUB="$W/bin"; mkdir -p "$STUB"; SD="$W/sd"; mkdir -p "$SD"
# ---------------------------------------------------------------- stand-ins
cat > "$STUB/apt-get" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_SD:?}/apt.log"
[ -f "$FAKE_SD/apt_fails" ] && [[ "$*" == *install* ]] && exit 1
if [[ "$*" == *openjdk-11-jdk-headless* ]] && [ ! -f "$FAKE_SD/no_jdk" ]; then
  J="${TC_ROOT:?}/usr/lib/jvm/java-11-openjdk-amd64"; mkdir -p "$J/bin" "$J/lib/server" "$TC_ROOT/etc/java-11-openjdk"; echo "jdk stand-in" > "$J/release"; printf '#!/bin/sh\nexit 0\n' > "$J/bin/java"; chmod +x "$J/bin/java"; head -c 4096 /dev/zero > "$J/lib/server/classes.jsa"; echo "java settings" > "$TC_ROOT/etc/java-11-openjdk/jvm.cfg"
  cat > "$J/bin/keytool" <<'EOK'
#!/usr/bin/env bash
[ -f "${FAKE_SD:?}/no_fingerprints" ] && exit 0
printf 'Alias name: a\nCertificate fingerprint (SHA-256): 11:22:33\nAlias name: b\nCertificate fingerprint (SHA-256): AA:BB:CC\n'
EOK
  chmod +x "$J/bin/keytool"
fi
exit 0
EOS
cat > "$STUB/curl" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; echo "$*" >> "$SD/curl.log"; [ -f "$SD/curl_fails" ] && exit 22
args=("$@"); out=""; resume=0; head=0; speed=0
for i in "${!args[@]}"; do case "${args[$i]}" in -o) out="${args[$((i+1))]}" ;; -C) resume=1 ;; -sIL) head=1 ;; -w) speed=1 ;; esac; done
url="${args[-1]}"; src="${FAKE_POOL:?}/$(basename "$url")"
if [ $head = 1 ]; then printf 'HTTP/1.1 200 OK\r\ncontent-length: %s\r\n\r\n' "$(cat "$SD/fake_size" 2>/dev/null || stat -c %s "$src")"; exit 0; fi
if [ $speed = 1 ]; then cat "$SD/speed" 2>/dev/null || echo 5000000; [ -f "$SD/speed_timeout" ] && exit 28; exit 0; fi   # a real curl that reaches --max-time prints the speed it measured and exits 28
if [ $resume = 1 ] && [ -f "$out" ]; then have=$(stat -c %s "$out"); tail -c +$((have + 1)) "$src" >> "$out"; else cp "$src" "$out"; fi
EOS
cat > "$STUB/useradd" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_SD:?}/useradd.log"
EOS
cat > "$STUB/chown" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "${FAKE_SD:?}/chown.log"
EOS
cat > "$STUB/dpkg-query" <<'EOS'
#!/usr/bin/env bash
printf 'openjdk-11-jdk-headless 11.0.99-0ubuntu1\nca-certificates 20240203\n'
EOS
cat > "$STUB/systemctl" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; ov() { [ -f "$SD/$1" ] && cat "$SD/$1"; }
case "$1" in
  daemon-reload) echo "daemon-reload" >> "$SD/systemctl.log" ;;
  --failed) cat "$SD/failed" 2>/dev/null ;;
  enable) [ -f "$SD/enable_fails" ] && exit 1; echo "enable $2" >> "$SD/systemctl.log" ;;
  stop) echo "stop $2" >> "$SD/systemctl.log" ;;
  disable) echo "disable $2" >> "$SD/systemctl.log" ;;
  is-active) ov "$2.active" || echo active ;;
  show) u="$2"; prop="$4"
    case "$prop" in
      Result) ov "$u.Result" || echo success ;;
      MainPID) ov "$u.MainPID" || echo 4242 ;;
      ExecMainStartTimestampMonotonic) ov "$u.start" || { [ "$u" = tc-measure.service ] && echo 1000000 || echo 9000000; } ;;
      ExecMainExitTimestampMonotonic) ov "$u.exit" || echo 5500000 ;;
    esac ;;
esac
EOS
for t in cloud-init journalctl; do cat > "$STUB/$t" <<EOS
#!/usr/bin/env bash
echo "$t \$*" >> "\${FAKE_SD:?}/misc.log"
EOS
done
cat > "$STUB/ps" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"
if [[ "$*" == *"-o user= -p"* ]]; then pid="${@: -1}"; cat "$SD/ps.user.$pid" 2>/dev/null || cat "$SD/ps.user" 2>/dev/null || echo hadoop; else printf 'hadoop 4242 /usr/lib/jvm/java-11-openjdk-amd64/bin/java -Dproc_namenode\n'; fi
EOS
cat > "$STUB/ss" <<'EOS'
#!/usr/bin/env bash
cat "${FAKE_SD:?}/ss.txt"
EOS
cat > "$STUB/getent" <<'EOS'
#!/usr/bin/env bash
cat "${FAKE_SD:?}/passwd" 2>/dev/null || echo 'hadoop:x:998:998::/var/lib/hadoop:/usr/sbin/nologin'
EOS
cat > "$STUB/runuser" <<'EOS'
#!/usr/bin/env bash
shift 3; exec "$@"
EOS
cat > "$STUB/systemd-analyze" <<'EOS'
#!/usr/bin/env bash
[ -f "${FAKE_SD:?}/analyze_noise" ] && echo "/lib/systemd/system/snapd.service:23: Unknown key name 'RestartMode' in section 'Service', ignoring."
[ -f "${FAKE_SD:?}/analyze_warns" ] && echo "/usr/local/lib/tc/units/tc-hdfs-format.service:9: Unknown key name 'ConditionPathExists' in section 'Service', ignoring."
exit 0
EOS
chmod +x "$STUB"/*; export PATH="$STUB:$PATH"
# a fake Hadoop tarball, with the checksum file in Apache's format
POOL="$W/pool"; mkdir -p "$POOL" "$W/th/hadoop-3.4.3/bin" "$W/th/hadoop-3.4.3/etc/hadoop" "$W/th/hadoop-3.4.3/share/doc" "$W/th/hadoop-3.4.3/share/hadoop/common"
printf '#!/bin/sh\necho hdfs\n' > "$W/th/hadoop-3.4.3/bin/hdfs"; printf '#!/bin/sh\necho yarn\n' > "$W/th/hadoop-3.4.3/bin/yarn"; chmod +x "$W/th/hadoop-3.4.3/bin/"*
echo "# env" > "$W/th/hadoop-3.4.3/etc/hadoop/hadoop-env.sh"; echo "docs" > "$W/th/hadoop-3.4.3/share/doc/readme"; echo "jar" > "$W/th/hadoop-3.4.3/share/hadoop/common/hadoop-common-3.4.3.jar"
tar czf "$POOL/hadoop-3.4.3.tar.gz" -C "$W/th" hadoop-3.4.3; H512="$(sha512sum "$POOL/hadoop-3.4.3.tar.gz" | cut -d' ' -f1)"; echo "SHA512 (hadoop-3.4.3.tar.gz) = $H512" > "$POOL/hadoop-3.4.3.tar.gz.sha512"
# ---------------------------------------------------------------- the fake builder (after the F0.2 preparation)
mkroot() { rm -rf "$W/fr"; FR="$W/fr"; for d in usr/local/lib/tc etc/tc etc/systemd/system usr/bin usr/lib/jvm etc/ssh var/lib/dbus; do mkdir -p "$FR/$d"; done
  cp "$I"/rootfs/usr/local/lib/tc/*.sh "$FR/usr/local/lib/tc/"; cp "$KIT/attest/measure/treehash.sh" "$KIT/attest/measure/rtmr3_replay.py" "$FR/usr/local/lib/tc/"; chmod +x "$FR"/usr/local/lib/tc/*
  cp "$I/rootfs/etc/tc/measured-paths.txt" "$FR/etc/tc/"; cp "$I/rootfs/etc/systemd/system/tc-measure.service" "$I/rootfs/etc/systemd/system/tc-placeholder.service" "$FR/etc/systemd/system/"
  echo openssl > "$FR/usr/bin/openssl"; echo wg > "$FR/usr/bin/wg"; rm -rf "$SD"; mkdir -p "$SD"; rm -rf "$W/bakework"; }
bake() { env TC_ROOT="$FR" TC_SUDO="" TC_WORK="$W/bakework" TC_FREE_KB="${BFREE:-9000000}" FAKE_SD="$SD" FAKE_POOL="${BPOOL:-$POOL}" bash "$I/build/tc-image-bake.sh" "${BKIT:-$KIT}" 2>&1; }
echo "=== A. the bake script against a fake builder"
mkroot; out="$(bake)"; rc=$?; echo "$out" | tail -2 | cut -c1-120
chk "happy path: exit 0 and READY" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
chk "step R4.3: the JDK's class-data cache (made at install time, different in every build) is removed, and the bake says so" $([ ! -e "$FR/usr/lib/jvm/java-11-openjdk-amd64/lib/server/classes.jsa" ] && grep -q 'JDKCACHE-OK: classes.jsa removed' <<<"$out"; echo $?)
chk "Hadoop is in /opt/hadoop (bin/hdfs runs) and the documentation folder was removed" $([ -x "$FR/opt/hadoop/bin/hdfs" ] && [ ! -e "$FR/opt/hadoop/share/doc" ] && [ -f "$FR/opt/hadoop/share/hadoop/common/hadoop-common-3.4.3.jar" ]; echo $?)
chk "the tarball was checked against the checksum file (the message names the hash prefix)" $(grep -q "sha512 ${H512:0:16}" <<<"$out"; echo $?)
chk "the configuration was rendered with the loopback address and equals its property files" $(grep -q '127.0.0.1:9000' "$FR/opt/hadoop/etc/hadoop/core-site.xml" && grep -q 'file:///var/lib/hadoop/namenode' "$FR/opt/hadoop/etc/hadoop/hdfs-site.xml" && python3 "$FR/usr/local/lib/tc/hadoop_conf.py" check "$FR/etc/tc/hadoop-props" "$FR/opt/hadoop/etc/hadoop" /unused >/dev/null; echo $?)
chk "the service user was made with no login shell, and the five folders were handed to it" $(grep -q -- '--shell /usr/sbin/nologin' "$SD/useradd.log" && [ "$(grep -c 'hadoop:hadoop' "$SD/chown.log")" = 5 ]; echo $?)
chk "the CA fingerprints were listed into /etc/tc (2 lines)" $([ "$(wc -l < "$FR/etc/tc/java-ca-fingerprints.txt")" = 2 ]; echo $?)
chk "the five units are installed in the measured folder and enabled from there" $([ "$(ls "$FR/usr/local/lib/tc/units/" | wc -l)" = 5 ] && [ "$(grep -c "^enable .*usr/local/lib/tc/units/tc-" "$SD/systemctl.log")" = 5 ]; echo $?)
chk "the four daemons are stopped BEFORE Hadoop is replaced (a used builder ran them at its boot)" $([ "$(grep -c "^stop tc-" "$SD/systemctl.log")" = 4 ] && [ "$(grep -n "^stop tc-namenode" "$SD/systemctl.log" | cut -d: -f1)" -lt "$(grep -n "^daemon-reload" "$SD/systemctl.log" | cut -d: -f1)" ] && grep -q "any daemons of an earlier boot" <<<"$out"; echo $?)
chk "the test-only stand-in unit was removed and disabled" $([ ! -e "$FR/etc/systemd/system/tc-placeholder.service" ] && grep -q 'disable tc-placeholder.service' "$SD/systemctl.log"; echo $?)
chk "the measured list is the longer one (10 entries), the role is single, and the versions are recorded" $(cmp -s "$FR/etc/tc/measured-paths.txt" "$I/rootfs/etc/tc/measured-paths-f03a.txt" && grep -q 'TC-LIST-OK: 10 entries' <<<"$out" && [ "$(cat "$FR/etc/tc/role")" = single ] && grep -q "hadoop: hadoop-3.4.3.tar.gz sha512 $H512" "$FR/etc/tc/bake-versions.txt" && grep -q 'openjdk-11-jdk-headless 11.0.99' "$FR/etc/tc/bake-versions.txt"; echo $?)
out="$(bake)"; rc=$?; chk "a second run is harmless (it reinstalls Hadoop)" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
echo "--- the units, read SECTION BY SECTION (the rehearsal cannot run systemd; a key in the wrong section is ignored by systemd, and a plain grep cannot see that)"
UV="$W/unitcheck.py"; cat > "$UV" <<'PYEOF'
import re, sys
ALLOWED = {"Unit": {"Description", "Requires", "After", "Wants", "Before"}, "Service": {"Type", "RemainAfterExit", "User", "Group", "Environment", "WorkingDirectory", "ExecStart", "NoNewPrivileges", "ProtectHome", "ProtectSystem", "PrivateTmp"}, "Install": {"WantedBy"}}
cond = re.compile(r"^(Condition|Assert)\w+$"); sec = None; keys = []; bad = []
for ln in open(sys.argv[1], encoding="utf-8"):
    ln = ln.strip()
    if not ln or ln.startswith("#"): continue
    m = re.match(r"^\[(\w+)\]$", ln)
    if m: sec = m.group(1); continue
    k, v = ln.split("=", 1); keys.append((sec, k, v))
    if not ((sec == "Unit" and (k in ALLOWED["Unit"] or cond.match(k))) or (sec in ("Service", "Install") and k in ALLOWED[sec])): bad.append("%s in [%s]" % (k, sec))
if bad: print("keys in the wrong or an unknown section: " + ", ".join(bad)); sys.exit(1)
for s, k, v in keys: print(s, k, v)
PYEOF
U="$I/rootfs/usr/local/lib/tc/units"; ok=0; for u in tc-namenode tc-datanode tc-resourcemanager tc-nodemanager tc-hdfs-format; do python3 "$UV" "$U/$u.service" > "$W/u.$u.keys" 2>&1 || { ok=1; cat "$W/u.$u.keys"; }; done
chk "every key of every unit is in a section where systemd reads it" $ok
has() { grep -q -- "^$2 $3 $4\$" "$W/u.$1.keys"; }
ok=0; for u in tc-namenode tc-datanode tc-resourcemanager tc-nodemanager tc-hdfs-format; do has $u Unit Requires "tc-measure.service.*" || has $u Unit Requires "tc-measure.service" || ok=1; grep -q '^Unit After .*tc-measure.service' "$W/u.$u.keys" || ok=1; has $u Service User hadoop || ok=1; grep -q '^Service ExecStart /opt/hadoop/bin/' "$W/u.$u.keys" || ok=1; has $u Install WantedBy multi-user.target || ok=1; done
chk "every unit requires and follows tc-measure.service, runs as hadoop from /opt/hadoop, and is wanted by multi-user.target" $ok
chk "the order is: format, then NameNode, then DataNode and ResourceManager, then NodeManager" $(grep -q '^Unit After tc-measure.service tc-hdfs-format.service' "$W/u.tc-namenode.keys" && grep -q '^Unit After tc-measure.service tc-namenode.service' "$W/u.tc-datanode.keys" && grep -q '^Unit After tc-measure.service tc-namenode.service' "$W/u.tc-resourcemanager.keys" && grep -q '^Unit After tc-measure.service tc-resourcemanager.service' "$W/u.tc-nodemanager.keys"; echo $?)
chk "the format unit is a one-shot, and its skip condition is in [Unit] (the section that systemd reads), not in [Service]" $(grep -q '^Service Type oneshot' "$W/u.tc-hdfs-format.keys" && grep -q '^Unit ConditionPathExists !/var/lib/hadoop/namenode/current' "$W/u.tc-hdfs-format.keys" && ! grep -q '^Service Condition' "$W/u.tc-hdfs-format.keys"; echo $?)
chk "no daemon unit restarts itself silently (a failed daemon stays visible)" $(! grep -q '^Service Restart' "$W"/u.*.keys; echo $?)
cp "$U/tc-hdfs-format.service" "$W/bad1.service"; python3 - "$W/bad1.service" <<'PYEOF'
import sys; p = sys.argv[1]; s = open(p).read(); s = s.replace("ConditionPathExists=!/var/lib/hadoop/namenode/current\n", "", 1).replace("RemainAfterExit=yes\n", "RemainAfterExit=yes\nConditionPathExists=!/var/lib/hadoop/namenode/current\n", 1); open(p, "w").write(s)
PYEOF
python3 "$UV" "$W/bad1.service" > "$W/bad1.out" 2>&1; chk "fault: the very mistake of the first image (the condition under [Service]) is caught by the validator" $([ $? != 0 ] && grep -q 'ConditionPathExists in \[Service\]' "$W/bad1.out"; echo $?)
cp "$U/tc-namenode.service" "$W/bad2.service"; sed -i 's/^After=tc-measure.service tc-hdfs-format.service/&\nRestart=always/' "$W/bad2.service"; python3 "$UV" "$W/bad2.service" > "$W/bad2.out" 2>&1; chk "fault: a Restart key in [Unit] is caught as well" $([ $? != 0 ] && grep -q 'Restart in \[Unit\]' "$W/bad2.out"; echo $?)
echo "--- faults of the bake"
abort() { local label="$1" want="$2"; out="$(bake)"; rc=$?; chk "fault: $label" $([ $rc != 0 ] && grep -q "ABORT: .*$want" <<<"$out"; echo $?); }
mkroot; rm -f "$FR/usr/local/lib/tc/tc-measure.sh"; abort "the image preparation has not run" "preparation has not run"
mkroot; BFREE=1000 abort "too little disk space" "less than 6 GB"
mkroot; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; rm -f "$W/badkit/ops/rebuild/hadoop_conf.py"; BKIT="$W/badkit" abort "hadoop_conf.py is missing from the kit" "missing in"
mkroot; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; rm -f "$W/badkit/ops/image/rootfs/usr/local/lib/tc/units/tc-datanode.service"; BKIT="$W/badkit" abort "a unit file is missing from the kit" "missing in"
mkroot; touch "$SD/apt_fails"; abort "the JDK cannot be installed" "install of the JDK failed"
mkroot; touch "$SD/no_jdk"; abort "no JDK folder after the install" "no JDK folder"
mkroot; touch "$SD/curl_fails"; abort "the download fails" "could not download"
mkroot; rm -rf "$W/pool2"; mkdir "$W/pool2"; cp "$POOL"/* "$W/pool2/"; echo "tampered" >> "$W/pool2/hadoop-3.4.3.tar.gz"; BPOOL="$W/pool2" abort "the tarball does not match the checksum file" "checksum mismatch"
mkroot; touch "$SD/no_fingerprints"; abort "no CA fingerprints are listed" "no CA fingerprints"
mkroot; rm -rf "$W/pool3"; mkdir "$W/pool3"; cp "$POOL"/* "$W/pool3/"; echo "a checksum file without any hash" > "$W/pool3/hadoop-3.4.3.tar.gz.sha512"; BPOOL="$W/pool3" abort "the checksum file holds no hash" "checksum mismatch"
echo "--- the download: resume, speed guard, and the two servers"
bakewith() { out="$(bake)"; rc=$?; }
mkroot; mkdir -p "$W/bakework"; head -c 300 "$POOL/hadoop-3.4.3.tar.gz" > "$W/bakework/hadoop-3.4.3.tar.gz"; bakewith
chk "a partly downloaded file is RESUMED (curl is called with -C -) and the result passes the checksum" $([ $rc = 0 ] && grep -q -- '-C -' "$SD/curl.log" && grep -q '^READY' <<<"$out"; echo $?)
mkroot; mkdir -p "$W/bakework"; cp "$POOL/hadoop-3.4.3.tar.gz" "$W/bakework/"; bakewith
chk "a complete file is not downloaded again" $([ $rc = 0 ] && ! grep -q -- '-C -' "$SD/curl.log" && ! grep -q -- '-o hadoop-3.4.3.tar.gz http' "$SD/curl.log"; echo $?)
mkroot; echo 500000000 > "$SD/fake_size"; echo 32768 > "$SD/speed"; out="$(bake)"; rc=$?
chk "fault: a server at 32 KB/s for 500 MB is refused before downloading, and the message names HADOOP_URL_BASE" $([ $rc != 0 ] && grep -q 'too slow' <<<"$out" && grep -q 'HADOOP_URL_BASE' <<<"$out" && ! grep -q -- '-C -' "$SD/curl.log"; echo $?)
mkroot; touch "$SD/speed_timeout"; echo 40000 > "$SD/speed"; HADOOP_ALLOW_SLOW=1 bakewith
chk "step R4: a speed probe that reaches its 30 s limit (curl exits 28 after printing the speed) does not end the bake silently: it goes on and reports the speed" $([ $rc = 0 ] && grep -q 'the server gives about' <<<"$out" && grep -q '^READY' <<<"$out"; echo $?)
mkroot; touch "$SD/speed_timeout"; echo 500000000 > "$SD/fake_size"; echo 32768 > "$SD/speed"; out="$(bake)"; rc=$?
chk "step R4: a slow server whose probe also times out is refused WITH a message that names HADOOP_URL_BASE (not silently)" $([ $rc != 0 ] && grep -q 'ABORT: .*too slow' <<<"$out" && grep -q 'HADOOP_URL_BASE' <<<"$out"; echo $?)
mkroot; touch "$SD/speed_timeout"; echo 0 > "$SD/speed"; HADOOP_ALLOW_SLOW=1 bakewith
chk "step R4: a probe that measured nothing (speed 0, exit 28) also goes on when HADOOP_ALLOW_SLOW=1" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
mkroot; export HADOOP_URL_BASE="http://mirror.example/hadoop" HADOOP_SUM_BASE="http://primary.example/sums"; bakewith; unset HADOOP_URL_BASE HADOOP_SUM_BASE
chk "the checksum file is fetched from the primary server and the tarball from the mirror" $([ $rc = 0 ] && grep -q 'primary.example/sums/hadoop-3.4.3.tar.gz.sha512' "$SD/curl.log" && grep -q 'mirror.example/hadoop/hadoop-3.4.3.tar.gz' "$SD/curl.log" && ! grep -q 'mirror.example/hadoop/hadoop-3.4.3.tar.gz.sha512' "$SD/curl.log"; echo $?)
mkroot; echo 99999 > "$SD/fake_size"; export HADOOP_ALLOW_SLOW=1 TC_RETRY_SLEEP=0; bakewith; unset HADOOP_ALLOW_SLOW TC_RETRY_SLEEP
chk "fault: a download that ends short of the announced size is reported as incomplete (and can be resumed by running again)" $([ $rc != 0 ] && grep -q 'download is incomplete' <<<"$out"; echo $?)
mkroot; touch "$SD/enable_fails"; abort "a unit cannot be enabled" "could not enable"
mkroot; touch "$SD/analyze_warns"; abort "systemd reports an unknown key in a unit" "systemd does not understand"
mkroot; touch "$SD/analyze_noise"; out="$(bake)"; rc=$?; chk "systemd's warning about Ubuntu's own snapd.service (seen on the real VM) does NOT stop the bake" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
mkroot; touch "$SD/analyze_noise" "$SD/analyze_warns"; abort "a warning about OUR unit still stops the bake when Ubuntu's warning is present too" "systemd does not understand"
mkroot; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; echo "this line has no equals sign" >> "$W/badkit/ops/image/rootfs/etc/tc/hadoop-props/core-site.props"; BKIT="$W/badkit" abort "a property file is malformed" "could not render"
rm -rf "$W/badkit"
# ---------------------------------------------------------------- the clean script
echo "=== A2. the registers tool"
RG="$I/test/f03-registers.py"; mkq() { python3 - "$1" "$2" <<'PYEOF'
import sys
q = bytearray(8000); off = {"MRTD": 184, "RTMR0": 376, "RTMR1": 424, "RTMR2": 472, "RTMR3": 520}
for i, (k, o) in enumerate(off.items()):
    q[o:o + 48] = bytes([int(sys.argv[2].split(",")[i], 16)]) * 48
open(sys.argv[1], "wb").write(q)
PYEOF
}
mkq "$W/qa.bin" "11,22,33,44,55"; mkq "$W/qb.bin" "11,22,99,44,55"; mkq "$W/qc.bin" "11,22,33,44,aa"
out="$(python3 "$RG" "$W/qa.bin" vm-a-boot1)"; chk "the tool reads MRTD, RTMR0 to RTMR3 at the proven offsets (distinct test values come back in the right fields)" $(grep -q "^vm-a-boot1 MRTD $(printf '11%.0s' $(seq 48)) RTMR0 $(printf '22%.0s' $(seq 48)) RTMR1 $(printf '33%.0s' $(seq 48)) RTMR2 $(printf '44%.0s' $(seq 48)) RTMR3 $(printf '55%.0s' $(seq 48))\$" <<<"$out"; echo $?)
{ python3 "$RG" "$W/qa.bin" vm-a-boot1; python3 "$RG" "$W/qb.bin" vm-b-boot1; } > "$W/regs.txt"; out="$(python3 "$RG" --compare "$W/regs.txt")"
chk "the comparison says DIFFERENT for exactly the register that differs (RTMR1) and EQUAL for the others" $(grep -q 'RTMR1 DIFFERENT' <<<"$out" && [ "$(grep -c EQUAL <<<"$out")" = 4 ]; echo $?)
{ python3 "$RG" "$W/qa.bin" vm-a-boot1; python3 "$RG" "$W/qc.bin" vm-c-boot1; } > "$W/regs2.txt"; out="$(python3 "$RG" --compare "$W/regs2.txt")"; chk "a difference in RTMR3 alone is reported on RTMR3 alone" $(grep -q 'RTMR3 DIFFERENT' <<<"$out" && [ "$(grep -c DIFFERENT <<<"$out")" = 1 ]; echo $?)
head -c 300 "$W/qa.bin" > "$W/short.bin"; out="$(python3 "$RG" "$W/short.bin" x 2>&1)"; rc=$?; chk "fault: a file that is too short for a quote is refused" $([ $rc != 0 ] && grep -q 'not a TDX quote' <<<"$out"; echo $?)
python3 "$RG" "$W/qa.bin" only-one > "$W/regs3.txt"; out="$(python3 "$RG" --compare "$W/regs3.txt" 2>&1)"; rc=$?; chk "fault: a comparison of a single VM is refused" $([ $rc != 0 ] && grep -q 'at least two' <<<"$out"; echo $?)
echo "=== B. the cleaning script"
KR="$W/kr"; mkcl() { rm -rf "$KR" "$SD"; mkdir -p "$SD" "$KR/etc/ssh" "$KR/var/lib/dbus" "$KR/var/lib/tc" "$KR/run/tc" "$KR/home/u1/.ssh" "$KR/home/u1/k617" "$KR/home/u1/bake" "$KR/home/u1/f03" "$KR/root/grub-backup-1" "$KR/var/lib/apt/lists" "$KR/var/log" "$KR/opt/hadoop/bin" "$KR/etc/tc" "$KR/var/lib/hadoop/namenode/current" "$KR/var/lib/hadoop/datanode/current" "$KR/var/lib/hadoop/tmp/nm-local-dir" "$KR/var/log/hadoop"
  echo "abc123" > "$KR/etc/machine-id"; echo "abc123" > "$KR/var/lib/dbus/machine-id"; echo key > "$KR/etc/ssh/ssh_host_rsa_key"; echo pub > "$KR/etc/ssh/ssh_host_rsa_key.pub"; echo 3 > "$KR/var/lib/tc/bootcount"
  echo k > "$KR/home/u1/.ssh/authorized_keys"; echo h > "$KR/home/u1/.bash_history"; echo "keep me" > "$KR/home/u1/keepme.txt"; echo x > "$KR/root/grub-backup-1/g"; echo l > "$KR/var/lib/apt/lists/a"; echo "log line" > "$KR/var/log/syslog"
  echo hdfs > "$KR/opt/hadoop/bin/hdfs"; echo list > "$KR/etc/tc/measured-paths.txt"; echo v > "$KR/var/lib/hadoop/namenode/current/VERSION"; echo b > "$KR/var/lib/hadoop/datanode/current/blk"; echo t > "$KR/var/lib/hadoop/tmp/nm-local-dir/x"; echo l > "$KR/var/log/hadoop/nn.log"; }
cleanit() { env TC_ROOT="$KR" TC_SUDO="" FAKE_SD="$SD" bash "$I/build/tc-image-clean.sh" "$@" 2>&1; }
mkcl; out="$(cleanit)"; rc=$?; chk "without its flag the cleaning refuses and touches nothing" $([ $rc = 2 ] && [ -s "$KR/etc/machine-id" ] && [ -f "$KR/etc/ssh/ssh_host_rsa_key" ]; echo $?)
out="$(cleanit --this-machine-becomes-an-image)"; rc=$?; echo "$out" | tail -1 | cut -c1-100
chk "happy path: exit 0 and CLEAN-OK" $([ $rc = 0 ] && grep -q '^CLEAN-OK' <<<"$out"; echo $?)
chk "the machine id is empty and the dbus id points to it; no ssh host keys are left" $([ ! -s "$KR/etc/machine-id" ] && [ "$(readlink "$KR/var/lib/dbus/machine-id")" = /etc/machine-id ] && ! ls "$KR"/etc/ssh/ssh_host_* >/dev/null 2>&1; echo $?)
chk "the measurement's state, the builder's folders and the key and history files are gone" $([ ! -e "$KR/var/lib/tc" ] && [ ! -e "$KR/home/u1/.ssh" ] && [ ! -e "$KR/home/u1/k617" ] && [ ! -e "$KR/home/u1/bake" ] && [ ! -e "$KR/home/u1/f03" ] && [ ! -e "$KR/home/u1/.bash_history" ] && [ ! -e "$KR/root/grub-backup-1" ]; echo $?)
chk "package lists are removed and logs are emptied" $([ -z "$(ls -A "$KR/var/lib/apt/lists" 2>/dev/null)" ] && [ ! -s "$KR/var/log/syslog" ]; echo $?)
chk "Hadoop's data and logs are gone (no HDFS travels in an image) but the folders stay for the service user" $([ ! -e "$KR/var/lib/hadoop/namenode/current" ] && [ ! -e "$KR/var/lib/hadoop/datanode/current" ] && [ ! -e "$KR/var/lib/hadoop/tmp/nm-local-dir" ] && [ ! -e "$KR/var/log/hadoop/nn.log" ] && [ -d "$KR/var/lib/hadoop/namenode" ] && [ -d "$KR/var/lib/hadoop/datanode" ] && [ -d "$KR/var/lib/hadoop/tmp" ] && [ -d "$KR/var/log/hadoop" ]; echo $?)
chk "cloud-init was cleaned (first-boot state removed)" $(grep -q 'cloud-init clean --logs' "$SD/misc.log"; echo $?)
chk "control: what belongs to the image is untouched (Hadoop, the measured list, a user's own file)" $([ -f "$KR/opt/hadoop/bin/hdfs" ] && [ -f "$KR/etc/tc/measured-paths.txt" ] && [ -f "$KR/home/u1/keepme.txt" ]; echo $?)
# ---------------------------------------------------------------- the check script
echo "=== C. the check after a boot, with every check made to fail on purpose"
CR="$W/cr"; RUNF="$W/run"; STATEF="$W/state"; OUTD="$W/out"
cat > "$W/f01stub.sh" <<'EOS'
#!/usr/bin/env bash
if [ -f "${FAKE_SD:?}/f01_fail" ]; then echo "   FAIL: stand-in failure of the F0.2 checks"; echo "F01-CHECK-FAILED (1) boot=1"; exit 1; fi
echo "F01-CHECK-OK boot=1 kernel=6.17.0-1022-gcp rtmr3=abcdef0123456789"
EOS
chmod +x "$W/f01stub.sh"
good_check() { rm -rf "$CR" "$RUNF" "$STATEF" "$OUTD" "$SD"; mkdir -p "$CR/etc/tc" "$CR/opt/hadoop/bin" "$CR/opt/hadoop/etc/hadoop" "$RUNF" "$STATEF" "$OUTD" "$SD/hdfs"
  mkdir -p "$CR/usr/local/lib/tc/units"; cp "$I"/rootfs/usr/local/lib/tc/units/*.service "$CR/usr/local/lib/tc/units/"; cp "$I/rootfs/etc/tc/measured-paths-f03a.txt" "$CR/etc/tc/measured-paths.txt"; echo "hadoop: hadoop-3.4.3.tar.gz sha512 abc" > "$CR/etc/tc/bake-versions.txt"; echo 1 > "$STATEF/bootcount"
  awk -F'\t' '!/^#/ && NF>=2 {printf "%s\t%s\t%s\t%s\n", $1, "dd", "bb", "cc"}' "$CR/etc/tc/measured-paths.txt" > "$RUNF/rtmr3-events.tsv"
  cat > "$CR/opt/hadoop/bin/hdfs" <<'EOS'
#!/usr/bin/env bash
S="${FAKE_SD:?}/hdfs"; mkdir -p "$S"; [ -f "$S/../hdfs_down" ] && exit 1
shift  # dfs
case "$1" in -ls) exit 0 ;; -put) cat > "$S/file"; [ -f "$S/../hdfs_corrupt" ] && echo wrong > "$S/file"; exit 0 ;; -cat) cat "$S/file" ;; -rm) rm -f "$S/file"; exit 0 ;; esac
EOS
  chmod 755 "$CR/opt/hadoop" "$CR/opt/hadoop/bin/hdfs"
  printf 'LISTEN 0 4096 127.0.0.1:9000 0.0.0.0:* users:(("java",pid=1,fd=1))\nLISTEN 0 4096 127.0.0.1:9870 0.0.0.0:* users:(("java",pid=1,fd=2))\nLISTEN 0 4096 127.0.0.1:9866 0.0.0.0:* users:(("java",pid=2,fd=1))\nLISTEN 0 4096 127.0.0.1:9864 0.0.0.0:* users:(("java",pid=2,fd=2))\nLISTEN 0 4096 127.0.0.1:9867 0.0.0.0:* users:(("java",pid=2,fd=3))\nLISTEN 0 4096 127.0.0.1:8030 0.0.0.0:* users:(("java",pid=3,fd=1))\nLISTEN 0 4096 127.0.0.1:8031 0.0.0.0:* users:(("java",pid=3,fd=2))\nLISTEN 0 4096 127.0.0.1:8032 0.0.0.0:* users:(("java",pid=3,fd=3))\nLISTEN 0 4096 127.0.0.1:8033 0.0.0.0:* users:(("java",pid=3,fd=4))\nLISTEN 0 4096 127.0.0.1:8088 0.0.0.0:* users:(("java",pid=3,fd=5))\nLISTEN 0 4096 0.0.0.0:13562 0.0.0.0:* users:(("java",pid=4,fd=1))\nLISTEN 0 128 0.0.0.0:22 0.0.0.0:* users:(("sshd",pid=5,fd=3))\n' > "$SD/ss.txt"; }
check() { env TC_ROOT="$CR" TC_RUN="$RUNF" TC_STATE="$STATEF" TC_OUT="$OUTD" TC_F01="$W/f01stub.sh" TC_TRIES=2 TC_SLEEP=0 FAKE_SD="$SD" bash "$I/test/f03a-check.sh" 2>&1; }
good_check; out="$(check)"; rc=$?; echo "$out" | tail -2 | cut -c1-120
chk "happy path: exit 0 and F03A-CHECK-OK" $([ $rc = 0 ] && grep -q '^F03A-CHECK-OK boot=1' <<<"$out"; echo $?)
chk "it reports the java listener on 0.0.0.0:13562 as a note for step F0.5 and does not fail on it" $(grep -q 'note: java also listens on 0.0.0.0:13562' <<<"$out" && ! grep -q 'FAIL' <<<"$out"; echo $?)
chk "it lists the 10 events and prints the measurement's duration" $(grep -q 'the log holds the 10 events of the list, in order' <<<"$out" && grep -q 'the measurement took 4 s' <<<"$out"; echo $?)
chk "it reports that systemd reads all 5 unit files, and lists the failed units (none)" $(grep -q "systemd reads all 5 unit files without an unknown key or section" <<<"$out" && grep -q "info: failed units: none" <<<"$out"; echo $?)
chk "evidence files are left behind (listeners, processes, versions)" $([ -s "$OUTD/f03a-boot1-listeners.txt" ] && [ -f "$OUTD/f03a-boot1-processes.txt" ] && [ -s "$OUTD/f03a-boot1-bake-versions.txt" ]; echo $?)
fault() { local label="$1" want="$2"; out="$(check)"; rc=$?; chk "fault: $label" $([ $rc != 0 ] && grep -q "FAIL: .*$want" <<<"$out" && grep -q '^F03A-CHECK-FAILED' <<<"$out"; echo $?); good_check; }
good_check; touch "$SD/f01_fail"; fault "the checks of step F0.2 fail" "did not pass"
good_check; head -9 "$RUNF/rtmr3-events.tsv" > "$RUNF/short.tsv"; mv "$RUNF/short.tsv" "$RUNF/rtmr3-events.tsv"; fault "the log has fewer events than the list" "are not the list's"
good_check; awk 'NR==1{l=$0; next} NR==2{print; print l; next} {print}' "$RUNF/rtmr3-events.tsv" > "$RUNF/x.tsv"; mv "$RUNF/x.tsv" "$RUNF/rtmr3-events.tsv"; fault "two events are in the wrong order" "are not the list's"
good_check; touch "$SD/analyze_warns"; fault "systemd reports an unknown key in a unit file (the first image's mistake)" "systemd does not understand"
good_check; touch "$SD/analyze_noise"; out="$(check)"; rc=$?; chk "systemd's warning about Ubuntu's own snapd.service does NOT fail the check" $([ $rc = 0 ] && grep -q "^F03A-CHECK-OK" <<<"$out" && grep -q "systemd reads all 5 unit files" <<<"$out"; echo $?)
good_check; touch "$SD/analyze_noise" "$SD/analyze_warns"; fault "a warning about OUR unit still fails the check when Ubuntu's warning is present too" "systemd does not understand"
good_check; echo inactive > "$SD/tc-datanode.service.active"; fault "a daemon is not active" "tc-datanode is not active"
good_check; echo root > "$SD/ps.user"; fault "a daemon runs as root" "runs as 'root', not hadoop"
good_check; echo 3000000 > "$SD/tc-namenode.service.start"; fault "a daemon started BEFORE the measurement finished" "tc-namenode did not start after the measurement"
good_check; echo failed > "$SD/tc-hdfs-format.service.Result"; fault "the format unit failed" "format unit's result is not success"
good_check; touch "$SD/hdfs_down"; fault "HDFS does not answer" "did not work"
good_check; touch "$SD/hdfs_corrupt"; fault "a file read back from HDFS differs from what was written" "read back from HDFS is"
good_check; chmod 775 "$CR/opt/hadoop"; fault "the Hadoop folder is writable by its group" "/opt/hadoop: owner"
good_check; echo 'hadoop:x:998:998::/var/lib/hadoop:/bin/bash' > "$SD/passwd"; fault "the service user has a login shell" "has a login shell"
good_check; sed -i 's/127.0.0.1:9000/0.0.0.0:9000/' "$SD/ss.txt"; fault "the NameNode listens on all interfaces" "port 9000 listens on 0.0.0.0:9000"
good_check; grep -v ':8088 ' "$SD/ss.txt" > "$SD/ss2.txt"; mv "$SD/ss2.txt" "$SD/ss.txt"; fault "the ResourceManager's web port is not listening" "nothing listens on port 8088"
echo; echo "pass: $PASS   fail: $FAILN"
if [ "$FAILN" = 0 ]; then echo "REHEARSAL-PASS: the real bake, clean and check scripts of step F0.3a pass against stand-ins, and every fault is refused; $PASS checks"; else echo "REHEARSAL-FAIL"; fi
[ "$FAILN" = 0 ]
