#!/usr/bin/env bash
# Rehearsal of the attack-root stage in its REAL (not dry) mode against a STATEFUL FAKE CLOUD that enforces the rules of GCE that have cost us runs: a c3 machine rejects pd-standard disks, names are unique, a disk that is in use cannot be attached again
# or deleted, deleting a VM removes its auto-delete disks and frees the others. ssh runs the command locally (with a fake home), the flip runs for real on a real ext4 image, the console of a corrupted root is the real console of the real-kernel run.
#   bash r3-cloud-rehearse.sh KITDIR      (as root; needs e2fsprogs and python3)
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; T="$KIT/ops/image/test"; PASS=0; FAILN=0; W="$(mktemp -d)"
chk() { local t="$1"; shift; if [ "${1:-1}" = 0 ]; then echo "  pass: $t"; PASS=$((PASS+1)); else echo "  FAIL: $t"; FAILN=$((FAILN+1)); fi; }
[ "$(id -u)" = 0 ] || { echo "  FAIL: needs root"; exit 2; }
mkdir -p "$W/bin" "$W/home" "$W/drvhome" "$W/img" "$W/root/usr/lib/systemd"; head -c 100000 /dev/urandom > "$W/root/usr/lib/systemd/systemd"; mke2fs -q -t ext4 -F -b 4096 -d "$W/root" "$W/img/p1" 64M >/dev/null 2>&1
printf '#!/bin/sh\nexec "$@"\n' > "$W/bin/sudo"; printf '#!/bin/sh\nexit 0\n' > "$W/bin/ssh-keygen"
cat > "$W/bin/gcloud" <<'EOS'
#!/usr/bin/env bash
FC="$FAKE_CLOUD"; FH="$FAKE_HOME"; args=("$@")
flag() { local k="$1" x; for x in "${args[@]}"; do case "$x" in --$k=*) echo "${x#--$k=}"; return 0;; esac; done; return 1; }
names() { local x; for x in "${args[@]:3}"; do case "$x" in --*) ;; *) echo "$x";; esac; done; }
err() { echo "ERROR: (gcloud.$1) $2" >&2; exit 1; }
fmt="$(flag format || true)"; res="${2:-}"; verb="${3:-}"
zone="$(flag zone || echo us-central1-a)"; ZC="$FC/z-$zone"; mkdir -p "$ZC/i" "$ZC/d"
stockout() { printf '%s\n' "ERROR: (gcloud.compute.instances.create) Could not fetch resource:" "---" "code: ZONE_RESOURCE_POOL_EXHAUSTED_WITH_DETAILS" "errorDetails:" "- localizedMessage:" "    locale: en-US" "    message: A c3-standard-4 VM instance is currently unavailable in the $zone zone. Try requesting the VM in another zone." "- errorInfo:" "    reason: stockout" "message: The zone 'projects/training-custody/zones/$zone' does not have enough resources available to fulfill the request.  '(resource type:compute)'." >&2; exit 1; }
if [ -n "${FAKE_FAIL_ONCE:-}" ] && [ "$FAKE_FAIL_ONCE" = "$res-$verb" ] && [ ! -e "$FC/failed-once" ]; then : > "$FC/failed-once"; echo "ERROR: (gcloud.compute.$res.$verb) Internal error. Please try again in 30 seconds. (the fake cloud fails the first call, once)" >&2; exit 1; fi
users_of() { cat "$ZC/d/$1/users" 2>/dev/null; }
case "$res/$verb" in
 instances/describe) n="$(names | head -1)"; [ -d "$ZC/i/$n" ] || err compute.instances.describe "The resource 'projects/p/zones/z/instances/$n' was not found"; if [ "$fmt" = "value(status)" ]; then cat "$ZC/i/$n/status"; else echo "name: $n"; fi ;;
 instances/create)
   n="$(names | head -1)"; [ -d "$ZC/i/$n" ] && err compute.instances.create "The resource 'instances/$n' already exists"; m="$(flag machine-type)"
   case "$m" in c3-*)
     case ",${FAKE_STOCKOUT_ZONES:-}," in *",$zone,"*) stockout ;; esac
     case ",${FAKE_STOCKOUT_SECOND:-}," in *",$zone,"*) c=$(cat "$FC/c3n-$zone" 2>/dev/null || echo 0); echo $((c + 1)) > "$FC/c3n-$zone"; [ "$c" -ge 1 ] && stockout ;; esac ;; esac
   mkdir -p "$ZC/i/$n"; : > "$ZC/i/$n/disks"; boot=""
   for x in "${args[@]}"; do case "$x" in
     --disk=*) spec="${x#--disk=}"; dn=""; bt=no; ad=yes; dv=""; IFS=, read -ra kv <<<"$spec"; for p in "${kv[@]}"; do case "$p" in name=*) dn="${p#name=}";; boot=*) bt="${p#boot=}";; auto-delete=*) ad="${p#auto-delete=}";; device-name=*) dv="${p#device-name=}";; esac; done
       [ -d "$ZC/d/$dn" ] || { rm -rf "$ZC/i/$n"; err compute.instances.create "The resource 'disks/$dn' was not found"; }
       case "$m" in c3-*) [ "$(cat "$ZC/d/$dn/type")" = pd-standard ] && { rm -rf "$ZC/i/$n"; echo "ERROR: (gcloud.compute.instances.create) Could not fetch resource:
 - pd-standard disk type cannot be used by $m machine type." >&2; exit 1; } ;; esac
       [ -s "$ZC/d/$dn/users" ] && { rm -rf "$ZC/i/$n"; err compute.instances.create "The disk resource 'disks/$dn' is already being used by '$(cat "$ZC/d/$dn/users")'"; }
       echo "$n" > "$ZC/d/$dn/users"; echo "$dn $ad $bt $dv" >> "$ZC/i/$n/disks"; [ "$bt" = yes ] && boot="$dn" ;;
     --create-disk=*) spec="${x#--create-disk=}"; dn=""; ty=pd-balanced; ad=yes; dv=""; IFS=, read -ra kv <<<"$spec"; for p in "${kv[@]}"; do case "$p" in name=*) dn="${p#name=}";; type=*) ty="${p#type=}";; auto-delete=*) ad="${p#auto-delete=}";; device-name=*) dv="${p#device-name=}";; esac; done
       case "$m" in c3-*) [ "$ty" = pd-standard ] && { rm -rf "$ZC/i/$n"; echo "ERROR: (gcloud.compute.instances.create) Could not fetch resource:
 - pd-standard disk type cannot be used by $m machine type." >&2; exit 1; } ;; esac
       mkdir -p "$ZC/d/$dn"; echo "$ty" > "$ZC/d/$dn/type"; echo "$n" > "$ZC/d/$dn/users"; echo 0 > "$ZC/d/$dn/flipped"; echo "$dn $ad no $dv" >> "$ZC/i/$n/disks" ;;
   esac; done
   if [ -z "$boot" ]; then img="$(flag image)" || err compute.instances.create "no boot disk"; mkdir -p "$ZC/d/$n"; echo pd-balanced > "$ZC/d/$n/type"; echo "$n" > "$ZC/d/$n/users"; echo 0 > "$ZC/d/$n/flipped"; cp "$FC/img/$img.p1" "$ZC/d/$n/p1"; echo "$n yes yes" >> "$ZC/i/$n/disks"; boot="$n"; fi
   echo RUNNING > "$ZC/i/$n/status"; echo "$m" > "$ZC/i/$n/machine"
   { echo "error: can't find command \`serial'."; if [ "$(cat "$ZC/d/$boot/flipped")" = 1 ]; then cat "$FAKE_FIXTURE"; else echo "tc-verity: the root disk matches the root hash abc"; echo "tc-scratch: nvme0n2 is the scratch disk (dm-integrity HMAC-SHA256 under dm-crypt AES-XTS, keys that exist only in this boot)"; echo "$n login: "; fi; } > "$ZC/i/$n/console"
   echo "NAME: $n"; echo "STATUS: RUNNING" ;;
 instances/delete) for n in $(names); do [ -d "$ZC/i/$n" ] || err compute.instances.delete "The resource 'instances/$n' was not found"; while read -r dn ad bt dv; do if [ "$ad" = yes ]; then rm -rf "$ZC/d/$dn"; else : > "$ZC/d/$dn/users"; fi; done < "$ZC/i/$n/disks"; rm -rf "$ZC/i/$n"; echo "Deleted [instances/$n]."; done ;;
 instances/reset|instances/stop|instances/start) echo "Updated [$verb]." ;;
 instances/get-serial-port-output) n="$(names | head -1)"; [ -d "$ZC/i/$n" ] || err compute.instances.get-serial-port-output "The resource 'instances/$n' was not found"; cat "$ZC/i/$n/console" ;;
 disks/create) n="$(names | head -1)"; [ -d "$ZC/d/$n" ] && err compute.disks.create "The resource 'disks/$n' already exists"; img="$(flag image || true)"; src="$(flag source-disk || true)"; t="$(flag type || true)"
   mkdir -p "$ZC/d/$n"; : > "$ZC/d/$n/users"; echo 0 > "$ZC/d/$n/flipped"
   if [ -n "$src" ]; then echo "$(cat "$ZC/d/$src/type")" > "$ZC/d/$n/type"; cp "$ZC/d/$src/p1" "$ZC/d/$n/p1" 2>/dev/null; else echo "${t:-pd-standard}" > "$ZC/d/$n/type"; cp "$FC/img/$img.p1" "$ZC/d/$n/p1"; fi; echo "Created [disks/$n]."; echo "TYPE: $(cat "$ZC/d/$n/type")" ;;
 disks/describe) n="$(names | head -1)"; [ -d "$ZC/d/$n" ] || err compute.disks.describe "The resource 'disks/$n' was not found"; case "$fmt" in "value(users)") users_of "$n" ;; "value(status)") echo READY ;; "value(type.basename())") cat "$ZC/d/$n/type" ;; *) echo "name: $n" ;; esac ;;
 disks/delete) for n in $(names); do [ -d "$ZC/d/$n" ] || err compute.disks.delete "The resource 'disks/$n' was not found"; [ -s "$ZC/d/$n/users" ] && err compute.disks.delete "The disk resource 'disks/$n' is already being used by '$(cat "$ZC/d/$n/users")'"; rm -rf "$ZC/d/$n"; echo "Deleted [disks/$n]."; done ;;
 images/describe) n="$(names | head -1)"; [ -f "$FC/img/$n.p1" ] || err compute.images.describe "The resource 'images/$n' was not found" ;;
 scp/*) vm="${4%%:*}"; [ -d "$ZC/i/$vm" ] || err compute.scp "no such instance $vm"; cp "$3" "$FH/$(basename "${4#*:}")" ;;
 ssh/*) n="$3"; [ -d "$ZC/i/$n" ] || err compute.ssh "no such instance $n"; mkdir -p /dev/disk/by-id
   while read -r dn ad bt dv; do if [ "$dv" = target ]; then ln -sf "$ZC/d/$dn/p1" /dev/disk/by-id/google-target-part1; cp -n "$ZC/d/$dn/p1" "$ZC/d/$dn/p1.orig"; fi; done < "$ZC/i/$n/disks"
   HOME="$FH" PATH="$FAKE_BIN:$PATH" bash -c "$(flag command)"; rc=$?
   while read -r dn ad bt dv; do if [ "$dv" = target ] && ! cmp -s "$ZC/d/$dn/p1" "$ZC/d/$dn/p1.orig"; then echo 1 > "$ZC/d/$dn/flipped"; fi; done < "$ZC/i/$n/disks"; exit $rc ;;
 *) echo "FAKE-GCLOUD: unsupported call: $*" >&2; exit 97 ;;
esac
EOS
chmod +x "$W/bin"/*
fresh() { rm -rf "$W/cloud" "$W/home/"* "$W/out"; mkdir -p "$W/cloud"/{img,z-us-central1-a/i,z-us-central1-a/d} "$W/out"; cp "$W/img/p1" "$W/cloud/img/tc-img-seal-4.p1"; cp "$W/img/p1" "$W/cloud/img/tc-img-dbg-1.p1"
  mkdir -p "$W/cloud/z-us-central1-a/d/tc-seal-work" "$W/cloud/z-us-central1-a/d/tc-atk-disk" "$W/cloud/z-us-central1-a/d/tc-seal-test" "$W/cloud/z-us-central1-a/d/tc-seal-test-scratch" "$W/cloud/z-us-central1-a/i/tc-seal-test"; echo pd-balanced > "$W/cloud/z-us-central1-a/d/tc-seal-work/type"; echo pd-standard > "$W/cloud/z-us-central1-a/d/tc-atk-disk/type"; echo pd-balanced > "$W/cloud/z-us-central1-a/d/tc-seal-test/type"; echo pd-balanced > "$W/cloud/z-us-central1-a/d/tc-seal-test-scratch/type"
  for d in tc-seal-work tc-atk-disk tc-seal-test tc-seal-test-scratch; do : > "$W/cloud/z-us-central1-a/d/$d/users"; echo 0 > "$W/cloud/z-us-central1-a/d/$d/flipped"; done; echo tc-seal-test > "$W/cloud/z-us-central1-a/d/tc-seal-test/users"; echo tc-seal-test > "$W/cloud/z-us-central1-a/d/tc-seal-test-scratch/users"
  printf 'tc-seal-test yes yes\ntc-seal-test-scratch yes no tcscratch\n' > "$W/cloud/z-us-central1-a/i/tc-seal-test/disks"; echo RUNNING > "$W/cloud/z-us-central1-a/i/tc-seal-test/status"; echo c3-standard-4 > "$W/cloud/z-us-central1-a/i/tc-seal-test/machine"; rm -f /dev/disk/by-id/google-target-part1; }
drive() { # DRIVER-DIR STAGES...: the real driver, not dry, against the fake cloud (the state of the cloud is kept between calls)
  local d="$1"; shift; ( cd "$KIT" && env -u DRY HOME="$W/drvhome" PATH="$W/bin:$PATH" FAKE_CLOUD="$W/cloud" FAKE_HOME="$W/home" FAKE_BIN="$W/bin" FAKE_FIXTURE="$T/fixtures/attack-root-console.txt" IMG=tc-img-seal-4 OUT="$W/out" KVER=6.17.0-1022-gcp SEAL_POLL=1 SEAL_WATCH_SECONDS=10 SEAL_REFETCH=0 RETRY_SLEEP=1 timeout 120 bash "$d/f03-drive.sh" "$@" 2>&1 ); }
cloud_has() { ls "$W/cloud/z-us-central1-a/i" "$W/cloud/z-us-central1-a/d" 2>/dev/null | tr '\n' ' '; }
echo "=== A. the sequence of Block 3c, from the state of Block 3b (old pd-standard attack disk, test VM running): seal-delete, attack-root, seal-delete"
fresh; o1="$(CONFIRM=yes drive "$T" seal-delete)"; rc1=$?
chk "step 1: seal-delete removes the old VM and BOTH old disks, by name" $([ $rc1 = 0 ] && [ ! -d "$W/cloud/z-us-central1-a/i/tc-seal-test" ] && [ ! -d "$W/cloud/z-us-central1-a/d/tc-atk-disk" ] && [ ! -d "$W/cloud/z-us-central1-a/d/tc-seal-work" ] && [ ! -d "$W/cloud/z-us-central1-a/d/tc-seal-test-scratch" ]; echo $?)
o2="$(drive "$T" attack-root)"; rc2=$?; echo "$o2" | grep -E "^STOP|ATTACK-ROOT|FLIP-OK|THE BOOT FAILED|not pd-balanced" | cut -c1-170 | sed 's/^/      /'
chk "step 2: attack-root runs to the end against the fake cloud: it ends with ATTACK-ROOT-REFUSED" $([ $rc2 = 0 ] && grep -q '^ATTACK-ROOT-REFUSED' <<<"$o2"; echo $?)
chk "the flip really happened (on the real ext4 image) and the helper was deleted, the attack VM exists and booted FROM the attack disk" $(grep -q '^FLIP-OK' <<<"$o2" && [ ! -d "$W/cloud/z-us-central1-a/i/tc-sealer" ] && [ -d "$W/cloud/z-us-central1-a/i/tc-atk-test" ] && grep -q 'tc-atk-disk yes' "$W/cloud/z-us-central1-a/i/tc-atk-test/disks" 2>/dev/null || grep -q '^tc-atk-disk no yes' "$W/cloud/z-us-central1-a/i/tc-atk-test/disks"; echo $?)
o3="$(CONFIRM=yes drive "$T" seal-delete)"; rc3=$?; chk "step 3: the final seal-delete leaves nothing of ours (no VM, no disk)" $([ $rc3 = 0 ] && [ -z "$(find "$W/cloud" -mindepth 3 -maxdepth 3 -path '*/z-*/*/*' 2>/dev/null)" ]; echo $?)
echo "=== B. the same stage with the mistakes of today put back, against the same rules"
cp -r "$KIT" "$W/mk1"; sed -i 's/--image="$IMG" --type=pd-balanced --zone/--image="$IMG" --zone/' "$W/mk1/ops/image/test/f03-drive.sh"; fresh; CONFIRM=yes drive "$T" seal-delete >/dev/null; o="$(drive "$W/mk1/ops/image/test" attack-root)"; rc=$?
chk "no --type: the stage stops at ONCE, right after the disk is created, with the pd-balanced message (not after 6 minutes of work), and no helper was created" $([ $rc != 0 ] && grep -q 'is not pd-balanced' <<<"$o" && [ ! -d "$W/cloud/z-us-central1-a/i/tc-sealer" ]; echo $?)
cp -r "$KIT" "$W/mk2"; sed -i 's/--image="$IMG" --type=pd-balanced --zone/--image="$IMG" --zone/; s/|| die "the disk $ATK is not pd-balanced/|| true "the disk $ATK is not pd-balanced/' "$W/mk2/ops/image/test/f03-drive.sh"; fresh; CONFIRM=yes drive "$T" seal-delete >/dev/null; o="$(drive "$W/mk2/ops/image/test" attack-root)"; rc=$?
chk "the fake cloud itself enforces the rule: without the type AND without the early check, the c3 VM creation is rejected with GCE's own message (this is the failure of Block 3b, reproduced)" $([ $rc != 0 ] && grep -q 'pd-standard disk type cannot be used by c3-standard-4' <<<"$o"; echo $?)
echo "=== C. a transient error of the cloud on the first creation of the helper: the stage tries again and ends the same way"
fresh; CONFIRM=yes drive "$T" seal-delete >/dev/null; o="$(FAKE_FAIL_ONCE=instances-create drive "$T" attack-root)"; rc=$?
chk "the helper creation fails once with an internal error: the error is shown, the stage tries again, and still ends with ATTACK-ROOT-REFUSED" $([ $rc = 0 ] && grep -q 'Internal error' <<<"$o" && grep -q 'trying again' <<<"$o" && grep -q '^ATTACK-ROOT-REFUSED' <<<"$o"; echo $?)
echo "=== D. Block 4's fleet-vms stage, not dry, against the same rules of the cloud (TDX c3 machines with a scratch disk)"
fresh; CONFIRM=yes drive "$T" seal-delete >/dev/null; rm -rf "$W/out2"; mkdir -p "$W/out2"
o="$( cd "$KIT" && env -u DRY HOME="$W/drvhome" PATH="$W/bin:$PATH" FAKE_CLOUD="$W/cloud" FAKE_HOME="$W/home" FAKE_BIN="$W/bin" FAKE_FIXTURE=/dev/null IMG=tc-img-seal-4 OUT="$W/out2" SCRATCH_GB=10 EXPORT_BUCKET=b EXPORT_SA=sa@x timeout 120 bash "$T/f1-drive.sh" fleet-vms 2>&1 )"; rc=$?; echo "$o" | grep -E "FAKE-GCLOUD|STOP|ERROR" | head -3 | cut -c1-200 | sed 's/^/      /'
chk "fleet-vms creates the master and the worker as c3 machines from the sealed image, each with its own scratch disk (pd-balanced, device name tcscratch)" $([ $rc = 0 ] && [ -d "$W/cloud/z-us-central1-a/i/tc-f1-m" ] && [ -d "$W/cloud/z-us-central1-a/i/tc-f1-w" ] && [ "$(cat "$W/cloud/z-us-central1-a/d/tc-f1-m-scratch/type" 2>/dev/null)" = pd-balanced ] && grep -q 'tc-f1-w-scratch yes no tcscratch' "$W/cloud/z-us-central1-a/i/tc-f1-w/disks"; echo $?)
empty_cloud() { [ -z "$(find "$W/cloud" -mindepth 3 -maxdepth 3 -path '*/z-*/*/*' 2>/dev/null)" ]; }
echo "=== E. a STOCKOUT of c3 machines in the first zone, as in the log of Block 3d"
fresh; CONFIRM=yes drive "$T" seal-delete >/dev/null; o="$(FAKE_STOCKOUT_ZONES=us-central1-a drive "$T" attack-root)"; rc=$?
chk "attack-root: the stockout in us-central1-a is shown with the cloud's own text, that zone is NOT retried, the disk and the helper made there are removed, and the stage ends with ATTACK-ROOT-REFUSED in us-central1-b" $([ $rc = 0 ] && grep -q 'reason: stockout' <<<"$o" && grep -q 'NO CAPACITY in us-central1-a' <<<"$o" && ! grep -q 'trying again in' <<<"$o" && grep -q '^ATTACK-ROOT-REFUSED' <<<"$o" && [ ! -d "$W/cloud/z-us-central1-a/d/tc-atk-disk" ] && [ ! -d "$W/cloud/z-us-central1-a/i/tc-sealer" ] && [ -d "$W/cloud/z-us-central1-b/i/tc-atk-test" ] && [ "$(cat "$W/out/zone-attack.txt")" = us-central1-b ]; echo $?)
CONFIRM=yes drive "$T" seal-delete >/dev/null; chk "seal-delete, run with the default zone, still finds and removes the attack VM and its disk in us-central1-b (it scans every candidate zone)" $(empty_cloud; echo $?)
fresh; CONFIRM=yes drive "$T" seal-delete >/dev/null; o="$(FAKE_STOCKOUT_ZONES=us-central1-a,us-central1-b,us-central1-c,us-central1-f drive "$T" attack-root)"; rc=$?
chk "a stockout in EVERY zone: the stage fails with a clear message that lists the zones, and leaves nothing behind in any zone" $([ $rc != 0 ] && grep -q 'no zone had capacity (tried: us-central1-a us-central1-b us-central1-c us-central1-f' <<<"$o" && empty_cloud; echo $?)
cp -r "$KIT" "$W/mk3"; sed -i 's|ORDER="$(zones_in_order \| tr .\\n. . .)"; \[ "$DRY" != 1 \] \|\| ORDER="$Z0"|ORDER="$Z0"|' "$W/mk3/ops/image/test/f03-drive.sh"; fresh; CONFIRM=yes drive "$T" seal-delete >/dev/null; o="$(FAKE_STOCKOUT_ZONES=us-central1-a drive "$W/mk3/ops/image/test" attack-root)"; rc=$?
chk "MUTANT with a single zone (the behaviour of Block 3d): the same stockout makes the stage fail, so the zone fallback is what fixes it" $([ $rc != 0 ] && grep -q 'no zone had capacity (tried: us-central1-a)' <<<"$o"; echo $?)
echo "=== G. the fleet of Block 4 with a stockout: the master is made, the worker fails, the master is removed, and both are made in the next zone"
fresh; CONFIRM=yes drive "$T" seal-delete >/dev/null; rm -rf "$W/out2"; mkdir -p "$W/out2"
fleet() { ( cd "$KIT" && env -u DRY HOME="$W/drvhome" PATH="$W/bin:$PATH" FAKE_CLOUD="$W/cloud" FAKE_HOME="$W/home" FAKE_BIN="$W/bin" FAKE_FIXTURE=/dev/null IMG=tc-img-seal-4 OUT="$W/out2" SCRATCH_GB=10 "$@" timeout 120 bash "$T/f1-drive.sh" fleet-vms 2>&1 ); }
o="$(fleet FAKE_STOCKOUT_SECOND=us-central1-a)"; rc=$?
chk "fleet-vms: the worker fails in zone a after the master was made there: the master is removed from zone a (nothing is left there), both VMs exist in us-central1-b, and zone.txt says so" $([ $rc = 0 ] && grep -q 'reason: stockout' <<<"$o" && grep -q 'could not host the fleet' <<<"$o" && [ ! -d "$W/cloud/z-us-central1-a/i/tc-f1-m" ] && [ -d "$W/cloud/z-us-central1-b/i/tc-f1-m" ] && [ -d "$W/cloud/z-us-central1-b/i/tc-f1-w" ] && [ "$(cat "$W/out2/zone.txt")" = us-central1-b ]; echo $?)
d="$( cd "$KIT" && DRY=1 IMG=tc-img-seal-4 OUT="$W/out2" bash "$T/f1-drive.sh" fleet-vms 2>&1 | sed 's/\\//g')"
chk "every later stage of the fleet driver uses the zone that fleet-vms found (a new invocation, without ZONE, prints --zone=us-central1-b)" $(grep -q -- '--zone=us-central1-b' <<<"$d" && ! grep -q -- '--zone=us-central1-a' <<<"$d"; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "R3-CLOUD-REHEARSAL-PASS"; else echo "R3-CLOUD-REHEARSAL-FAIL"; fi
rm -f /dev/disk/by-id/google-target-part1; rm -rf "$W"; [ "$FAILN" = 0 ]
