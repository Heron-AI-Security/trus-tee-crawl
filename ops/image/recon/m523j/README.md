# m523j: step 5.3.1, part 1b: the second read-only inventory (the facts that the first one could not see)

inventory2.sh (run on a node, with the passwordless sudo that the nodes already use): the firewall rules (iptables, nftables), the file system table, every unit enabled at boot, the login accounts with their groups and the NUMBER of keys
in each authorized_keys file (never the keys), whether OS Login is used, the NAMES (never the values) of the instance and project metadata, the packages that give remote access or a way to change the system, whether Hadoop is started by
the system or by hand, and the timers. It changes nothing, prints no key, refuses to overwrite its output and deletes the output if anything key-like got into it.
inventory2-rehearse.sh (8 checks): the real script with a planted authorized_keys file that must be counted and never shown, a planted fstab, an unreachable metadata server, and a planted leak.
Unpacking drops the executable flag: run  chmod +x ops/attested/*.sh  after unpacking.
