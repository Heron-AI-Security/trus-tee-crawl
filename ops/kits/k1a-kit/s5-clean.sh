( set -uo pipefail
cd ~/k1awork/tree; export IMG=tc-img-k1a-1 OUT=~/evidence-k1a-f WORKERS=10
CONFIRM=yes bash ops/image/test/f1-drive.sh fleet-delete
tar czf ~/evidence-k1a-final.tar.gz -C ~ evidence-k1a-A evidence-k1a-B evidence-k1a-s evidence-k1a-f evidence-k1a-diff.txt evidence-k1a-vs-old.txt k1a-p4 k1a-p56; echo "evidence fingerprint: $(sha256sum ~/evidence-k1a-final.tar.gz | cut -c1-64)"
gcloud compute instances list --format="table(name,status,zone.basename())"
echo BLOCK-E-DONE )
