#!/usr/bin/env python3
"""Step P2: tie a commit to an image and write release.json.
  python3 ops/make-release.py --commit COMMIT --image IMAGE --root-hash HASH --run RUNDIR --reference REFERENCE_JSON --out DIR [--apply-labels]
It checks, and stops at the first failure: (1) the reference is of this commit; (2) its `source` event is SHA-384 of "commit <id>\\n" (the image was built from this commit); (3) the reference is of this image; (4) the dummy run equals the reference (ops/reference-compare.py);
(5) the dm-verity root hash that the dummy run's RTMR2 events carry (tc.verity= on the kernel command line) equals --root-hash. Then it writes release.json (commit, image, root hash, the SHA-256 of the reference file, the settings of the dummy run)
and, with --apply-labels, labels the image: commit=<40 digits>, verity-a and verity-b = the two halves of the root hash (a label value is limited to 63 characters and the root hash has 64).
TC_GCLOUD names the gcloud command (for tests)."""
import argparse, hashlib, importlib.util, json, os, re, subprocess, sys, time
HERE = os.path.dirname(os.path.abspath(__file__))
def stop(m): print("RELEASE-FAILED: " + m); sys.exit(1)
def main():
    ap = argparse.ArgumentParser(); [ap.add_argument("--" + k, required=True) for k in ("commit", "image", "root-hash", "run", "reference", "out")]; ap.add_argument("--apply-labels", action="store_true"); a = ap.parse_args()
    root = a.root_hash.lower()
    if not re.fullmatch(r"[0-9a-f]{64}", root): stop("the root hash must be 64 lowercase hexadecimal digits")
    if not re.fullmatch(r"[0-9a-f]{7,40}", a.commit): stop("the commit must be 7 to 40 lowercase hexadecimal digits")
    if not re.fullmatch(r"[a-z]([-a-z0-9]{0,61}[a-z0-9])?", a.image): stop("the image name is not a GCE image name")
    for f in (a.reference, a.run + "/settings.json", a.run + "/image.json"):
        if not os.path.isfile(f): stop("the file is missing: " + f)
    ref = json.load(open(a.reference, encoding="utf-8")); full = str(ref.get("commit", ""))
    if not re.fullmatch(r"[0-9a-f]{40}", full): stop("the reference does not name a full commit id")
    if not full.startswith(a.commit): stop("the reference is of commit %s, not of %s" % (full[:12], a.commit)); 
    print("1. the reference is of commit %s" % full[:12])
    want = hashlib.sha384(("commit %s\n" % full).encode()).hexdigest()
    if (ref.get("stable_events") or {}).get("source") != want: stop("the `source` event of the reference is not SHA-384 of 'commit %s': the image was not built from this commit" % full[:12])
    print("2. the source event is SHA-384 of 'commit <id>': the image was built from this commit")
    if ref.get("image") != a.image: stop("the reference is of image %s, not of %s" % (ref.get("image"), a.image))
    print("3. the reference is of image %s" % a.image)
    r = subprocess.run([sys.executable, os.path.join(HERE, "reference-compare.py"), a.run, a.reference], capture_output=True, text=True)
    if r.returncode != 0: print(r.stdout[-900:]); stop("the dummy run does not equal the reference")
    print("4. the dummy run equals the reference (MRTD, RTMR0 to RTMR2, all stable events, debug bit off)")
    spec = importlib.util.spec_from_file_location("ccel_table", os.path.join(HERE, "ccel-table.py")); ct = importlib.util.module_from_spec(spec); spec.loader.exec_module(ct)
    try: events, _ = ct.load(a.run)
    except (FileNotFoundError, ValueError) as e: stop("the boot event log cannot be read: %s" % e)
    vh = ct.verity_hashes(events)
    if not vh: stop("no RTMR2 event carries tc.verity=: the root hash cannot be tied to the quote")
    if any(h != root for k, h in vh): stop("the RTMR2 events carry the root hash %s, not %s" % ([h[:16] + "..." for k, h in vh], root[:16] + "..."))
    print("5. the root hash equals the tc.verity= value in RTMR2 (event %d)" % vh[0][0])
    settings = json.load(open(a.run + "/settings.json")); image = json.load(open(a.run + "/image.json")); labels = {"commit": full, "verity-a": root[:32], "verity-b": root[32:]}
    rel = {"schema": 1, "commit": full, "image": a.image, "image_id": image.get("id"), "verity_root_hash": root, "reference_file": os.path.basename(a.reference), "reference_sha256": hashlib.sha256(open(a.reference, "rb").read()).hexdigest(),
           "dummy_run_settings": settings, "image_labels": labels, "created_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
    os.makedirs(a.out, exist_ok=True); open(a.out + "/release.json", "w").write(json.dumps(rel, indent=2) + "\n"); print("6. release.json written to %s" % a.out)
    if a.apply_labels:
        gc = os.environ.get("TC_GCLOUD", "gcloud"); lab = ",".join("%s=%s" % kv for kv in labels.items())
        r = subprocess.run([gc, "compute", "images", "add-labels", a.image, "--labels=" + lab], capture_output=True, text=True)
        if r.returncode != 0: stop("the image could not be labelled: " + r.stderr[-300:])
        d = subprocess.run([gc, "compute", "images", "describe", a.image, "--format=json"], capture_output=True, text=True)
        try: got = json.loads(d.stdout).get("labels", {})
        except ValueError: got = {}
        if any(got.get(k) != v for k, v in labels.items()): stop("the labels of the image are not what was set: %s" % got)
        print("7. the image is labelled: commit, verity-a, verity-b")
    print("RELEASE-OK commit=%s image=%s" % (full[:12], a.image))
main()
