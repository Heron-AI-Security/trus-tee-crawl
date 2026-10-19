# m523i: step 5.3.1, part 1: a read-only inventory of a node (the facts that the locked image is designed from)

inventory.sh (run on a node): reads the facts that decide what a locked image must remove or freeze: who can log in, ssh and its keys (counted, never shown), what listens, which services run, the mounts and what is writable,
what is installed, what starts at boot, how Hadoop runs, what the kernel offers for integrity (dm-verity, IMA, lockdown, overlay, squashfs), and the measured set that the quote already covers. It changes nothing, prints no key,
refuses to overwrite its output, and deletes the output if anything that looks like a key got into it.
inventory-rehearse.sh (8 checks): the real script on the machine it runs on, with a planted authorized_keys file that must be counted and never shown, and a planted leak that must be caught.
Unpacking drops the executable flag: run  chmod +x ops/attested/*.sh  after unpacking.
