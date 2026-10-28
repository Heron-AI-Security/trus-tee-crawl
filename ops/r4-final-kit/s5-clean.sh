( set -uo pipefail
cd ~/fin2work/tree; export IMG=tc-img-fin2-1 OUT=~/evidence-fin2-f
CONFIRM=yes bash ops/image/test/f1-drive.sh fleet-delete
tar czf ~/evidence-fin2-final.tar.gz -C ~ evidence-fin2-A evidence-fin2-B evidence-fin2-s evidence-fin2-f evidence-fin2-diff.txt evidence-fin2-vs-old.txt; echo "evidence fingerprint: $(sha256sum ~/evidence-fin2-final.tar.gz | cut -c1-64)"
gcloud compute instances list --format="table(name,status,zone.basename())"
echo BLOCK-E-DONE )
