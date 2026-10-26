#!/usr/bin/env bash
# Rehearsal of step F0.3c with stand-ins: the REAL tc-crawl.sh (the driver), tc-image-crawl.sh (the bake), f03c-check.sh, tc-measure.sh and the real unit file, against a fake root and fake systemctl, systemd-analyze,
# hdfs, yarn, the crawl script and nutch. Every check that matters is also made to FAIL on purpose.
#   bash f03c-rehearse.sh KITDIR      KITDIR holds ops/image, attest, ops/rebuild/hadoop_conf.py and ops/attested/wrapper-jar.sh
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; echo "${out:-}" | grep -v "^      " | tail -6 | sed "s/^/        | /"; fi; }
W="$(mktemp -d)"; STUB="$W/bin"; SD="$W/sd"; mkdir -p "$STUB" "$SD" "$W/home" "$W/mark"; export HOME="$W/home" FAKE_SD="$SD"
# ---------------------------------------------------------------- stand-ins
cat > "$STUB/systemctl" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; ov() { [ -f "$SD/$1" ] && cat "$SD/$1"; }
case "$1" in
  daemon-reload) echo "daemon-reload" >> "$SD/systemctl.log" ;;
  enable) [ -f "$SD/enable_fails" ] && exit 1; echo "enable $2" >> "$SD/systemctl.log" ;;
  show) u="$2"; prop="$4"; case "$prop" in
      ActiveState) ov "$u.ActiveState" || echo inactive ;;
      ConditionResult) ov "$u.ConditionResult" || echo yes ;;
      Result) ov "$u.Result" || echo success ;;
      ExecMainStartTimestampMonotonic) ov "$u.start" || { case "$u" in tc-crawl.service) echo 30000000 ;; *) echo 9000000 ;; esac; } ;;
      ExecMainExitTimestampMonotonic) ov "$u.exit" || echo 5500000 ;;
    esac ;;
