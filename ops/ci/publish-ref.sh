#!/usr/bin/env bash
# ops/ci/publish-ref.sh: step P3.2 of the mentor's plan. For the sealed image of a commit: two dummy runs, the reference values made from them, the release, the boot tables, and the files to publish.
# It publishes NOTHING itself (the workflow ci-publish uploads the files as a GitHub release). It also runs by hand in Cloud Shell, and then it uses YOUR account. Each dummy run creates one TDX VM and deletes it.
# Usage:   COMMIT=<9 to 40 hexadecimal digits of the commit that built the image>  bash ops/ci/publish-ref.sh [OUTDIR]       (OUTDIR defaults to publish-out)
# Ends with  PUBLISH-REF-OK commit=<commit> image=<image> files=<n> out=<folder> by=<commit of the workflow, or local>  or  PUBLISH-REF-FAILED: <reason>. Settings: ops/ci/ci.env, PUBLISH_WAIT (seconds to wait after a stockout, default 300), PUBLISH_HB (heartbeat seconds, default 60).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
# shellcheck source=ci.env
. "$HERE/ci.env"
OUT="${1:-publish-out}"
fail() { echo "PUBLISH-REF-FAILED: $*" >&2; exit 1; }
[[ "${COMMIT:-}" =~ ^[0-9a-f]{9,40}$ ]] || fail "COMMIT must be 9 to 40 lowercase hexadecimal digits (the commit that built the image), got '${COMMIT:-}'"
RUNNER="${TC_REFERENCE_RUN:-$ROOT/ops/reference-run.sh}"
for f in "$RUNNER" "$ROOT/ops/make-reference.py" "$ROOT/ops/reference-compare.py" "$ROOT/ops/make-release.py" "$ROOT/ops/ccel-table.py"; do [ -f "$f" ] || fail "the tool is missing: $f"; done
command -v gcloud >/dev/null 2>&1 || fail "gcloud is not installed"
rm -rf "$OUT"; mkdir -p "$OUT/publish" || fail "cannot make the folder $OUT"
echo "== 1. the image of the commit $COMMIT (found by its label commit=)"
L="$(gcloud compute images list --project "$PROJECT_ID" --no-standard-images --filter="labels.commit~^${COMMIT}" --format='value(name)' 2>&1)" || fail "the images cannot be listed: ${L:0:300}"
N="$(printf '%s\n' "$L" | grep -c .)"
[ "$N" = 1 ] || fail "$N images carry a label commit=${COMMIT}* (exactly 1 is needed): $(printf '%s' "$L" | tr '\n' ' ')"
IMAGE="$L"
D="$(gcloud compute images describe "$IMAGE" --project "$PROJECT_ID" --format=json 2>&1)" || fail "the image $IMAGE cannot be read: ${D:0:300}"
LAB="$(D="$D" python3 - <<'PY'
import json, os, re
try: lab = json.loads(os.environ["D"]).get("labels", {})
except ValueError: print("ERROR the description of the image is not JSON"); raise SystemExit
c, a, b = lab.get("commit", ""), lab.get("verity-a", ""), lab.get("verity-b", "")
if not re.fullmatch(r"[0-9a-f]{40}", c): print("ERROR the label commit of the image is not a full commit id: %r" % c)
elif not re.fullmatch(r"[0-9a-f]{64}", a + b): print("ERROR the labels verity-a and verity-b do not make a 64-digit root hash")
else: print("OK %s %s" % (c, a + b))
PY
)"
case "$LAB" in OK*) read -r _ FULL ROOTHASH <<<"$LAB";; *) fail "${LAB#ERROR }";; esac
case "$FULL" in "$COMMIT"*) :;; *) fail "the image $IMAGE is of commit $FULL, not of $COMMIT";; esac
echo "   image $IMAGE, commit $FULL, root hash ${ROOTHASH:0:16}... (from its labels; checked against the quote in step 5)"
echo "== 2. two dummy runs of $IMAGE (each creates one TDX VM, reads its quote, and deletes the VM)"
for n in 1 2; do
  ok=0
  for t in 1 2 3 4 5 6; do
    rm -rf "${OUT:?}/run$n"
    bash "$RUNNER" "$IMAGE" "$OUT/run$n" > "$OUT/run$n.log" 2>&1 &
    pid=$!; while kill -0 "$pid" 2>/dev/null; do sleep "${PUBLISH_HB:-60}"; echo "   ... dummy run $n is running ($(date -u +%H:%M) UTC)"; done; wait "$pid"
    if grep -q "REFERENCE-RUN-OK" "$OUT/run$n.log"; then ok=1; break; fi
    if grep -q -i -E "stockout|ZONE_RESOURCE_POOL_EXHAUSTED" "$OUT/run$n.log"; then echo "   no capacity right now (attempt $t of 6); waiting ${PUBLISH_WAIT:-300} seconds"; sleep "${PUBLISH_WAIT:-300}"; else break; fi
  done
  [ "$ok" = 1 ] || fail "dummy run $n did not finish; the end of its output: $(tail -6 "$OUT/run$n.log" | tr '\n' ' ' | cut -c1-600)"
  echo "   dummy run $n: $(grep -h 'REFERENCE-RUN-OK' "$OUT/run$n.log" | head -1)"
