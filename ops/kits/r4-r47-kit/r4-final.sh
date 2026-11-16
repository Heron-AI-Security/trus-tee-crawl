#!/usr/bin/env bash
# r4-final.sh (the kit of step R4.6, the dated Ubuntu archive): the whole verification on the real cluster, in one command, on ONE commit (the local commit that r4-prepare2.ps1 made on the laptop; nothing of it is on GitHub yet). It builds on FRESH builders.
#   cd ~ && unzip -oq r4-r47-kit.zip && bash r4-r47-kit/r4-final.sh          run everything (finished stages are skipped when you run it again after a failure)
#   bash r4-r47-kit/r4-final.sh --status                                       which stages are done, the VMs, the last lines of the logs
#   bash r4-r47-kit/r4-final.sh --probe                                        read-only: how fast would other Hadoop mirrors be (30 seconds)
#   bash r4-r47-kit/r4-final.sh --stop-all                                     stop the three builders and delete the fleet VMs (asks first)
#   bash r4-r47-kit/r4-final.sh --restart                                      forget the finished stages and start again from the first
# Stages: prepare, build (A and B at the same time), compare, seal-prep, seal-disk, seal-image, fleet, verify, clean. It stops at the first failure and says which stage and why. Nothing is deleted on failure.
set -uo pipefail
KD="$(cd "$(dirname "$0")" && pwd)"; R=~/r4-r47-run; mkdir -p "$R/logs"; DONE="$R/stages.done"; TIM="$R/timings.txt"; touch "$DONE" "$TIM"
Z=us-central1-a; [ -s ~/evidence-fin-A/zone.txt ] && Z="$(cat ~/evidence-fin-A/zone.txt)"; [ -s ~/evidence-r47-A/zone.txt ] && Z="$(cat ~/evidence-r47-A/zone.txt)"
case "${1:-}" in
  --report) R=~/r4-r47-run; DONE="$R/stages.done"; TIM="$R/timings.txt"; eval "$(sed -n '/^report() {/,/^}/p' "$0")"; report; exit 0;;
  --status) echo "== finished stages: $(tr '\n' ' ' < "$DONE")"; echo "== times:"; cat "$TIM" 2>/dev/null; gcloud compute instances list --filter="name~'^tc-(fin|r4|f1)'" --format="table(name,status,zone.basename())"; for l in "$R"/logs/*.log; do [ -f "$l" ] && { echo "--- $(basename "$l")"; tail -2 "$l" | cut -c1-160; }; done; exit 0;;
  --probe) U="archive.apache.org/dist/hadoop/common/hadoop-3.4.3 downloads.apache.org/hadoop/common/hadoop-3.4.3 dlcdn.apache.org/hadoop/common/hadoop-3.4.3"
    echo "== the speed of Hadoop 3.4.3 downloads from the builder tc-fin-a (10 seconds each, read-only; nothing is stored)"
    for u in $U; do gcloud compute ssh tc-fin-a --zone="$Z" --quiet --command="echo -n '$u : '; curl -sL --max-time 12 -r 0-40000000 -o /dev/null -w 'HTTP %{http_code}, %{speed_download} bytes/s\n' https://$u/hadoop-3.4.3.tar.gz" </dev/null 2>/dev/null | tail -1; done
    echo "(the bake uses the first one; 80000 bytes/s means 2 hours, 20000000 bytes/s means 25 seconds)"; exit 0;;
  --stop-all) echo "this stops tc-r47-a, tc-r47-b, tc-fin-a and tc-fin-b and deletes the fleet VMs tc-f1-m and tc-f1-w if they exist (the images stay). Type yes to continue:"; read -r a; [ "$a" = yes ] || { echo "nothing done"; exit 0; }
    for v in tc-r47-a tc-r47-b tc-fin-a tc-fin-b; do gcloud compute instances stop $v --zone="$Z" --quiet 2>&1 | tail -1; done
    for v in tc-f1-m tc-f1-w; do gcloud compute instances describe $v --zone="$Z" >/dev/null 2>&1 && gcloud compute instances delete $v --zone="$Z" --quiet 2>&1 | tail -1; done; exit 0;;
  --until) UNTIL="${2:?usage: --until STAGE}"; shift 2;;
  --restart) : > "$DONE"; : > "$TIM"; echo "the list of finished stages is cleared"; shift;;
esac
case "${1:-}" in --until) UNTIL="${2:?usage: --until STAGE}"; shift 2;; esac
exec 8>"$R/lock"; flock -n 8 || { echo "R4-FINAL: another run is already active in this Cloud Shell (look at its tab, or run --status). Do not start a second one"; exit 1; }
report() {
  echo; echo "=============== REPORT: paste everything between the two lines ==============="
  echo "commit $(cut -c1-9 ~/r47-commit.txt 2>/dev/null) | finished stages: $(tr '\n' ' ' < "$DONE") | $(tr '\n' ' ' < "$TIM" 2>/dev/null)"
  g() { grep -a -h -- "$1" "$R"/logs/$2 2>/dev/null | head -${3:-1} | cut -c1-175; }
  echo "-- committed packages:"; g "DEBS-OK" build-A.log; g "DEBS-OK" build-B.log
  echo "-- the two builds:"; g "^R4-DIFF" compare.log 2; g "packages:" compare.log; g "R4-RECOMPUTE-OK" compare.log
  echo "-- seal:"; g "SEAL-OK" seal-disk.log; g "SEAL-CHECK-OK" seal-image.log
  echo "-- fleet:"; g "FLEET-DIGEST-EQUAL" fleet.log; g "F1-CHECK-OK" fleet.log 2; g "crawl done" fleet.log; g "REFERENCE-OK" fleet.log; g "EXPORT-OK" fleet.log
  echo "-- verification:"; g "AUDIT-OK" verify.log; g "RECEIPT-VERIFY-OK" verify.log; g "ENFORCE-OK" verify.log; g "R4-ACCEPT-OK" verify.log
  echo "-- VMs: $(gcloud compute instances list --filter="name~'^tc-(pin|fin|f1|seal)'" --format='value(name,status)' 2>/dev/null | tr '\n' ';')"
  echo "=============== END OF REPORT ==============="
}
START=$(date +%s); fail() { echo; echo "R4-FINAL-STOPPED at stage $1: $2"; [ -f "$R/logs/$1.log" ] && { echo "--- the lines of the log that name an error:"; grep -a -n "FAIL\|STOP\|ERROR\|refus\|stockout\|EXHAUSTED\|message:" "$R/logs/$1.log" | cut -c1-210 | head -8; }; echo "Nothing later was run and nothing was deleted. The log is $R/logs/$1.log. Fix the cause (or paste the lines above to me) and run the same command again: the finished stages are skipped."; echo "To stop the VMs that cost money: bash $KD/r4-final.sh --stop-all"; report; exit 1; }
mins() { echo $(( ($(date +%s) - $1) / 60 )); }
echo "== integrity of this kit (a partial upload would show here)"; (cd "$KD" && sha256sum -c MANIFEST.sha256 2>&1 | grep -v ': OK$' | head -3); (cd "$KD" && sha256sum -c MANIFEST.sha256 >/dev/null 2>&1) || { echo "R4-FINAL-STOPPED: the files of this kit differ from its MANIFEST.sha256: upload r4-r47-kit.zip again"; exit 1; }
until_check() { [ "${UNTIL:-}" = "$1" ] && { report; echo "STOPPED AS ASKED after stage $1. Run the command again (with a later --until, or without it) to continue: the finished stages are skipped."; exit 0; }; return 0; }
stage() { # name script token
  local n="$1" s="$2" t="$3"; grep -qx "$n" "$DONE" && { echo "== stage $n: finished before, skipped"; until_check "$n"; return 0; }
  echo; echo "##### stage $n ($(date -u +%H:%M:%S) UTC)"; local t0=$(date +%s)
  bash "$KD/$s" > "$R/logs/$n.log" 2>&1; local rc=$?; grep -a -v '^\s*downloaded ' "$R/logs/$n.log" | tail -${TAILN:-14} | cut -c1-200
  { [ $rc = 0 ] && grep -aq "$t" "$R/logs/$n.log"; } || fail "$n" "the stage did not finish with its success line ($t); see the last lines above"
  echo "$n" >> "$DONE"; echo "$n: $(mins $t0) min" >> "$TIM"; echo "   stage $n done in $(mins $t0) min"; until_check "$n"
}
build_stage() {
  local n=build; grep -qx "$n" "$DONE" && { echo "== stage $n: finished before, skipped"; until_check "$n"; return 0; }
  echo; echo "##### stage build: the two builders, at the same time ($(date -u +%H:%M:%S) UTC; about 25 minutes)"; local t0=$(date +%s)
  for ID in A B; do ( ID=$ID bash "$KD/s1-build.sh" > "$R/logs/build-$ID.log" 2>&1 ) & eval "pid$ID=\$!"; done
  while kill -0 $pidA 2>/dev/null || kill -0 $pidB 2>/dev/null; do sleep "${POLL:-60}"; echo "   $(date -u +%H:%M) A: $(grep -a '^##### stage' "$R/logs/build-A.log" | tail -1 | cut -c7-40) | B: $(grep -a '^##### stage' "$R/logs/build-B.log" | tail -1 | cut -c7-40)"; done
  wait $pidA; ra=$?; wait $pidB; rb=$?
  for ID in A B; do tail -3 "$R/logs/build-$ID.log" | cut -c1-170; done
  for ID in A B; do grep -aq "BUILD-DONE (build $ID)" "$R/logs/build-$ID.log" || fail build "build $ID did not finish (exit A=$ra B=$rb); read $R/logs/build-$ID.log"; done
  echo "$n" >> "$DONE"; echo "$n: $(mins $t0) min" >> "$TIM"; echo "   stage build done in $(mins $t0) min"; until_check "$n"
}
stage prepare s0-prepare.sh "STAGE-OK prepare"
build_stage
stage compare s2-compare.sh "STAGE-OK compare"
stage seal-prep s3a-seal-prep.sh "BLOCK-A-DONE"
stage seal-disk s3b-seal-disk.sh "BLOCK-B-DONE"
stage seal-image s3c-seal-image.sh "BLOCK-C-DONE"
stage fleet s4a-fleet.sh "BLOCK-D-DONE"
stage verify s4b-verify.sh "BLOCK-D2-DONE"
stage clean s5-clean.sh "BLOCK-E-DONE"
C="$(cut -c1-9 ~/r47-commit.txt 2>/dev/null)"
[ -n "$C" ] || fail finish "no commit is recorded (~/r47-commit.txt is missing): the prepare stage did not run in the run folder $R, so nothing was verified. Run: rm -rf $R and start again"
echo; echo "================================================================"
echo "R4-FINAL-PASS commit=$C"
echo "   total $(mins $START) min in this run. The evidence: ~/evidence-r47-final.tar.gz (SHA-256 $(sha256sum ~/evidence-r47-final.tar.gz 2>/dev/null | cut -c1-16)...), the final reference: ~/evidence-r47-f/reference-values-pinned.json"
echo "   The times of the stages are in $TIM (for the documents)."
echo "   NOW, on the laptop: run r4-push2.ps1 and type  $C  when it asks. Until then nothing of this commit is on GitHub."
echo "================================================================"
report
