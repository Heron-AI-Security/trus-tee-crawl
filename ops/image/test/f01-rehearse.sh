#!/usr/bin/env bash
# Rehearsal of steps F0.1 and F0.2 with stand-ins: the REAL scripts run against a fake root, a fake hardware register that EXTENDS (new = SHA-384(old || data), like the real one),
# fake systemctl, journalctl, GRUB tools, dpkg and curl. Every check that matters is also made to FAIL on purpose.
#   bash f01-rehearse.sh KITDIR       KITDIR holds ops/image and attest
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; fi; }
W="$(mktemp -d)"; STUB="$W/bin"; mkdir -p "$STUB"
# ---------------------------------------------------------------- stand-ins
cat > "$STUB/hw-extend" <<'EOS'
#!/usr/bin/env bash
python3 -c 'import hashlib,sys
p=sys.argv[1]; old=open(p,"rb").read(); new=sys.stdin.buffer.read(48)
assert len(new)==48
open(p,"wb").write(hashlib.sha384(old+new).digest())' "$1"
EOS
cat > "$STUB/hw-overwrite" <<'EOS'
#!/usr/bin/env bash
python3 -c 'import sys
p=sys.argv[1]; new=sys.stdin.buffer.read(48); open(p,"wb").write(new)' "$1"
EOS
cat > "$STUB/systemctl" <<'EOS'
#!/usr/bin/env bash
SD="${FAKE_SD:?}"
case "$1" in
  is-active) cat "$SD/active" 2>/dev/null || echo inactive ;;
  show) case "$4" in Result) cat "$SD/result" ;; ExecMainExitTimestampMonotonic) cat "$SD/measure_exit" ;; ExecMainStartTimestampMonotonic) cat "$SD/placeholder_start" ;; esac ;;
  cat) [ -f "$SD/placeholder_present" ] ;;
  daemon-reload) : ;;
  enable) [ -f "$SD/enable_fails" ] && exit 1; echo "$2" >> "$SD/enabled" ;;
  mask) [ -f "$SD/mask_fails" ] && exit 1; echo "$*" >> "$SD/masked" ;;
  stop) echo "$*" >> "$SD/stopped" ;;
esac
EOS
cat > "$STUB/journalctl" <<'EOS'
#!/usr/bin/env bash
[ -f "${FAKE_SD:?}/journal" ] && cat "$FAKE_SD/journal"; exit 0
EOS
cat > "$STUB/grub-editenv" <<'EOS'
#!/usr/bin/env bash
E="${FAKE_GRUBENV:?}"
case "$1" in list) cat "$E" ;; -) [ "$2 $3" = "unset next_entry" ] && { [ -f "${FAKE_NO_UNSET:-/nonexistent}" ] || sed -i '/^next_entry=/d' "$E"; } ;; esac
EOS
cat > "$STUB/grub-set-default" <<'EOS'
#!/usr/bin/env bash
[ -f "${FAKE_NO_SETDEFAULT:-/nonexistent}" ] && exit 0
E="${FAKE_GRUBENV:?}"; sed -i '/^saved_entry=/d' "$E"; echo "saved_entry=$1" >> "$E"
EOS
cat > "$STUB/update-grub" <<'EOS'
#!/usr/bin/env bash
G="${BOOT_DIR:?}/grub/grub.cfg"; mkdir -p "$(dirname "$G")"
{ echo "menuentry 'Ubuntu, with Linux 6.8.0-1000-gcp' {"; echo "}"; [ -f "$BOOT_DIR/vmlinuz-6.17.0-1022-gcp" ] && { echo "menuentry 'Ubuntu, with Linux 6.17.0-1022-gcp' {"; echo "}"; }; echo 'set default="${saved_entry}"'; } > "$G"
EOS
cat > "$STUB/dpkg" <<'EOS'
#!/usr/bin/env bash
[ -f "${FAKE_DPKG_FAIL:-/nonexistent}" ] && { echo "dpkg: error" >&2; exit 1; }
touch "$BOOT_DIR/vmlinuz-6.17.0-1022-gcp"; "$(dirname "$0")/update-grub"   # the real package runs update-grub in its post-install step
if [ -f "${FAKE_CONFIG_NO:-/nonexistent}" ]; then echo "# CONFIG_TSM_MEASUREMENTS is not set" > "$BOOT_DIR/config-6.17.0-1022-gcp"; else echo "CONFIG_TSM_MEASUREMENTS=y" > "$BOOT_DIR/config-6.17.0-1022-gcp"; fi
EOS
cat > "$STUB/curl" <<'EOS'
#!/usr/bin/env bash
cp "${FAKE_POOL:?}/$(basename "${@: -1}")" .
EOS
cat > "$STUB/apt-get" <<'EOS'
#!/usr/bin/env bash
[ -f "${FAKE_APT_FAIL:-/nonexistent}" ] && exit 1
mkdir -p "$(dirname "$FAKE_WG")"; echo "wg stand-in" > "$FAKE_WG"
EOS
cat > "$STUB/pgrep" <<'EOS'
#!/usr/bin/env bash
# a process table in $FAKE_SD/ps: one line per process, "comm<TAB>command line"; -x matches the whole comm, -f matches the command line (an extended regular expression)
T="${FAKE_SD:-/nonexistent}/ps"; [ -f "$T" ] || exit 1
case "$1" in
  -x) awk -F'\t' -v n="$2" '$1 ~ ("^" n "$") {f=1} END{exit !f}' "$T" ;;
  -f) awk -F'\t' -v r="$2" '$2 ~ r {f=1} END{exit !f}' "$T" ;;
