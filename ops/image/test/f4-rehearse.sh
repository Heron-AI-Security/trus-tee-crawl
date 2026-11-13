#!/usr/bin/env bash
# Rehearsal of phase 4 (F0.4, F0.5, F0.6) with stand-ins: the lock script in both modes against a fake machine, the refusal of forbidden paths by the measurement, the self-report,
# and the firewall files. Every check that matters is also made to FAIL on purpose.      bash f4-rehearse.sh KITDIR
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; echo "${out:-}" | tail -4 | sed "s/^/        | /"; fi; }
W="$(mktemp -d)"; STUB="$W/bin"; mkdir -p "$STUB"; SD="$W/sd"; mkdir -p "$SD"; export FAKE_SD="$SD"
cat > "$STUB/dpkg" <<'EOS'
#!/usr/bin/env bash
[ "$1" = "-s" ] && grep -qx "$2" "$FAKE_SD/installed" 2>/dev/null; exit $?
EOS
cat > "$STUB/apt-get" <<'EOS'
#!/usr/bin/env bash
echo "apt-get $*" >> "$FAKE_SD/apt.log"
if [ "$1" = "purge" ] || [ "$2" = "purge" ]; then [ -f "$FAKE_SD/purge_fails" ] && exit 0; shift; for a in "$@"; do case "$a" in -*|DEBIAN_FRONTEND*|env|purge) ;; *) grep -vx "$a" "$FAKE_SD/installed" > "$FAKE_SD/installed.new" 2>/dev/null; mv "$FAKE_SD/installed.new" "$FAKE_SD/installed" ;; esac; done; fi
exit 0
EOS
cat > "$STUB/systemctl" <<'EOS'
#!/usr/bin/env bash
echo "systemctl $*" >> "$FAKE_SD/sc.log"; case "$1" in is-enabled) echo masked ;; is-active) echo active ;; show) echo success ;; --failed) for u in ${FAKE_FAILED:-}; do case "$*" in *--plain*) printf "%s loaded failed failed %s\\n" "$u" "$u" ;; *) printf "● %s loaded failed failed %s\\n" "$u" "$u" ;; esac; done ;; esac; exit 0
EOS
printf '#!/usr/bin/env bash\necho "nft $*" >> "$FAKE_SD/nft.log"\ncase "$*" in "list chain inet tc input") echo "chain input { type filter hook input priority 0; policy drop; }" ;; "list ruleset") echo "table inet tc {}" ;; esac\nexit 0\n' > "$STUB/nft"
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/netplan"; printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/systemd-analyze"
printf '#!/usr/bin/env bash\ncase "$1" in -ltnH) printf "LISTEN 0 4096 10.10.0.1:9000 0.0.0.0:*\\nLISTEN 0 4096 0.0.0.0:13562 0.0.0.0:*\\n" ;; esac\n' > "$STUB/ss"
printf '#!/usr/bin/env bash\nfor a in "$@"; do p="$a"; done\n[ "${FAKE_FINDMNT:-}" = empty ] && exit 0\ncase " ${FAKE_RO_TREES-usr etc opt boot root} " in *" ${p#/} "*) echo "ro,relatime" ;; *) echo "rw,relatime,lowerdir=/x" ;; esac\n' > "$STUB/findmnt"
printf '#!/usr/bin/env bash\ncase "$1" in genkey|pubkey) echo x ;; show) [ "$3" = peers ] && echo peer1 ;; esac\n' > "$STUB/wg"
cat > "$STUB/curl" <<'EOS'
#!/usr/bin/env bash
SDD="$FAKE_SD"; put=0; file=""; url="${@: -1}"; for a in "$@"; do case "$a" in PUT) put=1 ;; @*) file="${a#@}" ;; esac; done
if [ $put = 1 ]; then cp "$file" "$SDD/put.$(basename "$url")"; exit 0; fi
case "$url" in */instance/name) echo tc-f1-m ;; */instance/image) echo projects/p/global/images/tc-img-lock-1 ;; *) exit 22 ;; esac
EOS
chmod +x "$STUB"/*; export PATH="$STUB:$PATH"
mkroot() { rm -rf "$W/r" "$SD"/*; mkdir -p "$SD"; R="$W/r"; for d in usr/local/lib/tc/units etc/tc/crawl etc/tc/fleet-props etc/systemd/system etc/netplan etc/cloud usr/bin usr/lib/jvm/java-11-openjdk-amd64 etc/java-11-openjdk opt/hadoop/etc/hadoop opt/tc/nutch usr/sbin; do mkdir -p "$R/$d"; done
  cp "$I"/rootfs/usr/local/lib/tc/tc-measure.sh "$I"/rootfs/usr/local/lib/tc/tc-extend.sh "$KIT/attest/measure/treehash.sh" "$R/usr/local/lib/tc/"; printf '#!/bin/sh\n' > "$R/usr/local/lib/tc/tc-fleet.sh"; chmod +x "$R"/usr/local/lib/tc/*
  echo o > "$R/usr/bin/openssl"; echo w > "$R/usr/bin/wg"; echo j > "$R/usr/lib/jvm/java-11-openjdk-amd64/release"; echo c > "$R/etc/java-11-openjdk/jvm.cfg"; echo f > "$R/etc/tc/java-ca-fingerprints.txt"; echo "commit cafe0000cafe0000cafe0000cafe0000cafe0000" > "$R/etc/tc/source.txt"; echo x > "$R/opt/hadoop/etc/hadoop/core-site.xml"; echo job > "$R/opt/tc/nutch/job"
  echo p > "$R/etc/tc/crawl/params.env"; echo s > "$R/etc/tc/crawl/seeds.txt"; echo t > "$R/etc/systemd/system/tc-measure.service"; echo cf > "$R/etc/tc/fleet-props/core-site.props"; cp "$I/rootfs/etc/tc/measured-paths-f1.txt" "$R/etc/tc/measured-paths.txt"
  printf 'openssh-server\nopenssh-sftp-server\ngoogle-guest-agent\ngoogle-osconfig-agent\ngoogle-compute-engine-oslogin\n' > "$SD/installed"; }
lock() { out="$(env TC_ROOT="$R" TC_SUDO="" TC_NO_APT=1 TC_NO_NETPLAN=1 TC_NO_NFT=1 bash "$I/build/tc-image-lock.sh" "$1" "${KITX:-$KIT}" 2>&1)"; rc=$?; }
echo "=== A. the debug image"
mkroot; lock debug
chk "debug: exit 0 and READY" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
chk "debug: the firewall file is the one with port 22, the forbidden list has no entry, the mode is recorded" $(grep -q 'tcp dport 22 accept' "$R/etc/nftables.conf" && ! grep -qv '^#' "$R/etc/tc/forbidden-paths.txt" && [ "$(cat $R/etc/tc/image-mode)" = debug ]; echo $?)
chk "debug: nothing is purged and nothing is masked, and the host-key unit is enabled" $(! grep -q 'purge' "$SD/apt.log" 2>/dev/null && ! grep -q ' mask ' "$SD/sc.log" && grep -q 'enable .*tc-ssh-hostkeys.service' "$SD/sc.log"; echo $?)
# Work item, change 2: the events that the image measures at boot. The root hash (RTMR2) already covers every other file of the image; fleet, fleet-conf and export are extended at run time and are not in the list.
EXPECT_EVENTS="${EXPECT_EVENTS:-source crawl-params crawl-seeds}"; DROPPED_EVENTS="tc-lib tc-conf tc-units openssl wg jdk java-settings java-ca-fingerprints hadoop-code hadoop-conf nutch-deploy fleet-props firewall"
evlist() { awk -F'\t' '!/^#/ && NF>=2 {print $1}' "$R/etc/tc/measured-paths.txt" | tr '\n' ' ' | sed 's/ $//'; }
chk "the measured list has exactly the agreed events, in order ($EXPECT_EVENTS), and the check of the list accepts that many entries" $([ "$(evlist)" = "$EXPECT_EVENTS" ] && grep -q "TC-LIST-OK: $(wc -w <<<"$EXPECT_EVENTS" | tr -d ' ') entries" <<<"$out"; echo $?)
chk "none of the 13 image-fixed events that the root hash already covers is in the list any more (they are dropped unless the agreed list keeps them)" $(ok=0; for e in $DROPPED_EVENTS; do case " $EXPECT_EVENTS " in *" $e "*) continue;; esac; [ "$(tr ' ' '\n' <<<"$(evlist)" | grep -cx "$e")" = 0 ] || ok=1; done; echo $ok)
chk "cloud-init is off and its network file is gone, replaced by a generic one that matches any wired card (mode 600)" $([ -f "$R/etc/cloud/cloud-init.disabled" ] && [ ! -e "$R/etc/netplan/50-cloud-init.yaml" ] && [ "$(stat -c %a $R/etc/netplan/60-tc-dhcp.yaml)" = 600 ] && grep -q 'name: "en\*"' "$R/etc/netplan/60-tc-dhcp.yaml"; echo $?)
echo "=== B. the locked image"
mkroot; lock locked
chk "locked: exit 0 and READY" $([ $rc = 0 ] && grep -q '^READY' <<<"$out"; echo $?)
chk "locked: the same agreed measured list is installed (the list file is shared by both modes)" $([ "$(evlist)" = "$EXPECT_EVENTS" ] && grep -q "TC-LIST-OK: $(wc -w <<<"$EXPECT_EVENTS" | tr -d ' ') entries" <<<"$out"; echo $?)
chk "locked: the firewall file has NO port 22, and drops by default, and lets only wg0 and the WireGuard port in" $(! grep -q 'dport 22' "$R/etc/nftables.conf" && grep -q 'policy drop' "$R/etc/nftables.conf" && grep -q 'iifname "wg0" accept' "$R/etc/nftables.conf" && grep -q 'udp dport 51820 accept' "$R/etc/nftables.conf"; echo $?)
chk "locked: the login packages are purged (sshd, sftp, guest agent, osconfig agent, OS Login) and the login prompts of the serial console and the screen are masked" $(grep -q 'purge -y .*openssh-server' "$SD/apt.log" && grep -q 'google-guest-agent' "$SD/apt.log" && grep -q 'google-compute-engine-oslogin' "$SD/apt.log" && grep -q 'mask serial-getty@ttyS0.service' "$SD/sc.log" && grep -q 'getty@tty1.service' "$SD/sc.log"; echo $?)
chk "locked: the two GRUB bookkeeping units (grub-common, grub-initrd-fallback) are masked: they only write flags into /boot/grub/grubenv, which is a read-only bind in a locked image, and they failed on the first real boot of the lock" $(grep -q 'mask grub-common.service grub-initrd-fallback.service' "$SD/sc.log" && grep -q 'masked, because they only keep the GRUB flags' <<<"$out"; echo $?)
chk "locked: the forbidden list names sshd and the guest agent, and the mode is recorded" $(grep -q '^/usr/sbin/sshd$' "$R/etc/tc/forbidden-paths.txt" && grep -q 'google_guest_agent' "$R/etc/tc/forbidden-paths.txt" && [ "$(cat $R/etc/tc/image-mode)" = locked ]; echo $?)
chk "the two images have different firewall files and different forbidden lists, so their measurements differ" $(! cmp -s "$I/rootfs/etc/tc/nftables-locked.conf" "$I/rootfs/etc/tc/nftables-debug.conf" && ! cmp -s "$I/rootfs/etc/tc/forbidden-paths-locked.txt" "$I/rootfs/etc/tc/forbidden-paths-debug.txt"; echo $?)
mkroot; touch "$SD/purge_fails"; lock locked; chk "fault: if a package cannot be removed, the bake ABORTS (it does not make a locked image that has a login)" $([ $rc != 0 ] && grep -q 'ABORT: .*still installed' <<<"$out"; echo $?)
mkroot; : > "$SD/installed"; mkdir -p "$R/usr/sbin"; echo sshd > "$R/usr/sbin/sshd"; lock locked; chk "fault: a package list that says 'not installed' but an sshd file on disk: the forbidden-path check ABORTS the bake" $([ $rc != 0 ] && grep -q 'a forbidden path exists: /usr/sbin/sshd' <<<"$out"; echo $?)
mkroot; rm -f "$R/usr/local/lib/tc/tc-fleet.sh"; lock locked; chk "fault: the fleet flow is not in place" $([ $rc != 0 ] && grep -q 'ABORT: the fleet flow is not in place' <<<"$out"; echo $?)
mkroot; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; rm -f "$W/badkit/ops/image/rootfs/etc/tc/nftables-locked.conf"; KITX="$W/badkit" lock locked; KITX=""; chk "fault: the firewall file is missing from the kit" $([ $rc != 0 ] && grep -q 'ABORT: missing in' <<<"$out"; echo $?)
mkroot; lock sideways; chk "fault: an unknown mode" $([ $rc != 0 ] && grep -q 'usage' <<<"$out"; echo $?)
echo "=== C. the measurement refuses forbidden paths at every boot"
mkroot; cp "$I/rootfs/etc/tc/measured-paths-f1.txt" "$R/etc/tc/measured-paths.txt"; printf '# a comment\n\n/usr/sbin/sshd\n' > "$W/forbid.txt"
run_measure() { out="$(env TC_ROOT="$R" TC_LIST="$R/etc/tc/measured-paths.txt" TC_FORBID="$1" TC_LIB="$R/usr/local/lib/tc" TC_RUN="$W/run" TC_STATE="$W/state" bash "$I/rootfs/usr/local/lib/tc/tc-measure.sh" --check-list 2>&1)"; rc=$?; }
run_measure "$W/forbid.txt"; chk "control: with none of the forbidden paths on disk the list check passes (comments and blank lines are ignored)" $([ $rc = 0 ] && grep -q 'TC-LIST-OK' <<<"$out"; echo $?)
echo sshd > "$R/usr/sbin/sshd"; run_measure "$W/forbid.txt"; chk "an sshd on disk: the measurement STOPS, and names the path (so no daemon starts)" $([ $rc != 0 ] && grep -q 'TC-MEASURE-FAIL: a forbidden path exists: /usr/sbin/sshd' <<<"$out"; echo $?)
rm -f "$R/usr/sbin/sshd"; ln -s /nonexistent "$R/usr/sbin/sshd"; run_measure "$W/forbid.txt"; chk "even a dangling link at the forbidden path stops it" $([ $rc != 0 ] && grep -q 'forbidden path exists' <<<"$out"; echo $?)
rm -f "$R/usr/sbin/sshd"; echo sshd > "$R/usr/sbin/sshd"; run_measure "$I/rootfs/etc/tc/forbidden-paths-debug.txt"; chk "the DEBUG image's empty list lets the same disk pass" $([ $rc = 0 ]; echo $?)
echo "=== D. the self-report"
mkroot; mkdir -p "$W/run4"; echo locked > "$W/mode"; out="$(env TC_RUN="$W/run4" TC_REPORT_ONCE=1 TC_MODE_FILE="$W/mode" bash "$I/rootfs/usr/local/lib/tc/tc-report.sh" 2>&1)"; rc=$?
chk "one report is made, printed with its markers (for the serial console), and published as the guest attribute tc/report" $([ $rc = 0 ] && grep -q 'TC-REPORT-BEGIN' <<<"$out" && grep -q 'TC-REPORT-END' <<<"$out" && [ -s "$SD/put.report" ]; echo $?)
chk "it says the name, the image, the mode, whether login is installed, the port 22 count, the serial login prompt, the firewall policy, the units and the listeners" $(for k in 'name=tc-f1-m' 'hostname=' 'image=tc-img-lock-1' 'mode=locked' 'openssh_server_installed=' 'guest_agent_installed=' 'oslogin_installed=' 'port22_listening=0' 'serial_getty=masked' 'input_policy=policy drop' 'unit_tc-fleet=active/success' 'unit_tc-namenode=' 'unit_tc-crawl=' 'wg_peers=1' 'listeners=0.0.0.0:13562 10.10.0.1:9000'; do grep -qF "$k" "$SD/put.report" || { echo 1; exit; }; done; echo 0)
echo "=== E. the units"
# Work item, change 1: a locked VM has no login, so the reason of a failure must be in the report
mkroot; mkdir -p "$W/run7" "$W/hlogs"; printf '2026-11-12T14:20:20Z tc-crawl: round 1 started\n2026-11-12T14:31:02Z tc-crawl: FAILED: HDFS (with a live DataNode per worker) and YARN were not ready within 600 s\n' > "$W/crawl.log"
printf '2026-11-12 14:20:30 INFO DataNode: started\n2026-11-12 14:21:10 ERROR DataNode: Problem connecting to server: tc-f1-m:9000\n2026-11-12 14:21:20 INFO DataNode: retrying\n2026-11-12 14:21:30 WARN DataNode: slow\n' > "$W/hlogs/hadoop-hadoop-datanode-x.log"
env FAKE_FAILED="tc-crawl.service tc-fleet.service" TC_CRAWL_LOG="$W/crawl.log" TC_HADOOP_LOGS="$W/hlogs" TC_RUN="$W/run7" TC_REPORT_ONCE=1 TC_MODE_FILE="$W/mode" bash "$I/rootfs/usr/local/lib/tc/tc-report.sh" > /dev/null 2>&1
chk "the failed units are named (a bullet is not a name), and no bullet is in the report" $(grep -qx "failed_units=tc-crawl.service,tc-fleet.service," "$W/run7/report.txt" && ! grep -q "●" "$W/run7/report.txt"; echo $?)
chk "the report carries the last line of the crawl log, on one line" $(grep -qx "crawl_last=2026-11-12T14:31:02Z tc-crawl: FAILED: HDFS (with a live DataNode per worker) and YARN were not ready within 600 s" "$W/run7/report.txt"; echo $?)
chk "the report carries the last ERROR or FATAL line of the Hadoop logs (not a later INFO or WARN line)" $(grep -qx "hadoop_last_error=2026-11-12 14:21:10 ERROR DataNode: Problem connecting to server: tc-f1-m:9000" "$W/run7/report.txt"; echo $?)
chk "control: with no failed unit, no crawl log and no Hadoop log the three fields are empty, and the report is still made" $(grep -qx "failed_units=" "$W/run4/report.txt" && grep -qx "crawl_last=" "$W/run4/report.txt" && grep -qx "hadoop_last_error=" "$W/run4/report.txt"; echo $?)
chk "the report stays far below the 4096 bytes that a guest attribute may hold, also with the new lines at full length" $([ "$(wc -c < "$W/run7/report.txt")" -lt 2800 ]; echo $?)
# the early check in the driver: a wrong image is found at once, a right image goes on to wait for the crawl
mkdir -p "$W/gc2" "$W/lc2/out"; cat > "$W/gc2/gcloud" <<'EOS'
#!/usr/bin/env bash
case "$*" in *get-guest-attributes*) vm="$(sed -n 's/.*get-guest-attributes \([^ ]*\) .*/\1/p' <<<"$*")"; cat "$LC_DIR/$vm.txt" ;; *"compute ssh"*) exit 1 ;; *get-serial-port-output*) echo TC-REPORT-BEGIN ;; esac; exit 0
EOS
chmod +x "$W/gc2/gcloud"; printf '# tc-fleet v1\ntc-f1-m\tmaster\t10.10.0.1\t1.2.3.4:51820\tk1\ttc-f1-w\ntc-f1-w\tworker\t10.10.0.2\t1.2.3.5:51820\tk2\n' > "$W/lc2/out/fleet.tsv"; FS="$(sha384sum "$W/lc2/out/fleet.tsv" | cut -d' ' -f1)"
mkr() { printf 'name=%s\nhostname=%s\nmode=locked\nimage=x\ninput_policy=policy drop\nnft_rules_sha=0123456789abcdef\nfailed_units=\nunit_tc-measure=active/success\nunit_tc-fleet=active/success\nfleet_done=2026-11-12T14:20:17Z\nfleet_event=%s\nwg_peers=1\nopenssh_server_installed=no\nguest_agent_installed=no\noslogin_installed=no\nport22_listening=0\nserial_getty=masked\ntree_usr=%s\ntree_etc=ro\ntree_opt=ro\ntree_boot=ro\ntree_root=ro\nunit_tc-namenode=activating/success\nunit_tc-resourcemanager=activating/success\ncrawl_marker=\n' "$1" "$1" "$FS" "${2:-ro}" > "$W/lc2/$1.txt"; }
mkr tc-f1-m rw; mkr tc-f1-w
S0=$(date +%s); out="$(env PATH="$W/gc2:$PATH" LC_DIR="$W/lc2" IMG=x OUT="$W/lc2/out" LOCKMODE=locked WORKERS=1 timeout 60 bash "$I/test/f1-drive.sh" locked-check 2>&1)"; S1=$(( $(date +%s) - S0 ))
chk "locked-check finds a wrong image (a code tree that is read-write) at once, before the crawl (in $S1 s): it names the tree, says the early check failed, saves the serial consoles and never waits for the crawl" $([ "$S1" -lt 30 ] && grep -q "tc-f1-m: tree_usr is 'rw'" <<<"$out" && grep -q "the early check failed" <<<"$out" && ! grep -q "waiting for the crawl to finish" <<<"$out" && [ -s "$W/lc2/out/serial-tc-f1-m.txt" ] && [ -s "$W/lc2/out/serial-tc-f1-w.txt" ]; echo $?)
mkr tc-f1-m ro; mkr tc-f1-w
out="$(env PATH="$W/gc2:$PATH" LC_DIR="$W/lc2" IMG=x OUT="$W/lc2/out" LOCKMODE=locked WORKERS=1 timeout 8 bash "$I/test/f1-drive.sh" locked-check 2>&1)"
chk "a right image passes the early check (EARLY-REPORT-OK) and the stage goes on to wait for the crawl" $(grep -q "^EARLY-REPORT-OK" <<<"$out" && grep -q "waiting for the crawl to finish" <<<"$out" && ! grep -q "the early check failed" <<<"$out"; echo $?)
mkr tc-f1-m ro; mkr tc-f1-w; printf 'unit_tc-crawl=failed/exit-code\ncrawl_last=FAILED: HDFS not ready\nhadoop_last_error=ERROR DataNode: x\n' >> "$W/lc2/tc-f1-m.txt"
S0=$(date +%s); out="$(env PATH="$W/gc2:$PATH" LC_DIR="$W/lc2" IMG=x OUT="$W/lc2/out" LOCKMODE=locked WORKERS=1 timeout 60 bash "$I/test/f1-drive.sh" locked-check 2>&1)"; S1=$(( $(date +%s) - S0 ))
chk "locked-check does not wait for a crawl whose unit has failed (after a good early check): it says so at once (in $S1 s, not 45 minutes), prints the last crawl line and the last Hadoop error, and goes on to check the reports" $([ "$S1" -lt 30 ] && grep -q "^EARLY-REPORT-OK" <<<"$out" && grep -q "the crawl unit has FAILED" <<<"$out" && grep -q "crawl_last=FAILED: HDFS not ready" <<<"$out" && grep -q "hadoop_last_error=ERROR DataNode: x" <<<"$out" && ! grep -q "waiting for the crawl to finish" <<<"$out"; echo $?)
# Work item, change 1: the report says, for the five code trees, whether each is a read-only mount
chk "the report says tree_usr, tree_etc, tree_opt, tree_boot and tree_root, and says ro for a tree that is a read-only mount (a locked image)" $(m=0; for d in usr etc opt boot root; do grep -qx "tree_$d=ro" "$W/run4/report.txt" || m=$((m+1)); done; echo $m)
mkroot; mkdir -p "$W/run5"; env FAKE_RO_TREES="" TC_RUN="$W/run5" TC_REPORT_ONCE=1 TC_MODE_FILE="$W/mode" bash "$I/rootfs/usr/local/lib/tc/tc-report.sh" > /dev/null 2>&1
chk "on a tree that is not a read-only mount (a debug image) it says rw, never ro" $(m=0; for d in usr etc opt boot root; do grep -qx "tree_$d=rw" "$W/run5/report.txt" || m=$((m+1)); done; echo $m)
mkroot; mkdir -p "$W/run6"; env FAKE_FINDMNT=empty TC_RUN="$W/run6" TC_REPORT_ONCE=1 TC_MODE_FILE="$W/mode" bash "$I/rootfs/usr/local/lib/tc/tc-report.sh" > /dev/null 2>&1
chk "when the mount table cannot be read it says unknown, and never ro" $(m=0; for d in usr etc opt boot root; do grep -qx "tree_$d=unknown" "$W/run6/report.txt" || m=$((m+1)); done; echo $m)
chk "the report unit does not need the fleet unit (it must report a failed fleet too), restarts, and writes to the console" $(grep -q '^After=.*tc-fleet.service' "$I/rootfs/usr/local/lib/tc/units/tc-report.service" && ! grep -q '^Requires=' "$I/rootfs/usr/local/lib/tc/units/tc-report.service" && grep -q '^Restart=always' "$I/rootfs/usr/local/lib/tc/units/tc-report.service" && grep -q 'StandardOutput=journal+console' "$I/rootfs/usr/local/lib/tc/units/tc-report.service"; echo $?)
chk "the host-key unit of the debug image runs only where sshd exists, and before ssh" $(grep -q '^ConditionPathExists=/usr/sbin/sshd' "$I/rootfs/usr/local/lib/tc/units/tc-ssh-hostkeys.service" && grep -q '^Before=ssh.service' "$I/rootfs/usr/local/lib/tc/units/tc-ssh-hostkeys.service"; echo $?)
chk "the driver has the stages bake-lock, fleet-attacks, probe, locked-check, fleet-build-mismatch, mismatch-compare and images-compare" $(grep -q 'bake-lock)' "$I/test/f03-drive.sh" && for s in fleet-attacks probe locked-check fleet-build-mismatch mismatch-compare images-compare; do grep -q "  $s)" "$I/test/f1-drive.sh" || { echo 1; exit; }; done; echo 0)
echo "=== F. every gcloud command that the drivers generate, in dry run, whole lines, strict grammar"
lint() { # reads DRY lines on stdin. A gcloud line is: gcloud GROUP... VERB NAME... then only flags; "--flag=value" is complete, "--flag value" takes ONE value, a boolean flag takes none; any other bare word is an error
  python3 -c '
import sys, shlex
BOOL = {"--quiet", "--no-service-account", "--no-scopes"}; VERBS = {"create", "delete", "stop", "start", "describe", "add-metadata", "scp", "ssh", "get-serial-port-output"}
bad = 0; n = 0
for line in sys.stdin:
    if not line.startswith("DRY: gcloud "): continue
    t = shlex.split(line[5:].strip()); n += 1
    i = next((k for k, w in enumerate(t) if w in VERBS), None)
    if i is None: print("   not understood:", line.strip()[:200]); bad += 1; continue
    j = i + 1
    while j < len(t) and not t[j].startswith("--"): j += 1
    if j == i + 1: print("   no name after the verb:", line.strip()[:200]); bad += 1
    k = j
    while k < len(t):
        w = t[k]
        if not w.startswith("--"): print("   stray word %r:" % w, line.strip()[:240]); bad += 1; k += 1; continue
        k += 2 if ("=" not in w and w not in BOOL and k + 1 < len(t) and not t[k + 1].startswith("--")) else 1
print("%d gcloud lines, %d bad" % (n, bad)); sys.exit(1 if bad else 0)'
}
LDIR="$W/lint"; mkdir -p "$LDIR"
out="$( { for st in builder ship-builder image; do DRY=1 IMG=tc-img-x OUT="$LDIR" BUILDER_FROM=tc-img-dbg-1 bash "$I/test/f03-drive.sh" $st; done; DRY=1 IMG=tc-img-x OUT="$LDIR" bash "$I/test/f03-drive.sh" builder; DRY=1 IMG=tc-img-x OUT="$LDIR" VMM=a VMW=b bash "$I/test/f1-drive.sh" fleet-vms fleet-delete; } 2>&1 | lint)"; rc=$?
chk "the generated gcloud commands (builder from an image, builder from the family, the kit copy, the image, the fleet VMs, their deletion) are well formed: ${out##*$'\n'}" $([ $rc = 0 ]; echo $?)
chk "the builder from an image has exactly one --image=tc-img-dbg-1, no --image-family, and no stray bare image name" $(DRY=1 IMG=x OUT="$LDIR" BUILDER_FROM=tc-img-dbg-1 bash "$I/test/f03-drive.sh" builder 2>&1 | grep 'instances create' | python3 -c 'import sys,shlex; t=shlex.split(sys.stdin.read().split("DRY: ",1)[1]); sys.exit(0 if t.count("--image=tc-img-dbg-1")==1 and not any(w.startswith("--image-family") for w in t) and "tc-img-dbg-1" not in t else 1)'; echo $?)
printf 'DRY: gcloud compute instances create tc-builder --zone=z tc-img-dbg-1 --labels=a=b\n' | lint > "$W/lint1.txt" 2>&1; rcb=$?; chk "fault: the lint REFUSES the exact bug of the failed run (a stray image name after the flags)" $([ $rcb != 0 ] && grep -q "stray word 'tc-img-dbg-1'" "$W/lint1.txt"; echo $?)
printf 'DRY: gcloud compute instances delete a b --zone=z --quiet\nDRY: gcloud compute instances add-metadata a --zone=z --metadata-from-file tc-fleet=/x/f.tsv\nDRY: gcloud compute scp /tmp/x a:~/x --zone=z --quiet\n' | lint > "$W/lint2.txt" 2>&1; chk "control: two names, a flag with a separate value, and a copy with two paths are accepted" $([ $? = 0 ]; echo $?)
printf 'DRY: gcloud compute instances create x --zone=z --quiet stray\n' | lint > "$W/lint3.txt" 2>&1; chk "fault: a stray word after a boolean flag is refused" $([ $? != 0 ]; echo $?)
chk "no stage that comes after the lock needs ssh: the locked image is made by seal-locked (lock, cleaning and power-off in one session) and image (no ssh)" $(awk '/    seal-locked\)/,/;;/' "$I/test/f03-drive.sh" | grep -c 'rssh' | grep -qx 1 && ! awk '/    image\)/,/;;/' "$I/test/f03-drive.sh" | grep -q 'rssh'; echo $?)
chk "the locked image is sealed in ONE ssh session (lock, cleaning and power-off together, then a wait for the stop), the plain bake-lock refuses the locked mode, and the builder can be made from an existing image" $(grep -q 'seal-locked)' "$I/test/f03-drive.sh" && grep -q 'tc-image-lock.sh locked ~/f03 && bash ops/image/build/tc-image-clean.sh' "$I/test/f03-drive.sh" && grep -q 'SEAL-DONE' "$I/test/f03-drive.sh" && grep -q 'use the stage seal-locked' "$I/test/f03-drive.sh" && grep -q 'BUILDER_FROM' "$I/test/f03-drive.sh"; echo $?)
chk "the attacks script has the control, A1 to A9, the outsider and the two limits, and names them as documented" $(bash -n "$I/test/f4-attacks.sh" && for k in 'the clean control' 'A1 ' 'A2 ' 'A3 ' 'A3b ' 'A4 ' 'A5 ' 'A6 ' 'A7 ' 'A8 ' 'A9 ' 'L1 ' 'L2 ' 'UNDETECTED, as documented'; do grep -qF "$k" "$I/test/f4-attacks.sh" || { echo 1; exit; }; done; echo 0)
echo "=== G. the attack A10"
chk "the attack script waits for HDFS, and has A10 (a folder moved with the plain client is refused) and A10b (the wrapper's rename of it is refused too)" $(grep -q 'HDFS did not answer within 5 minutes' "$I/test/f4-attacks.sh" && grep -q 'A10 a folder moved' "$I/test/f4-attacks.sh" && grep -q 'A10b the wrapper' "$I/test/f4-attacks.sh" && grep -q 'Attested rename refused' "$I/test/f4-attacks.sh"; echo $?)
echo "=== H. the experiment of decision 2 (R3.0) and the test vectors (decision 5)"
python3 - "$W/ccel.bin" <<'PY'
import struct, sys
def ev2(mr, typ, data): return struct.pack("<III", mr, typ, 1) + struct.pack("<H", 0x000C) + b"\x11" * 48 + struct.pack("<I", len(data)) + data
spec = b"Spec ID Event03\0" + struct.pack("<IBBBB", 1, 0, 2, 0, 8) + struct.pack("<I", 1) + struct.pack("<HH", 0x000C, 48) + b"\x00"
log = struct.pack("<II20sI", 0, 3, bytes(20), len(spec)) + spec + ev2(1, 0x80000008, b"firmware") + ev2(3, 0xD, b"kernel_cmdline: /boot/vmlinuz-6.17.0-1022-gcp root=PARTUUID=abc ro console=ttyS0") + ev2(2, 0x80000003, b"shimx64.efi") + b"\xff" * 16
open(sys.argv[1], "wb").write(log)
PY
out="$(python3 "$I/test/r3-ccel.py" "$W/ccel.bin" 2>&1)"; chk "the boot-log parser finds the kernel command line event and says that it went into RTMR2 (MR index 3)" $(grep -q 'MR index 3 (RTMR2)  EV_IPL  kernel_cmdline' <<<"$out" && grep -q 'CCEL-PARSED' <<<"$out"; echo $?)
printf 'not a log' > "$W/bad.bin"; out="$(python3 "$I/test/r3-ccel.py" "$W/bad.bin" 2>&1)"; chk "fault: a file that is not a boot log is refused, not guessed at" $([ $? != 0 ] || grep -q 'too short\|not a Spec ID' <<<"$out"; echo $?)
chk "the probe script is read-only (no write, no install, no mount, no systemctl start), asks for the initrd, device-mapper in the kernel, the registers and the user hadoop, and the driver has the stage r3-probe" $(! grep -qE 'apt-get|\bmkfs|\bmount |systemctl (start|restart|stop)|>> */etc|tee /etc|rm -rf' "$I/test/r3-probe.sh" && grep -q 'CONFIG_DM_VERITY' "$I/test/r3-probe.sh" && grep -q 'CONFIG_DM_INIT' "$I/test/r3-probe.sh" && grep -q 'r3-ccel.py' "$I/test/r3-probe.sh" && grep -q '\.hadooprc' "$I/test/r3-probe.sh" && grep -q 'r3-probe)' "$I/test/f03-drive.sh"; echo $?)
if [ -f "$KIT/ops/attested/testvectors_check.py" ] && python3 -c "import cryptography" 2>/dev/null; then
  out="$(python3 "$KIT/ops/attested/testvectors_check.py" "$KIT/ops/attested/testvectors/attest-vectors-v1.json" 2>&1)"; chk "the test vectors of ATTEST04 and ATTEST05 (6 valid, 12 that must fail) give their verdicts under an implementation written only from the specification" $(grep -q 'TESTVECTORS-OK: 18 vectors (6 valid, 12' <<<"$out"; echo $?)
  python3 - "$KIT/ops/attested/testvectors/attest-vectors-v1.json" "$W/tv-bad.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
for v in d["vectors"]:
    if v["name"] == "folder-wrong-parent": v["valid"] = True; v["failure"] = ""
json.dump(d, open(sys.argv[2], "w"))
PY
  out="$(python3 "$KIT/ops/attested/testvectors_check.py" "$W/tv-bad.json" 2>&1)"; chk "fault: a vector that claims a wrong verdict is caught by the checker" $([ $? != 0 ] && grep -q 'TESTVECTORS-FAILED (1 of 18)' <<<"$out"; echo $?)
else echo "  (skipped: the vectors or the Python package cryptography are not in this kit)"; fi
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "F4-REHEARSAL-PASS: $PASS checks"; else echo "F4-REHEARSAL-FAIL"; fi
[ "$FAILN" = 0 ]
