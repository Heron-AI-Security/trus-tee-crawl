#!/usr/bin/env bash
# Step 1, build-twice: two fresh builders, A and B, build the image from the same commit at the same time. Build B starts from the repacked twin of the source archive, so that
# the comparison in the next step shows that the result does not depend on the bytes of one archive. Every build is its own builder VM with its own folder (~/build-<commit>/a and /b)
# and its own list of finished stages (done.txt): a second run skips the stages that are done and goes on at the failed one on the same builder. The Hadoop tarball comes from a fast
# mirror (the bake still checks its SHA-512 against the Apache archive, whichever server was used). Run by run-kit.sh; it reports its result with rk_result.
set -uo pipefail
KD="$(cd "$(dirname "$0")/.." && pwd)"; . "$KD/names.sh"; . "$KD/lib.sh"; . "$KD/tools.sh"; rk_load_names
H="$HOME"; TREE="$H/$BUILD_TREE"; CF="$H/$BUILD_COMMIT_FILE"; BD="$H/$BUILD_DIR"
HADOOP_VERSION=3.4.3; HADOOP_SIZE=514917037; HADOOP_BASE="https://dlcdn.apache.org/hadoop/common/hadoop-$HADOOP_VERSION"; HADOOP_PARTS=1
fail() { echo "BUILD-TWICE-FAILED: $*"; exit 1; }

[ -s "$CF" ] && [ -s "$TREE/ops/image/debs/SOURCE.txt" ] && [ -s "$H/$SOURCE_TGZ" ] && [ -s "$H/$SOURCE_ALT_TGZ" ] || fail "step 0 has not run (it unpacks the source archive and makes the second archive): run the same command without --until"
COMMIT="$(cat "$CF")"
BASE_IMAGE="$(sed -n 's/^base_image: *//p' "$TREE/ops/image/debs/SOURCE.txt" | tr -d ' \r')"; [[ "$BASE_IMAGE" =~ ^ubuntu-2204-jammy-v[0-9]{8}$ ]] || fail "ops/image/debs/SOURCE.txt names no base image (the builders are made from the image that the committed packages were captured against)"
KV="$(ls "$TREE/ops/image/debs" | sed -n 's/^linux-image-\(.*-gcp\)_.*\.deb$/\1/p' | sort -u)"; [ "$(echo "$KV" | grep -c .)" = 1 ] || fail "ops/image/debs must carry exactly one kernel image package (linux-image-...-gcp); found: $(echo $KV)"
REGION="${ZONE%-*}"; ZONES="$ZONE"; for z in a b c f; do [ "$REGION-$z" = "$ZONE" ] || ZONES="$ZONES $REGION-$z"; done
cd "$TREE" || exit 1

