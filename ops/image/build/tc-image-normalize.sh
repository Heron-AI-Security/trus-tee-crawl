#!/usr/bin/env bash
# Step P4 (the build cleanup). The LAST change to the root file system of an image before it is sealed: remove what belongs to the BUILDER and to the build session, so that two builds of one commit
# hold the same files (a verifier compares the file trees of the published image and of its own build, ops/tree-diff.py, and ANY difference except times fails).
#   tc-image-normalize.sh --root DIR [--report FILE] [--allow-snapd]
# DIR is the mounted root file system of the COPY of the builder's disk, read-write. It is called by tc-image-seal.sh (gate 6b), on the helper VM where nothing runs on that file system: the live cleaning
# (tc-image-clean.sh) cannot do this, because the SSH session that runs it writes logs while it runs, and the sealing itself adds files afterwards.
# What it does, group by group (the report names each group and how many entries it removed):
#   scratch      /tmp and /var/tmp (the builder's mktemp leftovers), /root/.cache, and the builder's shell history
#   grub         /root/grub-backup-* (made by the builder's GRUB edits; the live cleaning cannot see /root, which is mode 0700)
#   logs         every file under /var/log and the whole of /var/log/journal (the build session's logs; the journal directory carries an ACL that names the builder's login user)
#   caches       every file under /var/cache and /var/backups, the package-database snapshots, and the caches of landscape, command-not-found and Ubuntu Pro (apt-esm)
#   state        systemd's random seed and timer stamps, chrony's drift file, the DHCP leases (they hold the builder's address), logrotate's status, and cloud-init's state (it runs again at every boot)
#   identity     /etc/hostname (set to localhost: cloud-init sets the real name at boot), /etc/google_instance_id, the cloud-init network configuration and the sudoers file that cloud-init made for the builder's
#                login user, the backup copies of the account files (passwd-, shadow-, group-, gshadow-), and the machine id and the ssh host keys (the live cleaning removed them: checked here)
#   accounts     the accounts that the Google guest agent made on the builder from the SSH keys of the project (they are listed in /var/lib/google/google_users): their entries in passwd, shadow, group, gshadow,
#                subuid and subgid, their home folders and mail spools; the list is emptied. The agent makes the accounts again at boot from the keys in the metadata. They get their user ids in a DIFFERENT order on every
#                builder, and they carry real names, so they must not be in a published image. Afterwards no file may be owned by a removed user or group (NORMALIZE-STOP otherwise). Other accounts (ubuntu, the system users, hadoop) are not touched.
#   initrd       every /boot/initrd.img-* except initrd.img-tc* (the only initramfs that the sealed boot uses, and a measured one) and the links /boot/initrd.img and /boot/initrd.img.old that pointed at them: the plain initramfs of
#                the kernel is rebuilt with other bytes on every build and is not used. Only done if initrd.img-tc exists.
#   truststore   /etc/ssl/certs/java/cacerts (a Java JKS file): its certificates are kept, sorted by alias, with ONE fixed creation time and the integrity checksum recomputed with the standard password. The bytes of the file are
#                otherwise different on every build (a creation time per certificate); the certificates themselves are measured separately (the event java-ca-fingerprints). The set of certificates is checked to be unchanged.
#   snapd        must be gone (tc-image-clean.sh purges it): its device key, its serial assertion and its state.json are different in every build. --allow-snapd skips this check and says so.
# Nothing else is touched: not /boot, /usr, /opt, /home, /srv, /var/lib/dpkg, /var/lib/apt (except the lists that the live cleaning removed), not our own files under /etc/tc and /usr/local/lib/tc.
# Everything is done with find -xdev, which never follows a symbolic link and never leaves the file system. After the removals every group is CHECKED; any entry left is NORMALIZE-STOP (exit code 1).
# Exit codes: 0 NORMALIZE-OK, 1 NORMALIZE-STOP, 2 usage.
set -uo pipefail
ROOT=""; REPORT=""; ALLOWSNAP=0
while [ $# -gt 0 ]; do case "$1" in
  --root) ROOT="${2:-}"; shift 2 ;; --report) REPORT="${2:-}"; shift 2 ;; --allow-snapd) ALLOWSNAP=1; shift ;;
  *) echo "NORMALIZE-STOP: unknown argument $1" >&2; exit 2 ;; esac; done
