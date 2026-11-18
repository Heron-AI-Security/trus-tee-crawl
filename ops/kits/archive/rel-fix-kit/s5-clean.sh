( set -uo pipefail
cd ~/relwork/tree; export IMG=tc-img-rel-1 OUT=~/evidence-rel-f
CONFIRM=yes bash ops/image/test/f1-drive.sh fleet-delete
tar czf ~/evidence-rel-final.tar.gz -C ~ evidence-rel-A evidence-rel-B evidence-rel-s evidence-rel-f evidence-rel-diff.txt evidence-rel-vs-old.txt; echo "evidence fingerprint: $(sha256sum ~/evidence-rel-final.tar.gz | cut -c1-64)"
gcloud compute instances list --format="table(name,status,zone.basename())"
echo BLOCK-E-DONE )