build_one() {  # ID (A or B): the whole build on its own builder; its output goes to its own log
  local ID="$1" idl="${1,,}" BUILDER OUT ARCH ARCH_SHA DONE LOG z GOT rc st ZZ
  if [ "$ID" = A ]; then BUILDER="$BUILDER_A"; ARCH="$H/$SOURCE_TGZ"; else BUILDER="$BUILDER_B"; ARCH="$H/$SOURCE_ALT_TGZ"; fi
  ARCH_SHA="$(sha256sum "$ARCH" | cut -c1-64)"; OUT="$BD/$idl"; mkdir -p "$OUT"; DONE="$OUT/done.txt"; touch "$DONE"; LOG="$OUT/console.txt"
  local -a DENV=(env BASE_IMAGE="$BASE_IMAGE" BUILDER="$BUILDER" MANIFEST_VM="$BUILDER" OUT="$OUT" COMMIT_FILE="$CF" SRC_TGZ="$ARCH" SRC_SHA="$ARCH_SHA" HADOOP_ALLOW_SLOW=1 KVER="$KV")   # what the driver reads, in front of each call and nowhere else
  exec 9> "$OUT/lock"; flock -n 9 || { echo "BUILD-TWICE-FAILED: another run of build $ID is already active in this Cloud Shell (two runs of the same stage delete each other's work)"; exit 1; }
  echo "build $ID of commit ${COMMIT:0:9}: archive $(basename "$ARCH"), base image $BASE_IMAGE, kernel $KV, builder $BUILDER"
  echo "== the builder (the zones in turn, but only when a zone has no capacity; any other error stops here)"
  if ! grep -qx builder "$DONE"; then
    GOT=""
    for z in $ZONES; do
      echo "--- builder in $z" | tee -a "$LOG"
      "${DENV[@]}" ZONE="$z" bash "$TREE/$RK_T_IMAGE_DRIVER" builder 2>&1 | tee "$OUT/builder-$z.txt" | cut -c1-200; rc=${PIPESTATUS[0]}; cat "$OUT/builder-$z.txt" >> "$LOG"
      if [ "$rc" = 0 ]; then GOT="$z"; break; fi
      if [ -n "$(gcloud compute instances list --filter="name=$BUILDER" --format='value(name)' 2>/dev/null)" ]; then echo "BUILD-TWICE-FAILED: the builder $BUILDER was created in $z but its start failed (it is kept; look at the output above)"; exit 1; fi
      if grep -qE "$RK_CAPACITY_RX" "$OUT/builder-$z.txt"; then echo "   no capacity in $z: trying the next zone"; continue; fi
      echo "BUILD-TWICE-FAILED: the builder could not be created in $z for a reason other than capacity (the error is above; nothing was created, no other zone is tried)"; exit 1
    done
    [ -n "$GOT" ] || { echo "BUILD-TWICE-FAILED: no zone had capacity (nothing was created)"; exit 1; }
    echo "$GOT" > "$OUT/zone.txt"; echo builder >> "$DONE"
  fi
  ZZ="$(cat "$OUT/zone.txt")"; echo "the builder is in $ZZ"
  for st in $RK_BUILD_STAGES; do
    if grep -qx "$st" "$DONE"; then echo "== $st: done before, skipped"; continue; fi
    if [ "$st" = fetch-hadoop ]; then
      echo; echo "##### stage fetch-hadoop: the Hadoop tarball from a fast mirror ($HADOOP_BASE, $HADOOP_PARTS connection(s)); the bake still checks its SHA-512 against the Apache archive. If this fails, the bake downloads from its own server (slow)" | tee -a "$LOG"
      gcloud compute ssh "$BUILDER" --zone="$ZZ" --quiet --command='mkdir -p ~/bake' < /dev/null 2>&1 | tail -1
      gcloud compute ssh "$BUILDER" --zone="$ZZ" --quiet --command="HVER='$HADOOP_VERSION' HBASE='$HADOOP_BASE' PARTS=$HADOOP_PARTS EXPECT_SIZE=$HADOOP_SIZE bash -s" < "$KD/hadoop-fetch.sh" 2>&1 | tail -4 | tee -a "$LOG"
      echo fetch-hadoop >> "$DONE"; continue
    fi
    echo; echo "##### stage $st ($(date -u +%H:%M:%S) UTC)" | tee -a "$LOG"
    "${DENV[@]}" ZONE="$ZZ" bash "$TREE/$RK_T_IMAGE_DRIVER" "$st" 2>&1 | tee -a "$LOG" | cut -c1-200; rc=${PIPESTATUS[0]}
    [ "$rc" = 0 ] || { echo; echo "BUILD-TWICE-FAILED at stage $st (the builder $BUILDER is kept; the output is above)"; exit 1; }
    echo "$st" >> "$DONE"
  done
  echo; echo "== what build $ID recorded"
  echo "source: $(cat "$OUT/r4/source.txt")"; [ "$(cat "$OUT/r4/source.txt")" = "commit $COMMIT" ] || { echo "BUILD-TWICE-FAILED: the image of build $ID records another commit than the archive's"; exit 1; }
  echo "events measured: $(cut -f1 "$OUT/r4/events.tsv" | tr '\n' ' ')"
  tar czf "$BD/evidence-$idl.tar.gz" -C "$BD" "$idl" || { echo "BUILD-TWICE-FAILED: cannot pack the evidence of build $ID"; exit 1; }
  echo "evidence fingerprint: $(sha256sum "$BD/evidence-$idl.tar.gz" | cut -c1-64)"; echo "BUILD-DONE (build $ID)"
}

echo "== two builds at the same time, one builder each (the old kit needed about 25 minutes of work and more of copying; the logs are $BD/a/build.log and $BD/b/build.log)"
t0=$(date +%s); PIDS=()
for ID in A B; do idl="${ID,,}"; mkdir -p "$BD/$idl"; ( build_one "$ID" ) > "$BD/$idl/build.log" 2>&1 & PIDS+=($!); done
hb_print() { for idl in a b; do echo "   [heartbeat $(date -u +%H:%M) UTC, $(rk_mins "$t0") min] build ${idl^^}: $(grep -vx builder "$BD/$idl/done.txt" 2>/dev/null | grep -c .) of $(echo $RK_BUILD_STAGES | wc -w) stages done | last line: $(grep -av '^\s*downloaded ' "$BD/$idl/build.log" | tail -n 1 | cut -c1-110)"; done; }
rk_wait_watch hb_print "${PIDS[@]}"   # a heartbeat every few minutes, and the end is noticed within a second
BAD=0; for i in 0 1; do wait "${PIDS[$i]}" || { BAD=$((BAD + 1)); echo "build $(echo AB | cut -c$((i + 1))) FAILED. The end of its log:"; tail -n 14 "$BD/$(echo ab | cut -c$((i + 1)))/build.log" | cut -c1-200 | sed 's/^/   | /'; }; done
[ "$BAD" = 0 ] || fail "$BAD of the 2 builds failed (see above). The finished stages are kept: run the same command again and every build goes on at its failed stage on its own builder"
for idl in a b; do grep -q "^BUILD-DONE" "$BD/$idl/build.log" || fail "the log of build ${idl^^} does not end with BUILD-DONE"; done
NEV="$(grep -c . "$BD/a/r4/events.tsv")"
rk_result "both builds are finished in $(rk_mins "$t0") min: A on $BUILDER_A (zone $(cat "$BD/a/zone.txt")) and B on $BUILDER_B (zone $(cat "$BD/b/zone.txt")), $(echo $RK_BUILD_STAGES | wc -w) stages each, both record commit ${COMMIT:0:9}, build A measured $NEV events"