stop() { echo "NORMALIZE-STOP: $*" >&2; exit 1; }
[ -n "$ROOT" ] || { echo "usage: $0 --root DIR [--report FILE] [--allow-snapd]" >&2; exit 2; }
{ [ -d "$ROOT" ] && [ ! -L "$ROOT" ]; } || stop "$ROOT is not a directory"
R="$(cd "$ROOT" && pwd -P)"; [ "$R" != "/" ] || stop "refusing to normalize /"
[ -f "$R/etc/os-release" ] || stop "$R does not look like a root file system (no etc/os-release)"
[ "$(stat -c %d:%i "$R")" != "$(stat -c %d:%i /)" ] || stop "$R is the root of THIS machine"
REMOVED=0; : > "${REPORT:-/dev/null}" 2>/dev/null || stop "cannot write the report $REPORT"
note() { [ -z "$REPORT" ] || printf '%s\t%s\t%s\n' "$1" "$2" "$3" >> "$REPORT"; }
count() { local n; n="$(find "$@" 2>/dev/null | wc -l)"; echo "$n"; }
# wipe GROUP DIR: remove everything INSIDE DIR (the directory stays); a missing DIR, or one that is a symbolic link, is skipped
wipe() { local g="$1" d="$R$2" n; { [ -d "$d" ] && [ ! -L "$d" ]; } || return 0; n="$(count "$d" -xdev -mindepth 1)"; [ "$n" = 0 ] || { find "$d" -xdev -mindepth 1 -delete 2>/dev/null || true; REMOVED=$((REMOVED + n)); note "$g" "$2" "$n"; }; }
# nondirs GROUP DIR: remove every entry that is not a directory below DIR (the directory tree stays: services expect their folders)
nondirs() { local g="$1" d="$R$2" n; { [ -d "$d" ] && [ ! -L "$d" ]; } || return 0; n="$(count "$d" -xdev ! -type d)"; [ "$n" = 0 ] || { find "$d" -xdev ! -type d -delete 2>/dev/null || true; REMOVED=$((REMOVED + n)); note "$g" "$2" "$n"; }; }
# drop GROUP PATH: remove one file or one whole directory (a symbolic link is removed, never followed)
drop() { local g="$1" p="$R$2"; { [ -e "$p" ] || [ -L "$p" ]; } || return 0; find "$p" -xdev -delete 2>/dev/null || true; REMOVED=$((REMOVED + 1)); note "$g" "$2" 1; }
# dropglob GROUP DIR PATTERN: remove the entries of DIR whose name matches PATTERN (done by find AS THE CALLER: a shell glob would be expanded by whoever calls this, and /root is mode 0700)
dropglob() { local g="$1" d="$R$2" n; [ -d "$d" ] || return 0; n="$(count "$d" -xdev -maxdepth 1 -mindepth 1 -name "$3")"; [ "$n" = 0 ] || { find "$d" -xdev -maxdepth 1 -mindepth 1 -name "$3" -exec rm -rf {} + 2>/dev/null || true; REMOVED=$((REMOVED + n)); note "$g" "$2/$3" "$n"; }; }
if [ "$ALLOWSNAP" = 0 ]; then
  for p in /usr/lib/snapd/snapd /var/lib/snapd/state.json /var/lib/snapd/device /var/lib/snapd/assertions /snap /var/snap; do
    [ ! -e "$R$p" ] || stop "snapd is still on this disk ($p): purge it first (tc-image-clean.sh does, unless TC_KEEP_SNAPD is set), or pass --allow-snapd and accept that two builds will then differ in its state"
  done
