( set -uo pipefail
cd ~/relwork/tree; ZA="$(cat ~/evidence-rel-A/zone.txt)"; ZB="$(cat ~/evidence-rel-B/zone.txt)"; mkdir -p ~/evidence-rel-s
echo "== stop both builders (the image is made from the disk of A; the evidence of both is saved; a stopped VM costs only its disk)"
gcloud compute instances stop tc-rel-a --zone=$ZA --quiet 2>&1 | tail -1
gcloud compute instances stop tc-rel-b --zone=$ZB --quiet 2>&1 | tail -1
for v in tc-r47-a tc-r47-b; do gcloud compute instances stop $v --zone="$(cat ~/evidence-r47-A/zone.txt)" --quiet 2>&1 | tail -1; done
echo "== the preflight of the sealing session (read-only, seconds)"
BUILDER=tc-rel-a ZONE=$ZA IMG=tc-img-rel-1 OUT=~/evidence-rel-s BASE_IMAGE=tc-img-dbg-1 bash ops/image/test/r3-preflight.sh ~/relwork/tree && echo BLOCK-A-DONE || echo "BLOCK-A-FAILED: read the first FAIL line" )
