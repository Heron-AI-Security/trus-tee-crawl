#!/usr/bin/env bash
# Rehearsal of step P4 (the build cleanup): N) ops/image/build/tc-image-normalize.sh on a fake root with every kind of residue, awkward names, and a symbolic link that points out of the root; C) the live cleaning
# ops/image/build/tc-image-clean.sh (the /root glob that matched nothing, and the purge of snapd) with a stub apt-get; S) the REAL ops/image/build/tc-image-seal.sh on REAL ext4 images (real loop mounts and veritysetup):
# two builds that differ ONLY in the builder's residue must give the SAME file tree once sealed (ops/tree-manifest.py and ops/tree-diff.py are the judge), and the same two builds sealed with --no-normalize must NOT.
#   bash p4d-rehearse.sh KITDIR      (S needs root, e2fsprogs, cryptsetup-bin, gdisk, fdisk, cpio, grub-common, initramfs-tools-core; without them S is skipped)
# shellcheck disable=SC2015,SC2016   # SC2015: the chk lines are written as test && chk ok || chk no (chk never fails); SC2016: some patterns are literal text with a dollar sign
set -uo pipefail
KIT="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; I="$KIT/ops/image"; NORM="$I/build/tc-image-normalize.sh"; CLEAN="$I/build/tc-image-clean.sh"; SEAL="$I/build/tc-image-seal.sh"
ONLY="${REHEARSE_ONLY:-NCS}"; PASS=0; FAILN=0; W="$(mktemp -d)"; cleanup() { while read -r m; do umount "$m" 2>/dev/null; done < <(grep -F "$W" /proc/mounts 2>/dev/null | awk '{print $2}'); rm -rf "$W"; }; trap cleanup EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; fi; }
want() { grep -q -- "$1" "$W/out.txt"; }
ROOTUSER=0; [ "$(id -u)" = 0 ] && ROOTUSER=1
# ------------------------------------------------------------------ the fake root with the builder's residue
mkres() {   # mkres ROOTDIR TAG: a root file system that holds the builder's residue (its content depends on TAG)
  local r="$1" t="$2"
  mkdir -p "$r"/{etc/tc,etc/ssh,etc/netplan,etc/sudoers.d,boot,usr/bin,usr/local/lib/tc,opt/hadoop/bin,var/lib/dpkg,var/lib/hadoop/namenode,var/log/hadoop,var/cache,var/backups,root,home/user,tmp,var/tmp}
  echo 'NAME="Ubuntu"' > "$r/etc/os-release"; echo "kernel" > "$r/boot/vmlinuz-6.17"; echo "ls" > "$r/usr/bin/ls"; echo "hadoop" > "$r/opt/hadoop/bin/hdfs"; echo "paths" > "$r/etc/tc/measured-paths.txt"; echo "measure" > "$r/usr/local/lib/tc/tc-measure.sh"
  echo "Package: bash" > "$r/var/lib/dpkg/status"; echo "keep" > "$r/etc/sudoers.d/README"; echo "data" > "$r/var/lib/hadoop/namenode/keep.txt"; echo "mine" > "$r/home/user/notes.txt"
  mkdir -p "$r/tmp/tmp.abc$t" "$r/root/grub-backup-2026102911314$t/grub.d" "$r/root/.cache" "$r/var/log/journal/id$t" "$r/var/cache/debconf" "$r/var/cache/man" "$r/var/lib/command-not-found" "$r/var/lib/landscape" "$r/var/lib/ubuntu-advantage/apt-esm/var/cache/apt" "$r/var/lib/systemd/timers" "$r/var/lib/chrony" "$r/var/lib/dhcp" "$r/var/lib/logrotate" "$r/var/lib/cloud/data" "$r/var/lib/cloud/instances/i-$t"
  echo "x$t" > "$r/tmp/tmp.abc$t/f"; echo "h$t" > "$r/tmp/.hidden"; echo "s$t" > "$r/tmp/sp ace"; echo "n$t" > "$r/tmp/-dash"; printf 'nl%s' "$t" > "$r/tmp/new
line"; echo "v$t" > "$r/var/tmp/x"; echo "c$t" > "$r/root/.cache/x"; echo "hist$t" > "$r/root/.bash_history"; echo "g$t" > "$r/root/grub-backup-2026102911314$t/grub.d/40.cfg"; echo "keepme" > "$r/root/keep-me.txt"
  echo "log$t" > "$r/var/log/syslog"; echo "auth$t" > "$r/var/log/auth.log"; echo "j$t" > "$r/var/log/journal/id$t/system.journal"; echo "d$t" > "$r/var/cache/debconf/config.dat-old"; echo "m$t" > "$r/var/cache/man/index.db"; echo "b$t" > "$r/var/backups/dpkg.status.0"
  echo "c$t" > "$r/var/lib/command-not-found/commands.db"; echo "l$t" > "$r/var/lib/landscape/landscape-sysinfo.cache"; echo "p$t" > "$r/var/lib/ubuntu-advantage/apt-esm/var/cache/apt/pkgcache.bin"; echo "seed$t" > "$r/var/lib/systemd/random-seed"; echo "st$t" > "$r/var/lib/systemd/timers/stamp-x"
  echo "drift$t" > "$r/var/lib/chrony/chrony.drift"; echo "lease$t" > "$r/var/lib/dhcp/dhclient.leases"; echo "lr$t" > "$r/var/lib/logrotate/status"; echo "status$t" > "$r/var/lib/cloud/data/status.json"; echo "i$t" > "$r/var/lib/cloud/instances/i-$t/x"; ln -sfn "instances/i-$t" "$r/var/lib/cloud/instance"
  echo "tc-rel-$t" > "$r/etc/hostname"; echo "inst$t" > "$r/etc/google_instance_id"; echo "mac$t" > "$r/etc/netplan/50-cloud-init.yaml"; echo "user$t ALL=(ALL) NOPASSWD:ALL" > "$r/etc/sudoers.d/90-cloud-init-users"
  for f in passwd- shadow- group- gshadow- subuid- subgid-; do echo "$f$t" > "$r/etc/$f"; done; echo "hostkey$t" > "$r/etc/ssh/ssh_host_rsa_key"; echo "machine$t" > "$r/etc/machine-id"
  # the accounts that the guest agent made (their ids are in another order on every builder), the plain initramfs files, the Java trust store
  local order=(subhi_ramanathan dev subhiksharamanathan rishabsdp17); [ "$t" = B ] && order=(dev subhiksharamanathan rishabsdp17 subhi_ramanathan)
  mkdir -p "$r"/{etc,var/lib/google,home/ubuntu,var/lib/hadoop}; : > "$r/var/lib/google/google_users"; echo notes > "$r/home/ubuntu/notes.txt"
  { echo "root:x:0:0:root:/root:/bin/bash"; echo "hadoop:x:998:998::/var/lib/hadoop:/usr/sbin/nologin"; echo "ubuntu:x:1000:1000:Ubuntu:/home/ubuntu:/bin/bash"; } > "$r/etc/passwd"
  { echo "root:*:19000:0:99999:7:::"; echo "hadoop:!*:19000::::::"; echo "ubuntu:*:19000:0:99999:7:::"; } > "$r/etc/shadow"
  { echo "root:x:0:"; echo "adm:x:4:ubuntu"; echo "hadoop:x:998:"; echo "ubuntu:x:1000:"; echo "google-sudoers:x:1009:"; } > "$r/etc/group"
  { echo "root:*::"; echo "adm:*::ubuntu"; echo "hadoop:!::"; echo "ubuntu:!::"; echo "google-sudoers:!::"; } > "$r/etc/gshadow"; echo "ubuntu:100000:65536" > "$r/etc/subuid"; echo "ubuntu:100000:65536" > "$r/etc/subgid"
  local i=0 u adm="ubuntu" sud=""; for u in "${order[@]}"; do
    echo "$u:x:$((1001 + i)):$((1002 + i))::/home/$u:/bin/bash" >> "$r/etc/passwd"; echo "$u:!:19000:0:99999:7:::" >> "$r/etc/shadow"; echo "$u:x:$((1002 + i)):" >> "$r/etc/group"; echo "$u:!::" >> "$r/etc/gshadow"
    echo "$u:$((200000 + 65536 * i)):65536" >> "$r/etc/subuid"; echo "$u:$((200000 + 65536 * i)):65536" >> "$r/etc/subgid"; echo "$u" >> "$r/var/lib/google/google_users"
    adm="$adm,$u"; sud="${sud:+$sud,}$u"; mkdir -p "$r/home/$u/.cache"; echo "rc$t" > "$r/home/$u/.bashrc"; echo "c$t" > "$r/home/$u/.cache/motd"; i=$((i + 1)); done
  sed -i "s/^adm:x:4:.*/adm:x:4:$adm/; s/^google-sudoers:x:1009:.*/google-sudoers:x:1009:$sud/" "$r/etc/group"; sed -i "s/^adm:\*::.*/adm:*::$adm/; s/^google-sudoers:!::.*/google-sudoers:!::$sud/" "$r/etc/gshadow"; chmod 640 "$r/etc/shadow" "$r/etc/gshadow"
  echo "ird617$t" > "$r/boot/initrd.img-6.17.0-1022-gcp"; echo "ird68" > "$r/boot/initrd.img-6.8.0-1070-gcp"; [ -e "$r/boot/initrd.img-tc" ] || echo "irdtc" > "$r/boot/initrd.img-tc"; [ -e "$r/boot/initrd.img-tc.sha256" ] || echo "sha  /boot/initrd.img-tc" > "$r/boot/initrd.img-tc.sha256"
  ln -sfn initrd.img-6.17.0-1022-gcp "$r/boot/initrd.img"; ln -sfn initrd.img-6.8.0-1070-gcp "$r/boot/initrd.img.old"
  python3 "$W/jks.py" "$r/etc/ssl/certs/java/cacerts" "$t"
}
cat > "$W/jks.py" <<'PY'
import hashlib, os, struct, sys
PW = "changeit".encode("utf-16-be") + b"Mighty Aphrodite"
CERTS = [(b"alias-one", b"\x30\x82\x01" + b"one" * 40), (b"alias-two", b"\x30\x82\x02" + b"two" * 50), (b"Alias-Three", b"\x30\x82\x03" + b"three" * 30)]
def build(tag, tamper=None):
    order = CERTS if tag == "A" else list(reversed(CERTS)); ts = 1700000000000 if tag == "A" else 1750000000123
    out = struct.pack(">III", 0xFEEDFEED, 2, len(order))
    for i, (alias, cert) in enumerate(order):
        t = 1 if tamper == "tag1" and i == 0 else 2
        out += struct.pack(">I", t) + struct.pack(">H", len(alias)) + alias + struct.pack(">Q", ts + i) + struct.pack(">H", 5) + b"X.509" + struct.pack(">I", len(cert)) + cert
    d = hashlib.sha1(PW + out).digest()
    if tamper == "digest": d = bytes(20)
    return out + d
