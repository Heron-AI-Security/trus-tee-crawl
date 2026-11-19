( set -uo pipefail
cd ~/e15r2work/tree; export IMG=tc-img-e15r2-1 OUT=~/evidence-e15r2-f WORKERS=10
CONFIRM=yes bash ops/image/test/f1-drive.sh fleet-delete
tar czf ~/evidence-e15r2-final.tar.gz -C ~ evidence-e15r2-A evidence-e15r2-B evidence-e15r2-s evidence-e15r2-f evidence-e15r2-diff.txt evidence-e15r2-vs-old.txt e15r2-p4 e15r2-p56; echo "evidence fingerprint: $(sha256sum ~/evidence-e15r2-final.tar.gz | cut -c1-64)"
gcloud compute instances list --format="table(name,status,zone.basename())"
echo BLOCK-E-DONE )
