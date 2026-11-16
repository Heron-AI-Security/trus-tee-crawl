#!/usr/bin/env bash
# Step 0, check-source: is the source of this build what it claims to be, and is everything in place before the builders cost money?
# It unpacks the source archive of the commit, checks the committed packages against their checksums, checks that the archive names this commit in its own header,
# makes the second archive (for build B), runs the rehearsals of the repository once per commit, and checks that no builder or sealed image of this commit exists
# and that the quota has room. Nothing is created in the cloud. Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names
H="$HOME"; TREE="$H/$BUILD_TREE"; A="$H/$SOURCE_TGZ"; ALT="$H/$SOURCE_ALT_TGZ"; CF="$H/$BUILD_COMMIT_FILE"; MARK="$H/$REHEARSED_MARK"; RD="$H/$BUILD_REHEARSALS"
NEED_FREE_MB="${RK_NEED_FREE_MB:-700}"; NEED_C3_CPUS=24; NEED_DISK_GB=590   # what the build needs: the unpacked tree and the second archive; the vCPUs of two builders and the sealing helpers; the disks of both builds
fail() { echo "CHECK-SOURCE-FAILED: $*"; exit 1; }

echo "== 1. the source archive of commit $ID"
[ -f "$A" ] || fail "there is no ~/$SOURCE_TGZ. Make it on the laptop with   git archive --format=tar.gz -o $SOURCE_TGZ $C9   and upload it to the home folder of Cloud Shell"
FREE=$(df -Pm "$H" | awk 'NR==2{print $4}')
if [ "${FREE:-0}" -lt "$NEED_FREE_MB" ]; then
  echo "   the biggest items in the home folder (a list only; nothing was deleted; evidence-* folders and the files of this run must stay):"
  du -sk "$H"/* "$H"/.[!.]* 2>/dev/null | sort -rn | head -8 | awk '{printf "   %9.1f MB  %s\n", $1 / 1024, $2}'
  fail "only ${FREE:-0} MB are free in the home folder, and this step needs about $NEED_FREE_MB MB (the unpacked tree and the second archive each hold the committed packages). Free space first, then run the same command again"
fi
rm -rf "$TREE"; mkdir -p "$TREE" "$RD" || fail "cannot make the folder $TREE"
tar xzf "$A" -C "$TREE" || fail "the archive ~/$SOURCE_TGZ cannot be unpacked"
cd "$TREE" || exit 1
chmod +x ops/image/test/*.sh ops/image/build/*.sh ops/image/rootfs/usr/local/lib/tc/*.sh 2>/dev/null
#DEBS-CHECK-BEGIN
echo "== 2. the committed Ubuntu packages (ops/image/debs): every file must match SHA256SUMS, and SOURCE.txt names the base image that the builders are made from"
[ -s ops/image/debs/SHA256SUMS ] && [ -s ops/image/debs/SOURCE.txt ] || fail "ops/image/debs is not in this commit (the packages that the build installs are committed there)"
( cd ops/image/debs && sha256sum --quiet -c SHA256SUMS ) || fail "a committed package does not match SHA256SUMS"
BI="$(sed -n 's/^base_image: *//p' ops/image/debs/SOURCE.txt | tr -d ' \r')"; [[ "$BI" =~ ^ubuntu-2204-jammy-v[0-9]{8}$ ]] || fail "ops/image/debs/SOURCE.txt does not name a base image (base_image: ubuntu-2204-jammy-vYYYYMMDD)"
echo "   $(grep -c . ops/image/debs/SHA256SUMS) packages match; the builders are made from $BI"
#DEBS-CHECK-END
NP="$(grep -c . ops/image/debs/SHA256SUMS)"

echo "== 3. the files that the later steps need must be in this commit"
for f in $RK_REQUIRED_FILES; do [ -f "$f" ] || fail "$f is not in the commit that is to be built. The later steps need it, and it is better to know now than after hours: the commit that adds it must come before the commit that is built"; done
echo "   all $(echo $RK_REQUIRED_FILES | wc -w) files are there"

echo "== 4. the archive must name this commit in its own header, and build B gets a second archive of it"
HAVE="$(sha256sum "$A" | cut -c1-64)"; echo "   source archive SHA-256: $HAVE"
python3 -B "$TREE/$RK_T_ARCHIVE_CHECK" "$A" --sha256 "$HAVE" --expect "$ID" --commit-file "$CF" > "$H/$BUILD_DIR/archive-check.txt" 2>&1 || { sed 's/^/   | /' "$H/$BUILD_DIR/archive-check.txt" | head -5; fail "the archive ~/$SOURCE_TGZ is not an archive of commit $ID (the lines above are from the check tool)"; }
case "$(cat "$CF" 2>/dev/null)" in "$ID"*) ;; *) fail "the commit file $CF does not start with $ID";; esac
echo "   the header of the archive names commit $(cat "$CF")"
gzip -dc "$A" | gzip -1 -n > "$ALT" || fail "cannot make the second archive"
[ "$(sha256sum < "$A")" != "$(sha256sum < "$ALT")" ] || fail "the repacked archive equals the original, so the check that two builds from two different archives agree would prove nothing"
echo "   the second archive ~/$SOURCE_ALT_TGZ has other bytes (SHA-256 $(sha256sum < "$ALT" | cut -c1-16)... against $(sha256sum < "$A" | cut -c1-16)...)"

