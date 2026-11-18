( set -uo pipefail
cd ~/r47work/tree; ZA="$(cat ~/evidence-r47-A/zone.txt)"; ZB="$(cat ~/evidence-r47-B/zone.txt)"; mkdir -p ~/evidence-r47-s
echo "== stop both builders (the image is made from the disk of A; the evidence of both is saved; a stopped VM costs only its disk)"
gcloud compute instances stop tc-r47-a --zone=$ZA --quiet 2>&1 | tail -1
gcloud compute instances stop tc-r47-b --zone=$ZB --quiet 2>&1 | tail -1
for v in tc-fin-a tc-fin-b; do gcloud compute instances stop $v --zone="$(cat ~/evidence-fin-A/zone.txt)" --quiet 2>&1 | tail -1; done
echo "== the preflight of the sealing session (read-only, seconds)"
BUILDER=tc-r47-a ZONE=$ZA IMG=tc-img-r47-1 OUT=~/evidence-r47-s BASE_IMAGE=tc-img-dbg-1 bash ops/image/test/r3-preflight.sh ~/r47work/tree && echo BLOCK-A-DONE || echo "BLOCK-A-FAILED: read the first FAIL line" )
