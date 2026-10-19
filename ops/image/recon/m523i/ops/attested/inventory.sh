#!/usr/bin/env bash
# Step 5.3.1, part 1: a READ-ONLY inventory of what is on a node today, so that the locked image is designed from facts and not from memory.
# It changes nothing: it only reads (some reads need sudo, which is used without a password as elsewhere). It prints no key, no password and no file content of a key file: the keys' files are only counted.
#   bash inventory.sh OUTFILE
set -uo pipefail
OUT="${1:?usage: $0 OUTFILE}"
[ ! -e "$OUT" ] || { echo "INVENTORY-STOP: $OUT exists already; move it away" >&2; exit 1; }
SUDO="${INV_SUDO-sudo -n}"; HOMES="${INV_HOMES:-/home/*}"; ROOTSSH="${INV_ROOTSSH:-/root/.ssh/authorized_keys}"; HADHOME="${INV_HOME:-$HOME}"
sec() { echo; echo "##### $*"; }
{
echo "inventory: $(date -u +%FT%TZ) on $(hostname)   user=$(id -un)"
sec "1. the machine and its kernel"
grep -E '^(PRETTY_NAME|VERSION_ID)=' /etc/os-release; echo "kernel: $(uname -r)"; echo "cmdline: $(cat /proc/cmdline)"
[ -d /sys/kernel/config/tsm/report ] && echo "tsm report interface: present" || echo "tsm report interface: absent"
sec "2. who can log in (login shells, and the members of the groups that give root)"
getent passwd | awk -F: '$7 !~ /(nologin|false|sync|halt|shutdown)$/ {print "login shell: " $1 " " $7}'
for g in sudo adm admin google-sudoers lxd docker; do getent group $g >/dev/null 2>&1 && echo "group $g: $(getent group $g | cut -d: -f4)"; done
sec "3. ssh (the keys are only counted, never shown)"
for u in ssh ssh.socket sshd google-guest-agent google-osconfig-agent; do printf '%-24s enabled=%s active=%s\n' "$u" "$(systemctl is-enabled $u 2>/dev/null || echo no)" "$(systemctl is-active $u 2>/dev/null || echo no)"; done
$SUDO sshd -T 2>/dev/null | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|kbdinteractiveauthentication|allowusers|allowgroups) ' | sed 's/^/sshd: /' || echo "sshd -T: not available"
for f in $HOMES/.ssh/authorized_keys $ROOTSSH; do [ -e "$f" ] && echo "authorized_keys: $f has $(grep -c -E '^(ssh-|ecdsa-|sk-)' "$f" 2>/dev/null || echo 0) key(s)"; done
sec "4. what listens on the network"
$SUDO ss -H -lntup 2>/dev/null | awk '{print $1, $5, $7}' | sed 's/users:((//; s/))//' | sort
sec "5. services that are running, and how many are enabled at boot"
systemctl list-units --type=service --state=running --no-legend --no-pager 2>/dev/null | awk '{print "running: " $1}'
echo "enabled unit files: $(systemctl list-unit-files --state=enabled --no-legend --no-pager 2>/dev/null | wc -l)"
sec "6. mounts and what is writable"
findmnt -no TARGET,FSTYPE,OPTIONS / 2>/dev/null | sed 's/^/root: /'; for m in /boot /boot/efi /home /tmp /var; do findmnt -no TARGET,FSTYPE,OPTIONS $m >/dev/null 2>&1 && echo "mount: $(findmnt -no TARGET,FSTYPE,OPTIONS $m)"; done
lsblk -o NAME,SIZE,TYPE,RO,MOUNTPOINT 2>/dev/null
sec "7. what is installed"
echo "packages: $(dpkg-query -W 2>/dev/null | wc -l)"
for t in bash sh dash python3 perl gcc make curl wget nc ncat socat vim nano git sudo ssh scp tmux screen java; do p="$(command -v $t 2>/dev/null)"; echo "tool $t: ${p:-absent}"; done
sec "8. what starts at boot besides the system"
for u in cloud-init google-startup-scripts google-shutdown-scripts unattended-upgrades snapd apt-daily.timer; do printf '%-26s enabled=%s\n' "$u" "$(systemctl is-enabled $u 2>/dev/null || echo no)"; done
[ -d /etc/cloud/cloud.cfg.d ] && echo "cloud-init config files: $(ls /etc/cloud/cloud.cfg.d | tr '\n' ' ')"
sec "9. the Hadoop side"
ps -eo user:14,pid,args 2>/dev/null | grep -E 'java.*(NameNode|DataNode|ResourceManager|NodeManager)' | grep -v grep | cut -c1-110 | sed 's/^/process: /'
for d in "$HADHOME/hadoop" "$HADHOME/ccbot-work" "$HADHOME/m481"; do [ -d "$d" ] && echo "size: $(du -sh "$d" 2>/dev/null | cut -f1) $d"; done
grep -h -A1 -E 'dfs.(namenode.name|datanode.data).dir|hadoop.tmp.dir' "$HADHOME"/hadoop/etc/hadoop/*.xml 2>/dev/null | grep '<value>' | sed 's/^ */data path: /'
sec "10. what the kernel offers for integrity"
cfg="/boot/config-$(uname -r)"; if [ -r "$cfg" ]; then grep -E '^(CONFIG_DM_VERITY|CONFIG_IMA|CONFIG_SECURITY_LOCKDOWN_LSM|CONFIG_MODULE_SIG|CONFIG_OVERLAY_FS|CONFIG_SQUASHFS|CONFIG_TCG_TPM|CONFIG_INTEL_TDX_GUEST|CONFIG_TSM_REPORTS)[A-Z_]*=' "$cfg"; else echo "no kernel config file at $cfg"; fi
lsmod 2>/dev/null | grep -E 'dm_verity|overlay|squashfs' | awk '{print "module: " $1}'
[ -r /sys/kernel/security/lockdown ] && echo "lockdown: $(cat /sys/kernel/security/lockdown)"
sec "11. the measured set that the quote already covers"
[ -r "$HADHOME/rtmr3-events.tsv" ] && { echo "events: $(wc -l < "$HADHOME/rtmr3-events.tsv")"; cut -f1 "$HADHOME/rtmr3-events.tsv" | sed 's/^/event: /'; } || echo "no event log at $HADHOME/rtmr3-events.tsv"
} > "$OUT" 2>&1
if grep -q -E 'PRIVATE KEY|ssh-(rsa|ed25519)|ecdsa-sha2|BEGIN CERTIFICATE' "$OUT"; then rm -f "$OUT"; echo "INVENTORY-STOP: the output contained something that looks like a key or a certificate, so it was deleted" >&2; exit 1; fi
echo "INVENTORY-OK: $(wc -l < "$OUT") lines, $(grep -c '^#####' "$OUT") sections -> $OUT"
