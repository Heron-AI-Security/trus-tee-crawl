#!/usr/bin/env bash
# Step F0.3c, the baked crawl driver. It is started by tc-crawl.service after the four Hadoop daemons, with NO operator command, and it does what the hand-run ops/run-crawl.sh did: it reads its
# parameters from /etc/tc/crawl/params.env and its seeds from /etc/tc/crawl/seeds.txt (both measured: RTMR3 events crawl-params and crawl-seeds), waits for HDFS and YARN, puts the seeds into HDFS,
# runs Nutch's own crawl script on the baked job, checks that the crawl fetched what it should, and leaves a marker so that a later boot does not crawl again.
#   tc-crawl.sh                 run the crawl
#   tc-crawl.sh --check-params  only validate the parameters and the seeds (the image build uses it)
# The parameters are DATA: a line is KEY=VALUE with a capital key and a plain value, and nothing is ever executed from the file.
set -uo pipefail
R="${TC_ROOT:-}"; CONF="$R/etc/tc/crawl"; H="$R/opt/hadoop"; NUTCH="$R/opt/tc/nutch"; MARK="${TC_MARK:-/var/lib/tc-crawl/done}"; LOG="${TC_LOG:-/var/log/hadoop/tc-crawl.log}"
log() { echo "$(date -u +%FT%TZ) tc-crawl: $*" | tee -a "$LOG" 2>/dev/null || echo "$(date -u +%FT%TZ) tc-crawl: $*"; }
fail() { log "FAILED: $*"; exit 1; }
declare -A P
[ -f "$CONF/params.env" ] || fail "no $CONF/params.env"
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in ''|'#'*) continue ;; esac
  [[ "$line" =~ ^([A-Z_]+)=([A-Za-z0-9._:/-]+)$ ]] || fail "a line of params.env is not KEY=VALUE with a plain value: $line"
  P[${BASH_REMATCH[1]}]="${BASH_REMATCH[2]}"