echo "== 5. the rehearsals of the repository, run on the unpacked commit (about 5 to 7 minutes the first time)"
REH_N=0; LIST="${RK_REHEARSALS:-$RK_REHEARSALS_DEFAULT}"
RENV=(env -i HOME="$H" PATH="$PATH" LANG="${LANG:-C.UTF-8}" USER="${USER:-$(id -un)}" TERM="${TERM:-dumb}")   # a rehearsal runs as it does by hand: with nothing of this run in its environment
if [ -e "$MARK" ] && [ "$(cat "$MARK")" = "$RK_REHEARSALS_DEFAULT" ]; then echo "   all of them passed on this commit before: not run again"; REH_NOTE="passed before"
else
  command -v xxd >/dev/null 2>&1 || { mkdir -p "$H/.cloudshell"; touch "$H/.cloudshell/no-apt-get-warning"; sudo apt-get install -y -qq xxd < /dev/null > /dev/null 2>&1; }
  command -v xxd >/dev/null 2>&1 || fail "xxd is missing (the rehearsals need it): run  sudo apt-get install -y xxd  and start again"
  for s in $LIST; do
    SU=""; case " $RK_REHEARSALS_AS_ROOT " in *" $s "*) SU="sudo";; esac
    for try in 1 2; do
      $SU "${RENV[@]}" bash "$TREE/$RK_REHEARSAL_DIR/$s.sh" "$TREE" > "$RD/$s.out" 2>&1; [ -z "$SU" ] || sudo chown -R "$(id -u):$(id -g)" "$TREE" "$RD" 2>/dev/null
      tail -2 "$RD/$s.out" | tr '\n' ' ' | grep -q 'PASS' && break
      [ "$try" = 2 ] || { cp "$RD/$s.out" "$RD/$s.out.first"; echo "   $s did not pass: running it once more (a few checks fail now and then and pass on a second run; a real fault fails again)"; }
    done
    tail -2 "$RD/$s.out" | tr '\n' ' ' | grep -q 'PASS' || { F="$(grep -E '^ *FAIL' "$RD/$s.out" | head -8)"; [ -n "$F" ] || F="$(tail -12 "$RD/$s.out")"; echo "   its failing checks (or, if it printed none, its last lines):"; printf '%s\n' "$F" | cut -c1-200 | sed 's/^/   | /'; fail "the rehearsal $s does not pass here (its output: $RD/$s.out)"; }
    [ "$try" = 1 ] || echo "   NOTE: $s passed on the second run; the output of the first run is in $RD/$s.out.first"
    echo "   $s: passed"; REH_N=$((REH_N + 1))
  done
  echo "$LIST" > "$MARK"; REH_NOTE="$REH_N passed"; [ "$LIST" = "$RK_REHEARSALS_DEFAULT" ] || echo "   NOTE: this was a SHORTER list than the full one, so the next run without RK_REHEARSALS runs them all"
fi

echo "== 6. nothing of an earlier attempt may be left: no builder, no sealed image of this commit"
OLDV="$(gcloud compute instances list --filter="name~'^tc-b-${C9}-'" --format='value(name,zone.basename())' 2>/dev/null | tr '\n' ';')"
[ -z "$OLDV" ] || fail "builders of this commit exist from an earlier attempt: $OLDV Delete them (gcloud compute instances delete NAME --zone=ZONE) or use run-kit.sh stop build, and run again"
OLDI="$(gcloud compute images list --filter="name~'^tc-img-${C9}-'" --format='value(name)' 2>/dev/null | tr '\n' ' ')"
[ -z "$OLDI" ] || fail "sealed images of this commit exist already: $OLDI. The sealing steps skip an image that is ready, so this run would reuse an old image instead of making a new one. This commit is already built (look for its build record); to build it again, delete the images first"

echo "== 7. the quota must have room (two builders and the sealing helpers now; the disks of both builds)"
QJ="$(gcloud compute regions describe "${ZONE%-*}" --format=json 2>/dev/null)"
python3 - "$QJ" "$NEED_C3_CPUS" "$NEED_DISK_GB" <<'PYX' || fail "the quota has too little room for this build (the numbers are above). Stop something of OURS that is no longer needed (never the teammate's VMs) and run the same command again"
import json, sys
nc, ng = int(sys.argv[2]), int(sys.argv[3])
try: q = {x["metric"]: x for x in json.loads(sys.argv[1])["quotas"]}
except Exception: print("   the quota could not be read"); sys.exit(1)
bad = 0
c = q.get("C3_CPUS")
if c is not None:
    free = int(c["limit"] - c["usage"]); print("   C3_CPUS: %d of %d in use, %d free (this build needs about %d)" % (c["usage"], c["limit"], free, nc)); bad |= free < nc
for m in ("SSD_TOTAL_GB", "DISKS_TOTAL_GB"):
    x = q.get(m)
    if x is None: continue
    free = int(x["limit"] - x["usage"]); print("   %s: %d of %d GB in use, %d GB free (this build needs about %d)" % (m, x["usage"], x["limit"], free, ng)); bad |= free < ng
sys.exit(1 if bad else 0)
PYX
[ -z "$(find "$H/$BUILD_DIR" -name __pycache__ 2>/dev/null | head -1)" ] || fail "a tool left a __pycache__ folder in $H/$BUILD_DIR (every tool must run with python3 -B)"

rk_result "source of commit $C9 is ready: $NP packages match their checksums (base image $BI), the archive names the commit, the second archive differs, rehearsals $REH_NOTE, no builder or image of this commit exists, the quota has room"
