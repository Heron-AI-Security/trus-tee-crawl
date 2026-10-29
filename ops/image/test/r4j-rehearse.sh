#!/usr/bin/env bash
# Step R4.9 rehearsal (no cloud, seconds): the Public Suffix List is pinned in the crawler-commons jar, and two jars that differ only in what the library build leaves to chance come out identical.   bash r4j-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$K/ops/image"; H="$I/build/tc-psl-pin.py"; PIN="$I/build/psl/PIN"; PSLF="$I/build/psl/$(sed -n 's/^PSL_FILE=//p' "$PIN" 2>/dev/null)"; WANT="$(sed -n 's/^PSL_SHA256=//p' "$PIN" 2>/dev/null)"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "  pass: $1"; P=$((P+1)); else echo "  FAIL: $1"; F=$((F+1)); fi; }
mkjar() { python3 - "$@" <<'PY'
import sys, zipfile
out, text, rev, year, extra = sys.argv[1], sys.argv[2], sys.argv[3] == "rev", int(sys.argv[4]), sys.argv[5] == "extra"
items = [("META-INF/", b""), ("META-INF/MANIFEST.MF", b"Manifest-Version: 1.0\r\n\r\n"), ("a/", b""), ("a/B.class", b"B" * 300), ("a/C.class", b"C" * 200), ("effective_tld_names.dat", text.encode())]
if rev: items.reverse()
with zipfile.ZipFile(out, "w") as z:
    for n, d in items:
        zi = zipfile.ZipInfo(n, (year, 6, 7, 8, 9, 10)); zi.compress_type = zipfile.ZIP_STORED if n.endswith("/") else zipfile.ZIP_DEFLATED; zi.external_attr = 0o644 << 16
        if extra: zi.extra = b"UT\x05\x00\x01\x01\x02\x03\x04"
        z.writestr(zi, d)
PY
}
run() { OUT="$(python3 "$H" "$@" 2>&1)"; RC=$?; }
echo "== the pin in the repository is consistent"
[ -f "$PSLF" ] && [ "$(sha256sum "$PSLF" | cut -c1-64)" = "$WANT" ] && [[ "$WANT" =~ ^[0-9a-f]{64}$ ]] && [ "$(stat -c %s "$PSLF")" = "$(sed -n 's/^PSL_BYTES=//p' "$PIN")" ] && chk "the list in the repository has the SHA-256 and the size that PIN records" ok || chk "the list and PIN disagree" no
grep -q '^PSL_SOURCE=' "$PIN" && grep -q '^PSL_RETRIEVED=' "$PIN" && chk "PIN records where and when the list was taken" ok || chk "PIN lacks the source or the date" no
echo "== the property that was missing: builds that differ in chance things give the same jar"
mkjar "$W/j1.jar" "// list copy of 27 October" norm 2026 plain; mkjar "$W/j2.jar" "// list copy of 28 October" rev 2025 extra
[ "$(sha256sum < "$W/j1.jar")" != "$(sha256sum < "$W/j2.jar")" ] && chk "control: the two jars differ before the helper (another list, another entry order, other times, an extra field)" ok || chk "control void: the jars are already equal" no
run "$W/j1.jar" "$W/j1.jar.psl" "$WANT"; cp "$PSLF" "$W/psl.dat"; run "$W/j1.jar" "$W/psl.dat" "$WANT"; R1=$RC; run "$W/j2.jar" "$W/psl.dat" "$WANT"; R2=$RC
[ $R1 = 0 ] && [ $R2 = 0 ] && [ "$(sha256sum < "$W/j1.jar")" = "$(sha256sum < "$W/j2.jar")" ] && chk "after the helper the two jars are byte-identical" ok || chk "the jars still differ ($R1 $R2)" no
python3 - "$W/j1.jar" "$PSLF" > "$W/inspect.txt" <<'PY'
import hashlib, sys, zipfile
z = zipfile.ZipFile(sys.argv[1]); want = hashlib.sha256(open(sys.argv[2], "rb").read()).hexdigest(); names = [i.filename for i in z.infolist()]
print("entry_is_pinned", hashlib.sha256(z.read("effective_tld_names.dat")).hexdigest() == want)
print("others_kept", z.read("a/B.class") == b"B" * 300 and z.read("a/C.class") == b"C" * 200 and z.read("META-INF/MANIFEST.MF") == b"Manifest-Version: 1.0\r\n\r\n")
print("manifest_first", names[0] == "META-INF/MANIFEST.MF"); print("sorted_rest", names[1:] == sorted(names[1:])); print("times_fixed", all(i.date_time == (1980, 1, 1, 0, 0, 0) for i in z.infolist())); print("no_extra", all(i.extra == b"" for i in z.infolist()))
print("all_entries", len(names) == 6)
PY
for k in entry_is_pinned others_kept manifest_first sorted_rest times_fixed no_extra all_entries; do grep -q "^$k True" "$W/inspect.txt" && chk "result: $k" ok || chk "result: $k" no; done
S1="$(sha256sum < "$W/j1.jar")"; run "$W/j1.jar" "$W/psl.dat" "$WANT"; [ $RC = 0 ] && [ "$(sha256sum < "$W/j1.jar")" = "$S1" ] && chk "running it twice changes nothing (idempotent)" ok || chk "not idempotent" no
echo "== refusals leave the jar untouched"
mkjar "$W/r.jar" "x" norm 2026 plain; B0="$(sha256sum < "$W/r.jar")"
run "$W/r.jar" "$W/psl.dat" "$(printf '0%.0s' $(seq 1 64))"; [ $RC != 0 ] && grep -q "has SHA-256" <<<"$OUT" && [ "$(sha256sum < "$W/r.jar")" = "$B0" ] && chk "a wrong expected hash is refused" ok || chk "wrong hash not refused: $OUT" no
cp "$PSLF" "$W/bad.dat"; printf 'x' | dd of="$W/bad.dat" bs=1 seek=100 conv=notrunc 2>/dev/null; run "$W/r.jar" "$W/bad.dat" "$WANT"; [ $RC != 0 ] && grep -q "has SHA-256" <<<"$OUT" && [ "$(sha256sum < "$W/r.jar")" = "$B0" ] && chk "a list file with one changed byte is refused" ok || chk "changed list not refused: $OUT" no
python3 - "$W/noentry.jar" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1], "w"); z.writestr("a/B.class", b"x"); z.close()
PY
run "$W/noentry.jar" "$W/psl.dat" "$WANT"; [ $RC != 0 ] && grep -q "0 times" <<<"$OUT" && chk "a jar without the entry is refused" ok || chk "missing entry not refused: $OUT" no
python3 - "$W/dup.jar" <<'PY'
import sys, warnings, zipfile
warnings.simplefilter("ignore"); z = zipfile.ZipFile(sys.argv[1], "w"); z.writestr("effective_tld_names.dat", b"1"); z.writestr("effective_tld_names.dat", b"2"); z.close()
PY
run "$W/dup.jar" "$W/psl.dat" "$WANT"; [ $RC != 0 ] && grep -q "2 times" <<<"$OUT" && chk "a jar with the entry twice is refused" ok || chk "duplicate not refused: $OUT" no
run "$W/none.jar" "$W/psl.dat" "$WANT"; [ $RC != 0 ] && grep -q "missing" <<<"$OUT" && chk "a missing jar is refused" ok || chk "missing jar not refused" no
run "$W/r.jar" "$W/none.dat" "$WANT"; [ $RC != 0 ] && grep -q "missing" <<<"$OUT" && chk "a missing list file is refused" ok || chk "missing list not refused" no
run "$W/r.jar"; [ $RC != 0 ] && grep -q "usage" <<<"$OUT" && chk "wrong arguments are refused with the usage" ok || chk "usage not shown" no
echo "== the wiring in the job script"
J="$I/build/tc-image-job.sh"
grep -q 'PINF="$KIT/ops/image/build/psl/PIN"' "$J" && grep -q 'tc-psl-pin.py" "$PSLJARS" "$PSL_FILE" "$PSL_SHA256"' "$J" && chk "the job script reads the pin and calls the helper with the list and its hash" ok || chk "the job script is not wired" no
grep -q 'NJ" = 1 \] || fail "the crawler-commons jar is not in' "$J" && chk "the job script stops unless exactly one crawler-commons jar is installed" ok || chk "no check for exactly one jar" no
grep -q 'echo "public-suffix-list: sha256 $PSL_SHA256 bytes $PSL_BYTES"' "$J" && chk "the hash of the list is recorded in job-versions.txt (so tc-conf records it)" ok || chk "the list is not recorded" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4J-REHEARSAL-PASS" || { echo "R4J-REHEARSAL-FAIL"; exit 1; }
