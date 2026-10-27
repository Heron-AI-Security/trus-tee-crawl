#!/usr/bin/env bash
# Step R4.4 rehearsal (no cloud, seconds): two fake initramfs files that differ the way the real ones did (a random seed from the build machine, the time in two mdadm comments) become byte-identical, and every
# fault is refused.   bash r4e-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; B="$K/ops/image/build"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "   ok:   $1"; P=$((P+1)); else echo "   FAIL: $1"; F=$((F+1)); fi; }
say() { echo; echo "== $*"; }
for t in cpio gzip; do command -v $t >/dev/null || { echo "  FAIL: the rehearsal needs $t"; exit 2; }; done
mk() { # $1 name, $2 mdadm time text, $3 early (yes/no)
  local d="$W/$1"; rm -rf "$d"; mkdir -p "$d/etc/mdadm" "$d/scripts/local-top" "$d/bin" "$d/lib"; head -c 4096 /dev/urandom > "$d/.random-seed"
  for f in mdadm.conf mdadm.conf.tmp; do printf '# mdadm.conf\nDEVICE partitions\n# This configuration was auto-generated on %s by mkconf\n' "$2" > "$d/etc/mdadm/$f"; done
  printf '#!/bin/sh\necho verity\n' > "$d/scripts/local-top/tc-verity"; chmod 755 "$d/scripts/local-top/tc-verity"; ln -s ../scripts/local-top/tc-verity "$d/bin/link"; printf 'ELF-ish\n' > "$d/lib/libx.so"
  find "$d" -exec touch -h -d @1767225600 {} +; ( cd "$d" && find . | LC_ALL=C sort | cpio --quiet --reproducible -R 0:0 -o -H newc | gzip -n > "$W/$1.main" )
  if [ "${3:-no}" = yes ]; then mkdir -p "$W/$1-early/kernel/x86/microcode"; printf 'ucode\n' > "$W/$1-early/kernel/x86/microcode/GenuineIntel.bin"; ( cd "$W/$1-early" && find . | LC_ALL=C sort | cpio --quiet --reproducible -R 0:0 -o -H newc ) > "$W/$1.img"; cat "$W/$1.main" >> "$W/$1.img"; else cp "$W/$1.main" "$W/$1.img"; fi
}
say "two fake initramfs files that differ the way the real ones did (found by the experiment of step R4)"
mk a "Tue, 27 Oct 2026 08:00:56 +0000"; mk b "Tue, 27 Oct 2026 07:57:16 +0000"
[ "$(sha256sum < "$W/a.img")" != "$(sha256sum < "$W/b.img")" ] && chk "the two fake builds differ (a random seed and the time in two mdadm comments): the problem exists" ok || chk "the fake builds are equal: the test would prove nothing" no
for n in a b; do python3 "$B/tc-initrd-normalize.py" "$W/$n.img" "$W/$n.norm" > "$W/$n.out" 2>&1 || chk "normalizing $n failed: $(cat $W/$n.out)" no; done
[ "$(sha256sum < "$W/a.norm")" = "$(sha256sum < "$W/b.norm")" ] && chk "after the normalization the two builds are BYTE-IDENTICAL" ok || chk "the builds still differ after the normalization" no
grep -q 'INITRD-NORMALIZED: 13 entries; .random-seed zeroed (4096 bytes); 2 mdadm time stamp(s)' "$W/a.out" && chk "the report names what was done: the seed (4096 bytes) and 2 mdadm time stamps" ok || chk "the report is not as expected: $(cat $W/a.out)" no
python3 -B - "$W" <<'PYEOF' > "$W/check.txt" 2>&1
import gzip, sys, re
sys.path.insert(0, sys.argv[2] if False else "")
W = sys.argv[1]
def ents(path):
    raw = open(path, "rb").read(); dec = gzip.decompress(raw); p = 0; out = {}
    while True:
        f = [int(dec[p + 6 + 8 * i:p + 14 + 8 * i], 16) for i in range(13)]; size, nsize = f[6], f[11]
        name = dec[p + 110:p + 110 + nsize - 1].decode(); q = (p + 110 + nsize + 3) & ~3; out[name] = (f, dec[q:q + size]); p = (q + size + 3) & ~3
        if name == "TRAILER!!!": return raw, out
