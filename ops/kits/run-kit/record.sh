#!/usr/bin/env bash
# record.sh: the BUILD RECORD, the folder that the build leaves for every crawl. A crawl uses a sealed image only if the record of its build
# is complete and its fingerprint is the one written on the image. Sourced by run-kit.sh; it makes no cloud call.
#
# The record (all paths relative to the record folder):
#   commit.txt                    the full commit id that was built
#   source.sha256                 the SHA-256 of the source archive of build A (the archive itself is stored beside the record)
#   images.txt                    the names of the two sealed images, one per line: A, then B
#   compare.txt                   the result of the comparison of the two builds
#   a/measurements/events.tsv     what build A measured, item by item          (b/measurements/events.tsv: build B)
#   a/zone.txt   a/seal-report.txt   a/job-console.txt                          (the same three files for b/)
#   reference/reference.json      the published reference values of image A
RK_RECORD_REQUIRED="commit.txt source.sha256 images.txt compare.txt a/measurements/events.tsv a/zone.txt a/seal-report.txt a/job-console.txt b/measurements/events.tsv b/zone.txt b/seal-report.txt b/job-console.txt reference/reference.json"

rk_record_check() {  # DIR: every required file is there and not empty
  local d="$1" f missing=""
  for f in $RK_RECORD_REQUIRED; do [ -s "$d/$f" ] || missing="$missing $f"; done
  [ -z "$missing" ] || { echo "RUN-KIT-RECORD-INCOMPLETE: the build record $d lacks:$missing"; return 1; }
}

rk_record_pack() {  # DIR OUT: the same files always give the same archive (sorted names, fixed time and owner), so the fingerprint can be checked
  tar --sort=name --mtime='UTC 2000-01-01' --owner=0 --group=0 --numeric-owner -cf - -C "$1" . | gzip -n -9 > "$2"
}

rk_record_fingerprint() { sha256sum "$1" | cut -c1-64; }   # FILE

rk_record_verify() {  # FILE FINGERPRINT32: the image label holds the first 32 characters of the fingerprint
  local have; have="$(rk_record_fingerprint "$1")"
  [ "${have:0:32}" = "$2" ] || { echo "RUN-KIT-RECORD-MISMATCH: the record $1 has the fingerprint ${have:0:32}..., the image says $2..."; return 1; }
}
