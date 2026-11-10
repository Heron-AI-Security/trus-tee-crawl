#!/usr/bin/env python3
"""Test of r3_tls_honesty.evaluate with honest receipts (must pass) and with mutants, lying receipts (must be refused): a receipt that claims authentication that the evidence does not show must still fail check 8. Prints TLS-HONESTY-TEST-OK when every case behaves."""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__))); from r3_tls_honesty import evaluate
TS = 1000; GOOD = [{"not_before": 900, "not_after": 1100}, {"not_before": 800, "not_after": 1200}]; EXPIRED = [{"not_before": 100, "not_after": 900}, {"not_before": 800, "not_after": 1200}]
def rec(authenticated=True, chain="valid", hostname="match", cv=True, hm=True, dates=GOOD):
    return {"authenticated": authenticated, "chain": chain, "hostname": hostname}, {"chain_valid": cv, "hostname_matches": hm, "chain_validity": dates}
bad = []
def case(name, args, outcome, want, reason=None):
    got = evaluate(args[0], args[1], outcome, TS); ok = got[:3] == want and (reason is None or got[3] == reason)
    print("   %s %-92s honest/labels/strict = %s %s" % ("ok:  " if ok else "FAIL:", name, got[:3], ("reason: " + got[3]) if got[3] else ""))
    if not ok: bad.append(name)
print("== honest receipts: they pass the honesty rules, and only the authenticated one passes the strict rule")
case("authenticated, valid chain, hostname matches, dates enclose", rec(), True, (True, True, True), "")
case("not authenticated: the chain is expired (hostname matches)", rec(False, "expired", "match", False, True, EXPIRED), False, (True, True, False), "expired chain")
case("not authenticated: hostname not in the certificate (chain valid)", rec(False, "valid", "mismatch", True, False), False, (True, True, False), "hostname mismatch")
case("not authenticated: the chain comes from an untrusted issuer", rec(False, "untrusted", "match", False, True), False, (True, True, False), "untrusted chain")
case("not authenticated: expired and hostname mismatch", rec(False, "expired", "mismatch", False, False, EXPIRED), False, (True, True, False), "expired chain + hostname mismatch")
case("not authenticated: untrusted and hostname mismatch", rec(False, "untrusted", "mismatch", False, False), False, (True, True, False), "untrusted chain + hostname mismatch")
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
print("TLS-HONESTY-TEST-OK: %d cases" % 20 if not bad else "TLS-HONESTY-TEST-FAILED: %s" % bad); sys.exit(1 if bad else 0)
