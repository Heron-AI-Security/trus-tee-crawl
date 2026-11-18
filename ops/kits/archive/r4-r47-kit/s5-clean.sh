( set -uo pipefail
cd ~/r47work/tree; export IMG=tc-img-r47-1 OUT=~/evidence-r47-f
CONFIRM=yes bash ops/image/test/f1-drive.sh fleet-delete
tar czf ~/evidence-r47-final.tar.gz -C ~ evidence-r47-A evidence-r47-B evidence-r47-s evidence-r47-f evidence-r47-diff.txt evidence-r47-vs-old.txt; echo "evidence fingerprint: $(sha256sum ~/evidence-r47-final.tar.gz | cut -c1-64)"
gcloud compute instances list --format="table(name,status,zone.basename())"
echo BLOCK-E-DONE )