if __name__ == "__main__":
    path, tag = sys.argv[1], sys.argv[2]; tamper = sys.argv[3] if len(sys.argv) > 3 else None
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, "wb").write(b"not a jks file at all, just text\n" * 3 if tamper == "notjks" else build(tag, tamper))
PY
RES_GONE=(/tmp/tmp.abcA /tmp/.hidden "/tmp/sp ace" /tmp/-dash /var/tmp/x /root/.cache/x /root/.bash_history /root/grub-backup-20261029113140 /var/log/syslog /var/log/auth.log /var/log/journal /var/cache/debconf/config.dat-old /var/cache/man/index.db /var/backups/dpkg.status.0 /var/lib/command-not-found/commands.db /var/lib/landscape/landscape-sysinfo.cache /var/lib/ubuntu-advantage/apt-esm/var/cache/apt/pkgcache.bin /var/lib/systemd/random-seed /var/lib/systemd/timers/stamp-x /var/lib/chrony/chrony.drift /var/lib/dhcp/dhclient.leases /var/lib/logrotate/status /var/lib/cloud/data/status.json /var/lib/cloud/instances/i-A /var/lib/cloud/instance /home/dev /home/rishabsdp17 /home/subhi_ramanathan /home/subhiksharamanathan /boot/initrd.img-6.17.0-1022-gcp /boot/initrd.img-6.8.0-1070-gcp /boot/initrd.img /boot/initrd.img.old /etc/google_instance_id /etc/netplan/50-cloud-init.yaml /etc/sudoers.d/90-cloud-init-users /etc/passwd- /etc/shadow- /etc/group- /etc/gshadow- /etc/subuid- /etc/subgid- /etc/ssh/ssh_host_rsa_key)
RES_KEPT=(/etc/os-release /boot/vmlinuz-6.17 /usr/bin/ls /opt/hadoop/bin/hdfs /etc/tc/measured-paths.txt /usr/local/lib/tc/tc-measure.sh /var/lib/dpkg/status /etc/sudoers.d/README /var/lib/hadoop/namenode/keep.txt /home/user/notes.txt /root/keep-me.txt /home/ubuntu/notes.txt /boot/initrd.img-tc /boot/initrd.img-tc.sha256 /etc/ssl/certs/java/cacerts /etc/subuid /etc/subgid)
norm() { bash "$NORM" "$@" > "$W/out.txt" 2>&1; echo $?; }
# ------------------------------------------------------------------ N. the normalization on a fake root
if [[ "$ONLY" == *N* ]]; then
echo "== N. tc-image-normalize.sh on a fake root"
R="$W/r"; mkres "$R" A; mkdir -p "$W/outside"; echo "canary" > "$W/outside/canary"; ln -s "$W/outside" "$R/tmp/pointer"; mkdir -p "$W/tmpreal"; echo "canary2" > "$W/tmpreal/canary2"
( cd "$R" && find . -type f ! -path './tmp/*' ! -path './var/tmp/*' ! -path './root/.cache/*' ! -path './root/grub-backup-*' ! -path './var/log/*' ! -path './var/cache/*' ! -path './var/backups/*' ! -path './var/lib/command-not-found/*' ! -path './var/lib/landscape/*' ! -path './var/lib/ubuntu-advantage/*' ! -path './var/lib/systemd/*' ! -path './var/lib/chrony/*' ! -path './var/lib/dhcp/*' ! -path './var/lib/logrotate/*' ! -path './var/lib/cloud/*' ! -path './etc/hostname' ! -path './etc/google_instance_id' ! -path './etc/netplan/*' ! -path './etc/sudoers.d/90-*' ! -path './etc/*-' ! -path './etc/ssh/ssh_host_*' ! -path './etc/machine-id' ! -path './root/.bash_history' ! -path './etc/passwd' ! -path './etc/shadow' ! -path './etc/group' ! -path './etc/gshadow' ! -path './etc/subuid' ! -path './etc/subgid' ! -path './etc/ssl/certs/java/cacerts' ! -path './var/lib/google/google_users' ! -path './boot/initrd.img-6.*' ! -path './home/dev/*' ! -path './home/rishabsdp17/*' ! -path './home/subhi*' -exec sha256sum {} + | sort ) > "$W/kept.before"
rc=$(norm --root "$R" --report "$W/rep.txt"); [ "$rc" = 0 ] && want "^NORMALIZE-OK removed=[0-9]* snapd=absent" && chk "a root with the builder's residue is normalized: NORMALIZE-OK, snapd=absent" ok || chk "normalize: rc=$rc $(tail -3 "$W/out.txt" | tr '\n' ' ' | cut -c1-250)" no
gone=0; for p in "${RES_GONE[@]}"; do p2="${p//A/A}"; [ -e "$R$p2" ] || [ -L "$R$p2" ] && { gone=1; echo "     still there: $p2"; }; done; [ "$gone" = 0 ] && chk "every kind of residue is gone: temp files (also a name with a space, a newline, a leading dash and dot files), the grub backups, logs and the journal, caches, state, the cloud-init files, the builder's identity and its account backups" ok || chk "residue left" no
k=0; for p in "${RES_KEPT[@]}"; do [ -e "$R$p" ] || { k=1; echo "     lost: $p"; }; done; [ "$k" = 0 ] && [ -d "$R/tmp" ] && [ -d "$R/var/tmp" ] && [ -d "$R/var/log" ] && [ -d "$R/var/log/hadoop" ] && [ -d "$R/var/cache" ] && [ -d "$R/root" ] && [ -d "$R/etc/ssh" ] && chk "what is NOT residue is kept: the kernel, /usr, /opt, our /etc/tc and /usr/local/lib/tc, the package database, the HDFS data folders, home, a file in /root, other sudoers files; and the folders (/tmp, /var/log, /var/cache) stay" ok || chk "kept: lost something" no
( cd "$R" && find . -type f ! -path './tmp/*' ! -path './var/tmp/*' ! -path './root/.cache/*' ! -path './root/grub-backup-*' ! -path './var/log/*' ! -path './var/cache/*' ! -path './var/backups/*' ! -path './var/lib/command-not-found/*' ! -path './var/lib/landscape/*' ! -path './var/lib/ubuntu-advantage/*' ! -path './var/lib/systemd/*' ! -path './var/lib/chrony/*' ! -path './var/lib/dhcp/*' ! -path './var/lib/logrotate/*' ! -path './var/lib/cloud/*' ! -path './etc/hostname' ! -path './etc/google_instance_id' ! -path './etc/netplan/*' ! -path './etc/sudoers.d/90-*' ! -path './etc/*-' ! -path './etc/ssh/ssh_host_*' ! -path './etc/machine-id' ! -path './root/.bash_history' ! -path './etc/passwd' ! -path './etc/shadow' ! -path './etc/group' ! -path './etc/gshadow' ! -path './etc/subuid' ! -path './etc/subgid' ! -path './etc/ssl/certs/java/cacerts' ! -path './var/lib/google/google_users' ! -path './boot/initrd.img-6.*' ! -path './home/dev/*' ! -path './home/rishabsdp17/*' ! -path './home/subhi*' -exec sha256sum {} + | sort ) > "$W/kept.after"; cmp -s "$W/kept.before" "$W/kept.after" && chk "the files that are kept are byte for byte the same" ok || chk "kept files changed" no
[ "$(cat "$R/etc/hostname")" = localhost ] && [ -f "$R/etc/machine-id" ] && [ ! -s "$R/etc/machine-id" ] && [ "$(stat -c %a "$R/etc/machine-id")" = 644 ] && chk "/etc/hostname is localhost and /etc/machine-id is an empty file (mode 0644): systemd and cloud-init give the real values at boot" ok || chk "hostname/machine-id" no
[ "$(cat "$W/outside/canary")" = canary ] && [ -d "$W/outside" ] && chk "a symbolic link in /tmp that points OUT of the root is removed as a link, and its target and the file in it are untouched (nothing is followed)" ok || chk "symlink followed" no
mkdir -p "$W/r2/etc" "$W/r2/var"; echo 'NAME="Ubuntu"' > "$W/r2/etc/os-release"; ln -s "$W/tmpreal" "$W/r2/tmp"; ln -s "$W/tmpreal" "$W/r2/var/tmp"; rc=$(norm --root "$W/r2"); [ "$rc" = 0 ] && [ -f "$W/tmpreal/canary2" ] && chk "a /tmp that is itself a symbolic link is skipped: neither followed nor emptied" ok || chk "symlinked /tmp: rc=$rc" no
rc=$(norm --root "$R" --report "$W/rep2.txt"); [ "$rc" = 0 ] && want "NORMALIZE-OK removed=0" && chk "a second run on the same root removes nothing and is still OK (it is idempotent)" ok || chk "idempotent: rc=$rc $(tail -1 "$W/out.txt")" no
for g in scratch grub logs caches state identity; do grep -q "^$g	" "$W/rep.txt" || { echo "     no $g in the report"; k=1; }; done; [ "$k" = 0 ] && grep -q "^grub	/root/grub-backup-\*	1" "$W/rep.txt" && chk "the report names every group and how many entries were removed (for the audit trail)" ok || chk "report" no
# the new groups: accounts of the guest agent, the plain initramfs files, the Java trust store
P="$R/etc/passwd"; [ "$(cut -d: -f1 "$P" | tr '\n' ' ')" = "root hadoop ubuntu " ] && [ "$(cut -d: -f1 "$R/etc/shadow" | tr '\n' ' ')" = "root hadoop ubuntu " ] && [ "$(cut -d: -f1 "$R/etc/group" | tr '\n' ' ')" = "root adm hadoop ubuntu google-sudoers " ] && [ "$(cut -d: -f1 "$R/etc/gshadow" | tr '\n' ' ')" = "root adm hadoop ubuntu google-sudoers " ] && chk "the four accounts of the guest agent are gone from passwd, shadow, group and gshadow (their private groups too); root, the system user hadoop and the account ubuntu stay" ok || chk "accounts: passwd=$(cut -d: -f1 "$P" | tr '\n' ' ') group=$(cut -d: -f1 "$R/etc/group" | tr '\n' ' ')" no
grep -q "^adm:x:4:ubuntu$" "$R/etc/group" && grep -q "^google-sudoers:x:1009:$" "$R/etc/group" && grep -q "^adm:\*::ubuntu$" "$R/etc/gshadow" && [ "$(cat "$R/etc/subuid")" = "ubuntu:100000:65536" ] && [ "$(cat "$R/etc/subgid")" = "ubuntu:100000:65536" ] && chk "they are removed from the member lists of other groups (adm, google-sudoers) and from subuid and subgid; ubuntu is untouched" ok || chk "members: $(grep -E '^(adm|google-sudoers)' "$R/etc/group" | tr '\n' ' ')" no
[ ! -s "$R/var/lib/google/google_users" ] && [ -f "$R/var/lib/google/google_users" ] && [ "$(stat -c %a "$R/etc/shadow")" = 640 ] && [ "$(stat -c %a "$R/etc/gshadow")" = 640 ] && grep -q "^accounts	/etc/passwd	4$" "$W/rep.txt" && chk "the list file is emptied (and still exists), the modes of shadow and gshadow are kept (640), and the report counts 4 accounts" ok || chk "list/mode/report" no
[ ! -e "$R/boot/initrd.img-6.17.0-1022-gcp" ] && [ ! -e "$R/boot/initrd.img-6.8.0-1070-gcp" ] && [ ! -L "$R/boot/initrd.img" ] && [ ! -L "$R/boot/initrd.img.old" ] && [ -f "$R/boot/initrd.img-tc" ] && [ -f "$R/boot/initrd.img-tc.sha256" ] && chk "the plain initramfs files and their links are gone; initrd.img-tc and its checksum stay" ok || chk "initrd: $(find "$R/boot" -maxdepth 1 -mindepth 1 -printf '%f ')" no
RB="$W/rB"; mkres "$RB" B; mkdir -p "$W/outside2"; bash "$NORM" --root "$RB" > "$W/out.txt" 2>&1
same=1; for f in etc/passwd etc/shadow etc/group etc/gshadow etc/subuid etc/subgid etc/ssl/certs/java/cacerts var/lib/google/google_users; do cmp -s "$R/$f" "$RB/$f" || { same=0; echo "     differs: $f"; }; done; [ "$same" = 1 ] && chk "THE POINT: root A (user ids 1001 to 1004 in one order, one trust store) and root B (another order, another trust store) are BYTE FOR BYTE the same in all account files and in the trust store after the normalization" ok || chk "A and B differ after normalization" no
python3 - "$R/etc/ssl/certs/java/cacerts" <<'PY' && chk "the trust store is still valid: the integrity checksum matches the password changeit, the three certificates are there, all with the same fixed creation time, sorted by alias" ok || chk "trust store content" no
import hashlib, struct, sys
d = open(sys.argv[1], "rb").read(); body, dig = d[:-20], d[-20:]; PW = "changeit".encode("utf-16-be") + b"Mighty Aphrodite"
assert struct.unpack(">I", d[:4])[0] == 0xFEEDFEED and hashlib.sha1(PW + body).digest() == dig
n = struct.unpack(">I", body[8:12])[0]; off = 12; al = []; ts = set()
for _ in range(n):
    off += 4; l = struct.unpack(">H", body[off:off + 2])[0]; off += 2; al.append(body[off:off + l]); off += l; ts.add(struct.unpack(">Q", body[off:off + 8])[0]); off += 8
    tl = struct.unpack(">H", body[off:off + 2])[0]; off += 2 + tl; cl = struct.unpack(">I", body[off:off + 4])[0]; off += 4 + cl