fi
wipe scratch /tmp; wipe scratch /var/tmp; wipe scratch /root/.cache; drop scratch /root/.bash_history; drop scratch /root/.viminfo; drop scratch /root/.lesshst
dropglob grub /root 'grub-backup-*'
nondirs logs /var/log; drop logs /var/log/journal
nondirs caches /var/cache; nondirs caches /var/backups; wipe caches /var/lib/command-not-found; wipe caches /var/lib/landscape; wipe caches /var/lib/ubuntu-advantage/apt-esm/var
drop state /var/lib/systemd/random-seed; nondirs state /var/lib/systemd/timers; nondirs state /var/lib/chrony; nondirs state /var/lib/dhcp; nondirs state /var/lib/logrotate
for d in data instance instances sem handlers; do wipe state "/var/lib/cloud/$d"; done; drop state /var/lib/cloud/instance
drop identity /etc/google_instance_id; drop identity /etc/netplan/50-cloud-init.yaml; drop identity /etc/sudoers.d/90-cloud-init-users
for f in passwd- shadow- group- gshadow- subuid- subgid-; do drop identity "/etc/$f"; done
dropglob identity /etc/ssh 'ssh_host_*'
AOUT="$(python3 - "$R" <<'PYACC'
import os, re, shutil, sys
R = sys.argv[1]; lst = os.path.join(R, "var/lib/google/google_users")
def stop(m): print("ACCOUNTS-STOP: " + m, file=sys.stderr); sys.exit(1)
if not os.path.isfile(lst): sys.exit(0)
names = [l.strip() for l in open(lst, encoding="utf-8").read().splitlines() if l.strip()]
for n in names:
    if not re.fullmatch(r"[a-z_][a-z0-9_.-]{0,31}", n): stop("an odd account name in google_users: %r" % n)
names = set(names)
if not names: sys.exit(0)
def read(path):
    p = os.path.join(R, path)
    return open(p, encoding="utf-8").read().split("\n") if os.path.isfile(p) else None
def write(path, lines):
    p = os.path.join(R, path); st = os.stat(p); tmp = p + ".tcn"
    open(tmp, "w", encoding="utf-8").write("\n".join(lines)); os.chmod(tmp, st.st_mode & 0o7777)
    try: os.chown(tmp, st.st_uid, st.st_gid)
    except OSError: pass
    os.replace(tmp, p)
pw = read("etc/passwd")
if pw is None: stop("there is no /etc/passwd")
gone = {}; keep = []
for l in pw:
    f = l.split(":")
    if len(f) >= 7 and f[0] in names:
        if int(f[2]) < 1000: stop("%s is listed in google_users but has the system user id %s" % (f[0], f[2]))
        gone[f[0]] = (int(f[2]), int(f[3]), f[5])
    else: keep.append(l)
if not gone: sys.exit(0)
write("etc/passwd", keep); out = ["accounts\t/etc/passwd\t%d" % len(gone)]
gids = set(g for _, g, _ in gone.values()); uids = set(u for u, _, _ in gone.values())
def colon(path, fn, label):
    L = read(path)
    if L is None: return
    new = []; n = 0
    for l in L:
        r = fn(l.split(":"), l)
        if r is None: n += 1
        else:
            if r != l: n += 1
            new.append(r)
    if n: write(path, new); out.append("accounts\t/%s\t%d" % (path, n))
def rmmembers(field):
    m = field.split(",") if field else []
    return ",".join(x for x in m if x not in names)
def grp(f, l):
    if len(f) < 4: return l
    if f[0] in names and f[2].isdigit() and int(f[2]) in gids: return None
    f[3] = rmmembers(f[3]); return ":".join(f)
def gsh(f, l):
    if len(f) < 4: return l
    if f[0] in names: return None
    f[2] = rmmembers(f[2]); f[3] = rmmembers(f[3]); return ":".join(f)
colon("etc/shadow", lambda f, l: None if f[0] in names else l, "shadow"); colon("etc/group", grp, "group"); colon("etc/gshadow", gsh, "gshadow")
colon("etc/subuid", lambda f, l: None if f[0] in names else l, "subuid"); colon("etc/subgid", lambda f, l: None if f[0] in names else l, "subgid")
for n, (u, g, h) in sorted(gone.items()):
    hp = os.path.normpath(h)
    if hp.startswith("/home/") and hp.count("/") == 2:
        p = R + hp
        if os.path.isdir(p) and not os.path.islink(p): shutil.rmtree(p)
        elif os.path.lexists(p): os.unlink(p)
        out.append("accounts\t%s\t1" % hp)
    for m in ("var/mail/" + n, "var/spool/mail/" + n):
        if os.path.lexists(os.path.join(R, m)): os.unlink(os.path.join(R, m)); out.append("accounts\t/%s\t1" % m)
