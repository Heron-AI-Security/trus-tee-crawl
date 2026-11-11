# snapwait.sh (sourced by s0-prepare.sh and s1-build.sh): wait until Canonical's snapshot service is HEALTHY for this archive date.
# Why: the service answers 200, 404, 500, 502, 503 or times out at random, in good and bad periods (reported by many users since 4 November 2026). One good answer means nothing, and a build that starts in a bad period dies half way.
# A probe is GOOD when InRelease answers 200 AND the first 64 KB of the big index of jammy/main answers 206 (or 200). The wait ends when 11 of the last 12 probes (15 seconds apart) are good, and gives up after SNAP_WAIT_MIN minutes (default 180).
# Knobs (for tests): SNAP_NEED (11), SNAP_SLEEP (15), SNAP_WAIT_MIN (180), SNAP_HOST.
snap_wait() { # TS
  local ts="$1" maxm="${SNAP_WAIT_MIN:-180}" b="https://${SNAP_HOST:-snapshot.ubuntu.com}/ubuntu/$1/dists/jammy" hist="" t0 a p g n; t0=$(date +%s)
  echo "   waiting for a healthy snapshot service for $ts (11 of the last 12 probes good; gives up after $maxm minutes)"
  while :; do
    a=$(curl -s -o /dev/null --max-time 20 -w '%{http_code}' "$b/InRelease" 2>/dev/null); p=$(curl -s -o /dev/null --max-time 30 -r 0-65535 -w '%{http_code}' "$b/main/binary-amd64/Packages.xz" 2>/dev/null)
    if [ "$a" = 200 ] && { [ "$p" = 206 ] || [ "$p" = 200 ]; }; then g=1; else g=0; fi
    hist="$hist$g"; [ "${#hist}" -gt 12 ] && hist="${hist: -12}"   # in bash ${x: -12} is EMPTY when x is shorter than 12, so trim only when longer
    n=$(printf %s "$hist" | tr -cd 1 | wc -c)
    echo "   $(date -u +%H:%M:%S) snapshot probe: InRelease=$a index=$p | last ${#hist}: $hist ($n good)"
    if [ "${#hist}" -ge 12 ] && [ "$n" -ge "${SNAP_NEED:-11}" ]; then echo "   the snapshot service is healthy: $n of the last ${#hist} probes good"; return 0; fi
    if [ $(( $(date +%s) - t0 )) -ge $(( maxm * 60 )) ]; then echo "   the snapshot service did not become healthy within $maxm minutes"; return 1; fi
    sleep "${SNAP_SLEEP:-15}"
  done
}
