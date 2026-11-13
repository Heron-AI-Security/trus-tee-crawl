#!/usr/bin/env bash
# Step R4 acceptance, operator side (no cloud calls, seconds): the proof, on the quotes of a REAL fleet run, that the image is the image that the commit builds.
#   bash r4-accept.sh OUT COMMIT BUILD_DIR BUILD_DIR [BUILD_DIR ...]
# OUT is the folder of a fleet run (fleet.tsv, the quotes A and B, and reference-values.json written by  f1-drive.sh reference-values  with PIN_COMMIT set to the commit). BUILD_DIR is the ground truth of an
# independent build of that commit (events.tsv and source.txt, written by r4-manifest.sh). The steps: (1) the real run's reference names the commit; (2) the independent builds, built without looking at the run,
# agree among themselves and with every stable event that the real machines measured (r4-reference.py); (3) the verifier accepts every node with the pin (rule E9); (4) the verifier REFUSES a pin for another commit
# and a missing pin on the same quotes, so that the pin is proven to be enforced and not decoration.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="${1:?usage: $0 OUT COMMIT BUILD_DIR BUILD_DIR [BUILD_DIR ...]}"; C="${2:?usage: $0 OUT COMMIT BUILD_DIR BUILD_DIR [BUILD_DIR ...]}"; shift 2
die() { echo "R4-ACCEPT-FAILED: $*"; exit 1; }
[ $# -ge 2 ] || die "at least two build folders are needed (one build proves nothing about reproducibility)"
[ -s "$OUT/reference-values.json" ] || die "there is no reference-values.json in $OUT (run the stage reference-values of f1-drive.sh with PIN_COMMIT set to the commit)"
python3 -c 'import json, sys; sys.exit(0 if json.load(open(sys.argv[1])).get("commit") == sys.argv[2] else 1)' "$OUT/reference-values.json" "$C" || die "the reference values of the real run do not name the commit $C (run the stage reference-values with PIN_COMMIT=$C)"
echo "== 1. the independent builds against the real run (r4-reference.py)"
args=(); for b in "$@"; do args+=(--build "$b"); done
[ "${R4_LOCKED:-}" = 1 ] && args+=(--locked)   # a locked image: the real run measures fewer events than the builds (change 2 of the work item); see r4-reference.py
python3 -B "$HERE/r4-reference.py" "${args[@]}" --commit "$C" --platform "$OUT/reference-values.json" --out "$OUT/reference-values-pinned.json"; rc=$?
[ $rc = 0 ] && [ -s "$OUT/reference-values-pinned.json" ] || die "the builds and the real run do not agree (the line above says what differs)"
echo; echo "== 2. the verifier, pinned to the commit (rule E9)"
o="$(python3 -B "$HERE/f1-fleet.py" enforce "$OUT" "$OUT/reference-values-pinned.json" "$C" 2>&1)"; rc=$?; echo "$o" | tail -4 | cut -c1-230
{ [ $rc = 0 ] && grep -q '^ENFORCE-OK' <<<"$o" && grep -q "^PINNED (rule E9): every node was built from commit $C" <<<"$o"; } || die "the fleet is not accepted with the pin (see above)"
echo; echo "== 3. the verifier must REFUSE a wrong pin and a missing pin on the same quotes"
WRONG="1234567890123456789012345678901234567890"; [ "$C" != "$WRONG" ] || WRONG="0000000000000000000000000000000000000000"
o="$(python3 -B "$HERE/f1-fleet.py" enforce "$OUT" "$OUT/reference-values-pinned.json" "$WRONG" 2>&1)"; rc=$?
{ [ $rc != 0 ] && grep -q 'E9 the run is pinned to commit' <<<"$o"; } && echo "   ok: a pin for another commit (${WRONG:0:12}...) is refused (E9)" || die "a pin for another commit was NOT refused (rc=$rc): the pin is not enforced"
o="$(python3 -B "$HERE/f1-fleet.py" enforce "$OUT" "$OUT/reference-values-pinned.json" 2>&1)"; rc=$?
{ [ $rc != 0 ] && grep -q 'E9 the reference values are for commit' <<<"$o"; } && echo "   ok: no pin at all is refused (E9)" || die "a missing pin was NOT refused (rc=$rc): the pin is not enforced"
echo; echo "R4-ACCEPT-OK: the image of commit ${C:0:12}... was built by $# independent builds that agree with every stable event of the real fleet; the verifier accepts it with the pin and refuses the wrong and the missing pin; the reference is $OUT/reference-values-pinned.json"
