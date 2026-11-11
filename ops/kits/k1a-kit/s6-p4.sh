( set -uo pipefail
cd ~/k1awork/tree || { echo "P4-FAILED: no ~/k1awork/tree"; exit 1; }
C="$(cat ~/k1a-commit.txt)"; IA=tc-img-k1a-1; IB=tc-img-k1a-2; W=~/k1a-p4; rm -rf "$W"; mkdir -p "$W"
for f in ops/ci/publish-ref.sh ops/verify-reference.sh ops/tree-diff.sh ops/tree-helper.sh ops/tree-lib.sh ops/verify-reference.py; do [ -f "$f" ] || { echo "P4-FAILED: $f is not in the commit that was built: the P4 commits (p4b, p4c) must be pushed BEFORE this commit is made"; exit 1; }; done
RA="$(awk -F= '/^roothash=/ {print $2}' ~/evidence-k1a-s/seal-report.txt 2>/dev/null)"; RB="$(awk -F= '/^roothash=/ {print $2}' ~/evidence-k1a-s2/seal-report.txt 2>/dev/null)"
{ [[ "$RA" =~ ^[0-9a-f]{64}$ ]] && [[ "$RB" =~ ^[0-9a-f]{64}$ ]]; } || { echo "P4-FAILED: the seal reports of the two builds have no root hash (evidence-k1a-s and evidence-k1a-s2)"; exit 1; }
echo "== the two sealed images of ONE commit: A $IA root hash ${RA:0:16}..., B $IB root hash ${RB:0:16}..."
[ "$RA" != "$RB" ] || echo "   note: the two root hashes are EQUAL: the two builds are bit-identical"
echo "== 1. the labels (image A is the PUBLISHED image: it carries the commit and its root hash; image B is the second build of the same commit)"
gcloud compute images add-labels $IA --labels="commit=$C,verity-a=${RA:0:32},verity-b=${RA:32:32}" 2>&1 | tail -1
gcloud compute images add-labels $IB --labels="verity-a=${RB:0:32},verity-b=${RB:32:32},build=second" 2>&1 | tail -1
echo "== 2. the reference of image A: two dummy runs of it, then the published files (about 12 minutes)"
( COMMIT="${C:0:9}" bash ops/ci/publish-ref.sh "$W/pub" ) 2>&1 | tee "$W/publish.log" | tail -6
grep -q "^PUBLISH-REF-OK" "$W/publish.log" || { echo "P4-FAILED: the reference of image A could not be published (see $W/publish.log)"; exit 1; }
echo "== 3. verify-reference.sh: published = image A, own build = image B (built from the SECOND archive of the same commit), then the files of the two root disks, each opened through dm-verity (about 30 minutes)"
bash ops/verify-reference.sh "$C" --published "$W/pub/publish" --published-image $IA --own-image $IB --work "$W/verify" 2>&1 | tee "$W/verify.log" | grep -v "^  ok:"
grep -q "^VERIFY-REFERENCE-OK .* trees=identical image-run=exact" "$W/verify.log" || {
  echo "P4-FAILED: the two builds of one commit were NOT verified as the same (the lines above and $W/verify.log say why)"
  if [ -f "$W/verify/trees/differences.tsv" ]; then echo "== the differences of the file trees, by kind:"; cut -f2 "$W/verify/trees/differences.tsv" | sort | uniq -c | sort -rn; echo "== the differences (kind, path, detail), at most 80:"; cut -f2,3,4 "$W/verify/trees/differences.tsv" | sort -k2 | cut -c1-200 | head -80; fi
  exit 1; }
echo "   $(grep '^VERIFY-REFERENCE-OK' "$W/verify.log" | cut -c1-200)"
tar czf ~/evidence-k1a-p4.tar.gz -C ~ k1a-p4 2>/dev/null; echo "evidence fingerprint: $(sha256sum ~/evidence-k1a-p4.tar.gz | cut -c1-64)"
echo "P4-ACCEPT-OK commit=${C:0:9} A=$IA B=$IB" )
