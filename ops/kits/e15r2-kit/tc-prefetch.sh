#!/usr/bin/env bash
# tc-prefetch.sh: runs ON the builder, detached (setsid nohup), started by the kit (step "prefetch" of s1-build.sh).
# Why: Canonical's snapshot service is unreliable (random 404, 500, 502, 503, timeouts, in bad periods of minutes to hours). The build scripts of the commit download from it live, once, in the middle of the build, with immediate retries only, so one bad period kills the build.
# What: it fills apt's package lists and package cache from the DATED copy of the archive, PATIENTLY: it repeats "update, then download everything that the build will install" with pauses, for up to DEADLINE minutes. Every file that arrives stays on the disk and is never fetched again, so the progress cannot be lost. When it is done, tc-image-aptpin.sh, prep, bake, job and lock find everything locally.
# Nothing of it stays in the image: tc-image-clean.sh removes /var/lib/apt/lists and runs apt-get clean, and the files of this script are in the home folder like the other build files.
# The package lists are the exact install commands of the build scripts (the flags matter: wireguard-tools and xxd are installed WITH recommends, the others without):
#   tc-image-prep.sh: xxd | wireguard-tools     tc-image-bake.sh: --no-install-recommends openjdk-11-jdk-headless ca-certificates
#   tc-image-job.sh: --no-install-recommends ant maven git libcld2-0     tc-image-lock.sh: nftables
#   bash tc-prefetch.sh TS [DEADLINE_MINUTES]     writes ~/prefetch/{prefetch.log, pid, prefetch.done | prefetch.failed}
# Hooks for the rehearsal only: TC_PF_DIR, TC_SUDO, TC_APT, TC_APTCACHE, TC_PF_SLEEP, TC_PF_ARCH, TC_SNAPSHOT_URL.
set -u
TS="${1:?usage: tc-prefetch.sh TS [DEADLINE_MINUTES]}"; DEADLINE="${2:-360}"
D="${TC_PF_DIR:-$HOME/prefetch}"; mkdir -p "$D"; LOG="$D/prefetch.log"; exec >> "$LOG" 2>&1
SUDO="${TC_SUDO-sudo}"; APT="${TC_APT:-apt-get}"; APTC="${TC_APTCACHE:-apt-cache}"; SLEEP="${TC_PF_SLEEP:-60}"; ARCH="${TC_PF_ARCH:-/var/cache/apt/archives}"; BASE="${TC_SNAPSHOT_URL:-https://snapshot.ubuntu.com/ubuntu}"
[[ "$TS" =~ ^[0-9]{8}T[0-9]{6}Z$ ]] || { echo "ABORT: the archive date '$TS' is not in the form YYYYMMDDTHHMMSSZ"; echo "bad date" > "$D/prefetch.failed"; exit 1; }
echo $$ > "$D/pid"; rm -f "$D/prefetch.done" "$D/prefetch.failed"
echo "[$(date -u +%FT%TZ)] start: archive $TS, patient for up to $DEADLINE minutes"
mkdir -p "$D/empty.d"; : > "$D/pre.list"
for s in jammy jammy-updates jammy-security; do echo "deb $BASE/$TS $s main restricted universe multiverse" >> "$D/pre.list"; done
# the same lines as tc-image-aptpin.sh writes; a separate file, so that /etc/apt/sources.list (which aptpin keeps once as sources.list.tc-orig) is not touched here
OPTS=(-o Dir::Etc::sourcelist="$D/pre.list" -o Dir::Etc::sourceparts="$D/empty.d" -o Acquire::Check-Valid-Until=false -o Acquire::Retries=5 -o Acquire::http::Timeout=60 -o Acquire::https::Timeout=60 -o APT::Update::Error-Mode=any)
dl() { $SUDO env DEBIAN_FRONTEND=noninteractive $APT install --download-only -y "${OPTS[@]}" "$@"; }
round() {
  $SUDO $APT update -qq "${OPTS[@]}" || { echo "   the update did not complete"; return 1; }
  dl xxd || return 1
  dl wireguard-tools || return 1
  dl --no-install-recommends openjdk-11-jdk-headless ca-certificates || return 1
  dl --no-install-recommends ant maven git libcld2-0 || return 1
  dl nftables || return 1
  # apt-get update exits 0 even when some indexes failed: the proof is a candidate that comes from THIS dated copy
  local pol; pol="$($APTC "${OPTS[@]}" policy openjdk-11-jdk-headless 2>&1)"
  echo "$pol" | grep -q "^  Candidate: [^(]" || { echo "   no candidate for openjdk-11-jdk-headless: the package lists are incomplete"; return 1; }
  echo "$pol" | grep -q "$BASE/$TS" || { echo "   the candidate does not come from the dated copy $BASE/$TS"; return 1; }
  return 0
}
t0=$(date +%s); n=0
while :; do
  n=$((n+1)); echo "[$(date -u +%H:%M:%S)] round $n"
  if round; then break; fi
  el=$(( $(date +%s) - t0 ))
  if [ "$el" -ge $((DEADLINE*60)) ]; then echo "GAVE-UP after $DEADLINE minutes ($n rounds)"; echo "gave up after $n rounds" > "$D/prefetch.failed"; exit 1; fi
  echo "   round $n did not complete (a bad period of the snapshot service?): waiting $SLEEP s, $((el/60)) min so far"; sleep "$SLEEP"
done
NDEB=$(ls "$ARCH"/*.deb 2>/dev/null | wc -l); SZ=$(du -sh "$ARCH" 2>/dev/null | cut -f1)
echo "PREFETCH-DONE: $NDEB packages ($SZ) in the apt cache and the package lists of $TS on the disk, after $n round(s) and $(( ($(date +%s) - t0) / 60 )) min"
echo "rounds=$n packages=$NDEB size=$SZ archive=$TS finished=$(date -u +%FT%TZ)" > "$D/prefetch.done"
