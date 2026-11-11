#!/usr/bin/env python3
"""Step P5.7 (step 10 of ops/verify-export.py): the signed time of a run, checked offline.
   python3 verify_time_export.py EXPORT_DIR [PINNED_SERVERS_JSON]
Every fetch task of the crawl records signed Roughtime readings (tc-time-evidence/1) in tc_receipts/time-<attempt>.jsonl:
  start  request nonce = SHA-512("tc/time-start/v1" 0x00 canonical{attempt, nonce, seed})[:32]: asked before any fetch, so the fetches came after it
  end    request nonce = SHA-512("tc/time-end/v1" 0x00 canonical(receipt hashes))[:32]: asked after every receipt it names existed, because the nonce commits to them
Checked here, with nothing from the crawler's clock: every reading's delegation signature, response signature, delegation window and Merkle path under the PINNED key of its server
(ops/attested/sp/verify/time-servers.json: the verifier pins the keys, the crawler never supplies them); every request nonce is derived as specified; every reading lies in the files of its own task;
every task that has receipts has a start and an end reading; every receipt is named by an end reading of its own task; and every certificate of every authenticated receipt is valid across the whole signed
window [earliest start - radius, latest end + radius] (the signed time decides, not WARC-Date).
The signature check is the teammate's custody/roughtime.py, her canonical encoding, her definition of an authenticated receipt and her pinned keys, all copied unchanged into ops/attested/sp/ (see sp/SOURCE.txt).
The loop around them follows her verify/_common.py time_evidence() line by line, with one deliberate difference, which a crawl without a challenge nonce needs (every nonce is null): see sp/SOURCE.txt.
Exit code 0: every check passed. 1: a check failed. 3: this export holds no signed time evidence, so nothing was checked."""
import base64, glob, hashlib, json, os, re, sys, datetime
HERE = os.path.dirname(os.path.abspath(__file__)); SP = os.path.join(HERE, "sp"); PINNED = os.path.join(SP, "verify", "time-servers.json")
PASS, FAIL, NOTC = "PASS", "FAIL", "NOT CHECKED"
def _modules():
    if SP not in sys.path: sys.path.insert(0, SP)
    from custody import canonical, roughtime, source_receipt as sr
    return canonical, roughtime, sr
def validity_in_window(validity, window):
    """(ok, detail): every certificate valid for the whole signed window (the same rule as the teammate's verify/_common.py)."""
    lo, hi = window
    for i, v in enumerate(validity):
        if not (v["not_before"] <= lo and hi <= v["not_after"]): return False, "CERT_NOT_VALID_IN_TRUSTED_WINDOW: certificate %d valid %s..%s" % (i, v["not_before"], v["not_after"])
    return True, "all %d certificates valid across the signed window" % len(validity)
def tasks(export):
    out = {}
    for f in sorted(glob.glob(os.path.join(export, "tc", "crawl", "segments", "*", "tc_receipts", "*.jsonl"))):
        m = re.match(r"(time|receipts|outcomes)-(.+)\.jsonl$", os.path.basename(f))
        if m: out.setdefault(m.group(2), {"time": [], "receipts": [], "outcomes": []})[m.group(1)].append(f)
    return out
