( cd ~; set -u
  Z=""; for z in p4g-code*.zip; do [ -f "$z" ] || continue; [ "$(sha256sum "$z" | cut -c1-8)" = f31a5a5f ] && Z="$z"; done
  [ -n "$Z" ] || { echo "WRONG-ZIP: no zip with SHA-256 starting f31a5a5f is in the home folder. The zips here:"; ls p4g-code*.zip 2>/dev/null | while read -r z; do echo "   $z  $(sha256sum "$z" | cut -c1-8)"; done; echo "Upload the NEW p4g-code.zip."; exit 1; }
  [ -d ~/cl2-p4/pub/publish ] || { echo "P4G-HAND-FAILED: the folder ~/cl2-p4/pub/publish (the published reference of the build c60995fa4, made by the kit) is missing"; exit 1; }
  BASE="${P4G_BASE:-c60995fa4}"
  echo "== 1. the repository as it is on GitHub (the build cleanup commit $BASE), with the seven changed files on top"
  rm -rf p4g-test && git clone --quiet --branch feat/tee-hadoop-cluster --single-branch "${REPO_URL:-https://github.com/Heron-AI-Security/nutch-private.git}" p4g-test || { echo "P4G-HAND-FAILED: the clone failed"; exit 1; }
  echo "   head of the clone: $(git -C p4g-test log -1 --format='%h %s' | cut -c1-90)"
  [ "$(git -C p4g-test rev-parse --short=9 HEAD)" = "$BASE" ] || { echo "P4G-HAND-FAILED: the head of the clone is not $BASE (did somebody push?)"; exit 1; }
  unzip -oq "$Z" -d p4g-test || { echo "P4G-HAND-FAILED: the zip did not unpack"; exit 1; }
  echo "== 2. the rehearsals (no cloud)"
  for r in p42 tamper; do
    bash p4g-test/ops/image/test/$r-rehearse.sh p4g-test > p4g-$r.txt 2>&1; printf "   %-6s %s\n" "$r" "$(grep -E "pass: [0-9]+ +fail: [0-9]+" p4g-$r.txt | tail -1)"
    grep -q "REHEARSAL-PASS" p4g-$r.txt || { echo "-- the failing checks:"; grep FAIL p4g-$r.txt | head -8; echo "P4G-HAND-FAILED: the rehearsal $r did not pass"; exit 1; }
  done
  echo "== 3. REAL TEST 1 (a fault injected at the SSH probe ONLY): a real helper VM and real disks are made; the SSH probe is made to answer 'System is booting up' every time, so that the tool gives up after 8 attempts (about 2 minutes). It must name the booting VM, print the REAL serial console of the VM, and delete the VM and the disks. About 5 minutes, a few cents."
  echo "Type  yes  to start, or anything else to stop:"; read -r a
  [ "$a" = yes ] || { echo "stopped by you: nothing was created"; exit 0; }
  cat > ~/p4g-gcloud-wrapper.sh <<'EOW'
#!/usr/bin/env bash
case " $* " in *" --command true "*) echo "System is booting up. Unprivileged users are not permitted to log in yet. Please come back later. For technical details, see pam_nologin(8)." >&2; exit 255;; esac
exec gcloud "$@"
EOW
  chmod +x ~/p4g-gcloud-wrapper.sh; rm -rf ~/p4g-w1
  TC_GCLOUD=~/p4g-gcloud-wrapper.sh TREE_SSH_TRIES=8 TREE_SSH_WAIT=10 bash p4g-test/ops/tree-diff.sh diff tc-img-cl2-1 tc-img-cl2-2 --work ~/p4g-w1 > p4g-t1.txt 2>&1; rc1=$?
  grep -a -E "attempt 8 of 8|STILL BOOTING|serial console" p4g-t1.txt | cut -c1-200 | head -4; echo "   the first lines of the real serial console:"; sed -n '1,3p' ~/p4g-w1/serial.log 2>/dev/null | cut -c1-120 | sed 's/^/      /'
  [ "$rc1" = 2 ] && grep -a -q "after 8 attempts" p4g-t1.txt && grep -a -q "The VM was STILL BOOTING when this gave up" p4g-t1.txt && grep -a -q "the last 20 lines of the serial console" p4g-t1.txt && [ "$(grep -c . ~/p4g-w1/serial.log 2>/dev/null)" -gt 5 ] && grep -a -q -i -E "systemd|Linux version|kernel|BIOS" ~/p4g-w1/serial.log || { echo "P4G-HAND-FAILED: test 1 (exit code $rc1): the tool did not behave as designed (see p4g-t1.txt)"; tail -8 p4g-t1.txt | cut -c1-220; exit 1; }
  L="$(gcloud compute instances list --filter="labels.purpose=tc-tree-diff" --format="value(name)" 2>/dev/null; gcloud compute disks list --filter="labels.purpose=tc-tree-diff" --format="value(name)" 2>/dev/null)"; [ -z "$L" ] || { echo "P4G-HAND-FAILED: test 1 left behind: $L"; exit 1; }
  echo "   ok: test 1: the booting VM was named, its real console was shown and saved, and nothing was left behind"
  echo "== 4. REAL TEST 2 (the stress test of the boot): tree-diff.sh probe, four times in a row with the NEW defaults. Each time a real helper VM is made WITHOUT the disks, the two sealed disks (they carry the same labels UEFI and BOOT as the own disk of the VM, which made its boot fail in the first real runs) are attached AFTER the boot, and both must be visible. About 4 minutes each."
  for i in 1 2 3 4; do
    t0=$(date +%s); rm -rf ~/p4g-probe$i
    bash p4g-test/ops/tree-diff.sh probe tc-img-cl2-1 tc-img-cl2-2 --work ~/p4g-probe$i > p4g-probe$i.txt 2>&1; rc=$?; t1=$(date +%s)
    L="$(gcloud compute instances list --filter="labels.purpose=tc-tree-diff" --format="value(name)" 2>/dev/null; gcloud compute disks list --filter="labels.purpose=tc-tree-diff" --format="value(name)" 2>/dev/null)"
    if [ "$rc" = 0 ] && grep -a -q "^TREE-PROBE-OK images=tc-img-cl2-1,tc-img-cl2-2" p4g-probe$i.txt && [ -z "$L" ]; then echo "   probe $i: OK in $(( t1 - t0 )) seconds, $(grep -a '^   boot:' p4g-probe$i.txt | tr -s ' ')"
    else echo "P4G-HAND-FAILED: probe $i (exit code $rc, left behind: ${L:-nothing}): the helper did not boot cleanly with the disks attached afterwards (see p4g-probe$i.txt)"; tail -12 p4g-probe$i.txt | cut -c1-230; exit 1; fi
  done
  echo "   the partitions that the probe saw AFTER the boot (the duplicate labels are real):"; grep -a -E "^   (treea|treeb):" p4g-probe4.txt | cut -c1-200
  echo "== 5. REAL TEST 3: the real comparison of the two builds of c60995fa4 with the NEW defaults (no TREE_* setting at all): verify-reference.sh with published = tc-img-cl2-1 and own build = tc-img-cl2-2. It must say trees=identical image-run=exact. About 15 to 25 minutes; the time is printed."
  t0=$(date +%s)
  bash p4g-test/ops/verify-reference.sh c60995fa4bc585223f4d3690690188d075d79bc0 --published ~/cl2-p4/pub/publish --published-image tc-img-cl2-1 --own-image tc-img-cl2-2 --work ~/p4g-verify > p4g-t2.txt 2>&1; rc2=$?; t1=$(date +%s)
  grep -a -v "^  ok:" p4g-t2.txt | tail -8 | cut -c1-230
  grep -a -q "^VERIFY-REFERENCE-OK .* trees=identical image-run=exact" p4g-t2.txt || { echo "P4G-HAND-FAILED: test 3 (exit code $rc2): the two builds were not verified as the same with the new defaults (see p4g-t2.txt and ~/p4g-verify)"; exit 1; }
  echo "   ok: test 3. It took $(( (t1 - t0) / 60 )) minutes with the NEW defaults (the P4 stage of the kit took 28 minutes in all, which included publishing the reference and a helper that was lucky with its boot and waited with an override)"
  echo "== 6. the code that ran is exactly the code of the zip, and nothing is left behind"
  bad=0; n=0; for f in $(unzip -Z1 "$Z" | grep -v '/$'); do n=$((n+1)); cmp -s <(unzip -p "$Z" "$f") "p4g-test/$f" || { echo "   differs from the zip: $f"; bad=1; }; done
  [ "$bad" = 0 ] || { echo "P4G-HAND-FAILED: the code that ran is not the code of the zip"; exit 1; }; echo "   ok: the $n files in p4g-test are exactly the files of the zip"
  L="$(gcloud compute instances list --filter="labels.purpose=tc-tree-diff OR labels.purpose=tc-reference-run" --format="value(name)" 2>/dev/null; gcloud compute disks list --filter="labels.purpose=tc-tree-diff" --format="value(name)" 2>/dev/null)"; [ -z "$L" ] || { echo "P4G-HAND-FAILED: left behind in the cloud: $L"; exit 1; }; echo "   ok: nothing is left behind in the cloud"
  echo "P4G-HAND-OK zip=$(sha256sum "$Z" | cut -c1-8)"
)
