#!/usr/bin/env bash
# Step F1, the image build part 5: the fleet boot flow. On the builder, after tc-image-crawl.sh: install tc-fleet.sh and the quote helper, the fleet property templates, the new unit tc-fleet.service and the
# changed daemon units and crawl unit (role conditions, configuration from /run/tc/conf), enable tc-fleet, ask systemd whether it understands the units, and extend the measured list to 14 events (fleet-props).
# Nothing is started and the builder is not rebooted.   bash tc-image-fleet.sh KITDIR
# Hooks for the rehearsal only: TC_ROOT, TC_SUDO, TC_ANALYZE.
set -uo pipefail
KIT="${1:?usage: $0 KITDIR}"; R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"; IMGDIR="$KIT/ops/image/rootfs"
fail() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }
say "pre-flight"
[ -x "$R/usr/local/lib/tc/tc-crawl.sh" ] && [ -f "$R/etc/tc/crawl/params.env" ] || fail "the crawl is not in place: run tc-image-crawl.sh first"
FILES="usr/local/lib/tc/tc-fleet.sh usr/local/lib/tc/tc-crawl.sh usr/local/lib/tc/tc-export.sh etc/tc/fleet-props/core-site.props etc/tc/fleet-props/hdfs-site.props etc/tc/fleet-props/mapred-site.props etc/tc/fleet-props/yarn-site.props etc/tc/measured-paths-f1.txt"
UNITS="tc-fleet tc-namenode tc-datanode tc-resourcemanager tc-nodemanager tc-hdfs-format tc-crawl tc-export"
for f in $FILES; do [ -f "$IMGDIR/$f" ] || fail "missing in $KIT: ops/image/rootfs/$f"; done
for u in $UNITS; do [ -f "$IMGDIR/usr/local/lib/tc/units/$u.service" ] || fail "missing in $KIT: the unit $u"; done
[ -f "$KIT/attest/quote.sh" ] || fail "missing in $KIT: attest/quote.sh"
bash -n "$IMGDIR/usr/local/lib/tc/tc-fleet.sh" || fail "tc-fleet.sh has a syntax error"
echo "the crawl is in place; the fleet script, the templates, the units and the quote helper are in the kit"
say "install the scripts and the property templates (owned by root)"
$SUDO install -m 0755 "$IMGDIR/usr/local/lib/tc/tc-fleet.sh" "$R/usr/local/lib/tc/tc-fleet.sh"; $SUDO install -m 0755 "$IMGDIR/usr/local/lib/tc/tc-crawl.sh" "$R/usr/local/lib/tc/tc-crawl.sh"; $SUDO install -m 0755 "$IMGDIR/usr/local/lib/tc/tc-export.sh" "$R/usr/local/lib/tc/tc-export.sh"
$SUDO install -m 0755 "$KIT/attest/quote.sh" "$R/usr/local/lib/tc/tc-quote.sh"
$SUDO install -d -m 0755 "$R/etc/tc/fleet-props"; for f in core hdfs mapred yarn; do $SUDO install -m 0644 "$IMGDIR/etc/tc/fleet-props/$f-site.props" "$R/etc/tc/fleet-props/$f-site.props"; done
say "the units (in the measured folder, then enabled)"
for u in $UNITS; do $SUDO install -m 0644 "$IMGDIR/usr/local/lib/tc/units/$u.service" "$R/usr/local/lib/tc/units/$u.service"; done
$SUDO systemctl daemon-reload
for u in $UNITS; do $SUDO systemctl enable "$R/usr/local/lib/tc/units/$u.service" >/dev/null 2>&1 || fail "could not enable $u"; done
AOUT="$($SUDO ${TC_ANALYZE:-systemd-analyze} verify "$R"/usr/local/lib/tc/units/tc-*.service 2>&1 || true)"
if printf '%s\n' "$AOUT" | grep -i 'unknown' | grep -q 'tc-[a-z-]*\.service'; then printf '%s\n' "$AOUT" | grep -i 'unknown' | grep 'tc-[a-z-]*\.service' | sed 's/^/   /'; fail "systemd does not understand part of a unit file (a key in the wrong section?)"; fi
echo "enabled: the fleet unit and the changed units; systemd reads them without an unknown key or section"
say "the 14-event measured list"
$SUDO install -m 0644 "$IMGDIR/etc/tc/measured-paths-f1.txt" "$R/etc/tc/measured-paths.txt"
TC_ROOT="$R" TC_LIST="$R/etc/tc/measured-paths.txt" TC_LIB="$R/usr/local/lib/tc" "$R/usr/local/lib/tc/tc-measure.sh" --check-list || fail "the measured list does not match this machine"
echo
echo "READY (nothing was started, nothing was rebooted). Next: tc-image-clean.sh, then stop the builder and make the image."
