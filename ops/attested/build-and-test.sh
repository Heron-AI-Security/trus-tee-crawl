#!/usr/bin/env bash
# Compile the wrapper (src/java/org/apache/nutch/attested) and run its tests against the Hadoop that is installed on this machine:
# the unit tests of the keys (FleetKeysTest) and of the record format and the flat hash list (RecordsTest), and the smoke test of the wrapper
# over a fake file system (fake) and with a MapReduce job through it (mr, the local runner). No cluster is needed. Run from the repo root.
#   bash ops/attested/build-and-test.sh
# Settings (environment): ATTESTED_BUILD_DIR (default /tmp/attested-build), ATTESTED_JAVAC, ATTESTED_HCP (the Hadoop classpath; default `hadoop classpath`).
set -uo pipefail
OUT="${ATTESTED_BUILD_DIR:-/tmp/attested-build}"
JAVAC="${ATTESTED_JAVAC:-javac}"
HCP="${ATTESTED_HCP:-$(hadoop classpath)}"
SRC=src/java/org/apache/nutch/attested
TESTS="ops/attested/TestFleet.java ops/attested/FleetKeysTest.java ops/attested/RecordsTest.java ops/attested/AttestedFsSmoke.java"
for f in "$SRC/AttestedHdfsFileSystem.java" "$SRC/Records.java" $TESTS; do
  [ -f "$f" ] || { echo "ABORT: $f not found (run from the repo root)" >&2; exit 2; }
done
rm -rf "$OUT" && mkdir -p "$OUT/classes" "$OUT/logs"
echo "== compile"
$JAVAC -source 11 -target 11 -Xlint:all,-serial,-options -d "$OUT/classes" -cp "$HCP" "$SRC"/*.java $TESTS 2>&1 | grep -v '^Note:' | grep -v 'bad path element' | head -30
if [ "${PIPESTATUS[0]}" -ne 0 ]; then echo "COMPILE-FAILED"; exit 1; fi
echo "compiled into $OUT/classes"
fail=0
run() {  # run <label> <class> [args]
  local label="$1" cls="$2"; shift 2
  echo "== $label"
  java -cp "$OUT/classes:$HCP" "org.apache.nutch.attested.$cls" "$@" > "$OUT/logs/$label.log" 2>&1
  grep -E '^(PASS|FAIL)|ALL-PASS|SOME-FAILED|TEST-PASS|TEST-FAIL|^pass:' "$OUT/logs/$label.log" | grep -v '^PASS' | grep -v '^  pass'
  if ! grep -qE '^ALL-PASS|TEST-PASS' "$OUT/logs/$label.log"; then
    fail=1
    echo "   first error lines:"; grep -m5 -E 'Exception|Caused by|FAIL' "$OUT/logs/$label.log" | cut -c1-200
  fi
}
run fleetkeys FleetKeysTest
run records RecordsTest
run fake AttestedFsSmoke fake
run mr AttestedFsSmoke mr
echo
if [ "$fail" -eq 0 ]; then echo "ATTESTED-BUILD-AND-TEST: ALL-PASS"; else echo "ATTESTED-BUILD-AND-TEST: SOME-FAILED (logs in $OUT/logs)"; fi
exit "$fail"
