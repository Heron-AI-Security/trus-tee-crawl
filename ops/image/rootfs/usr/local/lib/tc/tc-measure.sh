#!/usr/bin/env bash
# Measure the image's fixed stack into RTMR3 at boot, before any Hadoop daemon (step F0.2).
# Reads the list /etc/tc/measured-paths.txt (NAME <TAB> PATH [<TAB> SKIP-PATHS]), one event per line, in that order.
# It refuses to run unless RTMR3 is zero at its start, and it stops (so that nothing that requires it starts) if a path is missing or an extension fails.
#   tc-measure.sh               measure
#   tc-measure.sh --check-list  only check that the list is well formed and every path exists (no TDX interface needed)
# Hooks for the rehearsal only: TC_ROOT (a fake root that the listed paths are under), TC_LIB, TC_LIST, TC_RTMR3, TC_RUN, TC_STATE.
set -euo pipefail
LIB="${TC_LIB:-/usr/local/lib/tc}"; LIST="${TC_LIST:-/etc/tc/measured-paths.txt}"
RT="${TC_RTMR3:-/sys/devices/virtual/misc/tdx_guest/measurements/rtmr3:sha384}"
RUN="${TC_RUN:-/run/tc}"; STATE="${TC_STATE:-/var/lib/tc}"
fail() { echo "TC-MEASURE-FAIL: $*" >&2; rm -f "$RUN/measure-done" 2>/dev/null || true; exit 1; }
[ -f "$LIST" ] || fail "no list at $LIST"
CHECK=no; [ "${1:-}" = "--check-list" ] && CHECK=yes
n=0
while IFS=$'\t' read -r name path skips; do
  case "$name" in ''|'#'*) continue ;; esac
  [ -n "${path:-}" ] || fail "list line without a path: $name"
  [ -e "${TC_ROOT:-}$path" ] || fail "measured path does not exist: $path ($name)"
  n=$((n+1))
done < "$LIST"
[ "$n" -ge 1 ] || fail "the list measures nothing"
if [ "$CHECK" = yes ]; then echo "TC-LIST-OK: $n entries, every path exists"; exit 0; fi
[ -e "$RT" ] || fail "no RTMR3 interface at $RT (is this a TDX guest with a kernel that can extend RTMR3, 6.16 or later?)"
R3="$(xxd -p "$RT" | tr -d '\n')"
[ -z "$(printf '%s' "$R3" | tr -d 0)" ] || fail "RTMR3 is not zero at start (already measured on this boot?)"
mkdir -p "$RUN" "$STATE"; rm -f "$RUN/measure-done"
LOGF="$RUN/rtmr3-events.tsv"; : > "$LOGF"
export TC_LOG="$LOGF" TC_RTMR3="$RT"
while IFS=$'\t' read -r name path skips; do
  case "$name" in ''|'#'*) continue ;; esac
  # shellcheck disable=SC2086
  "$LIB/tc-extend.sh" "$name" "${TC_ROOT:-}$path" ${skips:-} > /dev/null < /dev/null || fail "could not extend RTMR3 with $name"
done < "$LIST"
boot=$(( $(cat "$STATE/bootcount" 2>/dev/null || echo 0) + 1 )); echo "$boot" > "$STATE/bootcount"
cp "$LOGF" "$STATE/events-boot$boot.tsv"; cp "$LOGF" "$STATE/last-boot-events.tsv"
date -u +%FT%TZ > "$RUN/measure-done"
echo "TC-MEASURE-OK boot=$boot events=$n rtmr3=$(xxd -p "$RT" | tr -d '\n' | cut -c1-16)"
