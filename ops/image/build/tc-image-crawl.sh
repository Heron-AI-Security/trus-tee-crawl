#!/usr/bin/env bash
# Step F0.3c, the image build part 4: the crawl that runs by itself. On the builder, after tc-image-job.sh: install the crawl driver (/usr/local/lib/tc/tc-crawl.sh), its parameters and seeds
# (/etc/tc/crawl/), and the unit tc-crawl.service (in the measured folder, enabled from there); validate the parameters with the driver's own --check-params; ask systemd whether it understands the unit;
# and extend the measured list to 13 events (crawl-params and crawl-seeds, last). It starts nothing and does not reboot.
#   bash tc-image-crawl.sh KITDIR
# It replaces the hand-run ops/run-crawl.sh and its typed parameters (legacy step 5.3.2) for the image.
# Hooks for the rehearsal only: TC_ROOT, TC_SUDO, TC_ANALYZE.
set -uo pipefail
KIT="${1:?usage: $0 KITDIR}"; R="${TC_ROOT:-}"; SUDO="${TC_SUDO-sudo}"; IMGDIR="$KIT/ops/image/rootfs"
fail() { echo "ABORT: $*" >&2; exit 1; }
say() { echo "== $*"; }
say "pre-flight"
[ -f "$R/opt/tc/nutch/apache-nutch-1.22.job" ] && [ -x "$R/opt/tc/nutch/bin/crawl" ] && [ -f "$R/etc/tc/job-versions.txt" ] || fail "the job is not in place: run tc-image-job.sh first"
for f in etc/tc/crawl/seeds.txt etc/tc/crawl/params.env usr/local/lib/tc/tc-crawl.sh usr/local/lib/tc/tc-policy.py usr/local/lib/tc/units/tc-crawl.service etc/tc/measured-paths-f03c.txt; do [ -f "$IMGDIR/$f" ] || fail "missing in $KIT: ops/image/rootfs/$f"; done
bash -n "$IMGDIR/usr/local/lib/tc/tc-crawl.sh" || fail "the crawl driver has a syntax error"
echo "the job is in place; the driver, the parameters, the seeds and the unit are in the kit"
say "install the driver, the parameters and the seeds (owned by root)"
$SUDO install -d -m 0755 "$R/etc/tc/crawl"
$SUDO install -m 0644 "$IMGDIR/etc/tc/crawl/seeds.txt" "$R/etc/tc/crawl/seeds.txt"; $SUDO install -m 0644 "$IMGDIR/etc/tc/crawl/params.env" "$R/etc/tc/crawl/params.env"
$SUDO install -m 0755 "$IMGDIR/usr/local/lib/tc/tc-crawl.sh" "$R/usr/local/lib/tc/tc-crawl.sh"
say "the collection policy the source receipts name, from the image's JDK CA store (in /etc/tc, on the verified root; the same file on every node)"
$SUDO install -m 0755 "$IMGDIR/usr/local/lib/tc/tc-policy.py" "$R/usr/local/lib/tc/tc-policy.py"
$SUDO python3 "$R/usr/local/lib/tc/tc-policy.py" "$R/usr/lib/jvm/java-11-openjdk-amd64/bin/keytool" "$R/etc/tc/crawl/collection-policy.json" || fail "could not make the collection policy"
$SUDO chmod 0644 "$R/etc/tc/crawl/collection-policy.json"
OUTC="$(TC_ROOT="$R" bash "$R/usr/local/lib/tc/tc-crawl.sh" --check-params 2>&1)" || { echo "$OUTC" >&2; fail "the driver refuses the parameters or the seeds"; }
echo "$OUTC"
say "the unit (in the measured folder, then enabled)"
$SUDO install -d -m 0755 "$R/usr/local/lib/tc/units"; $SUDO install -m 0644 "$IMGDIR/usr/local/lib/tc/units/tc-crawl.service" "$R/usr/local/lib/tc/units/tc-crawl.service"
$SUDO systemctl daemon-reload
$SUDO systemctl enable "$R/usr/local/lib/tc/units/tc-crawl.service" >/dev/null 2>&1 || fail "could not enable tc-crawl.service"
AOUT="$($SUDO ${TC_ANALYZE:-systemd-analyze} verify "$R/usr/local/lib/tc/units/tc-crawl.service" 2>&1 || true)"
if printf '%s\n' "$AOUT" | grep -i 'unknown' | grep -q 'tc-[a-z-]*\.service'; then printf '%s\n' "$AOUT" | grep -i 'unknown' | grep 'tc-[a-z-]*\.service' | sed 's/^/   /'; fail "systemd does not understand part of the unit file (a key in the wrong section?)"; fi
echo "enabled: tc-crawl.service; systemd reads it without an unknown key or section"
say "the 13-event measured list"
$SUDO install -m 0644 "$IMGDIR/etc/tc/measured-paths-f03c.txt" "$R/etc/tc/measured-paths.txt"
TC_ROOT="$R" TC_LIST="$R/etc/tc/measured-paths.txt" TC_LIB="$R/usr/local/lib/tc" "$R/usr/local/lib/tc/tc-measure.sh" --check-list || fail "the measured list does not match this machine"
echo
echo "READY (nothing was started, nothing was rebooted). Next: tc-image-clean.sh, then stop the builder and make the image."
