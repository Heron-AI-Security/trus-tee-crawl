#!/usr/bin/env python3
"""Step R3.7 and R4: strip the TC_* rehearsal hooks from a script (ADR-075). One source of truth: the image build (tc-image-refresh.sh) runs this file on the six installed scripts,
and the offline recomputation of the measured values (r4-recompute.py) imports it, so both produce the same bytes.
   python3 tc-strip-hooks.py FILE        rewrites FILE in place
A hook is a ${TC_NAME:-default} (or ${TC_NAME-default}): it becomes its default. The one command hook (TC_WRITE) is removed with its branch. TC_LOG is NOT a hook (the event-log argument)."""
import re, sys
KEEP = {"LOG"}

def strip_text(s):
    s = re.sub(r'if \[ -n "\$\{TC_WRITE:-\}" \]; then [^\n]*\$TC_WRITE\nelse ([^\n]*); fi', r'\1', s)
    s = s.replace(' TC_RTMR3="$RT"', '')
    s = re.sub(r'(?m)^[ \t]*#[^\n]*\bTC_(?!LOG\b)[A-Z0-9_]+[^\n]*\n', '', s)   # a comment line that describes a hook that no longer exists
    s = re.sub(r'\$\{TC_([A-Z0-9_]+)(?::-|-)([^}]*)\}', lambda m: m.group(0) if m.group(1) in KEEP else m.group(2), s)
    return s

if __name__ == "__main__":
    p = sys.argv[1]; s = open(p).read(); open(p, "w").write(strip_text(s))
