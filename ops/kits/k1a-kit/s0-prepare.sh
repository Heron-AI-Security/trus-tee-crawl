( set -uo pipefail
cd ~; A=~/src-k1a.tgz; [ -n "${EXPECT:-}" ] && A=~/src-k1a-$EXPECT.tgz
[ -f "$A" ] || { echo "PREP-FAILED: upload $(basename $A) (made on the laptop by p56b-prepare.ps1) to the home folder"; exit 1; }
[ -n "${EXPECT:-}" ] || [ -s ~/expect-commit.txt ] || { echo "PREP-FAILED: give the commit id in the command (EXPECT=<the id> bash k1a-kit/k1a-run.sh), as printed by p56b-prepare.ps1"; exit 1; }
[ -s ~/r4-base-image.txt ] || { echo "PREP-FAILED: no ~/r4-base-image.txt (the pinned base image of the earlier builds)"; exit 1; }
[ -s ~/evidence-r47-B/zone.txt ] || { echo "PREP-FAILED: no ~/evidence-r47-B/zone.txt (the builder tc-r47-b of the last pair holds the Hadoop tarball; tc-r47-a was cleaned by the sealing)"; exit 1; }
rm -rf ~/k1awork && mkdir -p ~/k1awork/tree && tar xzf "$A" -C ~/k1awork/tree || { echo "PREP-FAILED: cannot unpack the archive"; exit 1; }
cd ~/k1awork/tree || exit 1
chmod +x ops/image/test/*.sh ops/image/build/*.sh ops/image/rootfs/usr/local/lib/tc/*.sh
K="$(cd "$(dirname "$0")" && pwd)"; CR=ops/image/rootfs/etc/tc/crawl
echo "== the crawl profile of this commit must be exactly the TEST profile of this kit (15 seeds, 2 rounds, 10 fetch tasks), and nothing else"
cmp -s $CR/params.env "$K/profile-params.env" && cmp -s $CR/seeds.txt "$K/profile-seeds.txt" || { echo "PREP-FAILED: the crawl profile in the archive is not the test profile of this kit ($CR/params.env and seeds.txt): the archive was made from another commit"; exit 1; }
echo "   ok: params.env and seeds.txt are the test profile; the build and the fleet use it"
rm -rf ~/k1awork/tree-defaults && cp -a ~/k1awork/tree ~/k1awork/tree-defaults && cp "$K/defaults-params.env" ~/k1awork/tree-defaults/$CR/params.env && cp "$K/defaults-seeds.txt" ~/k1awork/tree-defaults/$CR/seeds.txt || { echo "PREP-FAILED: could not make the copy with the default profile for the rehearsals"; exit 1; }
echo "   ok: the rehearsals run on a copy with the committed DEFAULT profile (they pin it, mistake 205); only the rehearsals use the copy"
for f in ops/ci/publish-ref.sh ops/verify-reference.sh ops/verify-reference.py ops/tree-diff.sh ops/tree-helper.sh ops/tree-lib.sh ops/image/build/tc-image-normalize.sh ops/verify-export.py ops/attested/verify_export_records.py ops/attested/verify_endorsement.py ops/attested/verify_fetchlist.py ops/image/test/fetchlist-rehearse.sh ops/image/test/verify-export-rehearse.py ops/attested/verify_intel_chain.py ops/attested/verify_intel_chain_rehearse.py ops/attested/verify_time_export.py ops/attested/verify_time_export_rehearse.py ops/attested/sp/custody/roughtime.py ops/attested/sp/verify/time-servers.json ops/image/rootfs/usr/local/lib/tc/tc-peer-verify.py src/java/org/commoncrawl/util/TcFetchLedger.java ops/image/test/r5-rehearse.sh; do [ -f "$f" ] || { echo "PREP-FAILED: $f is not in the commit that is to be built: the commits of steps P4, P5.2, P5.1 with P5.4, P5.6 part A and P5.5 must be pushed BEFORE the local commit of step P5.6 part B is made, and that commit must hold the fetch-list files (the stages of this run, P4 and verify-export, need them; it is better to know now than after hours)"; exit 1; }; done
HAVE=$(sha256sum "$A" | cut -c1-64); echo "source archive SHA-256: $HAVE"
EXP="${EXPECT:-$(tr -d ' \r\n' < ~/expect-commit.txt 2>/dev/null)}"; echo "== the commit that the archive's own header names (it must be $EXP, the local commit that this run verifies; taken from $([ -n "${EXPECT:-}" ] && echo 'the command (EXPECT)' || echo 'the file expect-commit.txt'))"
python3 -B ops/image/test/r4-archive.py "$A" --sha256 "$HAVE" --expect "$EXP" --commit-file ~/k1a-commit.txt | cut -c1-130 || { echo "PREP-FAILED: the archive check"; exit 1; }
ALT=~/src-k1a-$EXP-alt.tgz; gzip -dc "$A" | gzip -1 -n > "$ALT"
[ "$(sha256sum < "$A")" != "$(sha256sum < "$ALT")" ] || { echo "PREP-FAILED: the repacked archive equals the original: the test of step R4.7 would be void"; exit 1; }
echo "== the second archive of the same commit, for build B: $(basename $ALT): another name and other bytes (SHA-256 $(sha256sum < $ALT | cut -c1-16)... against $(sha256sum < $A | cut -c1-16)...)"
MARK=~/k1awork-rehearsals-ok-$(cut -c1-9 ~/k1a-commit.txt)
if [ -e "$MARK" ]; then echo "== the rehearsals: all passed on this commit before, not run again ($(basename $MARK))"; else
echo "== the rehearsals, run on the unpacked archive itself (the code that will be built; f03a and f03c take about 7 minutes)"
for s in ${REHEARSALS:-fetchlist-rehearse r5-rehearse p4d-rehearse r4-rehearse r4b-rehearse r4c-rehearse r4d-rehearse r4e-rehearse r4f-rehearse r4g-rehearse r4h-rehearse r4i-rehearse r4j-rehearse p1-rehearse p2a-rehearse f03-drive-rehearse f03a-rehearse f03c-rehearse}; do bash ~/k1awork/tree-defaults/ops/image/test/$s.sh ~/k1awork/tree-defaults > ~/k1awork-$s.out 2>&1; R=$(tail -2 ~/k1awork-$s.out | tr '\n' ' '); echo "$s: $(echo "$R" | cut -c1-60)"; echo "$R" | grep -q 'PASS' || { echo "PREP-FAILED: the rehearsal $s does not pass here; its failing checks:"; grep '^  FAIL' ~/k1awork-$s.out | cut -c1-170; exit 1; }; done
: > "$MARK"; fi
echo "== leftover: tc-r47-a was cleaned by the last sealing (no tarball, no ssh keys); it must not keep running"
za=$(cat ~/evidence-r47-A/zone.txt 2>/dev/null || cat ~/evidence-r47-B/zone.txt); [ "$(gcloud compute instances describe tc-r47-a --zone=$za --format='value(status)' 2>/dev/null)" = RUNNING ] && { echo "   tc-r47-a is running: stopping it"; gcloud compute instances stop tc-r47-a --zone=$za --quiet 2>&1 | tail -1; }
echo "== the seed builder tc-r47-b (never cleaned): running, answering on ssh, holding the Hadoop tarball (a download would take about two hours)"
z=$(cat ~/evidence-r47-B/zone.txt); st=$(gcloud compute instances describe tc-r47-b --zone=$z --format='value(status)' 2>/dev/null)
[ -n "$st" ] || { echo "PREP-FAILED: tc-r47-b does not exist"; exit 1; }
[ "$st" = RUNNING ] || { echo "   tc-r47-b is $st: starting it"; gcloud compute instances start tc-r47-b --zone=$z --quiet 2>&1 | tail -1; }
ok=0; E=""; for i in $(seq 1 ${SSH_TRIES:-24}); do E=$(gcloud compute ssh tc-r47-b --zone=$z --quiet --command=true </dev/null 2>&1) && { ok=1; break; }; sleep ${SSH_SLEEP:-10}; done
[ $ok = 1 ] || { echo "PREP-FAILED: tc-r47-b does not answer on ssh after $(( ${SSH_TRIES:-24} * ${SSH_SLEEP:-10} / 60 )) minutes; the last error: $(echo "$E" | tail -3 | tr '\n' ' ' | cut -c1-300)"; exit 1; }
sz=$(gcloud compute ssh tc-r47-b --zone=$z --quiet --command='stat -c %s ~/bake/hadoop-3.4.3.tar.gz 2>/dev/null || echo 0' </dev/null 2>/dev/null | tail -1)
if [ "$sz" = 514917037 ]; then echo "   tc-r47-b: the Hadoop tarball is there (514917037 bytes)"
elif [ "${ALLOW_DOWNLOAD:-0}" = 1 ]; then echo "   NO tarball (size $sz): the bakes will download it (about two hours): allowed by ALLOW_DOWNLOAD=1"
else echo "PREP-FAILED: tc-r47-b has no Hadoop tarball (size $sz): the bakes would download 491 MB at about 80 KB/s. Run again with ALLOW_DOWNLOAD=1 if you accept that"; exit 1; fi
echo "== fresh builders: none named tc-k1a-a or tc-k1a-b may exist, and the quota must have room (two builders, 8 vCPUs, plus tc-r47-b, 4)"
OLD="$(gcloud compute instances list --filter="name~'^tc-k1a-'" --format='value(name)' 2>/dev/null | tr '\n' ' ')"; [ -z "$OLD" ] || { echo "PREP-FAILED: these builders exist from an earlier attempt: $OLD. Delete them (gcloud compute instances delete $OLD --zone=$z) and run again"; exit 1; }
FL="$(gcloud compute instances list --filter="name~'^tc-f1-(m|w)$'" --format='value(name)' 2>/dev/null | tr '\n' ' ')"; [ -z "$FL" ] || { echo "PREP-FAILED: the fleet VMs of an earlier run still exist: $FL. The fleet stage would fail on them hours from now. Their data is exported already; delete them first (gcloud compute instances delete $FL --zone us-central1-a --quiet) and run this again"; exit 1; }
QJ="$(gcloud compute regions describe us-central1 --format=json 2>/dev/null)"
python3 - "$QJ" <<'PYX' && echo "   ok: the C3 quota has room (56 vCPUs: the builders now, the 11 VMs of the fleet later)" || { echo "PREP-FAILED: the C3 quota has less than 56 vCPUs free (this run creates 1 master and 10 workers): stop something of OURS first (never the teammate's VMs)"; exit 1; }
import json, sys
try: q = {x["metric"]: x for x in json.loads(sys.argv[1])["quotas"]}
except Exception: sys.exit(1)
c = q.get("C3_CPUS"); print("   C3_CPUS %s of %s in use" % (int(c["usage"]), int(c["limit"])) if c else "   (no C3_CPUS metric)"); sys.exit(0 if (c is None or c["limit"] - c["usage"] >= 56) else 1)
PYX
python3 - "$QJ" <<'PYD' || { echo "PREP-FAILED: the DISK quota has too little room for this run (see the numbers above). Delete a stopped builder of OURS that is no longer needed (for example tc-r47-a, which the last sealing cleaned) and run the same command again"; exit 1; }
import json, sys
q = {x["metric"]: x for x in json.loads(sys.argv[1])["quotas"]}; need = 590; bad = 0
for m in ("SSD_TOTAL_GB", "DISKS_TOTAL_GB"):
    x = q.get(m)
    if x is None: continue
    free = int(x["limit"] - x["usage"]); print("   %s: %d of %d GB in use, %d GB free (this run needs about %d)" % (m, x["usage"], x["limit"], free, need)); bad |= free < need
sys.exit(1 if bad else 0)
PYD
[ -z "$(find ~/k1awork -name __pycache__ | head -1)" ] || { echo "PREP-FAILED: a tool left a __pycache__"; exit 1; }
echo "STAGE-OK prepare (commit $(cut -c1-9 ~/k1a-commit.txt))" )