ok = lambda m, c: print(("PASS " if c else "FAIL ") + m)
ro, o = ents(W + "/a.main"); rn, n = ents(W + "/a.norm")
ok("the same entries with the same header fields (inode, mode, times, sizes)", list(o) == list(n) and all(o[k][0] == n[k][0] for k in o))
ok("the seed is zeros and has its length", n[".random-seed"][1] == bytes(4096))
ok("the mdadm comments carry the fixed time of SOURCE_DATE_EPOCH (Thu, 01 Jan 2026 00:00:00 +0000) and nothing else changed", all(n["etc/mdadm/" + f][1] == o["etc/mdadm/" + f][1].replace(b"Tue, 27 Oct 2026 08:00:56 +0000", b"Thu, 01 Jan 2026 00:00:00 +0000") for f in ("mdadm.conf", "mdadm.conf.tmp")))
ok("every other entry is byte for byte unchanged (script, link, library)", all(o[k][1] == n[k][1] for k in o if k not in (".random-seed", "etc/mdadm/mdadm.conf", "etc/mdadm/mdadm.conf.tmp")))
ok("the gzip header is the one of 'gzip -n' (no time, no name)", rn[:10] == bytes.fromhex("1f8b0800000000000003"))
PYEOF
[ "$(grep -c '^PASS' "$W/check.txt")" = 5 ] && chk "all 5 properties of the result hold (headers, seed, mdadm time, other entries, gzip header)" ok || chk "a property failed: $(grep FAIL "$W/check.txt" | tr '\n' '|')$(head -c 300 "$W/check.txt")" no
python3 "$B/tc-initrd-normalize.py" "$W/a.norm" "$W/a.norm2" > /dev/null 2>&1; [ "$(sha256sum < "$W/a.norm")" = "$(sha256sum < "$W/a.norm2")" ] && chk "a second run changes nothing (the result is stable)" ok || chk "the result is not stable" no
say "an initramfs with an early archive in front (microcode), as a real one can have"
mk c "Tue, 27 Oct 2026 08:00:56 +0000" yes; mk d "Tue, 27 Oct 2026 07:57:16 +0000" yes
for n in c d; do python3 "$B/tc-initrd-normalize.py" "$W/$n.img" "$W/$n.norm" > "$W/$n.out" 2>&1 || chk "normalizing $n failed: $(cat $W/$n.out)" no; done
[ "$(sha256sum < "$W/c.norm")" = "$(sha256sum < "$W/d.norm")" ] && chk "with an early archive in front the two builds are also byte-identical" ok || chk "early-archive case: the two builds differ" no
python3 -B - "$W/c.img" "$W/c.norm" <<'PYEOF2' > "$W/early.txt" 2>&1
import sys
a, b = open(sys.argv[1], "rb").read(), open(sys.argv[2], "rb").read(); oa, ob = a.find(b"\x1f\x8b\x08"), b.find(b"\x1f\x8b\x08")
print("PASS" if oa > 0 and oa == ob and a[:oa] == b[:ob] else "FAIL the early archive (%d bytes) was changed or moved (now %d)" % (oa, ob))
PYEOF2
grep -q '^PASS' "$W/early.txt" && chk "the early archive in front (microcode) is kept byte for byte, at the same place" ok || chk "$(cat $W/early.txt)" no
say "the tool's own safety net: it refuses a result that the rules do not allow"
python3 -B - "$B" "$W" > "$W/net.txt" 2>&1 <<'PYEOF3'
import importlib.util, sys, gzip, re
spec = importlib.util.spec_from_file_location("n", sys.argv[1] + "/tc-initrd-normalize.py"); n = importlib.util.module_from_spec(spec); spec.loader.exec_module(n)
W = sys.argv[2]; raw = open(W + "/a.img", "rb").read(); orig = gzip.decompress(raw); good, _ = n.patch(orig, 1767225600); ok = lambda m, c: print(("PASS " if c else "FAIL ") + m)
ok("the correct result has no problems", n.problems(orig, good, 1767225600) == [])
def flip(name, data):
    for nm, p, q, size, f in n.entries(good):
        if nm == name: b = bytearray(good); b[q] ^= 0xFF; return bytes(b)
ok("a changed script is detected", n.problems(orig, flip("scripts/local-top/tc-verity", good), 1767225600) != [])
ok("a seed that is not zeros is detected", n.problems(orig, flip(".random-seed", good), 1767225600) != [])
ok("a changed library is detected", n.problems(orig, flip("lib/libx.so", good), 1767225600) != [])
def hdr(): 
    nm, p, q, size, f = [e for e in n.entries(good) if e[0] == "lib/libx.so"][0]; b = bytearray(good); b[p + 6 + 8 * 1] ^= 1; return bytes(b)