esac
EOS
cat > "$STUB/systemd-analyze" <<'EOS'
#!/usr/bin/env bash
[ -f "${FAKE_SD:?}/analyze_noise" ] && echo "/lib/systemd/system/snapd.service:23: Unknown key name 'RestartMode' in section 'Service', ignoring."
[ -f "${FAKE_SD:?}/analyze_warns" ] && echo "/usr/local/lib/tc/units/tc-crawl.service:5: Unknown key name 'ConditionPathExists' in section 'Service', ignoring."
exit 0
EOS
printf '#!/usr/bin/env bash\nshift 3; exec "$@"\n' > "$STUB/runuser"
chmod +x "$STUB"/*; export PATH="$STUB:$PATH"
mkroot() { rm -rf "$W/fr" "$SD" "$W/mark" "$W/crawl.log"; mkdir -p "$SD" "$W/mark"; FR="$W/fr"
  for d in usr/local/lib/tc/units etc/tc etc/systemd/system usr/bin usr/lib/jvm/java-11-openjdk-amd64 etc/java-11-openjdk opt/hadoop/bin opt/hadoop/etc/hadoop opt/tc/nutch/bin var/log/hadoop; do mkdir -p "$FR/$d"; done
  cp "$I"/rootfs/usr/local/lib/tc/*.sh "$FR/usr/local/lib/tc/" 2>/dev/null; rm -f "$FR/usr/local/lib/tc/tc-crawl.sh"; cp "$KIT/attest/measure/treehash.sh" "$KIT/attest/measure/rtmr3_replay.py" "$FR/usr/local/lib/tc/"; chmod +x "$FR"/usr/local/lib/tc/*
  cp "$I/rootfs/etc/tc/measured-paths-f03b.txt" "$FR/etc/tc/measured-paths.txt"; echo "job: x" > "$FR/etc/tc/job-versions.txt"; cp "$I/rootfs/etc/systemd/system/tc-measure.service" "$FR/etc/systemd/system/"
  echo openssl > "$FR/usr/bin/openssl"; echo wg > "$FR/usr/bin/wg"; echo jdk > "$FR/usr/lib/jvm/java-11-openjdk-amd64/release"; echo jvm > "$FR/etc/java-11-openjdk/jvm.cfg"; echo fp > "$FR/etc/tc/java-ca-fingerprints.txt"; echo conf > "$FR/opt/hadoop/etc/hadoop/core-site.xml"
  echo job > "$FR/opt/tc/nutch/apache-nutch-1.22.job"
  cat > "$FR/opt/tc/nutch/bin/crawl" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; echo "$*" > "$SD/crawl.args"; [ -f "$SD/crawl_fails" ] && { echo "stand-in crawl failure"; exit 1; }; echo "stand-in crawl ran"; exit 0
EOS
  cat > "$FR/opt/tc/nutch/bin/nutch" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; F="$(cat "$SD/fetched" 2>/dev/null || echo 3)"; printf 'CrawlDb statistics start: /tc/crawl/crawldb\nTOTAL urls:\t7\nstatus 1 (db_unfetched):\t4\nstatus 2 (db_fetched):\t%s\n' "$F"
EOS
  cat > "$FR/opt/hadoop/bin/hdfs" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"; [ "$1" = dfsadmin ] && { [ -f "$SD/hdfs_down" ] && exit 1; echo "Name: 10.10.0.2:9866 (tc-w)"; exit 0; }   # the driver counts the live DataNodes (-report) and waits out safe mode
shift
case "$1" in
  -ls) if [ "$2" = / ]; then [ -f "$SD/hdfs_down" ] && exit 1; exit 0; fi; [ -f "$SD/no_segments" ] && exit 0; printf 'drwxr-xr-x - hadoop supergroup 0 2026-10-20 %s/20261020100000\ndrwxr-xr-x - hadoop supergroup 0 2026-10-20 %s/20261020100500\n' "$2" "$2" ;;
  -rm) ;; -mkdir) ;; -put) echo "$*" > "$SD/hdfs.put" ;;
  -test) [ -f "$SD/no_crawldb" ] && exit 1; exit 0 ;;
esac
exit 0
EOS
  printf '#!/usr/bin/env bash\n[ -f "${FAKE_SD:?}/yarn_down" ] && exit 0\nprintf "Total Nodes:1\\n Node-Id Node-State Node-Http-Address\\n localhost:33563 RUNNING localhost:8042 0\\n"\n' > "$FR/opt/hadoop/bin/yarn"
  chmod +x "$FR"/opt/hadoop/bin/* "$FR"/opt/tc/nutch/bin/*
  mkdir -p "$FR/etc/tc/crawl"; cp "$I/rootfs/etc/tc/crawl/seeds.txt" "$I/rootfs/etc/tc/crawl/params.env" "$FR/etc/tc/crawl/"; printf '{"version":2}' > "$FR/etc/tc/crawl/collection-policy.json"
  mkdir -p "$FR/usr/lib/jvm/java-11-openjdk-amd64/bin"; printf '#!/usr/bin/env bash\n[ -f "${FAKE_SD:?}/keytool_fails" ] && exit 1\nprintf -- "-----BEGIN CERTIFICATE-----\\nQUJD\\n-----END CERTIFICATE-----\\n-----BEGIN CERTIFICATE-----\\nREVG\\n-----END CERTIFICATE-----\\n"\n' > "$FR/usr/lib/jvm/java-11-openjdk-amd64/bin/keytool"; chmod +x "$FR/usr/lib/jvm/java-11-openjdk-amd64/bin/keytool"; }
drv() { out="$(env TC_ROOT="$FR" TC_MARK="$W/mark/done" TC_LOG="$W/crawl.log" TC_POLL=1 FAKE_SD="$SD" bash "${DRV:-$I/rootfs/usr/local/lib/tc/tc-crawl.sh}" "$@" 2>&1)"; rc=$?; }
# ---------------------------------------------------------------- A. the driver
echo "=== A. the crawl driver"
mkroot; drv --check-params; chk "--check-params validates the real parameters and seeds and prints a summary" $([ $rc = 0 ] && grep -q 'the parameters and the 2 seeds are valid (rounds 3' <<<"$out"; echo $?)
mkroot; drv; echo "$out" | tail -2 | cut -c1-120
chk "happy path: exit 0, the marker is written, and the log says done" $([ $rc = 0 ] && [ -s "$W/mark/done" ] && grep -q 'fetched=3 segments=2 rounds=3' "$W/mark/done" && grep -q 'done: 3 urls fetched, 2 segments' <<<"$out"; echo $?)
chk "Nutch's crawl script is called with exactly the parameters of the earlier runs, from params.env" $([ "$(cat "$SD/crawl.args")" = "-s /tc/seeds --num-fetchers 1 --num-tasks 1 --size-fetchlist 4 --num-threads 2 --time-limit-fetch 10 -D mapreduce.map.memory.mb=2048 -D mapreduce.map.java.opts=-Xmx1536m -D mapreduce.reduce.memory.mb=2048 -D mapreduce.reduce.java.opts=-Xmx1536m -D http.agent.name=training-custody-test-bot -D http.agent.url=https://github.com/Heron-AI-Security -D warc.export.software=Apache-Nutch-CommonCrawl-fork-training-custody -D fetcher.store.warc=true -D warc.export.path=/tc/warc -D tc.receipts.enabled=true -D tc.policy.file=/etc/tc/crawl/collection-policy.json -D tc.binding=tc-fleet-rtmr3/1 /tc/crawl 3" ]; echo $?)
chk "the seeds were put into HDFS before the crawl" $(grep -q 'seeds.txt /tc/seeds/seeds.txt' "$SD/hdfs.put"; echo $?)
echo "--- faults of the driver"
bad() { local label="$1" want="$2"; drv; chk "fault: $label" $([ $rc != 0 ] && grep -q "FAILED: .*$want" <<<"$out" && [ ! -e "$W/mark/done" ]; echo $?); }
mkroot; echo 'ROUNDS=3; touch /tmp/f03c-pwned' >> "$FR/etc/tc/crawl/params.env"; rm -f /tmp/f03c-pwned; bad "a params line with a command in it is refused and NOT executed" "not KEY=VALUE"; chk "control: nothing from the params file was executed" $([ ! -e /tmp/f03c-pwned ]; echo $?)
mkroot; echo 'ROUNDS=$(touch /tmp/f03c-pwned2)' >> "$FR/etc/tc/crawl/params.env"; rm -f /tmp/f03c-pwned2; bad "a command substitution in the params file is refused" "not KEY=VALUE"; chk "control: no command substitution was run" $([ ! -e /tmp/f03c-pwned2 ]; echo $?)
mkroot; grep -v '^ROUNDS=' "$FR/etc/tc/crawl/params.env" > "$W/p" && cp "$W/p" "$FR/etc/tc/crawl/params.env"; bad "a required key is missing" "lacks ROUNDS"
mkroot; sed -i 's/^ROUNDS=3/ROUNDS=three/' "$FR/etc/tc/crawl/params.env"; bad "a number is not a number" "must be a number"
mkroot; sed -i 's#^HDFS_CRAWL_DIR=/tc/crawl#HDFS_CRAWL_DIR=tc/crawl#' "$FR/etc/tc/crawl/params.env"; bad "an HDFS path is not absolute" "absolute HDFS path"
mkroot; echo 'file:///etc/passwd' >> "$FR/etc/tc/crawl/seeds.txt"; bad "a seed is not an http or https address" "not a plain http"
mkroot; : > "$FR/etc/tc/crawl/seeds.txt"; bad "the seed file is empty" "no seeds"
mkroot; touch "$SD/hdfs_down"; sed -i 's/^WAIT_FOR_CLUSTER_SECONDS=600/WAIT_FOR_CLUSTER_SECONDS=2/' "$FR/etc/tc/crawl/params.env"; bad "HDFS never answers" "were not ready within 2 seconds"
mkroot; touch "$SD/yarn_down"; sed -i 's/^WAIT_FOR_CLUSTER_SECONDS=600/WAIT_FOR_CLUSTER_SECONDS=2/' "$FR/etc/tc/crawl/params.env"; bad "no NodeManager is RUNNING" "were not ready within 2 seconds"
mkroot; touch "$SD/crawl_fails"; bad "Nutch's crawl script fails" "crawl script failed"
mkroot; echo 1 > "$SD/fetched"; bad "fewer urls were fetched than required" "only 1 urls are db_fetched"
mkroot; touch "$SD/no_segments"; bad "no segment was written" "no segment was written"
mkroot; rm "$FR/etc/tc/crawl/collection-policy.json"; bad "the image has no collection policy for the receipts" "no collection policy"
# ---------------------------------------------------------------- B. the bake
echo "=== B. the bake script"
bake() { out="$(env TC_ROOT="$FR" TC_SUDO="" FAKE_SD="$SD" bash "$I/build/tc-image-crawl.sh" "${BKIT:-$KIT}" 2>&1)"; rc=$?; }
mkroot; rm -rf "$FR/etc/tc/crawl" "$FR/usr/local/lib/tc/units"; mkdir -p "$FR/usr/local/lib/tc/units"; bake; echo "$out" | tail -2 | cut -c1-110
chk "happy path: exit 0 and READY" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
chk "the driver, the parameters, the seeds and the unit are installed, the driver is executable, and the parameters were validated" $([ -x "$FR/usr/local/lib/tc/tc-crawl.sh" ] && [ -f "$FR/etc/tc/crawl/params.env" ] && [ -f "$FR/etc/tc/crawl/seeds.txt" ] && [ -f "$FR/usr/local/lib/tc/units/tc-crawl.service" ] && grep -q 'the parameters and the 2 seeds are valid' <<<"$out"; echo $?)
chk "the collection policy is made from the image's JDK CA store, in canonical form, with its 2 anchors and their set hash" $(python3 -c '
import json, sys, hashlib
b = open(sys.argv[1], "rb").read(); p = json.loads(b); ders = sorted(hashlib.sha256(x).hexdigest() for x in (b"ABC", b"DEF"))
enc = lambda v: json.dumps(v, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()
sys.exit(0 if enc(p) == b and p["trust_anchors"]["count"] == 2 and p["trust_anchors"]["anchor_set_sha256"] == "sha256:" + hashlib.sha256(enc(ders)).hexdigest() else 1)' "$FR/etc/tc/crawl/collection-policy.json"; echo $?)
chk "the unit is enabled from the measured folder and systemd reads it cleanly" $(grep -q "^enable .*usr/local/lib/tc/units/tc-crawl.service" "$SD/systemctl.log" && grep -q 'systemd reads it without an unknown key' <<<"$out"; echo $?)
chk "the measured list has 13 entries, ending with crawl-params and crawl-seeds" $(grep -q 'TC-LIST-OK: 13 entries' <<<"$out" && [ "$(awk -F'\t' '!/^#/ && NF>=2 {print $1}' "$FR/etc/tc/measured-paths.txt" | tail -2 | tr '\n' ' ')" = "crawl-params crawl-seeds " ]; echo $?)
abortb() { local label="$1" want="$2"; bake; chk "fault: $label" $([ $rc != 0 ] && grep -q "ABORT: .*$want" <<<"$out"; echo $?); }
mkroot; rm -f "$FR/opt/tc/nutch/bin/crawl"; abortb "the job is not in place" "run tc-image-job.sh first"
mkroot; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; rm -f "$W/badkit/ops/image/rootfs/usr/local/lib/tc/units/tc-crawl.service"; BKIT="$W/badkit" abortb "the unit is missing from the kit" "missing in"
mkroot; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; echo 'ROUNDS=3; rm -rf /' >> "$W/badkit/ops/image/rootfs/etc/tc/crawl/params.env"; BKIT="$W/badkit" abortb "the parameters in the kit are refused by the driver" "refuses the parameters"
mkroot; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; echo 'if then fi done' >> "$W/badkit/ops/image/rootfs/usr/local/lib/tc/tc-crawl.sh"; BKIT="$W/badkit" abortb "the driver has a syntax error" "syntax error"
mkroot; touch "$SD/enable_fails"; abortb "the unit cannot be enabled" "could not enable"
mkroot; touch "$SD/keytool_fails"; abortb "the JDK CA store cannot be read: no policy, no image" "could not make the collection policy"
mkroot; touch "$SD/analyze_warns"; abortb "systemd reports a key of OUR unit in the wrong section" "systemd does not understand"
mkroot; touch "$SD/analyze_noise"; bake; chk "Ubuntu's own snapd warning does not stop the bake" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
rm -rf "$W/badkit"
echo "--- the unit file, read SECTION BY SECTION (a key in the wrong section is ignored by systemd)"
UV="$W/unitcheck.py"; cat > "$UV" <<'PYEOF'
import re, sys
ALLOWED = {"Unit": {"Description", "Requires", "After", "Wants", "Before"}, "Service": {"Type", "RemainAfterExit", "User", "Group", "Environment", "WorkingDirectory", "ExecStart", "NoNewPrivileges", "ProtectHome", "ProtectSystem", "PrivateTmp", "StateDirectory", "TimeoutStartSec"}, "Install": {"WantedBy"}}
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
U="$I/rootfs/usr/local/lib/tc/units/tc-crawl.service"; python3 "$UV" "$U" > "$W/u.keys" 2>&1; chk "every key of tc-crawl.service is in a section where systemd reads it" $?
chk "its skip condition is in [Unit], it requires and follows the measurement and all four daemons, runs as hadoop, and has a time limit" $(grep -q '^Unit ConditionPathExists !/var/lib/tc-crawl/done' "$W/u.keys" && ! grep -q '^Service Condition' "$W/u.keys" && grep -q '^Unit Requires tc-measure.service tc-namenode.service tc-datanode.service tc-resourcemanager.service tc-nodemanager.service' "$W/u.keys" && grep -q '^Unit After tc-measure.service tc-namenode.service tc-datanode.service tc-resourcemanager.service tc-nodemanager.service' "$W/u.keys" && grep -q '^Service User hadoop' "$W/u.keys" && grep -q '^Service TimeoutStartSec 3600' "$W/u.keys" && grep -q '^Service StateDirectory tc-crawl' "$W/u.keys"; echo $?)
cp "$U" "$W/bad.service"; python3 - "$W/bad.service" <<'PYEOF'
import sys; p = sys.argv[1]; s = open(p).read(); s = s.replace("ConditionPathExists=!/var/lib/tc-crawl/done\n", "", 1).replace("Type=oneshot\n", "Type=oneshot\nConditionPathExists=!/var/lib/tc-crawl/done\n", 1); open(p, "w").write(s)
PYEOF
python3 "$UV" "$W/bad.service" > "$W/bad.out" 2>&1; chk "fault: the mistake of the first image (the condition under [Service]) is caught here too" $([ $? != 0 ] && grep -q 'ConditionPathExists in \[Service\]' "$W/bad.out"; echo $?)
# ---------------------------------------------------------------- C. the check
echo "=== C. the check after a boot"
mkroot; mkdir -p "$W/state" "$W/outd"; echo 1 > "$W/state/bootcount"; mkdir -p "$W/mark"
printf '#!/usr/bin/env bash\nif [ -f "${FAKE_SD:?}/f03b_fail" ]; then echo "   FAIL: stand-in failure of the F0.3b checks"; echo "F03B-CHECK-FAILED (1) boot=1"; exit 1; fi\necho "   info: the measurement took 12 s"\necho "F03B-CHECK-OK boot=1"\n' > "$W/f03b-stub.sh"
printf 'crawl done 2026-10-20T10:00:00Z fetched=3 segments=2 rounds=3\n' > "$W/mark/done"; echo "log line one" > "$FR/var/log/hadoop/tc-crawl.log"
check() { out="$(env TC_ROOT="$FR" TC_STATE="$W/state" TC_OUT="$W/outd" TC_F03B="$W/f03b-stub.sh" TC_MARK="$W/mark/done" TC_CRAWL_WAIT="${CWAIT:-4}" TC_POLL=1 FAKE_SD="$SD" bash "$I/test/f03c-check.sh" 2>&1)"; rc=$?; }
clearflags() { rm -f "$SD"/*.ActiveState "$SD"/*.Result "$SD"/*.ConditionResult "$SD"/*.start "$SD"/*.exit "$SD"/fetched "$SD"/no_crawldb "$SD"/no_segments "$SD"/f03b_fail; printf 'crawl done 2026-10-20T10:00:00Z fetched=3 segments=2 rounds=3\n' > "$W/mark/done"; echo "log line one" > "$FR/var/log/hadoop/tc-crawl.log"; }
check; echo "$out" | tail -2 | cut -c1-100
chk "first boot, happy path: exit 0 and F03C-CHECK-OK" $([ $rc = 0 ] && grep -q '^F03C-CHECK-OK boot=1' <<<"$out"; echo $?)
chk "the report names the success, the start order, the marker, the database, the fetched urls and the segments" $(grep -q 'ended with the result success' <<<"$out" && grep -q 'started after the measurement finished and after the four daemons' <<<"$out" && grep -q 'the marker exists: crawl done' <<<"$out" && grep -q 'holds 3 fetched urls (at least 2 are required; 7 urls in all)' <<<"$out" && grep -q '2 segments were written' <<<"$out"; echo $?)
chk "the F0.3b part's info line is shown and the crawl's log and statistics are saved as evidence" $(grep -q 'info: the measurement took 12 s' <<<"$out" && [ -s "$W/outd/f03c-boot1-crawl.log" ] && [ -s "$W/outd/f03c-boot1-readdb.txt" ]; echo $?)
echo activating > "$SD/tc-crawl.service.ActiveState"; (sleep 3; echo inactive > "$SD/tc-crawl.service.ActiveState") & out="$(env TC_ROOT="$FR" TC_STATE="$W/state" TC_OUT="$W/outd" TC_F03B="$W/f03b-stub.sh" TC_MARK="$W/mark/done" TC_CRAWL_WAIT=30 TC_POLL=1 TC_BEAT=2 FAKE_SD="$SD" bash "$I/test/f03c-check.sh" 2>&1)"; wait; chk "while the crawl runs, the check prints a progress line at every beat (so an idle ssh session is not dropped)" $(grep -q "still waiting for the crawl that systemd started (2 s, state activating)" <<<"$out"; echo $?); clearflags
echo skipped-case > /dev/null; echo no > "$SD/tc-crawl.service.ConditionResult"; check; chk "a later boot: the unit is skipped because the marker exists, and that passes" $([ $rc = 0 ] && grep -q 'skipped because the crawl was done on an earlier boot' <<<"$out"; echo $?); clearflags
fault() { local label="$1" want="$2"; check; chk "fault: $label" $([ $rc != 0 ] && grep -q "FAIL: .*$want" <<<"$out" && grep -q '^F03C-CHECK-FAILED' <<<"$out"; echo $?); clearflags; }
echo activating > "$SD/tc-crawl.service.ActiveState"; CWAIT=2 fault "the crawl is still running when the wait ends" "was still running"
echo failed > "$SD/tc-crawl.service.Result"; fault "the unit ended with a failure" "result 'failed'"
echo 4000000 > "$SD/tc-crawl.service.start"; fault "the crawl started BEFORE the measurement finished" "did not start after the measurement"
echo 12000000 > "$SD/tc-nodemanager.service.start"; echo 11000000 > "$SD/tc-crawl.service.start"; fault "the crawl started before the last daemon" "did not start after the measurement and the daemons"
rm -f "$W/mark/done"; fault "the marker file is missing" "no marker file"
touch "$SD/no_crawldb"; fault "there is no crawl database in HDFS" "no crawl database"
echo 1 > "$SD/fetched"; fault "fewer urls fetched than required" "only 1 urls are db_fetched"
touch "$SD/no_segments"; fault "no segment in HDFS" "no segment"
rm -f "$FR/var/log/hadoop/tc-crawl.log"; fault "the crawl's log is missing" "no crawl log"
touch "$SD/f03b_fail"; fault "the checks of step F0.3b fail" "did not pass"
echo no > "$SD/tc-crawl.service.ConditionResult"; rm -f "$W/mark/done"; fault "the unit was skipped but there is no marker" "no marker file"
echo; echo "pass: $PASS   fail: $FAILN"
if [ "$FAILN" = 0 ]; then echo "REHEARSAL-PASS: the real crawl driver, bake script, unit file and check of step F0.3c pass against stand-ins, and every fault is refused; $PASS checks"; else echo "REHEARSAL-FAIL"; fi
[ "$FAILN" = 0 ]
REHEARSAL_END_MARK=1
