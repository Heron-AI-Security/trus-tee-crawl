( set -uo pipefail
cd ~; A=~/src-rel.tgz; [ -n "${EXPECT:-}" ] && A=~/src-rel-$EXPECT.tgz
[ -f "$A" ] || { echo "PREP-FAILED: upload $(basename $A) (made on the laptop by r4-prepare3.ps1) to the home folder"; exit 1; }
[ -n "${EXPECT:-}" ] || [ -s ~/expect-commit.txt ] || { echo "PREP-FAILED: give the commit id in the command (EXPECT=<the id> bash rel-fix-kit/rel-fix-run.sh), as printed by rel-prepare.ps1"; exit 1; }
[ -s ~/r4-base-image.txt ] || { echo "PREP-FAILED: no ~/r4-base-image.txt (the pinned base image of the earlier builds)"; exit 1; }
[ -s ~/evidence-r47-B/zone.txt ] || { echo "PREP-FAILED: no ~/evidence-r47-B/zone.txt (the builder tc-r47-b of the last pair holds the Hadoop tarball; tc-r47-a was cleaned by the sealing)"; exit 1; }
rm -rf ~/relwork && mkdir -p ~/relwork/tree && tar xzf "$A" -C ~/relwork/tree || { echo "PREP-FAILED: cannot unpack the archive"; exit 1; }
cd ~/relwork/tree || exit 1
chmod +x ops/image/test/*.sh ops/image/build/*.sh ops/image/rootfs/usr/local/lib/tc/*.sh
HAVE=$(sha256sum "$A" | cut -c1-64); echo "source archive SHA-256: $HAVE"
EXP="${EXPECT:-$(tr -d ' \r\n' < ~/expect-commit.txt 2>/dev/null)}"; echo "== the commit that the archive's own header names (it must be $EXP, the local commit that this run verifies; taken from $([ -n "${EXPECT:-}" ] && echo 'the command (EXPECT)' || echo 'the file expect-commit.txt'))"
python3 -B ops/image/test/r4-archive.py "$A" --sha256 "$HAVE" --expect "$EXP" --commit-file ~/rel-commit.txt | cut -c1-130 || { echo "PREP-FAILED: the archive check"; exit 1; }
ALT=~/src-rel-$EXP-alt.tgz; gzip -dc "$A" | gzip -1 -n > "$ALT"
[ "$(sha256sum < "$A")" != "$(sha256sum < "$ALT")" ] || { echo "PREP-FAILED: the repacked archive equals the original: the test of step R4.7 would be void"; exit 1; }
echo "== the second archive of the same commit, for build B: $(basename $ALT): another name and other bytes (SHA-256 $(sha256sum < $ALT | cut -c1-16)... against $(sha256sum < $A | cut -c1-16)...)"
TS="$(tr -d ' \r\n' < ops/image/build/apt-snapshot.txt)"; echo "== the archive date of this commit: $TS; does Canonical's snapshot service answer for it?"
CODE=$(curl -sL --max-time 40 -o /dev/null -w '%{http_code}' "https://snapshot.ubuntu.com/ubuntu/$TS/dists/jammy/InRelease"); echo "   InRelease of jammy at $TS: HTTP $CODE"
[ "$CODE" = 200 ] || { echo "PREP-FAILED: the snapshot service did not answer 200 for $TS (HTTP $CODE): the pin cannot work from here; nothing was built"; exit 1; }
MARK=~/relwork-rehearsals-ok-$(cut -c1-9 ~/rel-commit.txt)
if [ -e "$MARK" ]; then echo "== the rehearsals: all passed on this commit before, not run again ($(basename $MARK))"; else
echo "== the rehearsals, run on the unpacked archive itself (the code that will be built; f03a and f03c take about 7 minutes)"
for s in ${REHEARSALS:-r4-rehearse r4b-rehearse r4c-rehearse r4d-rehearse r4e-rehearse r4f-rehearse r4g-rehearse r4h-rehearse r4i-rehearse r4j-rehearse p1-rehearse p2a-rehearse f03-drive-rehearse f03a-rehearse f03c-rehearse}; do bash ops/image/test/$s.sh ~/relwork/tree > ~/relwork-$s.out 2>&1; R=$(tail -2 ~/relwork-$s.out | tr '\n' ' '); echo "$s: $(echo "$R" | cut -c1-60)"; echo "$R" | grep -q 'PASS' || { echo "PREP-FAILED: the rehearsal $s does not pass here; its failing checks:"; grep '^  FAIL' ~/relwork-$s.out | cut -c1-170; exit 1; }; done
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
echo "== fresh builders: none named tc-rel-a or tc-rel-b may exist, and the quota must have room (two builders, 8 vCPUs, plus tc-r47-b, 4)"
OLD="$(gcloud compute instances list --filter="name~'^tc-rel-'" --format='value(name)' 2>/dev/null | tr '\n' ' ')"; [ -z "$OLD" ] || { echo "PREP-FAILED: these builders exist from an earlier attempt: $OLD. Delete them (gcloud compute instances delete $OLD --zone=$z) and run again"; exit 1; }
QJ="$(gcloud compute regions describe us-central1 --format=json 2>/dev/null)"
python3 - "$QJ" <<'PYX' && echo "   ok: the C3 quota has room (12 vCPUs)" || { echo "PREP-FAILED: the C3 quota has less than 12 vCPUs free: stop something of OURS first (never the teammate's VMs)"; exit 1; }
import json, sys
try: q = {x["metric"]: x for x in json.loads(sys.argv[1])["quotas"]}
except Exception: sys.exit(1)
c = q.get("C3_CPUS"); print("   C3_CPUS %s of %s in use" % (int(c["usage"]), int(c["limit"])) if c else "   (no C3_CPUS metric)"); sys.exit(0 if (c is None or c["limit"] - c["usage"] >= 12) else 1)
PYX
python3 - "$QJ" <<'PYD' || { echo "PREP-FAILED: the DISK quota has too little room for this run (see the numbers above). Delete a stopped builder of OURS that is no longer needed (for example tc-r47-a, which the last sealing cleaned) and run the same command again"; exit 1; }
import json, sys
q = {x["metric"]: x for x in json.loads(sys.argv[1])["quotas"]}; need = 150; bad = 0
for m in ("SSD_TOTAL_GB", "DISKS_TOTAL_GB"):
    x = q.get(m)
    if x is None: continue
    free = int(x["limit"] - x["usage"]); print("   %s: %d of %d GB in use, %d GB free (this run needs about %d)" % (m, x["usage"], x["limit"], free, need)); bad |= free < need
sys.exit(1 if bad else 0)
PYD
[ -z "$(find ~/relwork -name __pycache__ | head -1)" ] || { echo "PREP-FAILED: a tool left a __pycache__"; exit 1; }
echo "STAGE-OK prepare (commit $(cut -c1-9 ~/rel-commit.txt), archive $TS)" )