assert n == 3 and off == len(body) and al == sorted(al) and len(ts) == 1
PY
if command -v keytool >/dev/null 2>&1 && command -v openssl >/dev/null 2>&1; then
  KD="$W/kt"; mkdir -p "$KD"; for i in 1 2 3; do openssl req -x509 -newkey rsa:2048 -nodes -keyout "$KD/k$i.pem" -out "$KD/c$i.pem" -subj "/CN=test$i" -days 30 >/dev/null 2>&1; done
  for t in a b; do rm -f "$KD/ks-$t"; for i in 1 2 3; do keytool -importcert -noprompt -alias "ca$i" -file "$KD/c$i.pem" -keystore "$KD/ks-$t" -storetype JKS -storepass changeit >/dev/null 2>&1; [ "$t" = b ] && sleep 1; done; done
  mkdir -p "$W/rk/etc/ssl/certs/java"; echo 'NAME="Ubuntu"' > "$W/rk/etc/os-release"; fp() { keytool -list -keystore "$1" -storepass changeit 2>/dev/null | grep -E "^ca[0-9]|fingerprint" | sed -E 's/^(ca[0-9]),.*/\1/' | sort | tr '\n' ' '; }
  FA="$(fp "$KD/ks-a")"; cp "$KD/ks-a" "$W/rk/etc/ssl/certs/java/cacerts"; bash "$NORM" --root "$W/rk" > "$W/out.txt" 2>&1; rcA=$?; cmpA="$W/rk/etc/ssl/certs/java/cacerts"; cp "$cmpA" "$KD/norm-a"
  cp "$KD/ks-b" "$W/rk/etc/ssl/certs/java/cacerts"; bash "$NORM" --root "$W/rk" > "$W/out.txt" 2>&1; rcB=$?; cp "$cmpA" "$KD/norm-b"
  [ "$rcA" = 0 ] && [ "$rcB" = 0 ] && cmp -s "$KD/norm-a" "$KD/norm-b" && [ "$(fp "$KD/norm-a")" = "$FA" ] && [ -n "$FA" ] && chk "WITH REAL JAVA: two keytool-made trust stores of the same certificates (made one second apart, so with different creation times) become byte for byte equal, and keytool -list still opens the result with the password changeit and shows the SAME certificate fingerprints" ok || chk "real keytool: rcA=$rcA rcB=$rcB same=$(cmp -s "$KD/norm-a" "$KD/norm-b" && echo yes || echo no) fp-same=$([ "$(fp "$KD/norm-a")" = "$FA" ] && echo yes || echo no)" no
