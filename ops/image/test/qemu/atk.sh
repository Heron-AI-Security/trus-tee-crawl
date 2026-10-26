#!/bin/bash
cd /tmp/rep; rm -f scratch.img; cp scratch.blank scratch.img
QTIMEOUT=250 ./boot.sh /tmp/initrd-prod.img /tmp/rep/atk1.log init=/sbin/tc-atk1
U="$(sed -n 's/^UUID=//p' /tmp/rep/atk1.log | tr -d '\r' | tail -1)"; echo "uuid1=$U" > /tmp/rep/atk.state
KEEP_SCRATCH=1 QTIMEOUT=250 ./boot.sh /tmp/initrd-prod.img /tmp/rep/atk2.log init=/sbin/tc-atk2 olduuid=$U
echo ATKDONE >> /tmp/rep/atk.state
