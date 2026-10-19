#!/usr/bin/env bash
# Step 5.3.1, part 2: the READ-ONLY facts that the first inventory could not see (it ran without root, so it could not look into other users' folders or the firewall):
# the firewall rules, the file system table, every unit enabled at boot, how many keys each account has (counted, never shown), whether OS Login is used, the names (never the values) of the instance
# and project metadata, and whether Hadoop is started by the system or by hand. It changes nothing and prints no key.
#   bash inventory2.sh OUTFILE
set -uo pipefail
OUT="${1:?usage: $0 OUTFILE}"
[ ! -e "$OUT" ] || { echo "INVENTORY2-STOP: $OUT exists already; move it away" >&2; exit 1; }
SUDO="${INV_SUDO-sudo -n}"; MD="${INV_METADATA:-http://metadata.google.internal/computeMetadata/v1}"; FSTAB="${INV_FSTAB:-/etc/fstab}"; HOMEGLOB="${INV_HOMEGLOB:-/home/*/.ssh/authorized_keys}"
sec() { echo; echo "##### $*"; }
{
echo "inventory2: $(date -u +%FT%TZ) on $(hostname)   user=$(id -un)   sudo=$($SUDO true 2>/dev/null && echo yes || echo no)"
sec "1. the firewall of this node"
echo "iptables rules: $($SUDO iptables -S 2>/dev/null | wc -l)"; $SUDO iptables -S 2>/dev/null | head -60 | sed 's/^/iptables: /'
echo "nftables rules: $($SUDO nft list ruleset 2>/dev/null | wc -l) lines"; $SUDO nft list ruleset 2>/dev/null | head -60 | sed 's/^/nft: /'
ip -br addr 2>/dev/null | sed 's/^/addr: /'; ip route 2>/dev/null | sed 's/^/route: /'
sec "2. the file system table (what is mounted how, and what is not)"
grep -v '^[[:space:]]*#' "$FSTAB" 2>/dev/null | grep -v '^[[:space:]]*$' | sed 's/^/fstab: /'; echo "tmp is a separate mount: $(findmnt -no TARGET /tmp >/dev/null 2>&1 && echo yes || echo no)"
sec "3. every unit that is enabled at boot"
systemctl list-unit-files --state=enabled --no-legend --no-pager 2>/dev/null | awk '{print "enabled: " $1}' | sort
sec "4. accounts: login shells, groups, and the number of keys in each authorized_keys file (counted, never shown)"
getent passwd | awk -F: '$7 !~ /(nologin|false|sync|halt|shutdown)$/ {print $1}' | while read -r u; do echo "account $u: $(id -nG "$u" 2>/dev/null)"; done
for f in $($SUDO sh -c "ls $HOMEGLOB /root/.ssh/authorized_keys 2>/dev/null"); do echo "keys: $f has $($SUDO grep -c -E '^(ssh-|ecdsa-|sk-)' "$f" 2>/dev/null || echo 0) key(s)"; done
echo "oslogin in nsswitch: $(grep -c oslogin /etc/nsswitch.conf 2>/dev/null || echo 0)   oslogin in sshd config: $($SUDO grep -rc -i 'AuthorizedKeysCommand.*oslogin' /etc/ssh/sshd_config /etc/ssh/sshd_config.d 2>/dev/null | awk -F: '{s+=$2} END{print s+0}')"
sec "5. the names of the metadata (never the values), as the node sees them"
for p in instance/attributes project/attributes; do echo "$p: $(curl -s -m 3 -H 'Metadata-Flavor: Google' "$MD/$p/" 2>/dev/null | tr '\n' ' ' || echo unreachable)"; done
echo "service accounts: $(curl -s -m 3 -H 'Metadata-Flavor: Google' "$MD/instance/service-accounts/" 2>/dev/null | tr '\n' ' ')"
sec "6. packages that give remote access, a way to run code at boot, or a way to change the system"
dpkg-query -W -f='${Package}\n' 2>/dev/null | grep -E '^(openssh-server|snapd|lxd|lxd-installer|cloud-init|google-guest-agent|google-osconfig-agent|unattended-upgrades|packagekit|policykit-1|polkitd|cron|rsyslog|multipath-tools|netplan.io|ufw|nftables|iptables|chrony|wireguard|wireguard-tools)$' | sort | sed 's/^/package: /'
sec "7. how Hadoop is started"
systemctl list-unit-files --no-legend --no-pager 2>/dev/null | grep -i -E 'hadoop|hdfs|yarn' | sed 's/^/unit: /' || true
echo "units for hadoop: $(systemctl list-unit-files --no-legend --no-pager 2>/dev/null | grep -c -i -E 'hadoop|hdfs|yarn')   crontab entries of this user: $(crontab -l 2>/dev/null | grep -c -v '^#')"
sec "8. timers and scheduled jobs"
systemctl list-timers --no-legend --no-pager 2>/dev/null | awk '{print "timer: " $(NF-1)}' | sort -u
echo "cron.d files: $(ls /etc/cron.d 2>/dev/null | tr '\n' ' ')"
} > "$OUT" 2>&1
if grep -q -E 'PRIVATE KEY|ssh-(rsa|ed25519)|ecdsa-sha2|BEGIN CERTIFICATE' "$OUT"; then rm -f "$OUT"; echo "INVENTORY2-STOP: the output contained something that looks like a key or a certificate, so it was deleted" >&2; exit 1; fi
echo "INVENTORY2-OK: $(wc -l < "$OUT") lines, $(grep -c '^#####' "$OUT") sections -> $OUT"
