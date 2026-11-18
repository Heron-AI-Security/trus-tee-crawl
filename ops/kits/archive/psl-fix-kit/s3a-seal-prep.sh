( set -uo pipefail
cd ~/pslwork/tree; ZA="$(cat ~/evidence-psl-A/zone.txt)"; ZB="$(cat ~/evidence-psl-B/zone.txt)"; mkdir -p ~/evidence-psl-s
echo "== stop both builders (the image is made from the disk of A; the evidence of both is saved; a stopped VM costs only its disk)"
gcloud compute instances stop tc-psl-a --zone=$ZA --quiet 2>&1 | tail -1
gcloud compute instances stop tc-psl-b --zone=$ZB --quiet 2>&1 | tail -1
for v in tc-r47-a tc-r47-b; do gcloud compute instances stop $v --zone="$(cat ~/evidence-r47-A/zone.txt)" --quiet 2>&1 | tail -1; done
echo "== the preflight of the sealing session (read-only, seconds)"
BUILDER=tc-psl-a ZONE=$ZA IMG=tc-img-psl-1 OUT=~/evidence-psl-s BASE_IMAGE=tc-img-dbg-1 bash ops/image/test/r3-preflight.sh ~/pslwork/tree && echo BLOCK-A-DONE || echo "BLOCK-A-FAILED: read the first FAIL line" )