esac
EOS
cat > "$STUB/reboot" <<'EOS'
#!/usr/bin/env bash
touch "${FAKE_SD:?}/reboot-called"
EOS
chmod +x "$STUB"/*
export PATH="$STUB:$PATH"
# ---------------------------------------------------------------- the fake root of the measurement tests
FR="$W/root"; for d in usr/local/lib/tc etc/tc etc/systemd/system usr/bin; do mkdir -p "$FR/$d"; done
cp "$I"/rootfs/usr/local/lib/tc/*.sh "$FR/usr/local/lib/tc/"; cp "$KIT/attest/measure/treehash.sh" "$KIT/attest/measure/rtmr3_replay.py" "$FR/usr/local/lib/tc/"
chmod +x "$FR"/usr/local/lib/tc/*   # a zip drops the executable bit, and the real prep script installs these files with mode 755
cp "$I/rootfs/etc/tc/measured-paths.txt" "$FR/etc/tc/"; cp "$I/rootfs/etc/systemd/system/tc-measure.service" "$FR/etc/systemd/system/"
echo "openssl stand-in" > "$FR/usr/bin/openssl"; echo "wg stand-in" > "$FR/usr/bin/wg"
REG="$W/reg"; RUNF="$W/run"; STATEF="$W/state"
zero() { head -c 48 /dev/zero > "$REG"; }
reg() { xxd -p "$REG" | tr -d '\n'; }
measure() { env TC_ROOT="$FR" TC_LIB="$FR/usr/local/lib/tc" TC_LIST="$FR/etc/tc/measured-paths.txt" TC_RTMR3="$REG" TC_RUN="$RUNF" TC_STATE="$STATEF" TC_WRITE="${HW:-$STUB/hw-extend $REG}" "$FR/usr/local/lib/tc/tc-measure.sh" "$@"; }
LIBF="$FR/usr/local/lib/tc"
echo "=== A. tc-extend: it extends (not overwrites), logs, and notices a register that does not behave"
zero; echo "hello" > "$W/f1"; LOGA="$W/a.tsv"; : > "$LOGA"
out="$(TC_LOG="$LOGA" TC_RTMR3="$REG" TC_WRITE="$STUB/hw-extend $REG" "$LIBF/tc-extend.sh" file1 "$W/f1" 2>&1)"; rc=$?
chk "a file is extended: exit 0 and 'register equals SHA-384(before + digest)'" $([ $rc = 0 ] && grep -q 'register equals' <<<"$out"; echo $?)
chk "the log line has 4 fields and its digest is the SHA-384 of the file" $([ "$(awk -F'\t' '{print NF}' "$LOGA")" = 4 ] && [ "$(cut -f2 "$LOGA")" = "$(sha384sum "$W/f1" | cut -d' ' -f1)" ]; echo $?)
mkdir -p "$W/d/sub"; echo a > "$W/d/x"; echo b > "$W/d/skipme"; zero; : > "$LOGA"; TC_LOG="$LOGA" TC_RTMR3="$REG" TC_WRITE="$STUB/hw-extend $REG" "$LIBF/tc-extend.sh" dir "$W/d" skipme >/dev/null 2>&1; D1="$(cut -f2 "$LOGA")"
echo changed > "$W/d/skipme"; zero; : > "$LOGA"; TC_LOG="$LOGA" TC_RTMR3="$REG" TC_WRITE="$STUB/hw-extend $REG" "$LIBF/tc-extend.sh" dir "$W/d" skipme >/dev/null 2>&1; D2="$(cut -f2 "$LOGA")"
echo changed > "$W/d/x"; zero; : > "$LOGA"; TC_LOG="$LOGA" TC_RTMR3="$REG" TC_WRITE="$STUB/hw-extend $REG" "$LIBF/tc-extend.sh" dir "$W/d" skipme >/dev/null 2>&1; D3="$(cut -f2 "$LOGA")"
chk "a folder is measured by treehash: a change in the SKIPPED file does not change the digest (control)" $([ -n "$D1" ] && [ "$D1" = "$D2" ]; echo $?)
chk "... and a change in a measured file does" $([ "$D1" != "$D3" ]; echo $?)
zero; : > "$LOGA"; out="$(TC_LOG="$LOGA" TC_RTMR3="$REG" TC_WRITE="$STUB/hw-overwrite $REG" "$LIBF/tc-extend.sh" file1 "$W/f1" 2>&1)"; rc=$?
chk "fault: a register that overwrites instead of extending is reported (MISMATCH, exit 1)" $([ $rc != 0 ] && grep -q MISMATCH <<<"$out"; echo $?)
echo "=== B. tc-measure: the whole boot measurement"
zero; rm -rf "$RUNF" "$STATEF"; out="$(measure 2>&1)"; rc=$?; echo "   $out" | tail -1 | cut -c1-120
chk "happy path: exit 0 and TC-MEASURE-OK with 5 events" $([ $rc = 0 ] && grep -q 'TC-MEASURE-OK boot=1 events=5' <<<"$out"; echo $?)
chk "the events are in the order of the list" $([ "$(cut -f1 "$RUNF/rtmr3-events.tsv" | tr '\n' ' ')" = "tc-lib tc-conf tc-units openssl wg " ]; echo $?)
REP="$(python3 "$LIBF/rtmr3_replay.py" "$RUNF/rtmr3-events.tsv")"
chk "the real replay tool says the chain is consistent and the replay equals the register" $(grep -q 'chain consistent: True' <<<"$REP" && [ "$(sed -n 's/^replayed RTMR3: //p' <<<"$REP")" = "$(reg | cut -c1-12)" ]; echo $?)
chk "measure-done exists, the boot counter is 1 and the boot's log is kept" $([ -f "$RUNF/measure-done" ] && [ "$(cat "$STATEF/bootcount")" = 1 ] && cmp -s "$RUNF/rtmr3-events.tsv" "$STATEF/events-boot1.tsv"; echo $?)
FIRST="$STATEF/events-boot1.tsv"; R_FIRST="$(reg)"
zero; out="$(measure 2>&1)"; rc=$?
chk "a second boot of the same files: the final RTMR3 is EQUAL (the measurement is reproducible), and the counter is 2" $([ $rc = 0 ] && [ "$(reg)" = "$R_FIRST" ] && [ "$(cat "$STATEF/bootcount")" = 2 ]; echo $?)
chk "f01-compare says 'same' for the two boots" $(python3 "$I/test/f01-compare.py" "$FIRST" "$STATEF/events-boot2.tsv" same >/dev/null 2>&1; echo $?)
echo "# a deliberate change" >> "$LIBF/tc-extend.sh"; zero; measure >/dev/null 2>&1
chk "control: a change in a measured file changes ONLY its event (tc-lib) and the final RTMR3" $(python3 "$I/test/f01-compare.py" "$FIRST" "$STATEF/events-boot3.tsv" changed tc-lib >/dev/null 2>&1; echo $?)
sed -i '$ d' "$LIBF/tc-extend.sh"; zero; measure >/dev/null 2>&1
chk "... and undoing the change brings the RTMR3 back to the first boot's value" $([ "$(reg)" = "$R_FIRST" ]; echo $?)
echo "--- faults of tc-measure (each must stop and leave nothing half done)"
zero; rm -rf "$RUNF" "$STATEF"; head -c 47 /dev/zero > "$REG"; printf '\1' >> "$REG"; out="$(measure 2>&1)"; rc=$?
chk "RTMR3 not zero at start: refused ('not zero'), nothing logged, no measure-done" $([ $rc != 0 ] && grep -q 'not zero' <<<"$out" && [ ! -e "$RUNF/measure-done" ] && [ ! -s "$RUNF/rtmr3-events.tsv" ]; echo $?)
zero; mv "$FR/usr/bin/wg" "$W/wg.away"; out="$(measure 2>&1)"; rc=$?
chk "a measured path is missing: refused ('does not exist') and RTMR3 is still zero (nothing was extended)" $([ $rc != 0 ] && grep -q 'does not exist' <<<"$out" && [ -z "$(reg | tr -d 0)" ]; echo $?)
chk "--check-list also refuses the missing path" $(measure --check-list >/dev/null 2>&1; [ $? != 0 ]; echo $?)
mv "$W/wg.away" "$FR/usr/bin/wg"
chk "--check-list passes when every path exists, and needs no register" $(TC_ROOT="$FR" TC_LIST="$FR/etc/tc/measured-paths.txt" TC_LIB="$LIBF" TC_RTMR3="$W/nonexistent" "$LIBF/tc-measure.sh" --check-list 2>&1 | grep -q 'TC-LIST-OK: 5 entries'; echo $?)
zero; out="$(TC_ROOT="$FR" TC_LIST="$W/nolist" TC_LIB="$LIBF" TC_RTMR3="$REG" TC_RUN="$RUNF" TC_STATE="$STATEF" "$LIBF/tc-measure.sh" 2>&1)"; chk "no list: refused" $([ $? = 0 ] || grep -q 'no list' <<<"$out"; echo $?)
printf '# only a comment\n' > "$W/empty.txt"; out="$(TC_ROOT="$FR" TC_LIST="$W/empty.txt" TC_LIB="$LIBF" TC_RTMR3="$REG" TC_RUN="$RUNF" TC_STATE="$STATEF" "$LIBF/tc-measure.sh" 2>&1)"; chk "a list that measures nothing: refused" $(grep -q 'measures nothing' <<<"$out"; echo $?)
printf 'broken\n' > "$W/nopath.txt"; out="$(TC_ROOT="$FR" TC_LIST="$W/nopath.txt" TC_LIB="$LIBF" TC_RTMR3="$REG" TC_RUN="$RUNF" TC_STATE="$STATEF" "$LIBF/tc-measure.sh" 2>&1)"; chk "a list line without a path: refused" $(grep -q 'without a path' <<<"$out"; echo $?)
zero; out="$(HW="$STUB/hw-overwrite $REG" measure 2>&1)"; rc=$?
chk "a register that does not extend: the measurement stops ('could not extend') and there is no measure-done" $([ $rc != 0 ] && grep -q 'could not extend' <<<"$out" && [ ! -e "$RUNF/measure-done" ]; echo $?)
echo "=== C. f01-check: after a boot, with every check made to fail on purpose"
CL="$W/checklib"; mkdir -p "$CL"; cp "$LIBF"/* "$CL/"
cat > "$CL/quote.sh" <<'EOS'
#!/usr/bin/env bash
python3 -c 'import hashlib,sys,os
log=open(sys.argv[1],"rb").read(); reg=open(os.environ["FAKE_REG"],"rb").read()
if os.environ.get("FAKE_QUOTE_BAD"): reg=bytes(48)
open(sys.argv[2],"wb").write(bytes(520)+reg+hashlib.sha512(log).digest())
print("quote written:",sys.argv[2])' "$1" "$2"
EOS
chmod +x "$CL/quote.sh"
SD="$W/sd"; GE="$W/grubenv"; OUTD="$W/out"; mkdir -p "$SD" "$OUTD"
good_state() { zero; rm -rf "$RUNF" "$STATEF"; measure >/dev/null 2>&1; echo "$(date -u +%FT%TZ)" > "$RUNF/placeholder-started"; echo active > "$SD/active"; echo success > "$SD/result"; echo 1000 > "$SD/measure_exit"; echo 2000 > "$SD/placeholder_start"; touch "$SD/placeholder_present"; echo "TC-MEASURE-OK boot=1 events=5 rtmr3=$(reg | cut -c1-16)" > "$SD/journal"; echo "saved_entry=Advanced options for Ubuntu>Ubuntu, with Linux 6.17.0-1022-gcp" > "$GE"; }
check() { env TC_LIB="$CL" TC_RUN="$RUNF" TC_STATE="$STATEF" TC_OUT="$OUTD" TC_RTMR3="$REG" TC_UNAME="${UN:-6.17.0-1022-gcp}" TC_SUDO="" FAKE_SD="$SD" FAKE_GRUBENV="$GE" FAKE_REG="$REG" FAKE_QUOTE_BAD="${QB:-}" bash "$I/test/f01-check.sh" 2>&1; }
good_state; out="$(check)"; rc=$?; echo "$out" | tail -1
chk "happy path: exit 0 and F01-CHECK-OK" $([ $rc = 0 ] && grep -q '^F01-CHECK-OK boot=1' <<<"$out"; echo $?)
chk "the check prints the right number of events (5, not 6: the replay's summary line must not be counted)" $(grep -q "chain is consistent (5 events)" <<<"$out"; echo $?)
chk "the evidence files of the boot are left behind (events, quote, kernel, grub, journal)" $([ -s "$OUTD/f01-boot1-events.tsv" ] && [ -s "$OUTD/f01-boot1-quote.bin" ] && [ -s "$OUTD/f01-boot1-uname.txt" ] && [ -s "$OUTD/f01-boot1-grubenv.txt" ] && [ -f "$OUTD/f01-boot1-journal.txt" ]; echo $?)
faultcheck() { local label="$1" want="$2"; out="$(check)"; rc=$?; chk "fault: $label" $([ $rc != 0 ] && grep -q "FAIL: .*$want" <<<"$out" && grep -q '^F01-CHECK-FAILED' <<<"$out"; echo $?); good_state; }
UN=6.8.0-1000-gcp faultcheck "a boot into the old kernel is refused" "running 6.8.0-1000-gcp"
good_state; echo "next_entry=Advanced options for Ubuntu>Ubuntu, with Linux 6.17.0-1022-gcp" >> "$GE"; faultcheck "a one-time entry means it was not a plain boot" "one-time entry"
good_state; echo "saved_entry=Advanced options for Ubuntu>Ubuntu, with Linux 6.8.0-1000-gcp" > "$GE"; faultcheck "a saved default that is not 6.17 is refused" "saved default is not"
good_state; zero; faultcheck "RTMR3 zero is refused" "RTMR3 is zero"
good_state; echo inactive > "$SD/active"; faultcheck "an inactive measurement unit is refused" "is not active"
good_state; echo failed > "$SD/result"; faultcheck "a failed result is refused" "result is not success"
good_state; rm -f "$SD/journal"; faultcheck "no TC-MEASURE-OK line in the journal is refused" "no TC-MEASURE-OK"
good_state; echo 3000 > "$SD/measure_exit"; faultcheck "stand-in daemons that started BEFORE the measurement finished are refused" "started .* before the measurement finished"
good_state; rm -f "$RUNF/placeholder-started"; faultcheck "stand-in daemons that never started are refused" "did not start"
good_state; sed -i '1s/\t[0-9a-f]*$/\t00/' "$RUNF/rtmr3-events.tsv"; faultcheck "a tampered event log (chain broken) is refused" "chain is not consistent"
good_state; QB=1 faultcheck "a quote whose RTMR3 differs from the replay is refused" "does not match the replay"
echo "=== D. f01-compare: wrong expectations are refused"
L1="$STATEF/events-boot1.tsv"; good_state; echo "# x" >> "$LIBF/tc-extend.sh"; zero; measure >/dev/null 2>&1; L3="$STATEF/events-boot2.tsv"; sed -i '$ d' "$LIBF/tc-extend.sh"
chk "'same' on two logs that differ is refused" $(python3 "$I/test/f01-compare.py" "$L1" "$L3" same >/dev/null 2>&1; [ $? != 0 ]; echo $?)
chk "'changed' naming the wrong event is refused" $(python3 "$I/test/f01-compare.py" "$L1" "$L3" changed openssl >/dev/null 2>&1; [ $? != 0 ]; echo $?)
chk "'changed' on two identical logs is refused" $(python3 "$I/test/f01-compare.py" "$L1" "$L1" changed tc-lib >/dev/null 2>&1; [ $? != 0 ]; echo $?)
head -3 "$L1" > "$W/short.tsv"; chk "logs with different events are refused" $(python3 "$I/test/f01-compare.py" "$L1" "$W/short.tsv" same >/dev/null 2>&1; [ $? != 0 ]; echo $?)
echo "=== E. tc-image-prep: the real script against a fake machine"
ENTRY="Advanced options for Ubuntu>Ubuntu, with Linux 6.17.0-1022-gcp"
prep_setup() { rm -rf "$W/p"; PR="$W/p"; for d in boot/grub etc/default/grub.d efi/efivars tsm pool work backup sd root/usr/bin home; do mkdir -p "$PR/$d"; done
  echo "menuentry 'Ubuntu, with Linux 6.8.0-1000-gcp' {" > "$PR/boot/grub/grub.cfg"; echo "}" >> "$PR/boot/grub/grub.cfg"
  : > "$PR/etc/default/grub.d/40-force-partuuid.cfg"; : > "$PR/etc/default/grub"; printf '\6\0\0\0\0' > "$PR/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"
  echo "openssl stand-in" > "$PR/root/usr/bin/openssl"
  # the process table of a REAL Ubuntu 22.04 VM: systemd, and the permanent unattended-upgrades daemon (it runs on every machine; the inventory of the nodes shows the service running)
  printf 'systemd\t/sbin/init\nunattended-upgr\t/usr/bin/python3 /usr/share/unattended-upgrades/unattended-upgrade-shutdown --wait-for-signal\n' > "$PR/sd/ps"
  echo "image deb" > "$PR/pool/linux-image-6.17.0-1022-gcp_6.17.0-1022.25_amd64.deb"; echo "modules deb" > "$PR/pool/linux-modules-6.17.0-1022-gcp_6.17.0-1022.25_amd64.deb"
  SI="$(sha256sum "$PR/pool/linux-image-6.17.0-1022-gcp_6.17.0-1022.25_amd64.deb" | cut -d' ' -f1)"; SM="$(sha256sum "$PR/pool/linux-modules-6.17.0-1022-gcp_6.17.0-1022.25_amd64.deb" | cut -d' ' -f1)"
  printf 'saved_entry=Advanced options for Ubuntu>Ubuntu, with Linux 6.8.0-1000-gcp\nnext_entry=Advanced options for Ubuntu>Ubuntu, with Linux 6.17.0-1022-gcp\n' > "$PR/grubenv"; }
prep() { env TC_ROOT="$PR/root" TC_SUDO="" TC_UNAME="${PUN:-6.8.0-1000-gcp}" TC_FREE_KB="${PFREE:-9000000}" TC_WAIT="${PWAIT:-2}" TC_POLL=1 BOOT_DIR="$PR/boot" GRUB_D="$PR/etc/default/grub.d" GRUB_FILE="$PR/etc/default/grub" EFI_DIR="$PR/efi" TC_TSM="$PR/tsm" TC_WORK="$PR/work" TC_BACKUP_DIR="$PR/backup" DEB_SHA_IMAGE="${PSI:-$SI}" DEB_SHA_MODULES="$SM" FAKE_POOL="$PR/pool" FAKE_GRUBENV="$PR/grubenv" FAKE_SD="$PR/sd" FAKE_WG="$PR/root/usr/bin/wg" HOME="$PR/home" FAKE_DPKG_FAIL="${FDF:-}" FAKE_CONFIG_NO="${FCN:-}" FAKE_NO_SETDEFAULT="${FNS:-}" FAKE_NO_UNSET="${FNU:-}" FAKE_APT_FAIL="${FAF:-}" bash "$I/build/tc-image-prep.sh" "${REPOD:-$KIT}" "$@" 2>&1; }
prep_setup; out="$(prep --with-placeholder)"; rc=$?; echo "$out" | tail -2 | cut -c1-110
chk "happy path: exit 0 and 'READY (nothing was rebooted)'" $([ $rc = 0 ] && grep -q 'READY (nothing was rebooted)' <<<"$out"; echo $?)
chk "6.17 is the saved default, and the leftover one-time entry was cleared" $(grep -qxF "saved_entry=$ENTRY" "$PR/grubenv" && ! grep -q '^next_entry=' "$PR/grubenv"; echo $?)
chk "the installed scripts are identical to the repository's (tc-measure, tc-extend, treehash, replay, quote)" $(R="$PR/root/usr/local/lib/tc"; cmp -s "$R/tc-measure.sh" "$I/rootfs/usr/local/lib/tc/tc-measure.sh" && cmp -s "$R/tc-extend.sh" "$I/rootfs/usr/local/lib/tc/tc-extend.sh" && cmp -s "$R/treehash.sh" "$KIT/attest/measure/treehash.sh" && cmp -s "$R/rtmr3_replay.py" "$KIT/attest/measure/rtmr3_replay.py" && cmp -s "$R/quote.sh" "$KIT/attest/quote.sh"; echo $?)
chk "modes: scripts 755, the list 644, the units 644" $([ "$(stat -c %a "$PR/root/usr/local/lib/tc/tc-measure.sh")" = 755 ] && [ "$(stat -c %a "$PR/root/etc/tc/measured-paths.txt")" = 644 ] && [ "$(stat -c %a "$PR/root/etc/systemd/system/tc-measure.service")" = 644 ]; echo $?)
chk "both units are enabled with the placeholder flag, and wireguard-tools was installed because wg was missing" $(grep -q tc-measure.service "$PR/sd/enabled" && grep -q tc-placeholder.service "$PR/sd/enabled" && [ -f "$PR/root/usr/bin/wg" ]; echo $?)
chk "nothing was rebooted" $([ ! -e "$PR/sd/reboot-called" ]; echo $?)
chk "the automatic upgrades were stopped and masked (they would change measured files between boots)" $(grep -q "unattended-upgrades.service" "$PR/sd/masked" && grep -q "apt-daily-upgrade.timer" "$PR/sd/masked" && grep -q "unattended-upgrades.service" "$PR/sd/stopped"; echo $?)
out="$(prep --with-placeholder)"; rc=$?; chk "a second run is harmless: it says the packages are already installed" $([ $rc = 0 ] && grep -q 'already installed' <<<"$out"; echo $?)
prep_setup; out="$(prep)"; chk "without the flag there is no placeholder unit, and only tc-measure is enabled" $([ ! -e "$PR/root/etc/systemd/system/tc-placeholder.service" ] && grep -q tc-measure.service "$PR/sd/enabled" && ! grep -q placeholder "$PR/sd/enabled"; echo $?)
abort() { local label="$1" want="$2"; shift 2; out="$(prep "$@")"; rc=$?; chk "fault: $label" $([ $rc != 0 ] && grep -q "ABORT: .*$want" <<<"$out"; echo $?); }
prep_setup; PUN=6.5.0-1-gcp abort "an unexpected running kernel" "unexpected running kernel"
prep_setup; printf '\6\0\0\0\1' > "$PR/efi/efivars/SecureBoot-8be4df61-93ca-11d2-aa0d-00e098032b8c"; abort "Secure Boot on" "Secure Boot is not off"
prep_setup; rm -f "$PR/etc/default/grub.d/40-force-partuuid.cfg"; abort "no initrdless setup file" "initrdless setup"
prep_setup; PFREE=1000 abort "too little disk space" "less than 1.5 GB"
prep_setup; rmdir "$PR/tsm"; abort "not a TDX guest (no configfs-tsm)" "not a TDX guest"
prep_setup; rm -f "$PR/boot/grub/grub.cfg"; echo "" > "$PR/boot/grub/grub.cfg"; abort "no GRUB entry for the running kernel" "no GRUB menu entry for the running kernel"
prep_setup; rm -rf "$W/badkit"; cp -r "$KIT" "$W/badkit"; rm -f "$W/badkit/attest/quote.sh"; REPOD="$W/badkit" abort "a file missing from the repository folder" "missing in"
prep_setup; PSI=0000 abort "a package whose checksum does not match" "checksum mismatch"
prep_setup; touch "$W/yes"; FDF="$W/yes" abort "dpkg fails" "dpkg failed"
prep_setup; touch "$W/yes"; FCN="$W/yes" abort "a kernel without CONFIG_TSM_MEASUREMENTS" "measurement option not enabled"
prep_setup; touch "$W/yes"; FNS="$W/yes" abort "the default is not recorded (grub-set-default does nothing)" "default was not recorded"
prep_setup; touch "$W/yes"; FNU="$W/yes" abort "a one-time entry that cannot be cleared" "one-time entry is still set"
prep_setup; touch "$W/yes"; FAF="$W/yes" abort "wireguard-tools cannot be installed and wg is missing" "could not install wireguard-tools"
prep_setup; echo "wg" > "$PR/root/usr/bin/wg"; rm -f "$PR/root/usr/bin/openssl"; abort "the measured list names a path that this machine does not have" "does not match this machine"
prep_setup; chk "control: the permanent unattended-upgrades daemon matches the OLD broad pattern (so the old guard blocked every run on a real VM)" $(FAKE_SD="$PR/sd" pgrep -f unattended-upgr >/dev/null; echo $?)
prep_setup; printf 'dpkg\tdpkg --configure -a\n' >> "$PR/sd/ps"; abort "dpkg is running" "still running"
prep_setup; printf 'apt-get\tapt-get -y upgrade\n' >> "$PR/sd/ps"; abort "apt-get is running" "still running"
prep_setup; printf 'apt.systemd.dai\t/usr/lib/apt/apt.systemd.daily install\n' >> "$PR/sd/ps"; abort "the daily apt job is running" "still running"
prep_setup; printf 'unattended-upgr\t/usr/bin/python3 /usr/bin/unattended-upgrade\n' >> "$PR/sd/ps"; abort "a RUN of unattended-upgrade (not its daemon) is running" "still running"
prep_setup; printf 'dpkg\tdpkg --configure -a\n' >> "$PR/sd/ps"; ( sleep 2; grep -v '^dpkg' "$PR/sd/ps" > "$PR/sd/ps.tmp"; mv "$PR/sd/ps.tmp" "$PR/sd/ps" ) & out="$(PWAIT=30 prep)"; rc=$?; wait
chk "a package job that finishes while the prep waits: it waits, then goes on and succeeds" $([ $rc = 0 ] && grep -q 'waiting up to' <<<"$out" && grep -q 'READY' <<<"$out"; echo $?)
prep_setup; touch "$PR/sd/mask_fails"; abort "the automatic upgrades cannot be masked" "could not stop the automatic upgrades"
rm -rf "$W/badkit"
echo; echo "pass: $PASS   fail: $FAILN"
if [ "$FAILN" = 0 ]; then echo "REHEARSAL-PASS: the real image-prep, measurement, check and compare scripts pass against stand-ins that extend like the hardware, and every fault is refused; $PASS checks"; else echo "REHEARSAL-FAIL"; fi
[ "$FAILN" = 0 ]
