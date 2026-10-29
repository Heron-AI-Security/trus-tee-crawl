( set -uo pipefail
cd ~/pslwork/tree; export IMG=tc-img-psl-1 OUT=~/evidence-psl-f
CONFIRM=yes bash ops/image/test/f1-drive.sh fleet-delete
tar czf ~/evidence-psl-final.tar.gz -C ~ evidence-psl-A evidence-psl-B evidence-psl-s evidence-psl-f evidence-psl-diff.txt evidence-psl-vs-old.txt; echo "evidence fingerprint: $(sha256sum ~/evidence-psl-final.tar.gz | cut -c1-64)"
gcloud compute instances list --format="table(name,status,zone.basename())"
echo BLOCK-E-DONE )