else chk "the trust store with real Java (skipped: no keytool or openssl here)" ok; fi
mkn() { rm -rf "$W/n$1"; mkdir -p "$W/n$1/etc"; echo 'NAME="Ubuntu"' > "$W/n$1/etc/os-release"; }
mkn 1; python3 "$W/jks.py" "$W/n1/etc/ssl/certs/java/cacerts" A notjks; rc=$(norm --root "$W/n1"); [ "$rc" = 1 ] && want "is not a JKS file" && chk "a trust store that is not a JKS file stops the normalization (it is not changed)" ok || chk "notjks: rc=$rc" no
mkn 2; python3 "$W/jks.py" "$W/n2/etc/ssl/certs/java/cacerts" A digest; rc=$(norm --root "$W/n2"); [ "$rc" = 1 ] && want "integrity checksum of cacerts does not match the password changeit" && chk "a trust store whose checksum does not match the standard password stops it (an unknown or damaged store is never rewritten)" ok || chk "digest: rc=$rc" no
mkn 3; python3 "$W/jks.py" "$W/n3/etc/ssl/certs/java/cacerts" A tag1; rc=$(norm --root "$W/n3"); [ "$rc" = 1 ] && want "not a trusted certificate" && chk "a trust store with a private key entry stops it (only trusted certificates are supported)" ok || chk "tag1: rc=$rc" no
mkn 4; rc=$(norm --root "$W/n4"); [ "$rc" = 0 ] && ! want "truststore" && chk "no trust store: nothing to do, still OK" ok || chk "no jks: rc=$rc" no
mkn 5; mkdir -p "$W/n5/var/lib/google" "$W/n5/etc"; printf 'root:x:0:0::/root:/bin/bash\nroot2:x:500:500::/home/root2:/bin/bash\n' > "$W/n5/etc/passwd"; echo root2 > "$W/n5/var/lib/google/google_users"; rc=$(norm --root "$W/n5"); [ "$rc" = 1 ] && want "has the system user id 500" && chk "a listed account with a SYSTEM user id (below 1000) is never removed: the normalization stops" ok || chk "system uid: rc=$rc" no
mkn 6; mkdir -p "$W/n6/var/lib/google" "$W/n6/etc"; printf 'root:x:0:0::/root:/bin/bash\n' > "$W/n6/etc/passwd"; printf 'bad name;rm\n' > "$W/n6/var/lib/google/google_users"; rc=$(norm --root "$W/n6"); [ "$rc" = 1 ] && want "an odd account name" && chk "an odd account name in the list stops the normalization (it is never used as a path)" ok || chk "odd name: rc=$rc" no
mkn 7; printf 'root:x:0:0::/root:/bin/bash\nroot2:x:1001:1002::/home/../etc:/bin/bash\n' > "$W/n7/etc/passwd"; mkdir -p "$W/n7/var/lib/google" "$W/n7/home"; echo root2 > "$W/n7/var/lib/google/google_users"; echo keep > "$W/n7/etc/keep.txt"; rc=$(norm --root "$W/n7"); [ -f "$W/n7/etc/keep.txt" ] && chk "a home path that tries to leave /home (../etc) is never removed" ok || chk "home escape: rc=$rc" no
if [ "$ROOTUSER" = 1 ]; then mkn 8; mkdir -p "$W/n8/var/lib/google" "$W/n8/srv"; printf 'root:x:0:0::/root:/bin/bash\nguest:x:1001:1002::/home/guest:/bin/bash\n' > "$W/n8/etc/passwd"; echo guest > "$W/n8/var/lib/google/google_users"; echo data > "$W/n8/srv/orphan.txt"; chown 1001:1002 "$W/n8/srv/orphan.txt"
  rc=$(norm --root "$W/n8"); [ "$rc" = 1 ] && want "still owned by a removed user or group, for example /srv/orphan.txt" && chk "a file elsewhere that is owned by a removed user stops the normalization and is named (it would have become an orphan with a bare number as its owner)" ok || chk "orphan: rc=$rc" no