open(lst, "w").close(); out.append("accounts\t/var/lib/google/google_users\temptied")
# the check: nothing of the removed users is left, and no file is owned by a removed user or group
for path in ("etc/passwd", "etc/shadow", "etc/subuid", "etc/subgid"):
    for l in read(path) or []:
        if l.split(":")[0] in names: stop("%s still has an entry of a removed user" % path)
for l in read("etc/group") or []:
    f = l.split(":")
    if len(f) >= 4 and (f[0] in names or any(x in names for x in f[3].split(","))): stop("/etc/group still names a removed user: %s" % l[:60])
dev = os.lstat(R).st_dev; bad = []
for dp, dn, fn in os.walk(R):
    dn[:] = [d for d in dn if os.lstat(os.path.join(dp, d)).st_dev == dev]
    for x in dn + fn:
        st = os.lstat(os.path.join(dp, x))
        if st.st_uid in uids or st.st_gid in gids: bad.append(os.path.join(dp, x)[len(R):])
if bad: stop("%d file(s) are still owned by a removed user or group, for example %s" % (len(bad), ", ".join(bad[:4])))
print("\n".join(out))
PYACC
)" || stop "the accounts of the guest agent could not be removed (the line above says why)"
while IFS=$'\t' read -r g pth c; do [ -n "$g" ] || continue; note "$g" "$pth" "$c"; case "$c" in ''|*[!0-9]*) ;; *) REMOVED=$((REMOVED + c)) ;; esac; done <<<"$AOUT"
if [ -e "$R/boot/initrd.img-tc" ]; then
  n="$(count "$R/boot" -xdev -maxdepth 1 -type f -name 'initrd.img-*' ! -name 'initrd.img-tc*')"
  [ "$n" = 0 ] || { find "$R/boot" -xdev -maxdepth 1 -type f -name 'initrd.img-*' ! -name 'initrd.img-tc*' -delete 2>/dev/null || true; REMOVED=$((REMOVED + n)); note initrd /boot/initrd.img-\* "$n"; }
  for l in /boot/initrd.img /boot/initrd.img.old /initrd.img /initrd.img.old; do [ -L "$R$l" ] && [ ! -e "$R$l" ] && { rm -f "$R$l"; REMOVED=$((REMOVED + 1)); note initrd "$l" 1; }; done
fi
TOUT="$(python3 - "$R" <<'PYJKS'
import hashlib, os, struct, sys
R = sys.argv[1]; p = os.path.join(R, "etc/ssl/certs/java/cacerts"); PW = "changeit".encode("utf-16-be") + b"Mighty Aphrodite"; FIXED = 1672531200000
def stop(m): print("TRUSTSTORE-STOP: " + m, file=sys.stderr); sys.exit(1)
if not os.path.isfile(p): sys.exit(0)
def parse(data):
    if len(data) < 32 or struct.unpack(">I", data[:4])[0] != 0xFEEDFEED: stop("/etc/ssl/certs/java/cacerts is not a JKS file")
    body, dig = data[:-20], data[-20:]
    if hashlib.sha1(PW + body).digest() != dig: stop("the integrity checksum of cacerts does not match the password changeit: not the standard Ubuntu trust store, or damaged")
    ver, count = struct.unpack(">II", body[4:12]); off = 12; ent = []
    if ver != 2: stop("JKS version %d is not supported" % ver)
    for _ in range(count):
        tag = struct.unpack(">I", body[off:off + 4])[0]; off += 4
        if tag != 2: stop("cacerts holds an entry that is not a trusted certificate (tag %d): not supported" % tag)
        n = struct.unpack(">H", body[off:off + 2])[0]; off += 2; alias = body[off:off + n]; off += n; off += 8
        tn = struct.unpack(">H", body[off:off + 2])[0]; off += 2; ct = body[off:off + tn]; off += tn
        cl = struct.unpack(">I", body[off:off + 4])[0]; off += 4; cert = body[off:off + cl]; off += cl; ent.append((alias, ct, cert))
    if off != len(body): stop("unexpected bytes in cacerts")
    return ent
