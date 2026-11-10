#!/usr/bin/env python3
"""run_tls_breakdown.py EVIDENCE_DIR [--run-name NAME] [--out DIR]: the breakdown of the TLS cases of a crawl, for every outcome of every round, in cases that exclude each other and add up to the total.
Read-only (it writes only NAME_tls_breakdown.md, .json, .csv and two pie charts as SVG into --out, default the evidence folder). Standard library only.
How an outcome is classified (the first rule that applies):
  1. the URL is plain http            -> C. plain HTTP: no TLS at all (whatever happened to the URL afterwards, including never attempted)
  2. a receipt exists (ACCEPTED)       -> A. authenticated, or B. not authenticated, by the receipt's own validation facts: expired chain, untrusted chain, hostname mismatch, or a combination
  3. the fetch ended in an SSL error   -> D. TLS handshake failed
  4. otherwise no TLS evidence was recorded because no page was stored -> E, by what the crawler reported: no connection, error status, robots.txt, not found, redirect or other status, truncated page, not attempted
Run: python3 run_tls_breakdown.py ~/evidence-k1a-f --run-name Test_Run_1K_URL_2026_11_09_Run_1"""
import collections, glob, json, os, re, sys, urllib.parse
def arg(n, d=None): a = sys.argv; return a[a.index(n) + 1] if n in a and a.index(n) + 1 < len(a) else d
CASES = [  # (code, group, label)
 ("A", "HTTPS page with a receipt", "A. TLS authenticated (valid chain, hostname matches, dates enclose the fetch)"),
 ("B1", "HTTPS page with a receipt", "B1. not authenticated: chain expired"),
 ("B2", "HTTPS page with a receipt", "B2. not authenticated: chain expired and hostname mismatch"),
 ("B3", "HTTPS page with a receipt", "B3. not authenticated: hostname not in the certificate (chain valid)"),
 ("B4", "HTTPS page with a receipt", "B4. not authenticated: chain from an untrusted issuer"),
 ("B5", "HTTPS page with a receipt", "B5. not authenticated: untrusted chain and hostname mismatch"),
 ("B6", "HTTPS page with a receipt", "B6. not authenticated: another combination"),
 ("C", "Plain HTTP", "C. plain HTTP URL: no TLS at all"),
 ("D", "TLS failed", "D. HTTPS: the TLS handshake failed"),
 ("E1", "No TLS evidence recorded", "E1. HTTPS: no connection (DNS failure, timeout, refused)"),
 ("E2", "No TLS evidence recorded", "E2. HTTPS: the server answered with an error status (page not stored)"),
 ("E3", "No TLS evidence recorded", "E3. HTTPS: refused by robots.txt (not fetched)"),
 ("E4", "No TLS evidence recorded", "E4. HTTPS: page not found (404 or 410)"),
 ("E5", "No TLS evidence recorded", "E5. HTTPS: redirect or another status (page not stored)"),
 ("E6", "No TLS evidence recorded", "E6. HTTPS: page truncated at the content limit (no receipt)"),
 ("E7", "No TLS evidence recorded", "E7. HTTPS: not attempted (dropped at the task timeout)"),
 ("E8", "No TLS evidence recorded", "E8. HTTPS: another fetch failure")]
LABEL = {c: l for c, _, l in CASES}; GROUP = {c: g for c, g, _ in CASES}
def classify(url, status, detail, receipt):
    """returns the code of the case; receipt is the receipt dict (or None)"""
    if urllib.parse.urlsplit(url).scheme != "https": return "C"
    if receipt is not None:
        v = (receipt.get("server") or {}).get("validation") or {}
        if v.get("authenticated") is True: return "A"
        ch, ho = v.get("chain"), v.get("hostname")
        if ch == "expired" and ho == "mismatch": return "B2"
        if ch == "expired": return "B1"
        if ch == "untrusted" and ho == "mismatch": return "B5"
        if ch == "untrusted": return "B4"
        if ch == "valid" and ho == "mismatch": return "B3"
        return "B6"
    d = str(detail or "").lower()
    if status == "NOT_ATTEMPTED": return "E7"
    if status == "TRUNCATED": return "E6"
    if status == "HTTP_STATUS": return "E5"
    if status == "NOT_FETCHED" or status not in ("ACCEPTED",):
        if re.search(r"ssl|tls|handshake|certificate|pkix", d): return "D"
        if "robots_denied" in d: return "E3"
        if re.search(r"notfound|fetch_gone", d) and "robots" not in d: return "E4"
        if re.search(r"unknownhost|timed out|sockettimeout|connection refused|no route|unreachable|connection reset|connect", d): return "E1"
        if "http code=" in d: return "E2"
    return "E8"