def lines(path): return [l for l in open(path, "rb").read().split(b"\n") if l]
def fmt(t): return datetime.datetime.fromtimestamp(t, datetime.timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
def check(export, pinned_path=None):
    """(status, lines) for the export folder."""
    if not os.path.isdir(export): return FAIL, ["there is no export folder %s" % export]
    T = tasks(export)
    if not any(v["time"] for v in T.values()):
        return NOTC, ["this export holds no signed time evidence (the crawl ran with tc.time.enabled=false, or it is the export of an older run)"]
    canonical, roughtime, sr = _modules()
    try: pinned = json.load(open(pinned_path or PINNED))["servers"]
    except (OSError, ValueError, KeyError) as e: return FAIL, ["the pinned servers file cannot be read (%s: %s): this is a FAIL, not a pass" % (type(e).__name__, e)]
    bad = []; starts = []; ends = []; nread = 0; servers = set(); nonces = set(); covered = {}; ntask = 0
    for att, v in sorted(T.items()):
        recs = []
        for f in v["time"]:
            for l in lines(f):
                try: t = canonical.decode(l)
                except Exception as e: bad.append("%s: TIME_EVIDENCE_MALFORMED: a line cannot be decoded (%s)" % (att, type(e).__name__)); continue
                recs.append(t)
        if not recs:
            if v["receipts"]: bad.append("%s: TIME_EVIDENCE_MISSING: the task has receipts but no signed time reading" % att)
            continue
        ntask += 1; phases = set(); cov = covered.setdefault(att, set())
        for t in recs:
            try:
                if not isinstance(t, dict) or t.get("version") != "tc-time-evidence/1" or t.get("phase") not in ("start", "end"): raise ValueError("TIME_EVIDENCE_MALFORMED")
                if t.get("attempt") != att: raise ValueError("TIME_EVIDENCE_FOR_ANOTHER_RUN: the reading is for task %s but lies in the files of task %s" % (t.get("attempt"), att))
                nonces.add(json.dumps(t.get("nonce")))
                if t["server"] not in pinned: raise ValueError("TIME_SERVER_NOT_PINNED: " + str(t["server"]))
                if t["phase"] == "start": domain, inp = "tc/time-start/v1", canonical.encode({"attempt": t["attempt"], "nonce": t["nonce"], "seed": t["seed"]})
                else: domain, inp = "tc/time-end/v1", canonical.encode(t["receipts"])
                want = hashlib.sha512(domain.encode() + b"\x00" + inp).digest()[:32]
                if t["request_nonce"] != want.hex(): raise ValueError("TIME_REQUEST_NONCE_NOT_DERIVED")
                try: midp, radi = roughtime.verify(base64.b64decode(t["response"]), want, base64.b64decode(pinned[t["server"]]))
                except roughtime.RoughtimeError as e: raise ValueError(str(e))
            except ValueError as e: bad.append("%s %s: %s" % (att, (t.get("phase") if isinstance(t, dict) else "?"), e)); continue
            except Exception as e: bad.append("%s: TIME_EVIDENCE_MALFORMED: %s: %s" % (att, type(e).__name__, e)); continue
            nread += 1; servers.add(t["server"]); phases.add(t["phase"])
            if t["phase"] == "start": starts.append(midp - radi)
            else: ends.append(midp + radi); cov.update(t["receipts"])
        if phases and phases != {"start", "end"}: bad.append("%s: TIME_EVIDENCE_INCOMPLETE: need a start and an end reading" % att)
    for att, v in sorted(T.items()):   # one nonce value in the whole run, and every receipt is named by an end reading of its own task
        for f in v["outcomes"] + v["receipts"]:
            for l in lines(f):
                try: nonces.add(json.dumps(json.loads(l).get("nonce")))
                except ValueError: pass
        for f in v["receipts"]:
            for l in lines(f):
                if att in covered and "sha256:" + hashlib.sha256(l).hexdigest() not in covered[att]:
                    try: u = json.loads(l).get("source_url", "?")
                    except ValueError: u = "?"
                    bad.append("%s: RECEIPT_NOT_COVERED_BY_END_READING: %s" % (att, u))
    if len(nonces) > 1: bad.append("TIME_EVIDENCE_FOR_ANOTHER_RUN: the records of this export do not carry one collection nonce (%s)" % ", ".join(sorted(nonces)[:3]))
    if bad: return FAIL, bad[:6] + (["... and %d more" % (len(bad) - 6)] if len(bad) > 6 else [])
    if not starts or not ends: return FAIL, ["TIME_EVIDENCE_INCOMPLETE: need a start and an end reading"]
    lo, hi = min(starts), max(ends); nrec = nauth = nok = 0; certbad = []
    for att, v in sorted(T.items()):
        for f in v["receipts"]:
            for l in lines(f):
                nrec += 1
                try: s = sr.from_bytes(l); a = sr.authentication(s)[0]
                except Exception as e: certbad.append("%s: RECEIPT_MALFORMED: %s: %s" % (att, type(e).__name__, e)); continue
                if a == "authenticated":
                    nauth += 1; ok, why = validity_in_window(s.server["chain_validity"], (lo, hi))
                    if ok: nok += 1
                    else: certbad.append("%s: %s: %s" % (att, s.source_url, why))
    if certbad: return FAIL, certbad[:6] + (["... and %d more" % (len(certbad) - 6)] if len(certbad) > 6 else [])
    return PASS, ["%d reading(s) of %d task(s) from %s: every delegation and response signature and Merkle path verifies under the pinned key of the server, and every request nonce is derived as specified" % (nread, ntask, ", ".join(sorted(servers))),
                  "signed window %s .. %s (%d s): given by the time server(s), not by the crawler's clock" % (fmt(lo), fmt(hi), hi - lo),
                  "%d receipt(s), each named by an end reading of its own task; %d authenticated, %d with every certificate valid across the whole window (the signed time decides, not WARC-Date)" % (nrec, nauth, nok)]
def main(argv):
    if not argv or len(argv) > 2: print(__doc__.split("\n")[1]); return 2
    st, ls = check(argv[0].rstrip("/"), argv[1] if len(argv) > 1 else None)
    for l in ls: print("   " + l)
    print({PASS: "TIME-OK", FAIL: "TIME-FAILED", NOTC: "TIME-NOT-CHECKED"}[st]); return {PASS: 0, FAIL: 1, NOTC: 3}[st]
if __name__ == "__main__": sys.exit(main(sys.argv[1:]))
