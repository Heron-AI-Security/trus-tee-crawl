( set -uo pipefail
cd ~/cl2work/tree; ZA="$(cat ~/evidence-cl2-A/zone.txt)"; ZB="$(cat ~/evidence-cl2-B/zone.txt)"; mkdir -p ~/evidence-cl2-s
echo "== stop both builders (the image is made from the disk of A; the evidence of both is saved; a stopped VM costs only its disk)"
gcloud compute instances stop tc-cl2-a --zone=$ZA --quiet 2>&1 | tail -1
gcloud compute instances stop tc-cl2-b --zone=$ZB --quiet 2>&1 | tail -1
for v in tc-r47-a tc-r47-b; do gcloud compute instances stop $v --zone="$(cat ~/evidence-r47-A/zone.txt)" --quiet 2>&1 | tail -1; done
echo "== the preflight of the sealing session (read-only, seconds)"
BUILDER=tc-cl2-a ZONE=$ZA IMG=tc-img-cl2-1 OUT=~/evidence-cl2-s BASE_IMAGE=tc-img-dbg-1 bash ops/image/test/r3-preflight.sh ~/cl2work/tree && echo BLOCK-A-DONE || echo "BLOCK-A-FAILED: read the first FAIL line" )
