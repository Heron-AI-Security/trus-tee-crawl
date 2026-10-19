#!/usr/bin/env bash
# Rehearsal of the driver's handling of a cleaned and restarted builder: a fake gcloud reports the builder as TERMINATED and then lets ssh succeed; the real driver must start it, forget the
# remembered host key of THAT instance only (in a fake known-hosts file), and keep the keys of other instances. A second test makes ssh fail with a changed-key message and checks that the driver
# prints the last ssh message and the hint instead of hiding it.   bash f03-drive-rehearse.sh KITDIR
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; D="$KIT/ops/image/test/f03-drive.sh"; W="$(mktemp -d)"; PASS=0; FAILN=0; mkdir -p "$W/bin" "$W/home/.ssh"
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; echo "$out" | tail -6 | sed 's/^/        | /'; fi; }
cat > "$W/bin/gcloud" <<'EOS'
#!/usr/bin/env bash
echo "$*" >> "$FAKE_LOG"
case "$*" in
  *"instances describe"*"value(status)"*) echo "${FAKE_STATUS:-TERMINATED}" ;;
  *"instances describe"*"value(id)"*) echo 5006564923807608531 ;;
  *"instances describe"*) exit 0 ;;
  *"instances start"*) echo "Starting instance(s) tc-builder... done." ;;
  *"compute ssh"*) if grep -q "^compute.5006564923807608531" "$HOME/.ssh/google_compute_known_hosts" 2>/dev/null; then echo "Host key for compute.5006564923807608531 has changed and you have requested strict checking."; echo "Host key verification failed."; exit 255; fi; if [ -f "$FAKE_SSH_FAILS" ]; then echo "Host key for compute.5006564923807608531 has changed and you have requested strict checking."; echo "Host key verification failed."; exit 255; fi; printf 'tc-builder\n6.17.0-1022-gcp\nconfigfs-tsm: present\nsudo: ok\n' ;;
esac
EOS
chmod +x "$W/bin/gcloud"; export PATH="$W/bin:$PATH" HOME="$W/home" FAKE_LOG="$W/log" FAKE_SSH_FAILS="$W/ssh_fails" OUT="$W/out"
command -v ssh-keygen >/dev/null || { echo 'the rehearsal needs ssh-keygen (package openssh-client): the driver uses the real one'; exit 2; }
ssh-keygen -q -t ed25519 -N '' -f "$W/k1" && ssh-keygen -q -t ed25519 -N '' -f "$W/k2"   # REAL keys, so that the real ssh-keygen parses the file as it does in Cloud Shell
printf 'compute.5006564923807608531 %s\ncompute.1111111111111111111 %s\n' "$(cut -d' ' -f1,2 "$W/k1.pub")" "$(cut -d' ' -f1,2 "$W/k2.pub")" > "$HOME/.ssh/google_compute_known_hosts"
out="$(bash "$D" builder 2>&1)"; rc=$?
chk "the stopped builder is started, and the run goes on to the console lines" $([ $rc = 0 ] && grep -q 'it is stopped: starting it' <<<"$out" && grep -q 'instances start' "$W/log" && grep -q '^tc-builder' <<<"$out"; echo $?)
chk "the remembered host key of THAT instance was forgotten (and the driver says so)" $(! grep -q '^compute.5006564923807608531' "$HOME/.ssh/google_compute_known_hosts" && grep -q 'forgot the remembered host key of tc-builder' <<<"$out"; echo $?)
chk "control: the key of another instance is kept" $(grep -q '^compute.1111111111111111111 ssh-ed25519 ' "$HOME/.ssh/google_compute_known_hosts"; echo $?)
rm -f "$HOME/.ssh/google_compute_known_hosts"; out="$(bash "$D" builder 2>&1)"; rc=$?; chk "with no file of remembered keys at all the driver still works" $([ $rc = 0 ] && grep -q '^tc-builder' <<<"$out"; echo $?)
# the case that the first version of the fix missed: the builder is ALREADY RUNNING (an earlier attempt started it), with a stale key remembered
printf 'compute.5006564923807608531 %s\ncompute.1111111111111111111 %s\n' "$(cut -d' ' -f1,2 "$W/k1.pub")" "$(cut -d' ' -f1,2 "$W/k2.pub")" > "$HOME/.ssh/google_compute_known_hosts"; : > "$W/log"
out="$(FAKE_STATUS=RUNNING bash "$D" builder 2>&1)"; rc=$?
chk "a RUNNING builder with a stale key: the driver forgets the key at once and connects (no start, no 7-minute wait)" $([ $rc = 0 ] && grep -q 'forgot the remembered host key of tc-builder' <<<"$out" && ! grep -q 'it is stopped' <<<"$out" && ! grep -q 'instances start' "$W/log" && grep -q '^tc-builder' <<<"$out"; echo $?)
chk "control: in that case too only the key of that instance is removed" $(grep -q '^compute.1111111111111111111 ssh-ed25519 ' "$HOME/.ssh/google_compute_known_hosts" && ! grep -q '^compute.5006564923807608531' "$HOME/.ssh/google_compute_known_hosts"; echo $?)
touch "$W/ssh_fails"; sed -i 's/seq 1 40/seq 1 2/; s/sleep 10/sleep 0/' "$W/d.sh" 2>/dev/null; sed 's/seq 1 40/seq 1 2/; s/sleep 10/sleep 0/' "$D" > "$W/d.sh"; out="$(bash "$W/d.sh" builder 2>&1)"; rc=$?
chk "fault: a failing ssh ends with STOP, shows the LAST ssh message, and gives the hint for a changed host key" $([ $rc != 0 ] && grep -q 'STOP: no ssh to tc-builder' <<<"$out" && grep -q 'Host key verification failed' <<<"$out" && grep -q 'hint: the VM has a new host key' <<<"$out"; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "REHEARSAL-PASS: the driver restarts a cleaned builder, forgets only its own old host key, and shows why an ssh wait failed; $PASS checks"; else echo "REHEARSAL-FAIL"; fi; [ "$FAILN" = 0 ]
