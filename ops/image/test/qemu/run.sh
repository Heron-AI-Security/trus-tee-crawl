#!/bin/bash
# run.sh INITRD LOG [kernel args]: boot and wait for the end
cd /tmp/rep; rm -f scratch.blank scratch.img; truncate -s "${SCRATCH:-2G}" scratch.blank; (nohup ./boot.sh "$@" > /dev/null 2>&1 &)
for i in $(seq 1 40); do sleep 8; grep -q "qemu exit" "$2" 2>/dev/null && break; done; echo "waited $((i*8)) s"