else chk "an orphan owned by a removed user (skipped: needs root to chown)" ok; fi
mkn 9; mkdir -p "$W/n9/boot"; echo x > "$W/n9/boot/initrd.img-6.17.0-1022-gcp"; rc=$(norm --root "$W/n9"); [ "$rc" = 0 ] && [ -f "$W/n9/boot/initrd.img-6.17.0-1022-gcp" ] && chk "without initrd.img-tc nothing is removed from /boot (this is not a sealed-image tree)" ok || chk "no tc initrd: rc=$rc" no
mkn 10; mkdir -p "$W/n10/boot"; echo x > "$W/n10/boot/initrd.img-6.17.0-1022-gcp"; echo t > "$W/n10/boot/initrd.img-tc"; ln -s initrd.img-tc "$W/n10/boot/initrd.img"; ln -s initrd.img-6.17.0-1022-gcp "$W/n10/boot/initrd.img.old"; rc=$(norm --root "$W/n10"); [ "$rc" = 0 ] && [ -L "$W/n10/boot/initrd.img" ] && [ -e "$W/n10/boot/initrd.img" ] && [ ! -L "$W/n10/boot/initrd.img.old" ] && chk "a link that still points at something (to initrd.img-tc) is kept; only the dangling one is removed" ok || chk "links: rc=$rc" no
# snapd
R3="$W/r3"; mkres "$R3" A; mkdir -p "$R3/usr/lib/snapd" "$R3/var/lib/snapd/device/private-keys-v1" "$R3/var/lib/snapd/assertions" "$R3/snap"; echo snapd > "$R3/usr/lib/snapd/snapd"; echo '{}' > "$R3/var/lib/snapd/state.json"; echo key > "$R3/var/lib/snapd/device/private-keys-v1/k"
rc=$(norm --root "$R3"); [ "$rc" = 1 ] && want "snapd is still on this disk (/usr/lib/snapd/snapd): purge it first" && [ -f "$R3/tmp/.hidden" ] && chk "snapd still installed: NORMALIZE-STOP before anything is removed, and the message says how to fix it" ok || chk "snapd stop: rc=$rc" no
rc=$(norm --root "$R3" --allow-snapd); [ "$rc" = 0 ] && want "snapd=allowed" && [ -f "$R3/var/lib/snapd/state.json" ] && chk "--allow-snapd goes on, says snapd=allowed, and does not touch snapd's files" ok || chk "allow-snapd: rc=$rc" no
# refusals and usage
rc=$(norm); [ "$rc" = 2 ] && want "usage:" && chk "no arguments: the usage, exit code 2" ok || chk "usage: rc=$rc" no
rc=$(norm --nonsense); [ "$rc" = 2 ] && want "unknown argument --nonsense" && chk "an unknown argument is refused" ok || chk "unknown arg: rc=$rc" no
rc=$(norm --root /); [ "$rc" = 1 ] && want "refusing to normalize /" && chk "/ is refused" ok || chk "root dir: rc=$rc" no
rc=$(norm --root "$W/nonexistent"); [ "$rc" = 1 ] && want "is not a directory" && chk "a path that is not a directory is refused" ok || chk "no dir: rc=$rc" no
mkdir -p "$W/empty"; rc=$(norm --root "$W/empty"); [ "$rc" = 1 ] && want "does not look like a root file system" && chk "a folder without etc/os-release is refused (it is not a root file system)" ok || chk "no os-release: rc=$rc" no
ln -s "$R" "$W/linkroot"; rc=$(norm --root "$W/linkroot"); [ "$rc" = 1 ] && want "is not a directory" && chk "a symbolic link as the root is refused" ok || chk "symlink root: rc=$rc" no
if [ "$ROOTUSER" = 1 ] && command -v mke2fs >/dev/null 2>&1 && command -v chattr >/dev/null 2>&1; then
  truncate -s 16M "$W/imm.img"; mke2fs -q -t ext4 -F "$W/imm.img" >/dev/null 2>&1; mkdir -p "$W/imm"; if mount -o loop "$W/imm.img" "$W/imm" 2>/dev/null; then
    mkdir -p "$W/imm/etc" "$W/imm/tmp"; echo 'NAME="Ubuntu"' > "$W/imm/etc/os-release"; echo stuck > "$W/imm/tmp/stuck"; chattr +i "$W/imm/tmp/stuck" 2>/dev/null
    rc=$(norm --root "$W/imm"); [ "$rc" = 1 ] && want "after the removals this is still left" && want "/tmp: 1 left" && chk "an entry that cannot be removed (immutable) is NOT ignored: NORMALIZE-STOP names what is left" ok || chk "immutable: rc=$rc $(tail -2 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
    chattr -i "$W/imm/tmp/stuck" 2>/dev/null; umount "$W/imm"
  else chk "an entry that cannot be removed (skipped: no loop mount here)" ok; fi