data = open(p, "rb").read(); ent = parse(data)
ent2 = sorted(ent, key=lambda e: e[0]); out = struct.pack(">III", 0xFEEDFEED, 2, len(ent2))
for alias, ct, cert in ent2: out += struct.pack(">I", 2) + struct.pack(">H", len(alias)) + alias + struct.pack(">Q", FIXED) + struct.pack(">H", len(ct)) + ct + struct.pack(">I", len(cert)) + cert
out += hashlib.sha1(PW + out).digest()
if sorted(parse(out)) != sorted(ent): stop("the rewritten trust store does not hold the same certificates")
if out != data:
    st = os.stat(p); tmp = p + ".tcn"; open(tmp, "wb").write(out); os.chmod(tmp, st.st_mode & 0o7777)
    try: os.chown(tmp, st.st_uid, st.st_gid)
    except OSError: pass
    os.replace(tmp, p)
print("truststore\t/etc/ssl/certs/java/cacerts\t%d certificates, fixed creation time, sorted" % len(ent))
PYJKS
)" || stop "the Java trust store could not be normalized (the line above says why)"
while IFS=$'\t' read -r g pth c; do [ -n "$g" ] || continue; note "$g" "$pth" "$c"; done <<<"$TOUT"
if [ -e "$R/etc/hostname" ] || [ -d "$R/etc" ]; then printf 'localhost\n' > "$R/etc/hostname" 2>/dev/null || stop "cannot write /etc/hostname"; note identity /etc/hostname "set to localhost"; fi
: > "$R/etc/machine-id" 2>/dev/null || stop "cannot empty /etc/machine-id"; chmod 0644 "$R/etc/machine-id" 2>/dev/null || true; note identity /etc/machine-id "emptied"
# ---- the check: every group is empty now (this is what makes the result the same in every build)
BAD=""
chk_empty() { local what="$1"; shift; local n; n="$(count "$@")"; [ "$n" = 0 ] || BAD="$BAD
   $what: $n left ($(find "$@" 2>/dev/null | head -3 | sed "s#^$R##" | tr '\n' ' '))"; }
chk_empty "/tmp" "$R/tmp" -xdev -mindepth 1; chk_empty "/var/tmp" "$R/var/tmp" -xdev -mindepth 1
chk_empty "/root/grub-backup-*" "$R/root" -xdev -maxdepth 1 -name 'grub-backup-*'
chk_empty "files under /var/log" "$R/var/log" -xdev ! -type d; chk_empty "files under /var/cache" "$R/var/cache" -xdev ! -type d; chk_empty "files under /var/backups" "$R/var/backups" -xdev ! -type d
for p in /var/log/journal /var/lib/systemd/random-seed /etc/google_instance_id /etc/netplan/50-cloud-init.yaml /etc/sudoers.d/90-cloud-init-users /etc/shadow- /etc/passwd- /etc/group- /etc/gshadow- /var/lib/cloud/instance; do [ ! -e "$R$p" ] || BAD="$BAD
   $p is still there"; done
[ ! -e "$R/boot/initrd.img-tc" ] || chk_empty "other initramfs files in /boot" "$R/boot" -xdev -maxdepth 1 -name 'initrd.img-*' ! -name 'initrd.img-tc*'
[ ! -s "$R/var/lib/google/google_users" ] || BAD="$BAD
   /var/lib/google/google_users is not empty"
chk_empty "/etc/ssh/ssh_host_*" "$R/etc/ssh" -xdev -maxdepth 1 -name 'ssh_host_*'
[ "$(cat "$R/etc/hostname" 2>/dev/null)" = localhost ] || BAD="$BAD
   /etc/hostname is not localhost"; [ ! -s "$R/etc/machine-id" ] || BAD="$BAD
   /etc/machine-id is not empty"
[ -z "$BAD" ] || stop "after the removals this is still left:$BAD"
echo "NORMALIZE-OK removed=$REMOVED snapd=$([ "$ALLOWSNAP" = 1 ] && echo allowed || echo absent)"
