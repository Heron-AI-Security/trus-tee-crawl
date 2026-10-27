#!/usr/bin/env bash
# Step R4.3, on the BUILDER: remove the JDK's class-data cache (lib/server/classes.jsa). The JDK package makes it when it is installed, and it differs from one build to the next (the experiment of step R4 found
# the same size and other content), so a measured JDK folder would differ although nothing that matters differs. Without it the JVM starts about 20 ms slower and works the same. The JVM is tested WITHOUT the cache
# first (-Xshare:off behaves like a missing archive); if that does not work, nothing is removed.
#   bash tc-image-jdkcache.sh JDKDIR          Hook for the rehearsal only: TC_SUDO.
set -uo pipefail
JDK="${1:?usage: $0 JDKDIR}"; SUDO="${TC_SUDO-sudo}"; J="$JDK/bin/java"; C="$JDK/lib/server/classes.jsa"
fail() { echo "JDKCACHE-STOP: $*" >&2; exit 1; }
[ -x "$J" ] || fail "no java at $J"
"$J" -Xshare:off -version >/dev/null 2>&1 || fail "the JVM does not start without the class-data archive: nothing was removed"
if [ -e "$C" ]; then n="$(stat -c %s "$C")"; $SUDO rm -f "$C" || fail "could not remove $C"; MSG="classes.jsa removed ($n bytes)"; else MSG="classes.jsa is not there (nothing to remove)"; fi
[ ! -e "$C" ] || fail "$C is still there"
"$J" -version >/dev/null 2>&1 || fail "the JVM does not start after the removal"
echo "JDKCACHE-OK: $MSG; the JVM starts without it"