PALETTE = ["#2e7d32", "#c62828", "#ef6c00", "#f9a825", "#6a1b9a", "#ad1457", "#8d6e63", "#455a64", "#1565c0", "#00838f", "#7cb342", "#5d4037", "#78909c", "#9e9d24", "#d84315", "#4527a0", "#37474f"]
def pie_svg(title, items):
    """items: list of (label, count); a pure SVG pie with a legend; zero counts are left out"""
    import math
    items = [(l, c) for l, c in items if c > 0]; tot = sum(c for _, c in items) or 1; cx, cy, r = 190, 215, 150; h = max(430, 90 + 24 * len(items))
    out = ['<svg xmlns="http://www.w3.org/2000/svg" width="980" height="%d" viewBox="0 0 980 %d" font-family="Arial, Helvetica, sans-serif">' % (h, h), '<rect width="980" height="%d" fill="white"/>' % h, '<text x="20" y="32" font-size="20" font-weight="bold">%s</text>' % title.replace("&", "&amp;"), '<text x="20" y="54" font-size="13" fill="#444">%d in all</text>' % tot]
    a0 = -math.pi / 2
    for i, (l, c) in enumerate(items):
        col = PALETTE[i % len(PALETTE)]
        if len(items) == 1: out.append('<circle cx="%d" cy="%d" r="%d" fill="%s"/>' % (cx, cy, r, col))
        else:
            a1 = a0 + 2 * math.pi * c / tot; x0, y0, x1, y1 = cx + r * math.cos(a0), cy + r * math.sin(a0), cx + r * math.cos(a1), cy + r * math.sin(a1)
            out.append('<path d="M %d %d L %.2f %.2f A %d %d 0 %d 1 %.2f %.2f Z" fill="%s" stroke="white" stroke-width="1"/>' % (cx, cy, x0, y0, r, r, 1 if (a1 - a0) > math.pi else 0, x1, y1, col)); a0 = a1
        y = 84 + 24 * i
        out.append('<rect x="400" y="%d" width="14" height="14" fill="%s"/><text x="422" y="%d" font-size="13">%s: %d (%.1f %%)</text>' % (y - 12, col, y, l.replace("&", "&amp;"), c, 100.0 * c / tot))
    return "\n".join(out + ["</svg>"]) + "\n"
