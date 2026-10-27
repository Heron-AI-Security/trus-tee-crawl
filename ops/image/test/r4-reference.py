#!/usr/bin/env python3
"""Step R4.4: generate the REFERENCE VALUES of a commit from builds that agree, instead of copying what one running machine reported.
   python3 r4-reference.py --build DIR --build DIR [...] --commit ID [--platform reference-values.json] --out FILE [--allow-single]
Each DIR is the ground truth that r4-manifest.sh wrote on a builder (events.tsv and source.txt). The tool refuses unless: the commit is a full id; every build recorded exactly 'commit ID' (never 'commit none');
every build measured the same events in the same order with the same digests; there are at least two builds (--allow-single is for development only). The events become the stable events of the reference, followed
by the per-run events fleet and fleet-conf, as the nodes append them. MRTD and RTMR0 to RTMR2 are measured by the platform and by the sealed disk, so they cannot come from a build on a builder: with --platform
they are taken from the reference of a REAL run of the image, and then every stable event of that real run must equal the events of the independent builds (a real machine that measured something else than the
builds is refused). Without --platform the result is incomplete and says so (the verifier cannot enforce it). The verifier (f1-fleet.py enforce OUT REFERENCE COMMIT) then accepts only a fleet that was built
from the pinned commit. Standard library only. Exit code 0 only when every check held."""
import sys; sys.dont_write_bytecode = True
import argparse, hashlib, json, os, re

PER_RUN = ["fleet", "fleet-conf"]

def load_build(d):
    ev = []
    try:
        for line in open(os.path.join(d, "events.tsv"), encoding="utf-8"):
            p = line.rstrip("\n").split("\t")
            if len(p) >= 2: ev.append((p[0], p[1]))
        src = open(os.path.join(d, "source.txt"), encoding="utf-8").read()
    except OSError as e: raise ValueError("%s: %s" % (d, e))
    return ev, src

def main():
    ap = argparse.ArgumentParser(); ap.add_argument("--build", action="append", default=[]); ap.add_argument("--commit", required=True); ap.add_argument("--platform"); ap.add_argument("--out", required=True); ap.add_argument("--allow-single", action="store_true")
    a = ap.parse_args()
    def stop(m): print("R4-REFERENCE-FAILED: " + m); return 1
    if not re.fullmatch(r"[0-9a-f]{40}|[0-9a-f]{64}", a.commit): return stop("--commit must be a full commit id (40 or 64 lower-case hex characters), not '%s'" % a.commit)
    if len(a.build) < 2 and not a.allow_single: return stop("at least two builds are needed (%d given): one build proves nothing about reproducibility (--allow-single is for development only)" % len(a.build))
    if not a.build: return stop("no build given")
    builds = []
    for d in a.build:
        try: builds.append((d,) + load_build(d))
        except ValueError as e: return stop(str(e))
    want = "commit %s\n" % a.commit
    for d, ev, src in builds:
        if src != want: return stop("%s records '%s', not 'commit %s' (a development image or another commit is never a reference)" % (d, src.strip(), a.commit[:12] + "..."))
        if not ev: return stop("%s has no events" % d)
    d0, ev0, _ = builds[0]
    for d, ev, _ in builds[1:]:
        if [n for n, _ in ev] != [n for n, _ in ev0]: return stop("%s and %s measured different events or in a different order" % (d0, d))
        for (n, g0), (_, g1) in zip(ev0, ev):
            if g0 != g1: return stop("the builds %s and %s disagree on the event %s (%s... and %s...): the build is not reproducible" % (d0, d, n, g0[:16], g1[:16]))
    stable = dict(ev0); names = [n for n, _ in ev0]
    if "source" not in stable: return stop("the builds did not measure a source event")
    if stable["source"] != hashlib.sha384(want.encode()).hexdigest(): return stop("the source event of the builds is not the SHA-384 of 'commit %s...'" % a.commit[:12])
    if any(n in PER_RUN for n in names): return stop("the builds already hold a per-run event (%s): they must be images, not fleets" % [n for n in names if n in PER_RUN])
    ref = {"commit": a.commit, "events_in_order": names + PER_RUN, "stable_events": stable, "per_run_events": list(PER_RUN), "ci_builds": len(builds)}
    if a.platform:
        try: plat = json.load(open(a.platform, encoding="utf-8"))
        except (OSError, ValueError) as e: return stop("cannot read the platform reference %s (%s)" % (a.platform, e))
        for k in ("image", "machine_type", "mrtd", "rtmr0", "rtmr1", "rtmr2", "events_in_order", "stable_events", "per_run_events"):
            if k not in plat: return stop("the platform reference lacks %s" % k)
        if plat["events_in_order"] != ref["events_in_order"]: return stop("the real run measured other events (or in another order) than the independent builds: %s against %s" % (plat["events_in_order"][:4], ref["events_in_order"][:4]))
        for n in names:
            if plat["stable_events"].get(n) != stable[n]: return stop("the real run measured the event %s as %s..., the independent builds as %s...: the running image is not the image that the commit builds" % (n, str(plat["stable_events"].get(n))[:16], stable[n][:16]))
        if set(plat["stable_events"]) != set(stable): return stop("the real run and the builds do not have the same stable events")
        out = dict(plat); out.update(ref)
        out["note"] = plat.get("note", "") + " Step R4.4: the stable events were recomputed by %d independent builds of commit %s (r4-reference.py) and equal what the real run measured; MRTD and RTMR0 to RTMR2 are from the real run." % (len(builds), a.commit)
    else:
        out = dict(ref); out["incomplete"] = "MRTD and RTMR0 to RTMR2 are missing: they come from a real run of the image (--platform); the verifier cannot enforce this file"
    with open(a.out + ".part", "w", encoding="utf-8") as f: f.write(json.dumps(out, indent=2) + "\n")
    os.replace(a.out + ".part", a.out)
    print("R4-REFERENCE-OK: commit %s, %d events from %d agreeing build(s)%s; written to %s" % (a.commit[:12] + "...", len(names), len(builds), " and checked against the real run of %s" % plat["image"] if a.platform else "; INCOMPLETE (no platform values)", a.out))
    return 0

if __name__ == "__main__": sys.exit(main())
