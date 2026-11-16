#!/usr/bin/env bash
# hadoop-fetch.sh: runs ON a builder (the kit sends it through ssh). Downloads the Hadoop tarball with several parallel connections into ~/bake, so that the bake finds it complete and skips its own slow single-connection download. Many servers limit every connection: N connections then give about N times the speed.
# NOTHING is trusted here: the bake checks the SHA-512 of the file against the checksum file of the official Apache archive afterwards, whichever server this script used.
# It never makes the build fail: if anything is not as expected it says so and leaves the download to the bake.
# Settings: HBASE (the folder of the server, default the Apache archive), PARTS (connections, default 8, 1 to 32), EXPECT_SIZE (the size the file must have), DEST (default ~/bake).
set -u
HVER="${HVER:-3.4.3}"; TAR="hadoop-$HVER.tar.gz"; BASE="${HBASE:-https://archive.apache.org/dist/hadoop/common/hadoop-$HVER}"; N="${PARTS:-8}"; DEST="${DEST:-$HOME/bake}"
[[ "$N" =~ ^[0-9]+$ ]] && [ "$N" -ge 1 ] && [ "$N" -le 32 ] || { echo "HADOOP-FETCH-SKIP: PARTS must be a number from 1 to 32 (the bake will download by itself)"; exit 0; }
mkdir -p "$DEST" && cd "$DEST" || { echo "HADOOP-FETCH-SKIP: no folder $DEST"; exit 0; }
SIZE="$(curl -sIL --connect-timeout 15 --max-time 30 "$BASE/$TAR" | grep -i '^content-length' | tail -1 | tr -dc 0-9)"
[ -n "$SIZE" ] && [ "$SIZE" -gt 1000000 ] || { echo "HADOOP-FETCH-SKIP: cannot read the size of $BASE/$TAR (the bake will download by itself)"; exit 0; }
[ -z "${EXPECT_SIZE:-}" ] || [ "$SIZE" = "$EXPECT_SIZE" ] || { echo "HADOOP-FETCH-SKIP: $BASE/$TAR is $SIZE bytes, expected $EXPECT_SIZE (another file?): the bake will decide"; exit 0; }
[ "$(stat -c %s "$TAR" 2>/dev/null || echo 0)" != "$SIZE" ] || { echo "HADOOP-FETCH-OK: $TAR is already here ($SIZE bytes)"; exit 0; }
CODE="$(curl -s -o /dev/null -r 0-0 -w '%{http_code}' --connect-timeout 15 --max-time 8 "$BASE/$TAR")"   # a server that ignores the range starts to send the whole file: 8 seconds are enough to see the answer code
[ "$CODE" = 206 ] || { echo "HADOOP-FETCH-SKIP: the server does not do range requests (HTTP $CODE): every part would be the whole file, so the bake will download by itself"; exit 0; }
PART=$(( (SIZE + N - 1) / N )); T0=$(date +%s)
echo "downloading $(( SIZE / 1048576 )) MB in $N parts of about $(( PART / 1048576 )) MB from $BASE"
rm -f "$TAR".part.* "$TAR.tmp"
fetch_part() { local i=$1 s=$2 e=$3 try want=$(( $3 - $2 + 1 )); for try in 1 2 3 4 5; do rm -f "$TAR.part.$i"; if curl -sfL --connect-timeout 15 --max-time 1800 -r "$s-$e" -o "$TAR.part.$i" "$BASE/$TAR" && [ "$(stat -c %s "$TAR.part.$i" 2>/dev/null)" = "$want" ]; then return 0; fi; sleep 3; done; return 1; }
PIDS=(); for i in $(seq 0 $((N - 1))); do s=$(( i * PART )); [ "$s" -lt "$SIZE" ] || break; e=$(( s + PART - 1 )); [ "$e" -lt "$SIZE" ] || e=$(( SIZE - 1 )); fetch_part "$i" "$s" "$e" & PIDS+=($!); done
BAD=0; for p in "${PIDS[@]}"; do wait "$p" || BAD=$((BAD + 1)); done
if [ "$BAD" != 0 ]; then rm -f "$TAR".part.*; echo "HADOOP-FETCH-FAILED: $BAD part(s) failed after 5 tries each: the bake will download by itself"; exit 0; fi
for i in $(seq 0 $(( ${#PIDS[@]} - 1 ))); do cat "$TAR.part.$i"; done > "$TAR.tmp"; rm -f "$TAR".part.*
[ "$(stat -c %s "$TAR.tmp")" = "$SIZE" ] || { rm -f "$TAR.tmp"; echo "HADOOP-FETCH-FAILED: the joined file has the wrong size: the bake will download by itself"; exit 0; }
mv "$TAR.tmp" "$TAR"; T=$(( $(date +%s) - T0 )); [ "$T" -gt 0 ] || T=1
echo "HADOOP-FETCH-OK: $TAR ($SIZE bytes) in $T s, about $(( SIZE / T / 1024 )) KB/s; the bake still checks its SHA-512 against the Apache archive"
