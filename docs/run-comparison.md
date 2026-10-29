# Comparison of the runs

Run 1 ([run-1-pilot.md](run-1-pilot.md)) used hand-typed commands on 2 October 2026. Run 2
([run-2-scripted.md](run-2-scripted.md)) used the committed scripts on 3 October 2026. Same cluster,
same crawler, same seeds, same cap.

**Status check, 30 October 2026.** Sections 1 to 8 compare runs 1 and 2 (2 and 3 October 2026) and are history. Section 9 adds the later runs in date order, from 6 October 2026 (section 9.1) to 29 October 2026 (section 9.19, the steps P1, P2 and P6). Reviewed on 30 October 2026: section 9.19 (the steps P1, P2 and P6) is the latest; nothing earlier changed.

Runs 3 and 4 (5 October 2026) are compared with run 2 in section 9, run 5 (6 October, over the WireGuard mesh) in section 9.1 and run 6 (6 October, through the hdfs:// wrapper) in section 9.2. This file was renamed from comparison-run1-run2.md on 6 October 2026. Runs 7 to 9 are in sections 9.3 to 9.6, runs 10 to 13 (13 and 14 October) in section 9.7, and runs 14 and 15, the first crawls with signing on (15 and 16 October), in section 9.8.

## Contents

- [1. Side by side](#1-side-by-side)
  - [Inputs](#inputs)
  - [Process](#process)
  - [Outputs](#outputs)
- [2. What this shows](#2-what-this-shows)
- [3. What differs, and why that is expected](#3-what-differs-and-why-that-is-expected)
- [4. What the evidence shows, and what it does not](#4-what-the-evidence-shows-and-what-it-does-not)
- [5. Observations that affect the trust discussion](#5-observations-that-affect-the-trust-discussion)
- [6. Limits of this comparison](#6-limits-of-this-comparison)
- [7. How the comparison was done](#7-how-the-comparison-was-done)
- [8. Next steps for the evidence](#8-next-steps-for-the-evidence)
- [9. Runs 3 and 4 (added 6 October 2026)](#9-runs-3-and-4-added-6-october-2026)
  - [9.1 Run 5 over the mesh (added 6 October 2026)](#91-run-5-over-the-mesh-added-6-october-2026)
  - [9.2 Run 6 through the hdfs:// wrapper (added 6 October 2026)](#92-run-6-through-the-hdfs-wrapper-added-6-october-2026)
  - [9.3 Run 7 with hashing (added 7 October 2026)](#93-run-7-with-hashing-added-7-october-2026)
  - [9.4 Run 8 with verified reads (added 7 October 2026)](#94-run-8-with-verified-reads-added-7-october-2026)
  - [9.5 A condition from the mentor (7 October 2026)](#95-a-condition-from-the-mentor-7-october-2026)
  - [9.6 Run 9 through the cluster's own wrapper (added 9 October 2026)](#96-run-9-through-the-clusters-own-wrapper-added-9-october-2026)
  - [9.7 Runs 10 to 13 (added 14 October 2026)](#97-runs-10-to-13-added-14-october-2026)
  - [9.8 Runs 14 and 15 (added 17 October 2026)](#98-runs-14-and-15-added-17-october-2026)
  - [9.9 The fixed-fleet runs (added 21 October 2026)](#99-the-fixed-fleet-runs-added-21-october-2026)
  - [9.10 The three-node debug run of step R1 (added 22 October 2026)](#910-the-three-node-debug-run-of-step-r1-added-22-october-2026)
  - [9.11 The export runs of step R5 (added 23 October 2026)](#911-the-export-runs-of-step-r5-added-23-october-2026)
  - [9.12 The receipts change on an unsealed image (added 26 October 2026)](#912-the-receipts-change-on-an-unsealed-image-added-26-october-2026)
  - [9.13 The sealed image runs of step R3 (added 26 October 2026)](#913-the-sealed-image-runs-of-step-r3-added-26-october-2026)
  - [9.14 The reproducible build and the acceptance run of step R4 (added 27 October 2026)](#914-the-reproducible-build-and-the-acceptance-run-of-step-r4-added-27-october-2026)
  - [9.15 The final verification run of step R4 and the policy that depended on the day (added 28 October 2026)](#915-the-final-verification-run-of-step-r4-and-the-policy-that-depended-on-the-day-added-28-october-2026)
  - [9.16 The package pin of step R4.6 (added 28 October 2026)](#916-the-package-pin-of-step-r46-added-28-october-2026)
  - [9.17 The commit in the job versions, step R4.7 (added 28 October 2026)](#917-the-commit-in-the-job-versions-step-r47-added-28-october-2026)
  - [9.18 Pinning the Public Suffix List, step R4.9 (added 29 October 2026)](#918-pinning-the-public-suffix-list-step-r49-added-29-october-2026)
  - [9.19 The dummy run, the boot event log and the release, steps P1, P2 and P6 (added 29 October 2026)](#919-the-dummy-run-the-boot-event-log-and-the-release-steps-p1-p2-and-p6-added-29-october-2026)

## 1. Side by side

### Inputs

| Input | Run 1 | Run 2 | How compared |
|---|---|---|---|
| Packaged crawler (`apache-nutch-1.22.job`) | built 2026-10-02 12:50:04 | same file, not rebuilt | `JOB-IDENTICAL` |
| `conf/nutch-site.xml` | committed `5635894b7` | same | `SAME` |
| Seed file | 57 bytes, hash `14a80f8c8eaa…` | same bytes | `SEEDS-IDENTICAL`, `SAME` |
| Public suffix list | downloaded, uncommitted | same file | `SAME` |
| Four Hadoop config files | identical on both nodes | identical on both nodes, same as run 1 | `SAME` (x4), `CONFIGS-IDENTICAL` |
| Helper library commits | `13118882ddfe…`, `38efccdc1ec1…` | same, recorded again | manifest |
| Crawl options | as in [cluster-configuration.md](cluster-configuration.md) | same, via `ops/run-crawl.sh` | script echo in the log |

### Process

| Aspect | Run 1 | Run 2 |
|---|---|---|
| How commands were issued | Typed by hand | Committed scripts at commit `441cb333c21b…` |
| Manifest | Built by hand, free layout | `make-manifest.sh`, fixed layout |
| Quote | `report0` folder, hand-made `reportdata` file | `quote.sh`: unique `req-…` folder, removed on exit |
| Binding check | Inline shell comparison | `verify-binding.sh` |
| Extra manifest fields | none | `libcld2` version, `scripts_repo_commit`, hashes of the four scripts |
| Duration of crawl | about 11 minutes | about 10 minutes |
| Deduplication job | 43,585 ms | 42,808 ms |

### Outputs

| Output | Run 1 | Run 2 |
|---|---|---|
| Segments | 3 (`20261002…`) | 3 (`20261003…`) |
| `pages/` records | 8 response, 8 metadata, 3 warcinfo | 8 / 8 / 3 |
| `diagnostics/` records | 2 / 2 / 3 | 2 / 2 / 3 |
| `robotstxt/` | 3 warcinfo only | 3 warcinfo only |
| Fetch attempts | 10 | 10 |
| Pages fetched | 8 URLs | the same 8 URLs (`SAME-PAGES`) |
| Redirects | two 301s (Einstein, Marilyn Monroe) | the same two |
| Fetching machine | `tdx-lab-worker` | `tdx-lab-worker` |
| WARC file names and hashes | `NUTCH-CRAWL-20261002…`, hash values differ | `NUTCH-CRAWL-20261003…`, hash values differ |
| Quotes | two, 8000 bytes, `MATCH` | two, 8000 bytes, `MATCH` |

## 2. What this shows

1. **The procedure is repeatable.** The same inputs gave the same page set, the same redirect behaviour and the same
   counts, one day apart.
2. **The scripts reproduce the hand-typed result.** Run 2's structure matches run 1's.
3. **The cap is reached exactly.** Both runs used all 10 attempts, so a longer run would have continued; the
   cap is a ceiling that was fully used.
4. **The crawler binary is the same artefact.** The job file was not rebuilt, so run 2 used the identical bytes.

## 3. What differs, and why that is expected

- **WARC files are not byte-identical.** Each file carries fetch timestamps, record ids and the fetch time, so hashes
  differ even when the pages are the same. Compare structure (record types, counts, URLs), not file hashes.
- **Segment ids and WARC file names embed the date and time.**
- **Manifests differ** in layout, in the date, and in the fields run 2 added.

## 4. What the evidence shows, and what it does not

| Claim | Supported? |
|---|---|
| The 64 bytes inside each quote equal the SHA-512 of its manifest | **Yes**, checked by the shell for all four quotes |
| Changing a manifest breaks that match | **Yes, tested.** One changed byte in run 2's master manifest gave `MISMATCH` (exit code 2) against the original quote. See [quote-verification.md](quote-verification.md). Not repeated on the worker |
| Each quote is a genuine Intel-signed statement from a TDX Trust Domain | **Yes, for all four quotes.** go-tdx-guest `check` verified each one, also with certificate data and revocation checks. A one-bit change to a quote makes its signature fail |
| The manifest lines are true | **No.** They are text written by a script on the VM. A quote vouches for a hash, not for the author's honesty |
| The boot measurements (MRTD, RTMRs) are the expected ones | **Examined, not judged.** MRTD is identical on all four quotes; RTMR0 to RTMR2 differ between the nodes. Without a reference value for the cloud's virtual firmware they cannot be judged |
| The pages came from the real websites | **No.** A TEE protects computation, not the network path. The WARC digests and headers are written by the crawler |
| The recorded time is correct | **No.** The clock is supplied by the host |
| The crawl stayed within the seed sites | **No, and it did not.** It fetched `www.zyte.com` in both runs |

## 5. Observations that affect the trust discussion

These feed the limitations and challenges table (still to be written):

1. Both nodes run different kernels (`6.8.0-1067-gcp` and `6.8.0-1069-gcp`) from the same image family. RTMR0, RTMR1 and RTMR2
   differ between the nodes while MRTD is identical, so a verifier cannot assume a single expected measurement for a
   cluster. The kernel difference may explain part of it, but naming the differing boot events needs the boot event log,
   which was not examined. Neither VM rebooted between the runs, so equal values across runs are expected.
2. Hadoop traffic between nodes crosses a network the host controls, and `default-allow-internal` opens every port
   between instances.
3. The helper libraries are built from moving snapshots, so their commit ids must be recorded or builds drift.
4. A downloaded file (the suffix list) sits outside version control; only its hash in the manifest accounts for it.
5. The WARC records show `WARC-IP-Address: 0.0.0.0` in the record read, so the server address is not captured there.
6. Unexpected `entry…` folders existed in the master's configfs-tsm report directory. Other software on the node can
   also request quotes, so a quote shows that a TD produced a statement, not which program asked for it.
7. TDX VMs cannot live-migrate, so unannounced stops are possible. Evidence must not live only on a VM disk.

## 6. Limits of this comparison

- Two runs, a day apart, against two practice sites that are static and built for crawling. The same stability
  may not hold on real sites.
- Run 2 file sizes were not captured, so sizes are compared only for run 1.
- Both runs used one operator, one cluster, and one fetch machine.

## 7. How the comparison was done

Comparisons were made by the shell, never by eye:

```bash
# inputs between runs, matched by file name
for f in nutch-site.xml seed.txt effective_tld_names.dat apache-nutch-1.22.job \
         core-site.xml hdfs-site.xml yarn-site.xml mapred-site.xml; do
  a=$(grep -E "[ /]$f\$" ~/evidence/master/manifest-master.txt | cut -d' ' -f1)
  b=$(grep -E "[ /]$f\$" ~/evidence-run2/master/attest-run2/manifest-master.txt | cut -d' ' -f1)
  [ -n "$a" ] && [ "$a" = "$b" ] && echo "SAME  $f" || echo "DIFF  $f"
done

# same pages fetched
U='/^WARC-Type:/{t=$2} /^WARC-Target-URI:/{ if(t=="response") print $2 }'
diff <(zcat warc-out/pages/*.warc.gz | tr -d '\r' | LC_ALL=C awk "$U" | sort) \
     <(zcat warc-out-run2/pages/*.warc.gz | tr -d '\r' | LC_ALL=C awk "$U" | sort) && echo SAME-PAGES

# identical Hadoop config and scripts across the two nodes of run 2
diff <(grep 'hadoop/etc' master/attest-run2/manifest-master.txt) \
     <(grep 'hadoop/etc' worker/attest-run2/manifest-worker.txt) && echo CONFIGS-IDENTICAL
```

## 8. Next steps for the evidence

1. Done: all four quotes verified with go-tdx-guest's `check` on a machine with no Google credentials.
2. Done: MRTD and RTMR values extracted and compared (see [quote-verification.md](quote-verification.md)).
3. Add a URL filter to keep the crawl inside the seed domains, and put the filter file's hash into the manifest.
4. Done: the limitations table and better-TEE assessment are in [limitations-and-trust.md](limitations-and-trust.md); its "Next experiments" list holds the remaining ideas.

This list is from 3 October 2026. For the later runs see sections 9.7 and 9.8 and the milestone reports.

## 9. Runs 3 and 4 (added 6 October 2026)

Run 3 is the clean baseline of [milestone-0-clean-baseline.md](milestone-0-clean-baseline.md); run 4 is the crawl on the measured stack of [milestone-1-code-measurement.md](milestone-1-code-measurement.md).

| Item | Run 2 | Run 3 | Run 4 |
|---|---|---|---|
| Date and duration | 3 Oct, about 10 minutes | 5 Oct, 09:52 to 10:03 | 5 Oct, 17:56 to 18:07 |
| HTTP client plugin (master's crawl log, 19 jobs) | `protocol-http` in 19, okhttp in 0 | okhttp in 19, `protocol-http` in 0 | same configuration and job as run 3; the log was not re-counted |
| `store.ip.address` | not set | true | true |
| Job file | SHA-256 `88161b64126a` | rebuilt, SHA-256 `bbd30ad90d35` | the run 3 file (no rebuild; its SHA-384 `f993fd407ab5` is in the master's measured log) |
| `WARC-IP-Address` | `0.0.0.0` | real: 8 page records and 2 diagnostics records | real: the same eight URL and address pairs as run 3 |
| Pages fetched | 8 | the same 8 URLs (`SAME-PAGES`) | the same 8 URLs (`SAME-PAGES`) |
| Kernel during the run | master 6.8.0-1067, worker 6.8.0-1069 | same | master 6.17.0-1022, worker 6.8.0-1069 |
| Measured stack | none | none | master: 10 events in RTMR3 before the crawl; all ten digests unchanged afterwards |
| WARC files | 9 | 18 (9 `.warc.gz` and 9 `.cdx.gz`) | 18 |
| Evidence | `evidence-run2` | `evidence-run3.tar.gz` | `evidence-run4.tar.gz` |

What this shows: the two configuration fixes changed the client and filled in the server addresses without changing which pages were fetched, and a measured stack on a newer kernel produced the same page list and addresses.

What it does not show:
- The comparison is by URL and address, not by page content or WARC bytes.
- `JOB-IDENTICAL` cannot be repeated between run 3 and earlier runs, because the configuration is inside the job file.
- The same two practice sites plus one external site, one operator, one cluster: the same limits as section 6.
- That okhttp ran inside the worker's tasks (see milestone 0, section 4).

### 9.1 Run 5 over the mesh (added 6 October 2026)

Run 5 repeats run 3's crawl after the WireGuard mesh and host firewall were added ([milestone-2-wireguard-mesh.md](milestone-2-wireguard-mesh.md)).

| Item | Run 3 | Run 5 |
|---|---|---|
| Date and duration | 5 Oct, 09:52 to 10:03 | 6 Oct, about 08:17 to 08:27 |
| Node-to-node traffic | ordinary network | through the WireGuard tunnel (master sent 3,915.2 MB during the crawl) |
| Job file | the run 3 build | the same file (no rebuild) |
| Pages fetched | 8 | the same 8 URLs (`SAME-PAGES`) |
| `WARC-IP-Address` | `toscrape` pages `35.211.122.109`; `www.zyte.com` `216.150.1.193` | `toscrape` pages the same; `www.zyte.com` `216.150.16.1` |
| WARC files | 18 | 18 |
| Plugin lines in the master's log | okhttp 19, old 0 | okhttp 19, old 0 |
| Worker task logs | gone by the time they were checked | not deleted: 22 list okhttp, 0 list the old plugin |
| Evidence | `evidence-run3.tar.gz` | `evidence-run5.tar.gz` |

What it shows: moving the nodes' traffic onto the mesh and closing the ordinary interface did not change which pages were fetched. What it does not show: the same limits as sections 6 and 9; and the changed address of one external site is a property of that site (it is served from a pool of addresses).

### 9.2 Run 6 through the hdfs:// wrapper (added 6 October 2026)

Run 6 repeats the crawl of run 5 with every HDFS request of the Nutch jobs going through the wrapper ([milestone-3-hdfs-wrapper.md](milestone-3-hdfs-wrapper.md)).

| Item | Run 5 | Run 6 |
|---|---|---|
| Date and duration | 6 Oct, about 08:17 to 08:27 | 6 Oct, first segment 13:42, finished 13:52:41 |
| HDFS access of the crawl's programs | the plain HDFS client | through `AttestedHdfsFileSystem` and `AttestedHdfs` (both lookups) |
| Driver | `ops/run-crawl.sh` | `ops/run-crawl-attested.sh` (the same plus three `-D` settings) |
| Job file | `bbd30ad90d357ca1`, 1029 entries | `ddc415a5d87c9e6b`, 1033 entries; the four extra entries are the wrapper's classes, nothing else differs (nested jars compared by content) |
| Pages fetched | 8 | the same 8 URLs (`SAME-PAGES`) |
| WARC files | 18 | 18 |
| `WARC-IP-Address` | `toscrape` pages `35.211.122.109`; `www.zyte.com` `216.150.16.1` | the same pairs |
| Page content (payload fingerprints) | | 7 of 8 identical; `www.zyte.com` differs |
| Crawl database (total, unfetched, fetched, redirects) | 257, 247, 8, 2 | 259, 249, 8, 2 |
| Plugin lines in the master's log | okhttp 19, old 0 | okhttp 19, old 0 |
| Worker task logs | 22 list okhttp, 0 the old plugin | 22 and 0 |
| HDFS byte counters in job reports | 27 read and 27 written lines; largest read 32,527 | 27 and 27; largest read 32,533 |
| YARN applications | 27 (numbers 0002 to 0028) | 27 (0029 to 0055) |
| Storage audit | | `AUDIT-CLEAN`: 187 added, 0 removed, 0 changed, all explained by the wrapper's log |
| Evidence | `evidence-run5.tar.gz` | `evidence-run6.tar.gz`, `evidence-run6-audit.tar.gz` |

**The one different page.** `www.zyte.com` has a different content fingerprint, and the crawl database has two more discovered URLs.

- Runs 3, 4 and 5 (no wrapper) have identical fingerprints for that page (`sha1:SOKCP57…`) and identical crawl databases; run 6 is the first to differ.
- The page shows why. Its deployment identifier changed from `dpl_Aw3cvvrezTgDVzNUPQtGSiZL7Jng` (fetched 08:24:52) to `dpl_6K3MMTWXqBLaBfG2FGJjgYif2oA4` (fetched 13:50:01), with new stylesheet file names. The live site at 14:37 serves the newer identifier.
- The new page has two more links that are not build assets (`/mcp/`, `/skills-and-plugins/`), which matches the two extra URLs in count; they were not traced individually.

What it shows: routing the crawl's storage requests through the wrapper did not change what the crawler fetched or how it counted it; the one difference comes from the website. What it does not show: a contemporaneous unwrapped run was not done, so the explanation rests on the control runs and the page's own evidence; and the same limits as sections 6 and 9 apply.

### 9.3 Run 7 with hashing (added 7 October 2026)

Run 7 repeats the crawl of run 6 with every file written through the wrapper also hashed when it is closed (observe only; nothing is verified). Report: [milestone-4-storage-integrity.md](milestone-4-storage-integrity.md), section 9.

| Item | Run 6 | Run 7 |
|---|---|---|
| Date and duration | 6 Oct, 13:41:59 to 13:52:41 (10 min 42 s) | 7 Oct, 07:25:08 to 07:35:51 (10 min 43 s) |
| What the wrapper does | forwards and logs | forwards, logs, and hashes every file at close (SHA-256 per 16,384-byte chunk, Merkle root) |
| Job file | `ddc415a5d87c9e6b`, 1033 entries | `8fdd7cdadd6a7e11`, 1036 entries; against the measured run 5 job: 7 more entries (the wrapper's folder and six classes), nothing else differs |
| Pages fetched | 8 | the same 8 URLs (`SAME-PAGES`) |
| Page content (payload fingerprints) | | 7 of 8 identical; `www.zyte.com` differs |
| Crawl database (total, unfetched, fetched, redirects) | 259, 249, 8, 2 | 259, 249, 8, 2 |
| Plugin lines in the master's log | okhttp 19, old 0 | okhttp 19, old 0 |
| Worker task logs | 22 list okhttp, 0 the old plugin | 22 and 0 |
| Storage audit | `AUDIT-CLEAN` (963 to 1150 paths) | `AUDIT-CLEAN` (1182 to 1369 paths) |
| Records | none | 54 of 54 files left under the crawl folder have a matching record; an independent re-hash agrees on all 54 |
| Evidence | `evidence-run6.tar.gz`, `evidence-run6-audit.tar.gz` | `evidence-run7.tar.gz`, `evidence-run7-audit.tar.gz` |

**The one different page.** `www.zyte.com` again has a new content fingerprint (run 6 `sha1:N6BMXVA...`, run 7 `sha1:Z4NYZYD...`). Its deployment identifier changed from `dpl_6K3MMTWXqBLaBfG2FGJjgYif2oA4` (fetched 6 Oct 13:50:01) to `dpl_J25tWhywpx6QetrVxFP7wgdX7PPC` (fetched 7 Oct 07:33:11), and the live site at 07:55 served the newer one. The page's links, apart from build assets, are the same. What it shows: hashing every written file did not change what the crawler fetched or how it counted it; the difference comes from the website. Not repeated for this run: the `WARC-IP-Address` check and the HDFS byte counters.

### 9.4 Run 8 with verified reads (added 7 October 2026)

Run 8 repeats the crawl with a record kept next to each file and every read checked against it. Report: [milestone-4-storage-integrity.md](milestone-4-storage-integrity.md), section 10.

| Item | Run 7 | Run 8 |
|---|---|---|
| Date and duration | 7 Oct, 07:25:08 to 07:35:51 (10 min 43 s) | 7 Oct, 09:16:02 to 09:26:59 (10 min 57 s) |
| What the wrapper does | forwards, logs, hashes at close | the same, keeps a companion record next to each file, and verifies every read against it |
| Job file | `8fdd7cdadd6a7e11`, 1036 entries | `a092d5fab91d4b73`, 1041 entries; five new classes and three changed classes, nothing else differs |
| Pages fetched | 8 | the same 8 URLs (`SAME-PAGES`) |
| Data files fetched for the evidence | 18 | 18, each with a hidden companion file |
| Page content (payload fingerprints) | | 7 of 8 identical; `www.zyte.com` differs |
| Crawl database (total, unfetched, fetched, redirects) | 259, 249, 8, 2 | 259, 249, 8, 2 |
| Plugin lines in the master's log | okhttp 19, old 0 | okhttp 19, old 0 |
| Worker task logs (the 27 applications of the run) | 22 and 0 | 22 list okhttp, 0 the old plugin, 0 a verification failure |
| Storage audit | `AUDIT-CLEAN` (1182 to 1369 paths) | `AUDIT-CLEAN`: 1377 to 1699 paths, 322 added, all explained |
| Records and companion files | 54 of 54 files have a record | 54 of 54 have a record and a companion file; the independent re-hash agrees on all 54 |
| How reads were verified | not applicable | 157 opens: 156 verified, 1 without a record (the seed file), 0 verification failures |
| Evidence | `evidence-run7.tar.gz`, `evidence-run7-audit.tar.gz` | `evidence-run8.tar.gz`, `evidence-run8-audit.tar.gz` |

**The one different page.** `www.zyte.com` differs once more (run 7 `sha1:Z4NYZYD...`, run 8 `sha1:XX7YZPKK...`). Its deployment identifier changed from `dpl_J25tWhywpx6QetrVxFP7wgdX7PPC` (fetched 7 Oct 07:33:11) to `dpl_2HdZ2H4ohADyL4QEFsb3pBbNMGvT` (fetched 09:24:12), and the live site at 12:06 served the newer one. What it shows: keeping records and verifying reads did not change what the crawler fetched or how it counted it. Not repeated for this run: the `WARC-IP-Address` check and the HDFS byte counters.

### 9.5 A condition from the mentor (7 October 2026)

Runs 6 to 8 were not paired with an unwrapped control in the same hour: run 6 was compared with run 5, which had been made hours earlier, and runs 7 and 8 were compared with run 6 and with each other. The mentor accepted this evidence and said that from Stage B on the unwrapped control is run in the same hour, with wall time and bytes fetched recorded for each pair (ADR-028). The three durations above (10 min 42 s, 10 min 43 s and 10 min 57 s) are therefore first timings, not a performance result. Since 8 October 2026 the NameNode's audit log is also on (cluster-configuration.md section 15), which runs 6 to 8 did not have, so later runs differ from them in that respect too.

### 9.6 Run 9 through the cluster's own wrapper (added 9 October 2026)

Run 9 is a procedure run for step 4.6. It is **not covered by the measurement** and has **no unwrapped control** in the same hour, so it is not compared with runs 7 and 8 on time or on the pages fetched, and its wall time (11 min 30 s, 05:08:18 to 05:19:48 UTC) is not a result. What differs from run 8 is how the wrapper was reached: with no wrapper options at all, so the cluster's own settings put it in place for the master's commands, the NodeManager and every container.

| | Run 8 | Run 9 |
|---|---|---|
| How the wrapper was switched on | three `-D` options passed by `ops/run-crawl-attested.sh` | none: `ops/run-crawl.sh` and the cluster's `core-site.xml` |
| The NodeManager's reads of the job files | through plain HDFS, outside the wrapper | through the wrapper: 108 opens (27 jobs, 4 files each), all verified |
| The seed folder | no record | a record (57 bytes and an 88-byte record) |
| NameNode comparison | not made on a crawl | clean with two stated rules: 0 unexplained of 1,894 events |
| Storage audit, expected records, verification summary, re-hash, tamper test | as in [milestone-4-storage-integrity.md](milestone-4-storage-integrity.md) sections 10 and 11 | `AUDIT-CLEAN` (322 added, all explained), `RECORDS-COMPLETE` (55 of 55), `VERIFY-CLEAN` (265 opens), `RECORDS-VERIFIED` (55 of 55), `TAMPER-PROVEN`, with nothing exempted |

Details and the evidence are in [milestone-4-storage-integrity.md](milestone-4-storage-integrity.md) section 20.


### 9.7 Runs 10 to 13 (added 14 October 2026)

Runs 10 and 11 are procedure runs; runs 12 and 13 are the first timing pair (ADR-028, ADR-041). Only run 12 is covered by the measurement (ADR-029); run 13 is the unwrapped control, which is outside it.

| | Run 10 | Run 11 | Run 12 | Run 13 |
|---|---|---|---|---|
| Date | 13 October | 14 October | 14 October, started 13:42:59 | 14 October, started 14:09:16 |
| File system | wrapped | wrapped | wrapped | plain (the wrapper switched off) |
| Job | the job of step 4.6.7 (section 22.8 of the report) | the patched job `91784e1a…` | the patched job `91784e1a…` | the patched job `91784e1a…` |
| Receipts | none | on | on | on |
| Covered by the measurement | no | no (before the re-measure) | **yes** (point-in-time) | no (plain mode) |
| Wall time of the crawl | 715 s | 693 s | 709 s | 672 s |
| Compared with a control in the same hour | no | no | yes: run 13 | yes: run 12 |

Runs 12 and 13 fetched the same pages: 10 pages from the same 10 URLs, 584,381 payload bytes each, 10 of 10 payloads byte-identical, 9 WARC files each. The wrapped run took 37 s (5.5 %) longer, read 3.3 % more and wrote 1.7 % more through HDFS, stored 0.3 % more (the wrapper's 141 record files), and made 59 % more NameNode calls. It is one pair with the wrapped run first, so it is a data point and not a result. The table and the evidence are in [milestone-4-storage-integrity.md](milestone-4-storage-integrity.md) section 23.4; run 10 is in section 22.5.


### 9.8 Runs 14 and 15 (added 17 October 2026)

Runs 14 and 15 are the first crawls with **signing and folder binding on and required**: run 14 (15 October) with a labelled test key, run 15 (16 October) with the real keys that each VM made at boot. They are procedure runs and not a timing pair: no control ran in the same hour, so nothing here says what the signing costs (limitations rows 108 and 116; the timing pairs follow ADR-041 in Milestone 6). Both ran in a reserved window, so the stack was not the measured one and **neither run is covered by the measurement** (ADR-029, ADR-045).

| | Run 12 (for reference) | Run 14 | Run 15 |
|---|---|---|---|
| Date | 14 October | 15 October, crawl started 18:37:50 | 16 October, crawl started 11:46:59 |
| File system | wrapped | wrapped, signing and folder binding on and required | wrapped, signing and folder binding on and required |
| Job | the patched job `91784e1a…` | the job of step 5.1.2, `6f98295641a4f559…` | the job of step 5.1.3, `3a55e21d17c07d78…` |
| Signing key | none | a labelled test key | the real keys, one per VM, made at boot |
| Covered by the measurement | yes (point-in-time) | no (a window) | no (a window) |
| Wall time of the crawl | 709 s | 770 s | 736 s |
| Compared with a control in the same hour | yes: run 13 | no | no |
| Output verified offline | not signed | 55 folders and 60 files, all clean | 55 folders and 60 files, all clean |
| Verified reads in the audit logs | not applicable | 265, every one with a signature and a folder binding | 211, every one with a signature and a folder binding |
| Paths added to HDFS | not applicable | 393 (3,409 to 3,802) | 230 (3,806 to 4,036) |

What the two runs show: a real Nutch job writes everything through the wrapper in this mode, including what Hadoop's output committer moves between folders, and every file ends with a signed record bound to its folder. Run 15 shows that the key is the machine's: the tree is signed by exactly two keys, the master's and the worker's, whose services signed 180 and 436 statements; with only the master's bundle in the key list the worker's files are refused (13 findings), so the check can fail. The offline verification made a plain copy of the output (175 files: 60 data files, 60 record files and 55 identity files) and verified it with the public keys only.

What they do not show: any timing; that the signing service is safe from the fetcher running as the same user (limitations row 109); the worker's task logs of run 14, which the window's close deleted (row 106); and anything about the data left in HDFS (rows 107 and 115). Two runs also cannot say whether two crawls of the same seeds sign the same bytes: the pages, and so the records, differ between runs. The details are in [milestone-5-signed-records.md](milestone-5-signed-records.md) section 5 (run 14) and section 6 (run 15).

### 9.9 The fixed-fleet runs (added 21 October 2026)

From 20 October 2026 every crawl runs by itself after the boot of a fleet made from an image (steps F0.3c to F4), always the same small crawl: two seeds, three rounds, at most four URLs per round, through the wrapper, on TDX and over the mesh. Each run fetched 8 URLs in 3 segments and 3 rounds. The table is taken from the saved check of each run (the master's `f1-check`, or the self-report for the locked image); "from joined to done" starts when the fleet unit says that the fleet is joined, so it includes the wait for HDFS and YARN, and it is not the crawl alone (the F1 run of [milestone-5-signed-records.md](milestone-5-signed-records.md) section 15 gives 12 minutes 37 seconds from the start of the crawl itself).

| Folder | Image | Fleet joined | Crawl done | From joined to done | What it was |
|---|---|---|---|---|---|
| `evidence-f3` | `tc-img-f3-1` | 2026-10-20 18:58:20 | 19:12:34 | 14 min 14 s | the first run with the fixed-behavior wrapper (steps F2 and F3) |
| `evidence-f4` | `tc-img-f4-1` | 2026-10-21 04:50:40 | 05:04:38 | 13 min 58 s | the run in which the contract tests matched plain HDFS |
| `evidence-f5d` | `tc-img-dbg-1` | 2026-10-21 06:49:25 | 07:03:17 | 13 min 52 s | the debug image, with the firewall |
| `evidence-f5l` | `tc-img-lock-1` | 2026-10-21 08:34:34 | 08:48:16 | 13 min 42 s | the locked image (the joined time is the report's `fleet_done`) |
| `evidence-f6d` | `tc-img-dbg-1` | 2026-10-21 09:57:39 | 10:11:52 | 14 min 13 s | the debug image, with the attack A10 |

The folders `evidence-f1` and `evidence-f2` have no finished crawl: those were the first fleet runs, which failed before the crawl ended with success (the causes are in the mistake log). The five runs differ in the image and in the wrapper's version, and they lie between 13 min 42 s and 14 min 14 s, a spread of 32 seconds (about 4 percent), so the wrapper's later changes, the firewall and the lock did not change the time of this small crawl in any way that these runs can show. **There is no unwrapped control in these runs:** from Stage B the mentor asked for a pair in the same hour (decision D1), but step 6.3 is now split (Subhi writes the benchmark spec and we run both sides, from 22 October 2026), at a larger size ([milestone-6-verifier-and-evidence.md](milestone-6-verifier-and-evidence.md) section 8). They show that the crawl is repeatable on the fleet, not what the custody layer costs. The folders are in the bundle `evidence-all.tar.gz` (SHA-256 `cbbb7e0b…`, 118 files) on the Cloud Shell.

### 9.10 The three-node debug run of step R1 (added 22 October 2026)

A debug fleet of three nodes (a master and two workers) from the image `tc-img-dbg-2`, built the same day from a fresh builder: the job `caf39643d1bc8496…` (134844151 bytes, 1054 entries, 18 wrapper classes, the receipt class `CustodyReceipt` in it), the wrapper jar `77658c5a881344cf…` (18 classes), Hadoop 3.4.3 (SHA-512 `e25be7e57b4d3c5b…`), and one build input, a source archive `6fee9a061e26f282…` that was made from a clone of the branch at `ee7914a9b` with the 26 files of step R1 laid over it and a local commit that was never pushed. The machine type is `c3-standard-4`.

| What | Result |
|---|---|
| The fleet | three announcements verified, `fleet.tsv` of 3 nodes (SHA-384 `22c872f0d8d894ba…`), the same fleet event in all three final quotes |
| The node check | `F1-CHECK-OK` on the master and on both workers: each node has the two others as `wg0` peers, the two wrapper keys are final, the job was built from one input and holds the receipt class; HDFS reports 2 live DataNodes |
| The crawl | ran by itself and ended with success, `fetched=8 segments=3 rounds=3`, 13 minutes after the fleet joined (14:52 to 15:05 UTC); the replication is 2 (`dfs.replication`, and the files of `/tc/crawl` show 2) |
| F2 and F4 | `F2-CHECK-OK`; `F4-ATTACKS-OK` with A1 to A14 and the two documented limits |
| Contract tests | 199 tests per run: plain 177 passed, 9 failed, 13 skipped; through the wrapper 176, 9, 14; `CONTRACT-SAME-AS-HDFS (1 explained difference)`: no test passes on plain HDFS and fails through the wrapper |
| Reference values and enforce | `REFERENCE-OK` for the three nodes (15 stable events), `ENFORCE-OK: all 3 nodes` against them, `REPORT-OK` (26 facts per node) |
| The same fleet against the reference of the locked image `tc-img-lock-1` | refused: `ENFORCE-FAILED (66 problems)`, rules E4 and E5 |

The evidence is in `evidence-r1b` (the build) and `evidence-r1f` (the fleet); the bundle `evidence-r1.tar.gz` has a SHA-256 that starts with `b08e99e34a1857e9`. The three VMs were deleted afterwards. The vCPU quota of the region (24 for `c3`) had to be freed first: the old nodes `tdx-lab` and `tdx-lab-worker` were stopped (limitations row 171).

### 9.11 The export runs of step R5 (added 23 October 2026)

Fleets of two nodes (a master and a worker) on `c3-standard-4`, each from an image built on the existing builder with `bake-fleet` and `bake-lock` (debug), with the bucket `training-custody-export-test` (retention 86400 s, not locked) and the service account `tc-export@training-custody.iam.gserviceaccount.com` (only `roles/storage.objectCreator` on that bucket, only on the master). In every run the fleet formed, `F1-CHECK-OK` held on both nodes and the crawl ended with success, `fetched=8 segments=3 rounds=3`.

| Run | Image | What happened |
|---|---|---|
| 1 | `tc-img-dbg-3` (deleted) | `tc-export.service` failed at once, at the end of the crawl: `runuser: command not found` (the unit's `PATH` had no `/usr/sbin`) |
| 2 | `tc-img-dbg-4` | the export job ran and wrote `/tc/warc/part-r-00000.seg-00000.attempt-00000.warc` (554289 bytes) with its record and its identity, and the script stopped: `the export job wrote no .warc.gz file` (the exporter writes plain `.warc` files) |
| 2b | the same fleet | a debugging run: the fixed script copied to the master and started by hand as root, with the unit's environment: manifest of 5 files (SHA-384 `c0ecfa223ac47993…`), 8 objects uploaded, `EXPORT-OK` and `ENFORCE-OK` with quote C accepted; the master's account was refused an overwrite and a delete (403 and 403) |
| 3 | `tc-img-dbg-5` | the clean run, with the image's own unit and no hand-off: the first wait found `quote C (19095 bytes)`; 6 files came back from the bucket (the `DONE` object names the manifest); `EXPORT-OK … rule E8`; `ENFORCE-OK … quote C accepted`; `REPORT-OK` (26 facts per node, no failed unit) and `LOCK-CHECK-OK (debug)` |

The fleet list of run 3 has the SHA-384 `b9b0aa10c3279283…` (the bucket prefix); the debugging run 2b has `c1f944bc4821f7d1…`. Run 2b is a debugging run and is not evidence for the image: its script did not come from the image. The evidence is in `evidence-r5b` (the image builds), `evidence-r5f` (run 2 and the debugging run 2b) and `evidence-r5g` (run 3); the sample export for the teammate is `export-sample-r5.tar.gz` (SHA-256 starting `56a6c468e51e7475`); the bundle `evidence-r5.tar.gz` has a SHA-256 that starts with `fa0acaf2e518a814`. The two test fleets were deleted.

### 9.12 The receipts change on an unsealed image (added 26 October 2026)

The teammate's receipts change (pull request 1, merged as `a795099e8`) was run on our cluster so that we do not rely on her numbers. A source archive made with `git archive` of the merge commit (SHA-256 `847b7c58a19101c1…`) went through `ship-source`, `job`, `bake-crawl`, `bake-fleet`, `clean` and `image` on the existing builder: image `tc-img-dbg-6` (debug, not sealed). The job has SHA-256 `8d54f6cd73625206…` and holds the receipt class; the collection policy was baked from the image's JDK CA store (120 anchors, SHA-256 `2021f9eef81745e7…`). A fleet of two nodes (a master and a worker, `c3-standard-4`, zone `us-central1-a`, fleet list SHA-384 `ad1e86d2079bc16c…`) formed, the crawl ran by itself (`fetched=8 segments=3 rounds=3`) and the master exported it (51 files and the manifest). `EXPORT-OK` (rule E8) and `ENFORCE-OK` passed. Then the claims of her description were recomputed from the exported files with our own tools (`r3-export-audit.py` and `r3-receipt-verify.py`; standard library only; none of her tools were used).

| What the teammate said (the description of the pull request) | What we recomputed on our cluster |
|---|---|
| Header-injection fix: the protocol plugins drop server-sent `_tc_*` headers before adding the TLS facts; before it, a server could get itself receipted as authenticated | **Not tested by us**: no attacking server was in our crawl. The code that ran has the fix |
| The fetcher writes the WARC files itself, through the wrapper, and not `nutch warc` (which wrote the literal text `IP` as `WARC-IP-Address`, wrote no HTTP headers, and could never carry receipts) | 9 WARC files, 36 records (9 warcinfo, 10 response, 17 metadata); all 10 response records start with HTTP headers; the literal text `IP` in 0 records (2 distinct addresses) |
| Outcome v2 with `source_authenticated` | 10 outcomes: 7 `ACCEPTED`, 2 `HTTP_STATUS` (308) and 1 `NOT_HTTPS`; every `ACCEPTED` outcome has a receipt and no other outcome has one |
| Receipts are on for the crawl and are carried in the WARC | For 7 receipts of 7: the receipt in the WARC is byte for byte the line of the receipts file; its `TC-Content-SHA256` header and its outcome's `receipt_sha256` are the SHA-256 of it; the document id is the WARC record id and the URL is the response's; `raw_content_hash` and `raw_content_length` are those of the payload and the WARC's own SHA-1 payload digest is right; `http_status` is the response's; the TLS facts are complete and `authenticated` is true in the receipt and the outcome, with a valid chain and a hostname match; the validity dates of every certificate enclose the fetch time |
| The collection policy is baked from the image's JDK CA store, lives in `/etc/tc` (so `tc-conf` measures it), and is the same file on every node | 120 anchors, SHA-256 `2021f9eef81745e7…`; every receipt's `collection_policy_hash` is that hash (7 of 7); every receipt's `code_hash` is the job's (7 of 7); both nodes agree on all 14 stable events |
| `tc-export.sh` exports the WARC files, the receipt outcomes and the policy, each with its record and folder identities, instead of running `nutch warc` | `EXPORT-OK` (rule E8): 51 files and the manifest, every file recomputed (51 of 51), no unlisted file; 21 receipt files |
| Signed time: Roughtime readings at the start and end of each fetch task | 3 tasks, each with a start and an end reading that parse, the start not after the end, and the WARC date of every receipted fetch inside the window (09:08:25 to 09:08:27, 09:12:27 to 09:12:44 and 09:17:03 to 09:17:16, radius 1.0 s, server `roughtime.cloudflare.com:2003`). **The signatures were not verified by us** |
| Real crawl: 7 receipted, 1 expired chain labelled, 2 correctly without; a live 10K crawl: 6,868 receipts and 9,354 outcomes | Ours: 10 fetches, 7 receipted and 3 correctly without (two HTTP 308 and one URL that is not https). No expired chain occurred, so that case is **not exercised by us**; the 10K crawl was **not run by us** |
| `r5-rehearse.sh` 42/42; `f03c-rehearse.sh` 50/51 (one unit-file check fails the same way on `820d4b05b`) | `r5-rehearse.sh` 42/42 reproduced by us; `f03c-rehearse.sh` not rerun. `f1-rehearse.sh`, which her change did not update, needed one line (a stand-in collection policy) in its stand-in root |
| Open point: the fleet issues no nonce, so receipts carry `nonce: null` | Confirmed (23 records with a null nonce); R7 is the teammate's (ADR-076) |
| Open point: a failed fetch attempt could leave a WARC file without a record, and the export would then refuse to run | **Not tested by us** |
| Open point: `verify_outcomes.py` needs a schedule for its completeness check | Our check accounts for every outcome against the WARC responses; **completeness is not checked** (there is no schedule). Her verifiers (`verify_warc.py` and `verify_outcomes.py`) are not in the repository and were not run by us |
| Not tested: a full run of the locked image and fleet | Also not done by us: her code ran on a debug image and on the sealed debug image (section 9.13), not on the locked image |

The evidence bundle is `evidence-r3p` (SHA-256 `8e2fc5d9…`). Two defects of our own were found while doing this: an operator command that named a reference file that the stage does not write, and a rehearsal stand-in that lacked the new policy file (mistakes 181 and 182).

### 9.13 The sealed image runs of step R3 (added 26 October 2026)

| Run | Image | What happened |
|---|---|---|
| 1 to 2 | `tc-img-seal-1` and `-2` | the first designs of the scratch disk: the sealed boot reached the scratch step and failed there (LUKS2 integrity without a wipe: `INTEGRITY AEAD ERROR` at `mke2fs`, then a power-off by design). Reproduced on a real kernel under QEMU, which also showed that the kernel refuses to recalculate HMAC tags; ADR-073 is the fix |
| 3 | `tc-img-seal-3` | the sealed boot worked and `SEAL-CHECK-OK` passed (evidence `evidence-r3u`, SHA-256 `71af937f…`); my boot watcher had first stopped the boot at second 0 on the harmless GRUB line `error: can't find command 'serial'` (mistake 177) |
| 4 | `tc-img-seal-4` | attacks 2 and 3 passed on the cluster (attack 2 after its tamper range was changed to be independent of the disk layout, mistake 178); attack 1's flip passed, but its VM could not be created: first a disk of the wrong type, then no `c3` capacity in any zone (mistakes 179 and 180) |
| 5 | `tc-img-seal-5` | the final run, below |

The final run rebuilt the image from the builder's disk after the receipts change (section 9.12): the hook strip passed (`REFRESH-OK`), the sealed initramfs was built and verified (SHA-256 `1aaaafef7dadc595…`), the sealing passed all nine gates (root hash `a2b4de40f4bb9e71…`). The sealed boot on a plain `c3` VM reached its login within 24 s and `SEAL-CHECK-OK` passed (the root is `/dev/mapper/vroot` read-only under an overlay, dm-verity status `V`, the scratch disk is dm-integrity under dm-crypt with no key file left, `/var/lib/hadoop`, `/var/log` and `/tmp` come from it). The three attacks were refused: (1) one flipped bit in `systemd` gives a kernel panic (`Attempted to kill init`) and no login; (2) garbage on the raw scratch disk gives a failed read with 8 new `Checksum failed` lines; (3) after a reset the marker is gone, the file system has a new UUID and no key file exists. Then a fleet of two TDX nodes ran on the sealed image with a 10 GB scratch disk each (zone `us-central1-a`, fleet list SHA-384 `9d90d2cd5112475b…`): both nodes passed `fleet-check`, the crawl ran by itself (`fetched=8 segments=3 rounds=3`), `EXPORT-OK` (rule E8, 51 files and the manifest) and `ENFORCE-OK` passed, and the audit and the receipt verifier of section 9.12 passed on this export too.

Against the unsealed image of section 9.12, the reference values changed as they should: RTMR2 is `daa83af907defbce…` (it was `7a2f21d0f79ae3ef…` on `tc-img-dbg-6`), because it now covers the kernel command line with the root hash; RTMR0 changed (`86e7884c…` against `1be7d362…`); MRTD and RTMR1 are equal; of the stable RTMR3 events only `tc-lib` changed (the stripped scripts). The evidence bundles are `evidence-r3-final` (SHA-256 `5bc501f3eaadfd6b…`) and `qemu-repro-evidence` (SHA-256 `b1340525…`, the console logs of the reproductions under QEMU).

### 9.14 The reproducible build and the acceptance run of step R4 (added 27 October 2026)

Two builders (`tc-r4-a` and `tc-r4-b`) were made from the same pinned base image (`ubuntu-2204-jammy-v20261021`) and built commit `9b45b91af` from the same source archive (`git archive`, SHA-256 `7c635315…`); the first experiment was from scratch, and the later rounds re-ran every stage after the preparation on the same two builders (the builder, the kernel and the Hadoop tarball were kept). The builds were compared item by item.

| Step | What happened |
|---|---|
| First experiment | 12 of 15 events equal. The three that differed: `jdk` (the file `classes.jsa`, 11,919,360 bytes), `nutch-deploy` (one build stamp in a `pom.properties` and the times of 1,369 zip headers in the job) and `tc-conf` (it recorded the job's hash). Evidence `17b31234…` |
| The fixes, tested on real data | The job normalizer turned three real jobs of three builds (134,851,488, 134,851,429 and 134,851,483 bytes) into one file of 134,719,542 bytes, SHA-256 `760f83d6…`: 90,816 entries, 361 nested jars, 58 date lines removed, 5 signed jars unchanged, 57 s each; Hadoop still unpacks it |
| Second experiment | 15 of 15 events equal, 601 package versions equal, one difference left: the initramfs (`24428cec…` and `17b5c3ce…`; 539 entries, 3 with different content: `.random-seed` and the date line of two `mdadm.conf` files). The normalizer turned both real files into one, `82da7978…` (17,912,696 bytes), and the gates of the sealing script accepted it |
| Third experiment | Both builds re-run with the fixes: the same initramfs `82da797804e25640…`, 15 of 15 events equal, the same recipe, a recompute from the commit of 8 events equal to the builds. Evidence `233a9b55…` |
| Acceptance on a real fleet | Builder A was cleaned, its disk copied and sealed (root hash `8c36e94de5f156d1…`, all nine gates), the image `tc-img-r4-1` booted on a plain VM in 24 s and `SEAL-CHECK-OK` passed; the fleet of two TDX nodes formed (fleet event `107439a68090b2aa…`), the crawl ended with `fetched=8 segments=3 rounds=3`, `EXPORT-OK` (51 files), `AUDIT-OK`, `RECEIPT-VERIFY-OK` (7 receipted fetches and 3 correctly without, with the hash of the normalized job) |
| The reference and the pin | MRTD `c1ee9c16…`, RTMR0 `86e7884c…` (the same as `tc-img-seal-5`), RTMR1 `942469f1…`, RTMR2 `c8066c42…` (it was `daa83af9…` on `tc-img-seal-5`: the sealed disk differs, limitations row 186). The 15 stable events of the real fleet equal the events of the two independent builds (`R4-ACCEPT-OK`); `enforce` accepted both nodes and quote C with the pin (`PINNED`), and refused a wrong pin and a missing pin on the same quotes. A changed digit in one build is refused by the generator and names the event |
| After the commits | `cba9386bf` and `83b096bcb` are on GitHub and the audit passes; a fresh clone in Cloud Shell passes the audit and, with the recipe of build A and the commit, recomputes 8 of 15 events equal to the real fleet's reference |

The evidence bundles are `evidence-r4-experiment` (SHA-256 `233a9b55…`), the two builds `evidence-r4-A` (`245bf841…`) and `evidence-r4-B` (`abf1f43d…`), and `evidence-r4-final` (SHA-256 `13678dee…`). What this does not show is in limitations rows 186 to 193: the hash of the sealed root is not reproducible, the image names the base commit and not the tree that built it, the builds were made by one operator, and the package versions are equal only within one day. Five defects of our own were found on the way (mistakes 183 to 187).

### 9.15 The final verification run of step R4 and the policy that depended on the day (added 28 October 2026)

| Step | What happened |
|---|---|
| A second pair of builds (27 October, commit `68961df9e`) | two new builders `tc-fin-a` and `tc-fin-b` from the pinned base image; the copy of the Hadoop tarball from the old builder failed on both, so each downloaded 491 MB at 81 KB/s (about 1 h 45 min, from 14:15 UTC); 15 of 15 events identical, 601 package versions equal, the same initramfs `82da7978…`; but the collection policy was `e623c150…` and the first pair's `1ba5c732…`. Evidence `f74d9a31…` |
| The diagnosis (read only, on two real builders) | the certificate store of the new builder was generated on Oct 27 and the old one's on Oct 26 (120 certificates each); the hash of the keytool text was `cfa67d60…` against `7e89bc58…`, and `757d0a8d…` on both without the `Creation date` lines; the policy was `e623c150…` against `1ba5c732…` |
| The fix, tried on the real machines | the fixed `tc-policy.py` (SHA-256 `b9d16172…`) made the policy `bd4a62bb…` on both builders; the set of certificates was unchanged (`16513a11…`) |
| The commit and the run on it | a local commit `43f6fd386` (the fix and the rehearsal `r4g`), then one command (`ops/kits/r4-final-kit/r4-final.sh`): both builds in 13 min with 15 of 15 events identical; the new build against the old one differed in exactly `source`, `tc-lib` and `tc-conf`; the recompute from the commit matched 8 of 15; the sealing took 7 min (root hash `8888150c…`, image `tc-img-fin2-1`); the first boot check hit a stockout of `c3-standard-4` in zone a (no test VM was made) and passed on the second run (3 min); the sealed fleet of two TDX nodes took 18 min: the same fleet list (SHA-384 `e71c26bc…`), RTMR2 `238055e3…`, the crawl `fetched=8 segments=3 rounds=3`, `EXPORT-OK` (51 files), `AUDIT-OK`, `RECEIPT-VERIFY-OK`, `ENFORCE-OK` pinned to `43f6fd386` with a wrong and a missing pin refused, and `R4-ACCEPT-OK`. Evidence `95e3c6ca…` |
| After the run | `43f6fd386` was pushed on 28 October after its commit id was typed as the proof; the audit printed `PREFLIGHT-OK` |
| Time | the verification took about 42 minutes in all (build 13, seal-prep 1, seal-disk 7, seal-image 3, fleet 18); on 27 October two builds had lost about 1 h 45 min each in downloads, a second pair of builds was needed only because of the flaw that it exposed, and the first run of the final stages stopped at the stockout |

What this does not show is in limitations rows 188 and 194 to 196: the rebuild by the teammate on another day is still to come, the earlier reference of `tc-img-r4-1` holds the day-dependent `tc-conf`, her `make_policy.py` has to drop the same lines, and the Hadoop download is slow. Five defects of our own were found on the way (mistakes 188 to 192). The sealed root is decided by default (ADR-081).

### 9.16 The package pin of step R4.6 (added 28 October 2026)

| Step | What happened |
|---|---|
| The decision | in her review of 28 October the mentor said that the packages must be pinned (a monthly horizon) as the new step, and not as the short-horizon default (ADR-084, superseded by ADR-086) |
| The build | a new stage `aptpin` before the preparation points apt at Canonical's snapshot service for the date `20261027T000000Z` (one line of `ops/image/build/apt-snapshot.txt`); the service answered HTTP 200 for that date from Cloud Shell; fresh builders `tc-pin-a` and `tc-pin-b`; the Hadoop tarball was copied inside the network from `tc-fin-b`, a builder that the sealing had not cleaned |
| The proof of the pin | `APTPIN-OK snapshot=20261027T000000Z openjdk-11-jdk-headless=11.0.32.1+1-1ubuntu1~22.04` on both builders: apt read the lists of jammy, jammy-updates and jammy-security from the dated copy |
| The two builds | 15 of 15 events identical and 601 package versions equal; against the last pair's build of A, 13 of 15 events were equal: `source` (the commit) and `tc-conf` differ, and in `tc-conf` two files differ: `source.txt` (the commit) and `job-versions.txt`, which is 3 bytes shorter because its first line names the source archive by file name and hash: `src-pin.tgz` (11 characters) against `src-final2.tgz` (14) in the last pair; the `tools:` lines of the two are identical (91 bytes each), so the packages are not the cause; the events `jdk`, `wg`, `hadoop-code`, `nutch-deploy` and `tc-lib` did not change, and the 601 package versions equal those of the last pair |
| What the pin run built from | the build stage shipped `src-pin.tgz` (SHA-256 `1dad36a7…`, the archive of the earlier local commit `ec581508a`) because the archive name was written in the stage and the old file was still in the home folder (the console line `ship the source archive (1dad36a7526ebab6...)` shows it); the two archives differ only in `f03a-rehearse.sh`, so the Nutch source, the job (`nutch-deploy` identical) and the image content are the same, and the `source` event names `1c8a2cc19`; the line in `job-versions.txt`, and so the reference's `tc-conf`, name the old archive (limitations rows 203 and 204) |
| Sealing and fleet | root hash `a6881d07…` (the fourth different root hash of four sealings) and RTMR2 `a77ea8fc…`; the same fleet list on both nodes (SHA-384 `3c74b38a…`); the crawl `fetched=8 segments=3 rounds=3` (finished 28 October 09:54 UTC); `EXPORT-OK`, `AUDIT-OK`, `RECEIPT-VERIFY-OK`, `ENFORCE-OK` pinned to `1c8a2cc19` (a wrong and a missing pin refused) and `R4-ACCEPT-OK`; evidence `214a76f7…` |
| Time | prepare 1, build 14, compare 0, seal-prep 1, seal-disk 6, seal-image 4, fleet 19, verify 0 and clean 0 minutes |
| What stopped the kit before it ran | five stops (mistakes 195 to 199), each found in the first minutes except an SSH wait of 4 minutes: a seed builder that the sealing had cleaned, a run folder shared with the previous kit (a PASS with an empty commit), a stale same-name upload, a rehearsal that passed for me as root and failed 3 checks in Cloud Shell, and a lock held by a leftover ssh-agent; the cost was the number of round trips |
| After the run | `1c8a2cc19` was pushed together with `e67410e50` (the repaired rehearsals) after its commit id was typed as the proof; the audit printed `PREFLIGHT-OK`; the pin kit that ran is kept outside the repository (`r4-pin-kit5.zip`, SHA-256 `b0d7d4addf1fa1ca…`) until the step R4.7 has run |

What this does not show is in limitations rows 197 to 204: the `tc-conf` of a second party's rebuild cannot match until row 203 is closed (the planned step R4.7), the build used a stale archive, the kernel packages come from the live archive pool, the date was chosen by us, the build depends on a third party's service, the kit has the lock defect, and a rebuild on another day by a second party is still to come. The sealed disk is still not identical across builds (row 186). The proof of the pin on a later day (the packages of the same date a month later) is the property that the date is meant to give, and it has not been shown yet.

### 9.17 The commit in the job versions, step R4.7 (added 28 October 2026)

| Step | What happened |
|---|---|
| The change | `tc-source-id.sh` writes `source: commit <40 digits>` into `job-versions.txt`, proven from the archive's own git header (commit `41033a7e0`, ADR-087); the kit gave build A the archive `src-r47-41033a7e0.tgz` and build B a repacked copy of it (`src-r47-41033a7e0-alt.tgz`: another name, other bytes) |
| The decisive test | both builds recorded `source: commit 41033a7e0…`, the two shipped archives differ, and the two builds are identical in all 15 events (the compare stage fails otherwise); against the pin run's build of A, 13 of 15 events are equal and `source` and `tc-conf` differ, as expected; the 601 package versions are equal |
| Sealing and fleet | root hash `ed3cdb1a…` (the fifth different value of five sealings), RTMR2 `d4d6d754…`; the same fleet list on both nodes (SHA-384 `f6050ce0…`); the crawl `fetched=8 segments=3 rounds=3` (28 October 12:56 UTC); `EXPORT-OK`, `AUDIT-OK`, `RECEIPT-VERIFY-OK`, `ENFORCE-OK` pinned to `41033a7e0` and `R4-ACCEPT-OK`; evidence `77a3468c…` |
| The stop and the repair | the sealing stopped at the copy of the builder's disk (a quota error, mistake 203); after the real error was read, four stopped builders of ours were deleted on your answer yes and the run continued from the sealing: its second start was not refused, which shows that the lock fix works |
| Time | prepare 5, build 15, compare 0, seal-prep 1, seal-disk 6, seal-image 5, fleet 19, verify 0 and clean 1 minutes |
| After the run | `41033a7e0` was pushed with its commit id typed as the proof; the kit that ran is committed as `ops/kits/r4-r47-kit/` |

What this does not show: the sealed root is still different in every sealing (row 186; step R4.8), the teammate's rebuild on another day is still to come (row 188), and the kit's last message names a stale push script (row 206).

### 9.18 Pinning the Public Suffix List, step R4.9 (added 29 October 2026)

| Step | What happened |
|---|---|
| The finding | in the end to end test (a local test commit that was discarded afterwards) the two builds of one commit differed in 2 of 15 events: `nutch-deploy` (the job was 16 bytes larger in build B) and `tc-conf` (`job-versions.txt` records the job's hash); inside the job only the entry `lib/crawler-commons-1.7-SNAPSHOT.jar` differed (254,303 against 254,304 bytes), and inside that jar only `effective_tld_names.dat` (338,012 bytes in both, other content); the library's pom downloads that list from publicsuffix.org while it is built |
| The change | the list is pinned by content (337,923 bytes, SHA-256 `d3e6243b…`, from the list's repository on 29 October); `tc-psl-pin.py` puts it into the installed jar and makes the jar reproducible; the job script records the hash; the rehearsal `r4j` (22 checks, seven mutants caught) shows that jars that differ in the list, the entry order, the times and an extra field come out byte identical (ADR-089, commit `5ae1aa386`) |
| The decisive test | the two new builds (build A from the archive, build B from a repacked copy of it, on different VMs) are identical in all 15 events; against the build of the last pair, 12 of 15 events are equal and `source`, `tc-conf` and `nutch-deploy` differ, as expected; the 601 package versions are equal; both builds give the same recipe and 8 of 15 events are recomputed from the commit |
| Sealing and fleet | root hash `ad12cba9…` (the sixth different value of six sealings), the same fleet list on both nodes (SHA-384 `9cfaf16b…`), the crawl `fetched=8 segments=3 rounds=3` (29 October 12:57 UTC), `EXPORT-OK`, `AUDIT-OK`, `RECEIPT-VERIFY-OK`, `ENFORCE-OK` and `R4-ACCEPT-OK` pinned to `5ae1aa386`; evidence `447b06b5…` |
| The stops | build B stopped twice in its preparation because the kernel download was cut (curl error 18; limitations row 209), so its VM was replaced and it passed; the sealing helper VM could not be created because of a capacity stockout in the zone (row 210), so a block removed the leftovers and the run continued and passed |
| Time | prepare 5, build 15, compare 0, seal-prep 1, seal-disk 7, seal-image 5, fleet 18, verify 0 and clean 0 minutes (31 in the last run) |

What this does not show: that a second party gets the same jar (that is the mentor's step 4), that the kernel packages stay available in the live archive (row 197), and how the crawler behaves on the 15 sites of the end to end test ([end-to-end-testing.md](end-to-end-testing.md)).

### 9.19 The dummy run, the boot event log and the release, steps P1, P2 and P6 (added 29 October 2026)

| Step | What happened |
|---|---|
| P1, the dummy run (commit `9a3e9a845`) | `ops/reference-run.sh` made one TDX VM from the sealed image `tc-img-psl-1` without a fleet list and read its announcement; the comparison with the pinned reference of the real fleet of that image gave MRTD, RTMR0, RTMR1, RTMR2 and all 15 stable events equal and the debug bit off (ADR-091) |
| The image change (commit `16bafb3b1`) | the node publishes its firmware boot event log as guest attributes (ADR-092); the image run of the new commit passed in all its stages (about 34 minutes from the sealing to the end after a resume), giving the image `tc-img-rel-1` |
| P1 again on the new image | the dummy run equals the reference of the new fleet: MRTD `f21e6b48…`, RTMR0 `d413e692…` and RTMR1 `942469f1…` are the same as for the previous image (they depend on the firmware and the boot manager, not on our content), RTMR2 is `279e9417…` (it changed because the new root hash is on the kernel command line), all 15 stable events equal, debug bit off, the settings printed |
| P6, the boot events (tools `a950bf882`, option `--full` in `6572340da`) | the log has 262,144 bytes in 22 chunks (SHA-256 `553789f8…`) and 45 events: MRTD 2, RTMR0 17, RTMR1 7, RTMR2 19; the replay of RTMR0, RTMR1 and RTMR2 equals the quote; the kernel, its command line and the initrd are in **RTMR2** ([boot-events.md](boot-events.md)) |
| P2, the release (ADR-093) | the five checks passed for commit `16bafb3b19b3` and image `tc-img-rel-1`: the reference is of the commit, its source event is SHA-384 of the commit text, it is of this image, the dummy run equals it, and the root hash `b80370de63d9…` equals the `tc.verity=` value in RTMR2 (events 13, 15 and 17); `release.json` was written (SHA-256 `3daa43b2…`) and the image is labelled with the commit and the two halves of the root hash |
| The stops | the first try stopped in its first stage because a rehearsal that had never run in Cloud Shell was in the kit's list (limitations row 214, mistake 210); a later run lost its Cloud Shell session during a silent step (mistakes 211 and 212) and was resumed from the kit's progress files |

What this does not show: that a second party gets the same image (that is P4), the publication of `release.json` and the image (P3), the Intel signature chain and the WARC checks (P5), the 17 RTMR0 events (not tabulated), and whether the registers depend on the scratch disk (limitations row 212).
