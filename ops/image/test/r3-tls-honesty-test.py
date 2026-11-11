#!/usr/bin/env python3
"""Test of r3_tls_honesty.evaluate with honest receipts (must pass) and with mutants, lying receipts (must be refused): a receipt that claims authentication that the evidence does not show must still fail check 8. Prints TLS-HONESTY-TEST-OK when every case behaves."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from r3_tls_honesty import evaluate, matrix, matrix_lines, CHAINS, HOSTS
TS = 1000; GOOD = [{"not_before": 900, "not_after": 1100}, {"not_before": 800, "not_after": 1200}]; EXPIRED = [{"not_before": 100, "not_after": 900}, {"not_before": 800, "not_after": 1200}]
NOTYET = [{"not_before": 1100, "not_after": 1300}, {"not_before": 800, "not_after": 1200}]
def rec(authenticated=True, chain="valid", hostname="match", cv=True, hm=True, dates=GOOD):
    return {"authenticated": authenticated, "chain": chain, "hostname": hostname}, {"chain_valid": cv, "hostname_matches": hm, "chain_validity": dates}
bad = []; ncase = [0]
def case(name, args, outcome, want, reason=None):
    ncase[0] += 1; got = evaluate(args[0], args[1], outcome, TS); ok = got[:3] == want and (reason is None or got[3] == reason)
    print("   %s %-92s honest/labels/strict = %s %s" % ("ok:  " if ok else "FAIL:", name, got[:3], ("reason: " + got[3]) if got[3] else ""))
    if not ok: bad.append(name)
print("== honest receipts: they pass the honesty rules, and only the authenticated one passes the strict rule")
case("authenticated, valid chain, hostname matches, dates enclose", rec(), True, (True, True, True), "")
case("not authenticated: the chain is expired (hostname matches)", rec(False, "expired", "match", False, True, EXPIRED), False, (True, True, False), "expired chain")
case("not authenticated: hostname not in the certificate (chain valid)", rec(False, "valid", "mismatch", True, False), False, (True, True, False), "hostname mismatch")
case("not authenticated: the chain comes from an untrusted issuer", rec(False, "untrusted", "match", False, True), False, (True, True, False), "untrusted chain")
case("not authenticated: expired and hostname mismatch", rec(False, "expired", "mismatch", False, False, EXPIRED), False, (True, True, False), "expired chain + hostname mismatch")
case("not authenticated: untrusted and hostname mismatch", rec(False, "untrusted", "mismatch", False, False), False, (True, True, False), "untrusted chain + hostname mismatch")
case("not authenticated: the chain is not yet valid (hostname matches)", rec(False, "not_yet_valid", "match", False, True, NOTYET), False, (True, True, False), "not yet valid chain")
case("not authenticated: not yet valid and hostname mismatch", rec(False, "not_yet_valid", "mismatch", False, False, NOTYET), False, (True, True, False), "not yet valid chain + hostname mismatch")
print("== mutants: a receipt that lies must be refused")
case("LIE: claims authenticated, but its own chain facts say not valid (expired)", rec(True, "expired", "match", False, True, EXPIRED), True, (False, True, False))
case("LIE: claims authenticated, but the hostname does not match", rec(True, "valid", "mismatch", True, False), True, (False, True, False))
case("LIE: claims authenticated, the facts say valid, but a certificate date does not enclose the fetch", rec(True, "valid", "match", True, True, EXPIRED), True, (False, False, False))
case("LIE: claims authenticated, but there are no certificate dates at all", rec(True, "valid", "match", True, True, []), True, (False, False, False))
case("MISMATCH: the receipt says not authenticated but the signed outcome says authenticated", rec(False, "expired", "match", False, True, EXPIRED), True, (False, True, False))
case("MISMATCH: the receipt says authenticated but the signed outcome says not", rec(), False, (False, True, False))
case("UNDERSTATED: the receipt says not authenticated although every fact is valid", rec(False, "valid", "match", True, True), False, (False, True, False))
case("NOT A BOOL: the flag is the text true", rec("true"), True, (False, True, False))
case("NOT A BOOL: the flag is missing", ({"chain": "valid", "hostname": "match"}, rec()[1]), True, (False, True, False))
case("LABEL LIE: chain labelled valid while the facts say not valid", rec(False, "valid", "match", False, True), False, (True, False, False))
case("LABEL LIE: chain labelled expired while every date encloses the fetch", rec(False, "expired", "match", False, True), False, (True, False, False))
case("LABEL LIE: hostname labelled match while the facts say mismatch", rec(False, "valid", "match", True, False), False, (True, False, False))
case("LABEL LIE: an unknown label", rec(False, "fine", "match", False, True), False, (True, False, False))
case("LIE: claims authenticated, but its own chain facts say not valid (not yet valid)", rec(True, "not_yet_valid", "match", False, True, NOTYET), True, (False, True, False))
case("LABEL LIE: chain labelled not_yet_valid while every date encloses the fetch", rec(False, "not_yet_valid", "match", False, True), False, (True, False, False))
case("LABEL LIE: chain labelled not_yet_valid although the facts say valid", rec(False, "not_yet_valid", "match", True, True, NOTYET), False, (False, False, False))
print("== the breakdown table (4 chain classes by 2 hostname classes)")
def chk(name, ok):
    ncase[0] += 1; print("   %s %s" % ("ok:  " if ok else "FAIL:", name))
    if not ok: bad.append(name)
cells, other = matrix([("valid", "match")] * 3 + [("expired", "match")] * 2 + [("expired", "mismatch"), ("not_yet_valid", "match"), ("untrusted", "mismatch"), ("weird", "match")]); L = matrix_lines(cells, other)
chk("the table has all 8 cells, zeros included", len(cells) == 8 and set(cells) == {(c, h) for c in CHAINS for h in HOSTS})
chk("the counts are the hand-counted ones, and the receipt with an unknown label is counted apart", cells[("valid", "match")] == 3 and cells[("expired", "match")] == 2 and cells[("expired", "mismatch")] == 1 and cells[("not_yet_valid", "match")] == 1 and cells[("untrusted", "mismatch")] == 1 and cells[("valid", "mismatch")] == 0 and other == 1)
chk("the printed table names every chain class, says 9 receipts, and its total row is 8 (one receipt has another label)", all(any(x.strip().startswith(c) for x in L) for c in CHAINS) and "9 receipts" in L[0] and L[-2].split()[-1] == "8" and L[-1].endswith(": 1"))
print(("TLS-HONESTY-TEST-OK: %d cases" % ncase[0]) if not bad else "TLS-HONESTY-TEST-FAILED: %s" % bad); sys.exit(1 if bad else 0)
