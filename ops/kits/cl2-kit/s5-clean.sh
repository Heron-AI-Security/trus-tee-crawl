( set -uo pipefail
cd ~/cl2work/tree; export IMG=tc-img-cl2-1 OUT=~/evidence-cl2-f
CONFIRM=yes bash ops/image/test/f1-drive.sh fleet-delete
tar czf ~/evidence-cl2-final.tar.gz -C ~ evidence-cl2-A evidence-cl2-B evidence-cl2-s evidence-cl2-f evidence-cl2-diff.txt evidence-cl2-vs-old.txt; echo "evidence fingerprint: $(sha256sum ~/evidence-cl2-final.tar.gz | cut -c1-64)"
gcloud compute instances list --format="table(name,status,zone.basename())"
echo BLOCK-E-DONE )
