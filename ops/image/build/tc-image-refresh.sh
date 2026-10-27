#!/usr/bin/env bash
# Steps R3.7 and R7, on the BUILDER: install the six fleet scripts from the kit into /usr/local/lib/tc and STRIP the TC_* rehearsal hooks from the installed copies (the sources keep them, because the rehearsals use them).
# A hook is a ${TC_NAME:-default} (or ${TC_NAME-default}): it becomes its default. The one command hook (TC_WRITE in tc-extend.sh) is removed with its branch. TC_LOG is NOT a hook but the event-log argument that our scripts pass to each other.
# GATE: after the strip no TC_ name except TC_LOG is left, every script parses, and nothing is installed unless all six passed.
#   tc-image-refresh.sh --kit DIR [--dest DIR]
set -uo pipefail
KIT="${HOME:-/root}/f03"; DEST=/usr/local/lib/tc
while [ $# -gt 0 ]; do case "$1" in --kit) KIT="$2"; shift 2 ;; --dest) DEST="$2"; shift 2 ;; *) echo "REFRESH-STOP: unknown argument $1" >&2; exit 2 ;; esac; done
die() { echo "REFRESH-STOP: $*" >&2; exit 1; }
FILES="tc-measure.sh tc-crawl.sh tc-export.sh tc-extend.sh tc-fleet.sh tc-report.sh"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
[ "$(id -u)" = 0 ] || die "run as root"; command -v python3 >/dev/null || die "python3 is missing"
for f in $FILES; do
  [ -f "$KIT/ops/image/build/tc-strip-hooks.py" ] || die "the kit lacks tc-strip-hooks.py"; [ -f "$KIT/ops/image/rootfs/usr/local/lib/tc/$f" ] || die "the kit lacks $f"; cp "$KIT/ops/image/rootfs/usr/local/lib/tc/$f" "$W/$f"
  python3 "$KIT/ops/image/build/tc-strip-hooks.py" "$W/$f" || die "the strip of $f failed"
  bash -n "$W/$f" || die "$f does not parse after the strip"
done
LEFT="$(grep -ohE 'TC_[A-Z0-9_]+' $(for f in $FILES; do echo "$W/$f"; done) | sort -u | tr '\n' ' ')"
case "$LEFT" in ""|"TC_LOG ") ;; *) die "these TC_ names are left after the strip: $LEFT" ;; esac
for f in $FILES; do install -m 0755 -o root -g root "$W/$f" "$DEST/$f.new" && mv "$DEST/$f.new" "$DEST/$f" || die "could not install $f"; done
echo "REFRESH-OK: six scripts installed without TC_ hooks (left: ${LEFT:-none})"
