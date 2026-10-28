( set -uo pipefail
cd ~/fin2work/tree; ZA="$(cat ~/evidence-fin2-A/zone.txt)"; ZB="$(cat ~/evidence-fin2-B/zone.txt)"; mkdir -p ~/evidence-fin2-s
echo "== stop both builders (the image is made from the disk of A; the evidence of both is saved; a stopped VM costs only its disk)"
gcloud compute instances stop tc-fin-a --zone=$ZA --quiet 2>&1 | tail -1
gcloud compute instances stop tc-fin-b --zone=$ZB --quiet 2>&1 | tail -1
echo "== the preflight of the sealing session (read-only, seconds)"
BUILDER=tc-fin-a ZONE=$ZA IMG=tc-img-fin2-1 OUT=~/evidence-fin2-s BASE_IMAGE=tc-img-dbg-1 bash ops/image/test/r3-preflight.sh ~/fin2work/tree && echo BLOCK-A-DONE || echo "BLOCK-A-FAILED: read the first FAIL line" )
