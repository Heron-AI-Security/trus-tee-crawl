#!/usr/bin/env bash
# Step R4.7 rehearsal (no cloud, seconds): the source line of the job versions names the COMMIT and not the archive.   bash r4i-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$K/ops/image"; H="$I/build/tc-source-id.sh"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "  pass: $1"; P=$((P+1)); else echo "  FAIL: $1"; F=$((F+1)); fi; }
mkdir "$W/r" && cd "$W/r" && git init -q . && git config user.email t@t && git config user.name t && echo a > a.txt && git add -A && git commit -q -m one && C1=$(git rev-parse HEAD) && echo b >> a.txt && git commit -qam two && C2=$(git rev-parse HEAD)
git archive --format=tar.gz -o "$W/one.tgz" "$C1"; git archive --format=tar.gz -o "$W/two.tgz" "$C2"; cd "$W"
run() { OUT="$(bash "$H" "$@" 2>&1)"; RC=$?; }
echo "== the line names the commit, proven by the archive's own header"
run "$W/one.tgz" "$C1"; [ $RC = 0 ] && [ "$OUT" = "source: commit $C1" ] && chk "a git archive of the commit gives exactly: source: commit <the 40 digits>" ok || chk "wrong line: $OUT" no
echo "== the property that was missing: the line does not depend on the name or on the bytes of the archive"
gzip -dc "$W/one.tgz" | gzip -1 -n > "$W/other-name-and-bytes.tgz"
[ "$(sha256sum < "$W/one.tgz")" != "$(sha256sum < "$W/other-name-and-bytes.tgz")" ] && chk "the test archive really differs in name and bytes from the first" ok || chk "the repacked archive has the same bytes: the test is void" no
run "$W/other-name-and-bytes.tgz" "$C1"; [ $RC = 0 ] && [ "$OUT" = "source: commit $C1" ] && chk "the repacked archive of the same commit gives the SAME line" ok || chk "the repacked archive gives: $OUT" no
OLD1="source: $(basename "$W/one.tgz") sha256 $(sha256sum < "$W/one.tgz" | cut -c1-64)"; OLD2="source: $(basename "$W/other-name-and-bytes.tgz") sha256 $(sha256sum < "$W/other-name-and-bytes.tgz" | cut -c1-64)"
[ "$OLD1" != "$OLD2" ] && chk "control: the OLD line (file name and hash) differs between the two archives, which is the defect that was found" ok || chk "control failed: the old line does not differ" no
echo "== refusals"
run "$W/two.tgz" "$C1"; [ $RC != 0 ] && grep -q "archive is of commit" <<<"$OUT" && chk "an archive of another commit is refused" ok || chk "another commit not refused: $OUT" no
run "$W/one.tgz" "${C1:0:12}"; [ $RC != 0 ] && grep -q "40-digit" <<<"$OUT" && chk "a short commit id is refused" ok || chk "short id not refused" no
run "$W/one.tgz" "$(printf 'Z%.0s' $(seq 1 40))"; [ $RC != 0 ] && grep -q "40-digit" <<<"$OUT" && chk "a commit id that is not hexadecimal is refused" ok || chk "non-hex id not refused" no
run "$W/missing.tgz" "$C1"; [ $RC != 0 ] && grep -q "missing" <<<"$OUT" && chk "a missing archive is refused" ok || chk "missing archive not refused" no
mkdir "$W/plain" && echo x > "$W/plain/x" && tar czf "$W/plain.tgz" -C "$W/plain" . ; run "$W/plain.tgz" "$C1"; [ $RC != 0 ] && grep -q "no commit header" <<<"$OUT" && chk "an archive that is not a git archive (no commit header) is refused" ok || chk "headerless archive not refused: $OUT" no
echo "== the wiring"
grep -q 'tc-source-id.sh" "$SRC_TGZ" "$SRC_COMMIT"' "$I/build/tc-image-job.sh" && grep -q 'SRCLINE="source: $(basename "$SRC_TGZ") sha256 $SRC_SHA"' "$I/build/tc-image-job.sh" && chk "the job script uses the commit line when SRC_COMMIT is set, and keeps the old line only as the fallback" ok || chk "the job script is not wired" no
grep -q 'echo "$SRCLINE"; ' "$I/build/tc-image-job.sh" && chk "the line that is written to job-versions.txt is the one that was computed" ok || chk "the written line is not SRCLINE" no
grep -q 'SRC_COMMIT=$SCOM bash ops/image/build/tc-image-job.sh' "$I/test/f03-drive.sh" && grep -q 'SCOM="$(tr' "$I/test/f03-drive.sh" && chk "the driver passes the commit of COMMIT_FILE to the job stage" ok || chk "the driver does not pass SRC_COMMIT" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4I-REHEARSAL-PASS" || { echo "R4I-REHEARSAL-FAIL"; exit 1; }