def main():
    if len(sys.argv) < 2 or sys.argv[1].startswith("--"): print(__doc__.split("\n")[0]); return 2
    E = os.path.expanduser(sys.argv[1]).rstrip("/"); m = re.match(r"evidence-(.+)-f$", os.path.basename(E)); name = arg("--run-name", m.group(1) if m else "run"); out = os.path.expanduser(arg("--out", E)); seg = os.path.join(E, "export", "tc", "crawl", "segments")
    outcomes = []; receipts = {}
    for f in sorted(glob.glob(os.path.join(seg, "*", "tc_receipts", "outcomes-*.jsonl"))): outcomes += [json.loads(l) for l in open(f, encoding="utf-8") if l.strip()]
    for f in sorted(glob.glob(os.path.join(seg, "*", "tc_receipts", "receipts-*.jsonl"))):
        for l in open(f, encoding="utf-8"):
            if l.strip(): r = json.loads(l); receipts[r["source_url"]] = r
    if not outcomes: print("TLS-BREAKDOWN-FAILED: no outcomes under %s" % seg); return 2
    cnt = collections.Counter(); hosts = collections.defaultdict(list); proto = collections.Counter(); cipher = collections.Counter()
    for o in outcomes:
        u = o.get("source_url", ""); r = receipts.get(u) if o.get("status") == "ACCEPTED" else None; c = classify(u, o.get("status"), o.get("detail"), r); cnt[c] += 1; hosts[c].append(urllib.parse.urlsplit(u).hostname or u)
        if r is not None: s = r.get("server") or {}; proto[s.get("protocol", "?")] += 1; cipher[s.get("cipher_suite", "?")] += 1
    total = sum(cnt.values()); assert total == len(outcomes); hs = sum(cnt[c] for c, g, _ in CASES if g == "HTTPS page with a receipt")
    rows = [(c, GROUP[c], LABEL[c], cnt[c]) for c, _, _ in CASES]; os.makedirs(out, exist_ok=True); base = os.path.join(out, name + "_tls_breakdown")
    L = ["# TLS breakdown of the run `%s`" % name, "", "Every outcome of every round is in exactly one case, so the cases add up to the total (%d outcomes). Made by `ops/perf/run_tls_breakdown.py` from the signed outcome records and the receipts." % total, "",
         "## 1. All outcomes", "", "| Case | Group | Count | Share of all outcomes |", "|---|---|---|---|"] + ["| %s | %s | %d | %.1f %% |" % (l, g, n, 100.0 * n / total) for c, g, l, n in rows if n] + ["| **Total** | | **%d** | 100.0 %% |" % total, "",
         "By group: " + "; ".join("%s %d (%.1f %%)" % (g, sum(n for c, gg, l, n in rows if gg == g), 100.0 * sum(n for c, gg, l, n in rows if gg == g) / total) for g in dict.fromkeys(g for _, g, _ in CASES)) + ".", "",
         "## 2. HTTPS pages with a receipt (%d)" % hs, "", "| Case | Count | Share of the pages with a receipt |", "|---|---|---|"] + ["| %s | %d | %.1f %% |" % (l, n, 100.0 * n / hs) for c, g, l, n in rows if g == "HTTPS page with a receipt" and n] + ["", "TLS protocol versions of those pages: " + (", ".join("%s %d" % kv for kv in proto.most_common()) or "none") + ".", "", "Cipher suites: " + (", ".join("%s %d" % kv for kv in cipher.most_common()) or "none") + ".", "",
         "## 3. The sources that were not authenticated", ""]
    na = [(c, h) for c, _, _ in CASES if c.startswith("B") for h in sorted(set(hosts[c]))]
    L += (["| Case | Host |", "|---|---|"] + ["| %s | %s |" % (c, h) for c, h in na]) if na else ["None."]
    L += ["", "## 4. Examples of the other cases (up to 5 hosts each)", "", "| Case | Hosts |", "|---|---|"] + ["| %s | %s |" % (c, ", ".join(sorted(set(hosts[c]))[:5])) for c, _, _ in CASES if cnt[c] and not c.startswith("B") and c != "A"] + ["", "## 5. How the cases are decided", "", "1. A URL that is not `https` is case C, whatever happened to it afterwards. 2. An `ACCEPTED` outcome has a receipt: authenticated (A), or not authenticated for the reason that the receipt's own validation facts give (B1 to B6). 3. An SSL, TLS, handshake or certificate error in the report of a failed fetch is case D. 4. All other outcomes stored no page, so no TLS evidence was recorded: no connection (E1), an error status (E2), robots.txt (E3), not found (E4), a redirect or another status (E5), a truncated page (E6), not attempted (E7), or another failure (E8). A receipt exists only for an ACCEPTED page; an HTTPS fetch that ended in an error status or a redirect did complete a handshake, but the crawler did not record its certificate, so it is E and not A or B.", ""]
    open(base + ".md", "w", encoding="utf-8", newline="\n").write("\n".join(L))
    json.dump({"run_name": name, "outcomes_total": total, "cases": {c: cnt[c] for c, _, _ in CASES}, "groups": {g: sum(n for c, gg, l, n in rows if gg == g) for g in dict.fromkeys(g for _, g, _ in CASES)}, "https_pages_with_receipt": hs, "tls_protocols": dict(proto), "cipher_suites": dict(cipher), "not_authenticated_hosts": [{"case": c, "host": h} for c, h in na]}, open(base + ".json", "w"), indent=1)
    open(base + ".csv", "w", encoding="utf-8", newline="\n").write("case,group,label,count,share_of_all_outcomes_percent,share_of_https_pages_with_receipt_percent\n" + "\n".join('%s,"%s","%s",%d,%.2f,%s' % (c, g, l, n, 100.0 * n / total, ("%.2f" % (100.0 * n / hs)) if g == "HTTPS page with a receipt" and hs else "") for c, g, l, n in rows) + "\n")
    open(base + "_all_outcomes.svg", "w", encoding="utf-8", newline="\n").write(pie_svg("TLS cases of all %d outcomes: %s" % (total, name), [(l.split(". ", 1)[0] + ". " + l.split(". ", 1)[1][:60], n) for c, g, l, n in rows]))
    open(base + "_https_pages.svg", "w", encoding="utf-8", newline="\n").write(pie_svg("HTTPS pages with a receipt: %s" % name, [(l.split(". ", 1)[0] + ". " + l.split(". ", 1)[1][:70], n) for c, g, l, n in rows if g == "HTTPS page with a receipt"]))
    print("\n".join(L[:22])); print("TLS-BREAKDOWN-DONE: %s{.md,.json,.csv,_all_outcomes.svg,_https_pages.svg}" % base); return 0
if __name__ == "__main__": sys.exit(main())