done < "$CONF/params.env"
for k in ROUNDS NUM_FETCHERS NUM_TASKS SIZE_FETCHLIST NUM_THREADS TIME_LIMIT_FETCH MAP_MEMORY_MB MAP_JAVA_OPTS REDUCE_MEMORY_MB REDUCE_JAVA_OPTS HDFS_SEED_DIR HDFS_CRAWL_DIR WAIT_FOR_CLUSTER_SECONDS MIN_FETCHED AGENT_NAME AGENT_URL WARC_SOFTWARE; do [ -n "${P[$k]:-}" ] || fail "params.env lacks $k"; done
for k in ROUNDS NUM_FETCHERS NUM_TASKS SIZE_FETCHLIST NUM_THREADS TIME_LIMIT_FETCH MAP_MEMORY_MB REDUCE_MEMORY_MB WAIT_FOR_CLUSTER_SECONDS MIN_FETCHED; do [[ "${P[$k]}" =~ ^[0-9]+$ ]] || fail "$k must be a number, not '${P[$k]}'"; done
for k in HDFS_SEED_DIR HDFS_CRAWL_DIR; do [[ "${P[$k]}" =~ ^/[A-Za-z0-9._/-]+$ ]] || fail "$k must be an absolute HDFS path"; done
[[ "${P[AGENT_URL]}" =~ ^https://[A-Za-z0-9./_-]+$ ]] || fail "AGENT_URL must be a plain https address (the page that tells a site owner who runs the crawler)"
for k in AGENT_NAME WARC_SOFTWARE; do [[ "${P[$k]}" =~ ^[A-Za-z0-9._-]+$ ]] || fail "$k must be plain letters, digits, dot, dash or underscore"; done
[ -s "$CONF/seeds.txt" ] || fail "no seeds in $CONF/seeds.txt"
NSEEDS=0; while IFS= read -r u || [ -n "$u" ]; do [ -z "$u" ] && continue; [[ "$u" =~ ^https?://[A-Za-z0-9./:_-]+$ ]] || fail "a seed is not a plain http(s) address: $u"; NSEEDS=$((NSEEDS+1)); done < "$CONF/seeds.txt"
[ "$NSEEDS" -ge 1 ] || fail "no seed addresses in $CONF/seeds.txt"
if [ "${1:-}" = --check-params ]; then echo "the parameters and the $NSEEDS seeds are valid (rounds ${P[ROUNDS]}, at most ${P[SIZE_FETCHLIST]} urls per round, hdfs dirs ${P[HDFS_SEED_DIR]} and ${P[HDFS_CRAWL_DIR]})"; exit 0; fi

HD() { "$H/bin/hdfs" "$@"; }
log "start: $NSEEDS seeds, ${P[ROUNDS]} rounds, crawl dir ${P[HDFS_CRAWL_DIR]}"
t0=$(date +%s)
NW="$(awk -F'\t' '!/^#/ && $2=="worker"' "$R/run/tc/fleet.tsv" 2>/dev/null | wc -l)"; [ "$NW" -ge 1 ] || NW=1   # a fleet: wait for every worker's NodeManager
until HD dfs -ls / >/dev/null 2>&1 && [ "$(HD dfsadmin -D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem -report 2>/dev/null | grep -c '^Name:')" -ge "$NW" ] && [ "$("$H/bin/yarn" node -list -states RUNNING 2>/dev/null | grep -c RUNNING)" -ge "$NW" ]; do
  [ $(( $(date +%s) - t0 )) -lt "${P[WAIT_FOR_CLUSTER_SECONDS]}" ] || fail "HDFS (with a live DataNode per worker) and YARN were not ready within ${P[WAIT_FOR_CLUSTER_SECONDS]} seconds"
  sleep "${TC_POLL:-5}"
done
log "HDFS has its DataNodes and a NodeManager is RUNNING (after $(( $(date +%s) - t0 )) s)"
timeout 300 "$H/bin/hdfs" dfsadmin -D fs.hdfs.impl=org.apache.hadoop.hdfs.DistributedFileSystem -safemode wait >>"$LOG" 2>&1 || fail "HDFS stayed in safe mode for 300 seconds"
log "HDFS is out of safe mode"
HD dfs -rm -r -f "${P[HDFS_CRAWL_DIR]}" "${P[HDFS_SEED_DIR]}" >/dev/null 2>&1
okp=0; for try in 1 2 3 4; do HD dfs -mkdir -p "${P[HDFS_SEED_DIR]}" >>"$LOG" 2>&1 && HD dfs -put -f "$CONF/seeds.txt" "${P[HDFS_SEED_DIR]}/seeds.txt" >>"$LOG" 2>&1 && { okp=1; break; }; sleep "${TC_POLL:-5}"; done
[ "$okp" = 1 ] || fail "could not put the seeds into HDFS after 4 tries (the HDFS error is in $LOG)"
log "the seeds are in HDFS; running Nutch's crawl script on the baked job"
"$NUTCH/bin/crawl" -s "${P[HDFS_SEED_DIR]}" --num-fetchers "${P[NUM_FETCHERS]}" --num-tasks "${P[NUM_TASKS]}" --size-fetchlist "${P[SIZE_FETCHLIST]}" --num-threads "${P[NUM_THREADS]}" --time-limit-fetch "${P[TIME_LIMIT_FETCH]}" \
  -D "mapreduce.map.memory.mb=${P[MAP_MEMORY_MB]}" -D "mapreduce.map.java.opts=${P[MAP_JAVA_OPTS]}" -D "mapreduce.reduce.memory.mb=${P[REDUCE_MEMORY_MB]}" -D "mapreduce.reduce.java.opts=${P[REDUCE_JAVA_OPTS]}" \
  -D "http.agent.name=${P[AGENT_NAME]}" -D "http.agent.url=${P[AGENT_URL]}" -D "warc.export.software=${P[WARC_SOFTWARE]}" \
  "${P[HDFS_CRAWL_DIR]}" "${P[ROUNDS]}" >> "$LOG" 2>&1 || fail "the crawl script failed (see $LOG)"
STATS="$("$NUTCH/bin/nutch" readdb "${P[HDFS_CRAWL_DIR]}/crawldb" -stats 2>&1)"
FETCHED="$(printf '%s\n' "$STATS" | grep -E 'db_fetched' | grep -o '[0-9][0-9]*$' | head -1)"; FETCHED="${FETCHED:-0}"
SEGS="$(HD dfs -ls "${P[HDFS_CRAWL_DIR]}/segments" 2>/dev/null | grep -c "${P[HDFS_CRAWL_DIR]}/segments/")"
[ "$FETCHED" -ge "${P[MIN_FETCHED]}" ] || { printf '%s\n' "$STATS" >> "$LOG"; fail "only $FETCHED urls are db_fetched, at least ${P[MIN_FETCHED]} are required"; }
[ "$SEGS" -ge 1 ] || fail "no segment was written under ${P[HDFS_CRAWL_DIR]}/segments"
mkdir -p "$(dirname "$MARK")" && printf 'crawl done %s fetched=%s segments=%s rounds=%s\n' "$(date -u +%FT%TZ)" "$FETCHED" "$SEGS" "${P[ROUNDS]}" > "$MARK" || fail "could not write the marker $MARK"
log "done: $FETCHED urls fetched, $SEGS segments; marker $MARK"