else chk "an entry that cannot be removed (skipped: needs root, mke2fs and chattr)" ok; fi
fi
# ------------------------------------------------------------------ C. the live cleaning
if [[ "$ONLY" == *C* ]]; then
echo "== C. tc-image-clean.sh: the /root glob and the purge of snapd"
mkclean() {   # mkclean ROOT: a fake root for the live cleaning, with the stub apt-get in $W/bin
  local r="$1"; rm -rf "$r"; mkdir -p "$r"/{etc/ssh,var/lib/dbus,var/lib/hadoop/namenode,var/log/hadoop,root/grub-backup-20261029113145/grub.d,root/grub-backup-20261029165542,home/user/snap/x,usr/lib/snapd,var/lib/snapd/device/private-keys-v1,snap/core22,var/snap,var/cache/snapd,root/snap} "$W/bin"
  echo m > "$r/etc/machine-id"; echo k > "$r/etc/ssh/ssh_host_rsa_key"; echo snapd > "$r/usr/lib/snapd/snapd"; echo key > "$r/var/lib/snapd/device/private-keys-v1/k"; echo g > "$r/root/grub-backup-20261029113145/grub.d/x"; echo keep > "$r/root/keep.txt"
  cat > "$W/bin/apt-get" <<'STUB'
#!/usr/bin/env bash
echo "apt-get $*" >> "$APT_LOG"
case "$*" in
  "-s purge snapd") echo "Remv snapd [2.63]"; echo "Remv ubuntu-server [1.539]"; [ -f "$APT_CRIT" ] && echo "Remv cloud-init [23.4]"; exit 0;;
  "purge -y snapd") [ -f "$APT_FAIL" ] && exit 100; [ -f "$APT_KEEP" ] || rm -f "$FAKE_ROOT/usr/lib/snapd/snapd"; exit 0;;
  *) exit 0;;
