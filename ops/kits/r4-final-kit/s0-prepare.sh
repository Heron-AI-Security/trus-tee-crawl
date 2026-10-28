( set -uo pipefail
cd ~; A=~/src-final2.tgz
[ -f "$A" ] || { echo "PREP-FAILED: upload src-final2.tgz (made on the laptop by r4-prepare.ps1)"; exit 1; }
[ -s ~/expect-commit.txt ] || { echo "PREP-FAILED: upload expect-commit.txt (made on the laptop by r4-prepare.ps1, together with the archive)"; exit 1; }
[ -s ~/r4-base-image.txt ] || { echo "PREP-FAILED: no ~/r4-base-image.txt (the pinned base image of the earlier builds)"; exit 1; }
[ -s ~/evidence-fin-A/zone.txt ] && [ -s ~/evidence-fin-B/zone.txt ] || { echo "PREP-FAILED: no ~/evidence-fin-A/zone.txt or ~/evidence-fin-B/zone.txt (the builders of the first pair)"; exit 1; }
rm -rf ~/fin2work && mkdir -p ~/fin2work/tree && tar xzf "$A" -C ~/fin2work/tree || { echo "PREP-FAILED: cannot unpack the archive"; exit 1; }
cd ~/fin2work/tree || exit 1
chmod +x ops/image/test/*.sh ops/image/build/*.sh ops/image/rootfs/usr/local/lib/tc/*.sh
HAVE=$(sha256sum "$A" | cut -c1-64); echo "source archive SHA-256: $HAVE"
EXP="$(tr -d ' \r\n' < ~/expect-commit.txt)"; echo "== the commit that the archive's own header names (it must be $EXP, the local commit that this run verifies)"
python3 -B ops/image/test/r4-archive.py "$A" --sha256 "$HAVE" --expect "$EXP" --commit-file ~/fin2-commit.txt | cut -c1-130 || { echo "PREP-FAILED: the archive check"; exit 1; }
echo "== the rehearsals, run on the unpacked archive itself (the code that will be built)"
for s in r4-rehearse r4b-rehearse r4c-rehearse r4d-rehearse r4e-rehearse r4f-rehearse r4g-rehearse; do R=$(bash ops/image/test/$s.sh ~/fin2work/tree 2>&1 | tail -2 | tr '\n' ' '); echo "$s: $R"; echo "$R" | grep -q 'PASS' || { echo "PREP-FAILED: the rehearsal $s does not pass here"; exit 1; }; done
echo "== the two builders: running, answering on ssh, and holding the Hadoop tarball (a download would take about two hours)"
for v in tc-fin-a tc-fin-b; do
  id=$(echo ${v: -1} | tr a-b A-B); z=$(cat ~/evidence-fin-$id/zone.txt)
  st=$(gcloud compute instances describe $v --zone=$z --format='value(status)' 2>/dev/null)
  [ -n "$st" ] || { echo "PREP-FAILED: the builder $v does not exist (it was made by the first pair of builds)"; exit 1; }
  [ "$st" = RUNNING ] || { echo "   $v is $st: starting it"; gcloud compute instances start $v --zone=$z --quiet 2>&1 | tail -1; }
  ok=0; for i in $(seq 1 24); do gcloud compute ssh $v --zone=$z --quiet --command=true </dev/null >/dev/null 2>&1 && { ok=1; break; }; sleep 10; done
  [ $ok = 1 ] || { echo "PREP-FAILED: $v does not answer on ssh after 4 minutes"; exit 1; }
  sz=$(gcloud compute ssh $v --zone=$z --quiet --command='stat -c %s ~/bake/hadoop-3.4.3.tar.gz 2>/dev/null || echo 0' </dev/null 2>/dev/null | tail -1)
  if [ "$sz" = 514917037 ]; then echo "   $v: running, ssh answers, the Hadoop tarball is there (514917037 bytes): no download"
  elif [ "${ALLOW_DOWNLOAD:-0}" = 1 ]; then echo "   $v: NO tarball: the bake will download it (about two hours): allowed by ALLOW_DOWNLOAD=1"
  else echo "PREP-FAILED: $v has no Hadoop tarball (size $sz): the bake would download 491 MB at about 80 KB/s, about two hours. Run again with ALLOW_DOWNLOAD=1 if you accept that"; exit 1; fi
done
[ -z "$(find ~/fin2work -name __pycache__ | head -1)" ] || { echo "PREP-FAILED: a tool left a __pycache__"; exit 1; }
echo "STAGE-OK prepare (commit $(cut -c1-9 ~/fin2-commit.txt))" )