ok("a changed header field (mode) is detected", n.problems(orig, hdr(), 1767225600) != [])
PYEOF3
[ "$(grep -c '^PASS' "$W/net.txt")" = 5 ] && chk "the verifier accepts the correct result and detects a changed script, a non-zero seed, a changed library and a changed header field" ok || chk "the verifier is wrong: $(grep FAIL "$W/net.txt" | tr '\n' '|')$(head -c 300 "$W/net.txt")" no
sed 's/^    return bytes(buf), notes$/    for nm, p, q, size, f in entries(dec):\n        if nm == "lib\/libx.so": buf[q] = 65\n    return bytes(buf), notes/' "$B/tc-initrd-normalize.py" > "$W/buggy.py"
python3 -B "$W/buggy.py" "$W/a.img" "$W/buggy.out" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'INITRD-NORMALIZE-FAILED' "$W/o.txt" && [ ! -e "$W/buggy.out" ] && chk "a copy of the tool with a bug that corrupts a script REFUSES to write its result (it checks itself before it writes)" ok || chk "the self-check did not stop a corrupting bug: $(head -c 200 $W/o.txt)" no
say "faults: each must be refused, and the input must not be touched"
sha_in="$(sha256sum < "$W/a.img")"
echo "not an initramfs" > "$W/bad.img"; python3 "$B/tc-initrd-normalize.py" "$W/bad.img" "$W/bad.out" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'no gzip stream' "$W/o.txt" && [ ! -e "$W/bad.out" ] && chk "fault: a file that is not an initramfs is refused and nothing is written" ok || chk "non-initramfs not refused: $(cat $W/o.txt)" no
python3 -c "import gzip,sys; sys.stdout.buffer.write(gzip.compress(b'this is gzip but not cpio'))" > "$W/notcpio.img"; python3 "$B/tc-initrd-normalize.py" "$W/notcpio.img" "$W/notcpio.out" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'not a cpio newc archive' "$W/o.txt" && [ ! -e "$W/notcpio.out" ] && chk "fault: a gzip file that is not a cpio archive is refused" ok || chk "non-cpio not refused: $(cat $W/o.txt)" no
head -c 300 "$W/a.img" > "$W/trunc.img"; python3 "$B/tc-initrd-normalize.py" "$W/trunc.img" "$W/trunc.out" > "$W/o.txt" 2>&1; [ $? = 1 ] && [ ! -e "$W/trunc.out" ] && chk "fault: a truncated initramfs is refused and nothing is written" ok || chk "truncated not refused" no
mk e "Tue, 7 Oct 2026 08:00:56 +0000"; python3 "$B/tc-initrd-normalize.py" "$W/e.img" "$W/e.out" > "$W/o.txt" 2>&1; rc=$?
[ $rc = 0 ] && chk "a time in another format is not matched by the rule (it is left as it is: the rule only fixes what mkconf writes)" ok || chk "unexpected refusal: $(cat $W/o.txt)" no
python3 "$B/tc-initrd-normalize.py" "$W/a.img" "$W/f.out" --sde 5 > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'since 1980' "$W/o.txt" && chk "fault: a SOURCE_DATE_EPOCH before 1980 is refused" ok || chk "bad sde not refused" no
python3 "$B/tc-initrd-normalize.py" "$W/missing.img" "$W/g.out" > "$W/o.txt" 2>&1; [ $? = 1 ] && grep -q 'cannot read' "$W/o.txt" && chk "fault: a missing input is refused with a message" ok || chk "missing input not refused" no
[ "$(sha256sum < "$W/a.img")" = "$sha_in" ] && chk "the input file was never modified" ok || chk "the input changed" no
say "the sealing script uses it: after mkinitramfs, before the gates, from its own folder"
S="$B/tc-image-sealbake.sh"; m="$(grep -n 'mkinitramfs -d' "$S" | head -1 | cut -d: -f1)"; n="$(grep -n 'tc-initrd-normalize.py' "$S" | head -1 | cut -d: -f1)"; v="$(grep -n '^verify_initrd "\$W/initrd.tc"' "$S" | head -1 | cut -d: -f1)"
[ -n "$m" ] && [ -n "$n" ] && [ -n "$v" ] && [ "$m" -lt "$n" ] && [ "$n" -lt "$v" ] && chk "the normalizer runs after mkinitramfs and before the verification gates (they check the file that is installed)" ok || chk "the order in tc-image-sealbake.sh is wrong (mkinitramfs $m, normalize $n, verify $v)" no
grep -q 'dirname "\$0"' "$S" && chk "the tool is found next to the script itself (any kit layout)" ok || chk "the tool is not located relative to the script" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4E-REHEARSAL-PASS" || { echo "R4E-REHEARSAL-FAIL"; exit 1; }