esac
STUB
  chmod +x "$W/bin/apt-get"
}
cl() { env TC_ROOT="$R" TC_SUDO="" TC_APT="$W/bin/apt-get" APT_LOG="$W/apt.log" APT_FAIL="$W/apt.fail" APT_KEEP="$W/apt.keep" APT_CRIT="$W/apt.crit" FAKE_ROOT="$R" "$@" bash "$CLEAN" --this-machine-becomes-an-image > "$W/out.txt" 2>&1; echo $?; }
R="$W/c1"; mkclean "$R"; : > "$W/apt.log"; rm -f "$W/apt.fail" "$W/apt.keep"; rc=$(cl env)
[ "$rc" = 0 ] && want "CLEAN-OK" && [ ! -e "$R/root/grub-backup-20261029113145" ] && [ ! -e "$R/root/grub-backup-20261029165542" ] && [ -f "$R/root/keep.txt" ] && chk "the grub backups (both of them) are removed, and a file next to them is kept" ok || chk "grub backups: rc=$rc $(find "$R/root" -maxdepth 1 -mindepth 1 -printf '%f ')" no
! grep -q '"\$R"/root/grub-backup' "$CLEAN" && grep -q "find \"\$R/root\" -maxdepth 1 -mindepth 1 -name 'grub-backup-\*' -exec rm -rf" "$CLEAN" && chk "the script no longer uses a shell glob on /root (the caller cannot read a mode-0700 /root, so the glob matched nothing and the backups stayed in the image): find does it, as root" ok || chk "glob still in the script" no
want "Remv snapd" && want "Remv ubuntu-server" && grep -q "^apt-get purge -y snapd" "$W/apt.log" && want "verified: snapd and its device key are gone" && [ ! -e "$R/usr/lib/snapd/snapd" ] && [ ! -e "$R/var/lib/snapd" ] && [ ! -e "$R/snap" ] && [ ! -e "$R/var/snap" ] && [ ! -e "$R/home/user/snap" ] && [ ! -e "$R/root/snap" ] && chk "snapd is purged, the packages that go with it are listed in the output, and its folders (/snap, /var/snap, /var/lib/snapd, the user's snap folders) are gone" ok || chk "snapd purge: $(grep -E 'apt-get|snapd' "$W/out.txt" | head -3 | tr '\n' ' ' | cut -c1-200)" no
[ ! -s "$R/etc/machine-id" ] && [ ! -e "$R/etc/ssh/ssh_host_rsa_key" ] && chk "the old behaviour stays: the machine id is emptied and the ssh host keys are removed" ok || chk "old behaviour" no
R="$W/c2"; mkclean "$R"; : > "$W/apt.log"; rc=$(cl env TC_KEEP_SNAPD=1); [ "$rc" = 0 ] && want "snapd: KEPT" && ! grep -q "purge" "$W/apt.log" && [ -e "$R/usr/lib/snapd/snapd" ] && chk "TC_KEEP_SNAPD=1 keeps snapd, says so, and does not call apt-get purge" ok || chk "keep snapd: rc=$rc" no
R="$W/c3"; mkclean "$R"; : > "$W/apt.log"; : > "$W/apt.fail"; rc=$(cl env); rm -f "$W/apt.fail"; [ "$rc" = 1 ] && want "ABORT: snapd could not be purged" && chk "a purge that fails stops the cleaning (the image is NOT made with snapd silently left in it)" ok || chk "purge fails: rc=$rc" no
R="$W/c4"; mkclean "$R"; : > "$W/apt.log"; : > "$W/apt.keep"; rc=$(cl env); rm -f "$W/apt.keep"; [ "$rc" = 1 ] && want "ABORT: snapd is still on disk after the purge" && chk "a purge that reports success but leaves snapd on the disk is caught by the check afterwards" ok || chk "purge lies: rc=$rc" no
R="$W/c6"; mkclean "$R"; : > "$W/apt.log"; : > "$W/apt.crit"; rc=$(cl env); rm -f "$W/apt.crit"; [ "$rc" = 1 ] && want "ABORT: purging snapd would also remove packages that the image needs (cloud-init )" && ! grep -q "^apt-get purge" "$W/apt.log" && [ -e "$R/usr/lib/snapd/snapd" ] && chk "if the purge would also remove a package that the image needs (cloud-init here), the cleaning ABORTS BEFORE the purge and nothing is removed" ok || chk "critical package: rc=$rc $(tail -2 "$W/out.txt" | tr '\n' ' ' | cut -c1-200)" no
R="$W/c5"; mkclean "$R"; rm -rf "$R/usr/lib/snapd" "$R/var/lib/snapd"; : > "$W/apt.log"; rc=$(cl env); [ "$rc" = 0 ] && ! grep -q "purge" "$W/apt.log" && chk "no snapd on the disk: nothing is purged and the cleaning is still OK" ok || chk "no snapd: rc=$rc" no
fi
# ------------------------------------------------------------------ S. the real sealing on real images
if [[ "$ONLY" == *S* ]]; then
echo "== S. tc-image-seal.sh (gate 6b) on real ext4 images"
need=1; for t in mke2fs e2fsck resize2fs tune2fs debugfs dumpe2fs veritysetup sfdisk sgdisk cpio lsinitramfs grub-script-check; do command -v $t >/dev/null || need=0; done
if [ "$ROOTUSER" != 1 ] || [ "$need" != 1 ] || [ ! -f "$KIT/ops/tree-manifest.py" ] || [ ! -f "$KIT/ops/tree-diff.py" ]; then chk "the sealing with normalization on real images (skipped: this needs root, the e2fsprogs/cryptsetup/gdisk/grub tools and ops/tree-manifest.py)" ok; else
KV=6.17.0-1022-gcp; TPL="$I/rootfs/etc/tc/grub-sealed.cfg.in"; B="$W/base"; mkdir -p "$B/tree/boot" "$B/tree/etc/tc" "$B/ird/scripts/local-top" "$B/ird/scripts/init-bottom" "$B/ird/lib/modules/$KV" "$B/esp/EFI/ubuntu"
head -c 65536 /dev/urandom > "$B/tree/boot/vmlinuz-$KV"; echo 'NAME="Ubuntu"' > "$B/tree/etc/os-release"; head -c $((8 * 1048576)) /dev/urandom > "$B/tree/bulk.bin"
for f in scripts/local-top/tc-scratch-dev scripts/init-bottom/tc-scratch-bind scripts/init-bottom/overlayroot lib/modules/$KV/dm-verity.ko lib/modules/$KV/dm-integrity.ko lib/modules/$KV/dm-crypt.ko lib/modules/$KV/dm-bufio.ko; do echo "$f" > "$B/ird/$f"; done
echo tcverity > "$B/ird/scripts/local-top/tc-verity"; ( cd "$B/ird" && find . | cpio -o -H newc --quiet | gzip -n ) > "$B/initrd"; cp "$B/initrd" "$B/tree/boot/initrd.img-tc"; echo "$(sha256sum "$B/initrd" | cut -d' ' -f1)  /boot/initrd.img-tc" > "$B/tree/boot/initrd.img-tc.sha256"; cp "$TPL" "$B/tree/etc/tc/grub-sealed.cfg.in"
printf 'search.fs_uuid 00000000-0000-0000-0000-000000000000 root\nconfigfile ($root)/boot/grub/grub.cfg\n' > "$B/esp/EFI/ubuntu/grub.cfg"; echo efi > "$B/esp/EFI/ubuntu/grubx64.efi"
mkimg() {   # mkimg NAME TAG [snapd]: a fixture made from the SAME base tree, plus the builder's residue (its content depends on TAG)
  F="$W/$1"; rm -rf "$F"; mkdir -p "$F/out"; cp -a "$B/tree" "$F/tree"; cp -a "$B/esp" "$F/esp"; mkres "$F/tree" "$2"
  if [ "${3:-}" = snapd ]; then mkdir -p "$F/tree/usr/lib/snapd" "$F/tree/var/lib/snapd/device"; echo snapd > "$F/tree/usr/lib/snapd/snapd"; fi
  mke2fs -q -t ext4 -F -b 4096 -O has_journal,metadata_csum,64bit -d "$F/tree" "$F/p1.img" 256M >/dev/null 2>&1; truncate -s 400M "$F/disk.img"; sgdisk -n 14:2048:+4M -t 14:ef02 -n 15:0:+16M -t 15:ef00 -n 1:0:0 -t 1:8300 "$F/disk.img" >/dev/null 2>&1
}
seal() { out="$(bash "$SEAL" --disk "$F/disk.img" --p1 "$F/p1.img" --esp-dir "$F/esp" --kver $KV --destructive-ok --blocks 32768 --out "$F/out" --no-kernel-test "$@" 2>&1)"; rc=$?; echo "$out" > "$W/out.txt"; }
mnt() { MN=""; mkdir -p "$W/m$1"; mount -o ro,loop "$F/p1.img" "$W/m$1" 2>/dev/null && MN="$W/m$1"; }
manifest() { python3 "$KIT/ops/tree-manifest.py" "$1" --label x --out "$2" >/dev/null 2>&1; }
mkimg sa A; seal; sa_rc=$rc; RHA="$(awk -F= '/^roothash=/ {print $2}' "$F/out/seal-report.txt")"; mnt a; SA="$MN"
[ "$sa_rc" = 0 ] && want "gate 6b: normalize the root file system" && want "NORMALIZE-OK removed=" && want "SEAL-OK roothash=" && [ -s "$F/out/normalize-report.txt" ] && chk "the real sealing runs gate 6b between the shrink and the hash tree, ends with SEAL-OK, and leaves the report of what was removed in its output folder" ok || chk "seal: rc=$sa_rc $(tail -4 "$W/out.txt" | tr '\n' ' ' | cut -c1-300)" no
g=0; if [ -n "$SA" ]; then for p in "${RES_GONE[@]}"; do [ -e "$SA$p" ] || [ -L "$SA$p" ] && { g=1; echo "     still there: $p"; }; done; k=0; for p in "${RES_KEPT[@]}" /boot/vmlinuz-$KV /boot/initrd.img-tc /bulk.bin; do [ -e "$SA$p" ] || { k=1; echo "     lost: $p"; }; done; else g=1; k=1; fi
[ "$g" = 0 ] && chk "in the SEALED partition (mounted read-only) the builder's residue is gone" ok || chk "sealed residue" no
[ "$k" = 0 ] && cmp -s "$SA/bulk.bin" "$B/tree/bulk.bin" && cmp -s "$SA/boot/vmlinuz-$KV" "$B/tree/boot/vmlinuz-$KV" && chk "and everything that is not residue is there, byte for byte: the kernel, the initramfs, the bulk data, the files of the earlier checks" ok || chk "sealed kept" no
[ -n "$SA" ] && manifest "$SA" "$W/ma.m"; [ -n "$SA" ] && umount "$SA"
mkimg sb B; seal; sb_rc=$rc; RHB="$(awk -F= '/^roothash=/ {print $2}' "$F/out/seal-report.txt")"; mnt b; SB="$MN"; [ -n "$SB" ] && manifest "$SB" "$W/mb.m"; [ -n "$SB" ] && umount "$SB"
python3 "$KIT/ops/tree-diff.py" "$W/ma.m" "$W/mb.m" > "$W/out.txt" 2>&1; rc=$?
real=0; grep -q "/boot/vmlinuz-$KV" "$W/ma.m" 2>/dev/null && grep -q "/boot/vmlinuz-$KV" "$W/mb.m" 2>/dev/null && [ "$(grep -c "^F" "$W/ma.m")" -gt 8 ] && real=1
[ "$sb_rc" = 0 ] && [ "$rc" = 0 ] && [ "$real" = 1 ] && want "TREE-DIFF-IDENTICAL" && chk "THE POINT OF THE STEP: two builds that differ only in the builder's residue (another builder name, instance id, journal, logs, temp files, grub backups) give the SAME file tree once sealed (ops/tree-diff.py: IDENTICAL)" ok || chk "two builds: sb_rc=$sb_rc diff rc=$rc $(grep -E 'differ|DIFF' "$W/out.txt" | head -4 | tr '\n' ' ' | cut -c1-250)" no
[ "$RHA" != "$RHB" ] && chk "(the two root hashes still differ, as they must: the file systems are not bit-identical, which is why the comparison is of the file trees)" ok || chk "root hashes equal: surprising" no
mkimg sc A; seal --no-normalize; sc_rc=$rc; want "gate 6b: SKIPPED (--no-normalize)" && [ "$sc_rc" = 0 ] && mnt c; SC="$MN"; [ -n "$SC" ] && manifest "$SC" "$W/mc.m"; [ -n "$SC" ] && umount "$SC"
mkimg sd B; seal --no-normalize; mnt d; SD="$MN"; [ -n "$SD" ] && manifest "$SD" "$W/md.m"; [ -n "$SD" ] && umount "$SD"
python3 "$KIT/ops/tree-diff.py" "$W/mc.m" "$W/md.m" --max 500 > "$W/out.txt" 2>&1; rc=$?
real=0; grep -q "/boot/vmlinuz-$KV" "$W/mc.m" 2>/dev/null && grep -q "/boot/vmlinuz-$KV" "$W/md.m" 2>/dev/null && [ "$(grep -c "^F" "$W/mc.m")" -gt 8 ] && real=1
[ "$rc" = 1 ] && [ "$real" = 1 ] && want "TREE-DIFF-DIFFERENT" && want "/etc/hostname" && want "/var/log/syslog" && chk "THE CONTROL: the same two builds sealed with --no-normalize are DIFFERENT (the hostname, the logs, the journal, ...): the test has teeth" ok || chk "control: rc=$rc" no
mkimg se A snapd; seal; se_rc=$rc; [ "$se_rc" != 0 ] && want "SEAL-STOP: the normalization stopped" && want "snapd is still on this disk" && ! grep -qF "$F/p1.img" /proc/mounts && chk "snapd still on the disk: the SEALING STOPS at gate 6b with the reason, and nothing is left mounted" ok || chk "snapd seal: rc=$se_rc" no
mkimg sf A snapd; seal --allow-snapd; [ "$rc" = 0 ] && want "snapd=allowed" && want "SEAL-OK" && chk "with --allow-snapd the sealing goes on (and the output says snapd=allowed)" ok || chk "allow-snapd seal: rc=$rc" no
fi
fi
echo; echo "pass: $PASS   fail: $FAILN"; if [ "$FAILN" = 0 ]; then echo "P4D-REHEARSAL-PASS"; else echo "P4D-REHEARSAL-FAIL"; exit 1; fi
