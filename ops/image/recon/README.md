# ops/image/recon: the read-only inventory of the nodes (the recon of step F0)

Before the locked image is designed, these two scripts list what a cluster node has today: who can log in, how ssh is set up, what listens, which services run and start at boot, what is mounted and writable, what is installed, how Hadoop is started, what the kernel offers for integrity, and what the measured set already covers. They are the "before" picture for steps F0.4 (remove login) and F0.5 (close the doors); what they showed is in the Milestone 5 report.

| Folder | Script | What it reads |
|---|---|---|
| `m523i/` | `ops/attested/inventory.sh` | the facts that need no root: login shells and groups, ssh and its keys (counted), listeners, running and enabled services, mounts, installed tools, boot, Hadoop, kernel integrity features, the measured set |
| `m523j/` | `ops/attested/inventory2.sh` | the facts that need root (the first script could not see them): the firewall rules, `fstab`, every unit enabled at boot, the key count of every account, OS Login, the names of the instance and project metadata, how Hadoop is started, timers |

Both are **read-only**: they change nothing, print no key (key files are only counted), refuse to overwrite their output, and delete the output if anything that looks like a key got into it. Each has a rehearsal that runs the real script with a planted key file and a planted leak: `bash inventory-rehearse.sh <the m523i folder>` and `bash inventory2-rehearse.sh <the m523j folder>`.

They ran on the two cluster nodes on 17 October 2026, as they are here; the evidence bundles are `evidence-m523i` and `evidence-m523j` (outside the repository). One cosmetic defect is known and left as it ran: an empty key file is counted with `grep -c ... || echo 0`, which prints the `0` twice.
