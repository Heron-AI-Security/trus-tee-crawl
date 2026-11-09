# Benchmark seed lists (1K / 10K / 100K / 1M)

`seeds-1m.txt` holds 1,000,000 URLs from the Common Crawl **CC-MAIN-2026-39** Parquet URL index (`cc-index-table`, `subset=warc`). Every smaller benchmark list is a prefix of it, so the file is committed once and the other lists are derived from it.

| List | URLs | Hosts | SHA-256 | How to get it |
|---|---:|---:|---|---|
| seeds-1k.txt | 1,000 | 997 | `50ede1c0de016ce2204152a927b1c01ecf00fbec785ceac387c6a3f015a680e6` | `head -n 1000 seeds-1m.txt` |
| seeds-10k.txt | 10,000 | 9,638 | `d76338f95cb1814fed91c757c933decb8d121a5444743029054a55c9b855b71f` | `head -n 10000 seeds-1m.txt` |
| seeds-100k.txt | 100,000 | 60,025 | `f6fa21ded7ce4274c9c3617ad08e93bc774ce036dbea4aa6f37c37987390b9a1` | `head -n 100000 seeds-1m.txt` |
| seeds-1m.txt | 1,000,000 | 591,500 | `28f4f194fb6186f981653fba2e73ccc48559c7090d21aa164d80386c3b68b4dc` | this file |

## Fleet lists

The baked crawl (`ops/image/rootfs/usr/local/lib/tc/tc-crawl.sh`) accepts only plain addresses matching `^https?://[A-Za-z0-9./:_-]+$`. The fleet list of any size is that size's list filtered by this rule:

```bash
head -n 1000 seeds-1m.txt | grep -E '^https?://[A-Za-z0-9./:_-]+$' > seeds-1k-fleet.txt
```

| Fleet list | URLs | SHA-256 |
|---|---:|---|
| seeds-1k-fleet.txt | 908 | `b8f684871b418faa6da84652acf48ed146b57875f5b2f464cd792e09f2a5aa4a` |
| seeds-10k-fleet.txt | 9,053 | `2b5b058568cdc0704969a637db7f006a45060888d1df2b8468b7ba102fac8fda` |
| seeds-100k-fleet.txt | 90,686 | `d46966eb26880002fa99b0f6ea2a27f82f9af5abd632891a0668a42b39f6018e` |
| seeds-1m-fleet.txt | 911,385 | `aaad962947e93edeb74b62a901ae4fc79fa185f2816cfeecb9cbb27dcddbb7a4` |

The 1M run (image `tc-img-1m-3`, branch `1m-run`) baked `seeds-1m-fleet.txt` as `ops/image/rootfs/etc/tc/crawl/seeds.txt`. This PR does **not** change the baked seeds on main.

## How the list was made

- **First 100,000 URLs:** the existing 100K list, unchanged. It was sampled earlier from the CDX index of the same crawl.
- **Remaining 900,000 URLs:** from `tools/gen_1m.py`, with seed `20261022`:
  1. For each of the 300 `subset=warc` Parquet files, read one row group, chosen by `Random(seed + file index)`. Only 4 columns are read, over HTTP range requests (`tools/rangefile.py`).
  2. Keep a row only if it has fetch status 200, detected MIME `text/html`, is not `/robots.txt`, is http(s), and has no space or quote characters. Keep at most 2 URLs per host.
  3. Exclude the hosts already in the 100K list. Rank the remaining hosts by `SHA-256("20261022|host")`, take their URLs in that order up to 900,000, shuffle them with `Random(seed + 1)`, and append them.

The run read 426,281,139 index rows (5.4 GB). It produced 12,774,272 candidates over 7,331,647 hosts. `seeds-1m.meta.json` records every file and row group read, the manifest's SHA-256 and all counts.

To regenerate (requires `pyarrow`; resumable; stops for good on an HTTP 403, it never works around a block):

```bash
python tools/gen_1m.py cc-index-table.paths.gz seeds-100k.txt out/
```

## Checks done

- 1,000,000 lines, no duplicates, at most 2 URLs per host.
- The 1K/10K/100K lists are exact prefixes.
- The domain and https mix match the 100K list.
- Every hash above was recomputed from `seeds-1m.txt` with the commands shown.