done
echo "== 3. the reference values from the two runs (they must agree on everything)"
python3 "$ROOT/ops/make-reference.py" --run "$OUT/run1" --run "$OUT/run2" --commit "$FULL" --image "$IMAGE" --out "$OUT/reference.json" | tee "$OUT/make-reference.txt"; [ "${PIPESTATUS[0]}" = 0 ] || fail "the reference could not be made (the line above says why)"
echo "== 4. each run against the reference"
for n in 1 2; do
  python3 "$ROOT/ops/reference-compare.py" "$OUT/run$n" "$OUT/reference.json" > "$OUT/compare$n.txt" 2>&1 || { tail -5 "$OUT/compare$n.txt"; fail "dummy run $n does not equal the reference"; }
  echo "   run $n: $(tail -1 "$OUT/compare$n.txt" | cut -c1-150)"
done
echo "== 5. the release: the root hash of the labels against the kernel command line that RTMR2 measured"
python3 "$ROOT/ops/make-release.py" --commit "$FULL" --image "$IMAGE" --root-hash "$ROOTHASH" --run "$OUT/run1" --reference "$OUT/reference.json" --out "$OUT/release" | tee "$OUT/make-release.txt" | tail -4; [ "${PIPESTATUS[0]}" = 0 ] || fail "the release checks failed"
[ -s "$OUT/release/release.json" ] || fail "release.json was not written"
echo "== 6. the boot event tables (the replay of RTMR0 to RTMR2 against the quote)"
python3 "$ROOT/ops/ccel-table.py" "$OUT/run1" --markdown "$OUT/boot-tables.md" --full > "$OUT/ccel-table.txt" 2>&1 || { tail -5 "$OUT/ccel-table.txt"; fail "the boot event tables could not be made"; }
tail -1 "$OUT/ccel-table.txt"
echo "== 7. the files to publish (nothing that names the project)"
P="$OUT/publish"
if ! { cp "$OUT/reference.json" "$OUT/release/release.json" "$OUT/boot-tables.md" "$P/" && cp "$OUT/run1/quote.bin" "$P/quote-run1.bin" && cp "$OUT/run2/quote.bin" "$P/quote-run2.bin" && cp "$OUT/run1/announce.txt" "$P/announce-run1.txt" && cp "$OUT/run1/rtmr3-events.tsv" "$OUT/run1/settings.json" "$P/"; }; then fail "a file to publish is missing"; fi
if [ -f "$OUT/run1/ccel.bin" ]; then cp "$OUT/run1/ccel.bin" "$P/" || fail "ccel.bin could not be copied"; else fail "the boot event log ccel.bin is missing: this image does not publish it"; fi
FULL="$FULL" IMAGE="$IMAGE" ROOT="$ROOT" python3 - "$P/publication.json" <<'PY'
import hashlib, json, os, sys, time
root = os.environ["ROOT"]; tools = {}
for t in ("ops/make-reference.py", "ops/reference-run.sh", "ops/reference-compare.py", "ops/make-release.py", "ops/ccel-table.py", "ops/ci/publish-ref.sh"):
    p = os.path.join(root, t); tools[t] = hashlib.sha256(open(p, "rb").read()).hexdigest() if os.path.isfile(p) else None
e = os.environ; url = "%s/%s/actions/runs/%s" % (e["GITHUB_SERVER_URL"], e["GITHUB_REPOSITORY"], e["GITHUB_RUN_ID"]) if e.get("GITHUB_RUN_ID") and e.get("GITHUB_REPOSITORY") else ""
json.dump({"schema": 1, "image_commit": e["FULL"], "image": e["IMAGE"], "published_by_commit": e.get("GITHUB_SHA", "local"), "tag": e.get("GITHUB_REF_NAME", ""), "run_url": url, "made_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "tools_sha256": tools}, open(sys.argv[1], "w"), indent=2); open(sys.argv[1], "a").write("\n")
PY
[ -s "$P/publication.json" ] || fail "publication.json was not written"
for bad in instance.json image.json; do [ ! -e "$P/$bad" ] || fail "$bad must not be published (it names the project)"; done
if grep -r -l -F -- "$PROJECT_ID" "$P" >/dev/null 2>&1; then fail "a file to publish contains the project id: $(grep -r -l -F -- "$PROJECT_ID" "$P" | tr '\n' ' ')"; fi
if ! { ( cd "$P" && find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort | xargs sha256sum > "../sums.tmp" ) && mv "$OUT/sums.tmp" "$P/SHA256SUMS"; }; then fail "SHA256SUMS could not be made"; fi
( cd "$P" && sha256sum -c --quiet SHA256SUMS ) || fail "SHA256SUMS does not verify"
NF="$(find "$P" -maxdepth 1 -type f | wc -l)"
echo "   $NF files, SHA256SUMS verifies:"; ( cd "$P" && find . -maxdepth 1 -type f -printf '     %s %f\n' | LC_ALL=C sort -k2 )
echo; echo "PUBLISH-REF-OK commit=$FULL image=$IMAGE files=$NF out=$P by=${GITHUB_SHA:-local}"
