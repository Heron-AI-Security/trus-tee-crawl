"""The honesty rules for the TLS facts of one receipt (part of check 8 of ops/verify-export.py), as plain functions so that they can be tested with mutants. Standard library only.

A receipt says whether its source was authenticated. The crawler records a source whose certificate does not validate with authenticated=false (certificate checking is off by design, ADR-002), so the verifier does not demand that every receipt be authenticated (ADR-106, the mentor's decision of 10 November 2026): it demands that no receipt LIES about it.
evaluate(validation, server, outcome_flag, fetch_ts) returns (honest, labels_ok, strict_ok, reason):
  honest     the flag is a bool, it equals the result of the receipt's own chain and hostname facts, the signed outcome says the same, and a receipt that claims authentication has certificate dates that enclose the fetch time
  labels_ok  the labels of the validation (chain: valid, expired, not_yet_valid or untrusted; hostname: match or mismatch) agree with the facts and with the dates ('expired' exactly when a date does not enclose the fetch time, 'valid' only when all do)
  strict_ok  the old, strict rule: authenticated, valid chain, hostname match, dates enclose (used only when TC_REQUIRE_AUTHENTICATED=1)
  reason     for a receipt that is not authenticated: why (expired chain, untrusted chain, chain not valid, hostname mismatch, or a combination); empty for an authenticated one"""
CHAINS = ("valid", "expired", "not_yet_valid", "untrusted"); HOSTS = ("match", "mismatch")   # the classes that the crawler writes (CustodyReceipt.java, validate())
def matrix(pairs):
    """Counts of the receipts by (chain class, hostname class): all 8 cells, zeros included, and the receipts with any other label as 'other'."""
    cells = {(c, h): 0 for c in CHAINS for h in HOSTS}; other = 0
    for c, h in pairs:
        if (c, h) in cells: cells[(c, h)] += 1
        else: other += 1
    return cells, other
def matrix_lines(cells, other):
    """The table that the report prints (without the info: prefix): chain classes down, hostname classes across."""
    n = sum(cells.values()) + other; w = max(len(c) for c in CHAINS); col = lambda h: sum(cells[(c, h)] for c in CHAINS)
    L = ["TLS breakdown of the %d receipts, by certificate chain (down) and hostname (across):" % n, "   %-*s %9s %9s %9s" % (w, "chain", "match", "mismatch", "total")]
    for c in CHAINS: L.append("   %-*s %9d %9d %9d" % (w, c, cells[(c, "match")], cells[(c, "mismatch")], cells[(c, "match")] + cells[(c, "mismatch")]))
    L.append("   %-*s %9d %9d %9d" % (w, "total", col("match"), col("mismatch"), n - other))
    if other: L.append("   receipts with another label: %d" % other)
    return L
def evaluate(validation, server, outcome_flag, fetch_ts):
    v = validation or {}; s = server or {}; claimed = v.get("authenticated"); cv = s.get("chain_valid") is True; hm = s.get("hostname_matches") is True
    dates = s.get("chain_validity") or []; enclose = bool(dates) and all(x["not_before"] <= fetch_ts <= x["not_after"] for x in dates)
    lab_c, lab_h = v.get("chain"), v.get("hostname")
    honest = isinstance(claimed, bool) and claimed == (cv and hm) and outcome_flag is claimed and (enclose or not claimed)
    labels = lab_c in CHAINS and lab_h in HOSTS and (lab_c == "valid") == cv and (lab_h == "match") == hm and (lab_c != "expired" or not enclose) and (lab_c != "not_yet_valid" or not enclose) and (lab_c != "valid" or enclose)
    strict = claimed is True and outcome_flag is True and cv and hm and enclose
    reason = ""
    if claimed is not True:
        parts = []
        if not cv: parts.append("expired chain" if lab_c == "expired" else "not yet valid chain" if lab_c == "not_yet_valid" else "untrusted chain" if lab_c == "untrusted" else "chain not valid")
        if not hm: parts.append("hostname mismatch")
        reason = " + ".join(parts) or "flag false although the facts are valid"
    return bool(honest), bool(labels), bool(strict), reason
