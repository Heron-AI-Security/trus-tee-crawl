# prefetch.sh (sourced by s1-build.sh): the step "prefetch" of a build.
# It puts tc-prefetch.sh on the builder, starts it there DETACHED (so that it survives a recycled Cloud Shell), and polls it. It is safe to run again after any interruption: if the downloader is running it is not started twice, and if it is done nothing is repeated.
#   prefetch_builder BUILDER ZONE ARCHIVE_DATE OUT_DIR       returns 0 when the builder holds everything, 1 otherwise
# Knobs: PREFETCH_MIN (how long the downloader may be patient, default 360 minutes), PF_POLL (seconds between polls, default 60).
prefetch_builder() {
  local b="$1" z="$2" ts="$3" out="$4" kd dlm poll t0 res state fails=0 started
  kd="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; dlm="${PREFETCH_MIN:-360}"; poll="${PF_POLL:-60}"; t0=$(date +%s)
  sshb() { gcloud compute ssh "$b" --zone="$z" --quiet --command="$1" 2>&1; }
  echo "   the patient downloader for the archive of $ts goes to $b: it runs ON the builder, detached"
  res="$(sshb 'if [ -f ~/prefetch/prefetch.done ]; then echo PF-DONE; elif [ -f ~/prefetch/pid ] && kill -0 "$(cat ~/prefetch/pid)" 2>/dev/null; then echo PF-RUNNING; else echo PF-IDLE; fi' </dev/null | grep -m1 -x 'PF-DONE\|PF-RUNNING\|PF-IDLE')"
  case "$res" in
    PF-DONE) echo "   $b: the downloader had finished before: nothing to repeat";;
    PF-RUNNING) echo "   $b: the downloader is already running: not started twice";;
    PF-IDLE)
      gcloud compute ssh "$b" --zone="$z" --quiet --command='mkdir -p ~/prefetch && cat > ~/prefetch/tc-prefetch.sh && chmod +x ~/prefetch/tc-prefetch.sh' < "$kd/tc-prefetch.sh" 2>&1 | tail -1
      started="$(sshb "cd ~/prefetch && (setsid nohup bash tc-prefetch.sh $ts $dlm > /dev/null 2>&1 < /dev/null &); sleep 3; if [ -s ~/prefetch/pid ] && { kill -0 \"\$(cat ~/prefetch/pid)\" 2>/dev/null || [ -f ~/prefetch/prefetch.done ] || [ -f ~/prefetch/prefetch.failed ]; }; then echo PF-STARTED; else echo PF-NOT-STARTED; fi" </dev/null | grep -m1 -x 'PF-STARTED\|PF-NOT-STARTED')"
      [ "$started" = PF-STARTED ] || { echo "   the downloader did not start on $b ($started)"; return 1; }
      echo "   $b: started";;
    *) echo "   $b: no answer over ssh ($res): trying anyway"; ;;
  esac
  while :; do
    res="$(sshb 'f=~/prefetch; if [ -f $f/prefetch.done ]; then echo PF-DONE; cat $f/prefetch.done; elif [ -f $f/prefetch.failed ]; then echo PF-FAILED; cat $f/prefetch.failed; else echo PF-RUNNING; tail -n 1 $f/prefetch.log; fi' </dev/null)"
    state="$(echo "$res" | grep -m1 -x 'PF-DONE\|PF-FAILED\|PF-RUNNING')"
    case "$state" in
      PF-DONE) echo "   $(date -u +%H:%M) $b: the downloader is done: $(echo "$res" | tail -1 | cut -c1-150)"; sshb 'tail -n 80 ~/prefetch/prefetch.log' </dev/null > "$out/prefetch-console.txt" 2>/dev/null; return 0;;
      PF-FAILED) echo "   $b: the downloader gave up: $(echo "$res" | tail -1 | cut -c1-120)"; sshb 'tail -n 40 ~/prefetch/prefetch.log' </dev/null > "$out/prefetch-console.txt" 2>/dev/null; return 1;;
      PF-RUNNING) fails=0; echo "   $(date -u +%H:%M) $b: downloading, $(( ( $(date +%s) - t0 ) / 60 )) min so far | $(echo "$res" | tail -1 | cut -c1-110)";;
      *) fails=$((fails+1)); echo "   $(date -u +%H:%M) $b: no answer over ssh ($fails in a row): $(echo "$res" | tail -1 | cut -c1-100)"; [ "$fails" -ge 30 ] && { echo "   too many failed ssh calls in a row"; return 1; };;
    esac
    if [ $(( $(date +%s) - t0 )) -ge $(( (dlm + 15) * 60 )) ]; then echo "   waited $((dlm + 15)) minutes: giving up (the downloader may still be running on $b: run the kit again to keep waiting)"; return 1; fi
    sleep "$poll"
  done
}
