#!/usr/bin/env bash
# Step R4.4 rehearsal (no cloud, seconds): the reference values of a commit are generated from builds that agree, and every fault is refused. The result is also fed to the REAL verifier (f1-fleet.py): its
# consistency rule for a reference that names a commit must accept what this tool writes.   bash r4f-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; T="$K/ops/image/test"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "   ok:   $1"; P=$((P+1)); else echo "   FAIL: $1"; F=$((F+1)); fi; }
say() { echo; echo "== $*"; }
C=cafe0000cafe0000cafe0000cafe0000cafe0000
H="$(python3 -c "import hashlib; print(hashlib.sha384(b'commit $C\n').hexdigest())")"
mkbuild() { # $1 dir, $2 commit line, $3 digest of tc-conf
  mkdir -p "$W/$1"; printf '%s\n' "$2" > "$W/$1/source.txt"; printf 'source\t%s\t1\tfile\t/etc/tc/source.txt\t\ntc-lib\t%s\t20\tdir\t/usr/local/lib/tc\t\ntc-conf\t%s\t24\tdir\t/etc/tc\tskipme\njdk\t%s\t335\tdir\t/usr/lib/jvm\t\n' "$H" "$(printf 'a%.0s' $(seq 96))" "$3" "$(printf 'b%.0s' $(seq 96))" > "$W/$1/events.tsv"
}
CONF="$(printf 'c%.0s' $(seq 96))"; mkbuild a "commit $C" "$CONF"; mkbuild b "commit $C" "$CONF"
python3 - "$W/plat.json" "$H" "$CONF" <<'PYEOF'
import json, sys
h, conf = sys.argv[2], sys.argv[3]
json.dump({"image": "tc-img-test", "machine_type": "c3-standard-4", "note": "platform note.", "mrtd": "1" * 96, "rtmr0": "2" * 96, "rtmr1": "3" * 96, "rtmr2": "4" * 96, "events_in_order": ["source", "tc-lib", "tc-conf", "jdk", "fleet", "fleet-conf"], "stable_events": {"source": h, "tc-lib": "a" * 96, "tc-conf": conf, "jdk": "b" * 96}, "per_run_events": ["fleet", "fleet-conf"]}, open(sys.argv[1], "w"))
PYEOF
say "two agreeing builds and the platform values of a real run"
out="$(python3 "$T/r4-reference.py" --build "$W/a" --build "$W/b" --commit $C --platform "$W/plat.json" --out "$W/ref.json" 2>&1)"; rc=$?
[ $rc = 0 ] && grep -q "^R4-REFERENCE-OK: commit cafe0000cafe\.\.\., 4 events from 2 agreeing build(s) and checked against the real run of tc-img-test" <<<"$out" && chk "two agreeing builds plus a real run give the reference values (R4-REFERENCE-OK)" ok || chk "the reference was not made: $out" no
python3 - "$W/ref.json" "$C" "$H" > "$W/props.txt" 2>&1 <<'PYEOF'
import hashlib, json, sys
d = json.load(open(sys.argv[1])); c, h = sys.argv[2], sys.argv[3]; ok = lambda m, x: print(("PASS " if x else "FAIL ") + m)
ok("the commit is named", d["commit"] == c)
ok("the stable events are the builds' events, and the per-run events follow in the order list", d["stable_events"]["tc-conf"] == "c" * 96 and d["events_in_order"] == ["source", "tc-lib", "tc-conf", "jdk", "fleet", "fleet-conf"] and d["per_run_events"] == ["fleet", "fleet-conf"])
ok("the platform values come from the real run (MRTD and RTMR0 to RTMR2) and the image and machine type are kept", d["mrtd"] == "1" * 96 and d["rtmr2"] == "4" * 96 and d["image"] == "tc-img-test" and d["machine_type"] == "c3-standard-4")
ok("the number of builds is recorded and the note says where each part comes from", d["ci_builds"] == 2 and "independent builds of commit" in d["note"] and d["note"].startswith("platform note."))
ok("the source event is the SHA-384 of the commit line (the rule of the verifier)", d["stable_events"]["source"] == hashlib.sha384(("commit %s\n" % c).encode()).hexdigest())
PYEOF
[ "$(grep -c '^PASS' "$W/props.txt")" = 5 ] && chk "all 5 properties of the reference hold (commit, events and order, platform values, the number of builds, the source digest)" ok || chk "a property failed: $(grep FAIL "$W/props.txt" | tr '\n' '|')$(head -c 200 "$W/props.txt")" no
say "the REAL verifier reads it (its consistency rule for a reference that names a commit)"
mkdir -p "$W/run"; printf '# a run folder whose fleet.tsv has no rows: the verifier loads the reference first and stops at the rows\n' > "$W/run/fleet.tsv"; out="$(python3 "$K/ops/image/test/f1-fleet.py" enforce "$W/run" "$W/ref.json" "$C" 2>&1)"; grep -q 'fleet.tsv has no rows' <<<"$out" && chk "the verifier loads the reference and gets past it (it stops only at the empty fleet.tsv: the commit, the source digest and the keys are consistent)" ok || chk "the verifier rejected the reference: $out" no
python3 - "$W/ref.json" "$W/ref-bad.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d["stable_events"]["source"] = "9" * 96; json.dump(d, open(sys.argv[2], "w"))
PYEOF
out="$(python3 "$K/ops/image/test/f1-fleet.py" enforce "$W/run" "$W/ref-bad.json" "$C" 2>&1)"; grep -q 'the reference values are inconsistent' <<<"$out" && chk "control: the same reference with a changed source digest IS rejected by the verifier (the test above is not vacuous)" ok || chk "the verifier accepted a tampered reference: $out" no
say "faults: each must be refused, and nothing is written"
rf() { rm -f "$W/o.json"; out="$(python3 "$T/r4-reference.py" "$@" --out "$W/o.json" 2>&1)"; rc=$?; }
rf --build "$W/a" --commit $C; [ $rc = 1 ] && grep -q 'at least two builds are needed (1 given)' <<<"$out" && [ ! -e "$W/o.json" ] && chk "fault: one build is refused (one build proves nothing about reproducibility)" ok || chk "one build accepted: $out" no
rf --build "$W/a" --commit $C --allow-single; [ $rc = 0 ] && grep -q 'INCOMPLETE' <<<"$out" && python3 -c 'import json,sys; sys.exit(0 if "incomplete" in json.load(open(sys.argv[1])) else 1)' "$W/o.json" && chk "development only: --allow-single works and the result says that it is INCOMPLETE (no platform values)" ok || chk "allow-single behaves wrongly: $out" no
mkbuild c "commit $C" "$(printf 'd%.0s' $(seq 96))"; rf --build "$W/a" --build "$W/c" --commit $C; [ $rc = 1 ] && grep -q 'disagree on the event tc-conf' <<<"$out" && grep -q 'not reproducible' <<<"$out" && [ ! -e "$W/o.json" ] && chk "fault: two builds that disagree on one event are refused, the event is named, and nothing is written" ok || chk "disagreement not caught: $out" no
mkbuild d "commit 1234567890123456789012345678901234567890" "$CONF"; rf --build "$W/a" --build "$W/d" --commit $C; [ $rc = 1 ] && grep -q "records 'commit 1234567890123456789012345678901234567890'" <<<"$out" && chk "fault: a build of another commit is refused" ok || chk "other commit not caught: $out" no
mkbuild e "commit none" "$CONF"; rf --build "$W/a" --build "$W/e" --commit $C; [ $rc = 1 ] && grep -q "records 'commit none'" <<<"$out" && chk "fault: a development build ('commit none') is never a reference" ok || chk "commit none not caught: $out" no
rf --build "$W/a" --build "$W/b" --commit cafe0000; [ $rc = 1 ] && grep -q 'full commit id' <<<"$out" && chk "fault: a short commit is refused here (the reference names the full id)" ok || chk "short commit accepted" no
mkdir -p "$W/f"; cp "$W/b/source.txt" "$W/f/"; printf 'tc-conf\t%s\t24\tdir\t/etc/tc\t\nsource\t%s\t1\tfile\t/x\t\ntc-lib\t%s\t20\tdir\t/y\t\njdk\t%s\t1\tdir\t/z\t\n' "$CONF" "$H" "$(printf 'a%.0s' $(seq 96))" "$(printf 'b%.0s' $(seq 96))" > "$W/f/events.tsv"; rf --build "$W/a" --build "$W/f" --commit $C; [ $rc = 1 ] && grep -q 'different events or in a different order' <<<"$out" && chk "fault: builds that measured the events in a different order are refused" ok || chk "order not caught: $out" no
python3 - "$W/plat.json" "$W/plat-bad.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); d["stable_events"]["tc-conf"] = "e" * 96; json.dump(d, open(sys.argv[2], "w"))
PYEOF
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/plat-bad.json"; [ $rc = 1 ] && grep -q 'the real run measured the event tc-conf' <<<"$out" && grep -q 'not the image that the commit builds' <<<"$out" && [ ! -e "$W/o.json" ] && chk "fault: a real run that measured an event differently from the independent builds is refused (the running image is not the commit's image)" ok || chk "platform mismatch not caught: $out" no
python3 - "$W/plat.json" "$W/plat-short.json" <<'PYEOF'
import json, sys
d = json.load(open(sys.argv[1])); del d["rtmr2"]; json.dump(d, open(sys.argv[2], "w"))
PYEOF
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/plat-short.json"; [ $rc = 1 ] && grep -q 'platform reference lacks rtmr2' <<<"$out" && chk "fault: a platform reference without its registers is refused" ok || chk "short platform accepted" no
mkdir -p "$W/g"; cp "$W/a/source.txt" "$W/g/"; sed "s/^source\t$H/source\t$(printf '9%.0s' $(seq 96))/" "$W/a/events.tsv" > "$W/g/events.tsv"; mkdir -p "$W/g2"; cp "$W/g/"* "$W/g2/"; rf --build "$W/g" --build "$W/g2" --commit $C; [ $rc = 1 ] && grep -q 'the source event of the builds is not the SHA-384' <<<"$out" && chk "fault: builds whose source event does not match their own commit line (two builds that agree on a wrong source event) are refused" ok || chk "wrong source digest not caught: $out" no
python3 - "$W/plat.json" "$W/plat-order.json" <<'PYEOF2'
import json, sys
d = json.load(open(sys.argv[1])); d["events_in_order"] = ["tc-lib", "source", "tc-conf", "jdk", "fleet", "fleet-conf"]; json.dump(d, open(sys.argv[2], "w"))
PYEOF2
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/plat-order.json"; [ $rc = 1 ] && grep -q 'the real run measured other events (or in another order)' <<<"$out" && chk "fault: a real run that measured the same events in another order is refused (the order is part of RTMR3)" ok || chk "order mismatch not caught: $out" no
rf --build "$W/nonexistent" --build "$W/b" --commit $C; [ $rc = 1 ] && grep -q 'nonexistent' <<<"$out" && chk "fault: a missing build folder is refused with its name" ok || chk "missing folder not caught: $out" no
say "a LOCKED image: the real run measures only the events that are left (work item, change 2); the builds measure more"
python3 - "$W/plat.json" "$W" "$H" <<'PYEOF3'
import json, sys
d = json.load(open(sys.argv[1])); w, h = sys.argv[2], sys.argv[3]
def mk(name, order, stable):
    x = dict(d); x["events_in_order"] = order; x["stable_events"] = stable; json.dump(x, open("%s/%s.json" % (w, name), "w"))
mk("lplat", ["source", "fleet", "fleet-conf"], {"source": h})
mk("lplat-extra", ["source", "zzz", "fleet", "fleet-conf"], {"source": h, "zzz": "e" * 96})
mk("lplat-src", ["source", "fleet", "fleet-conf"], {"source": "9" * 96})
mk("lplat-order", ["fleet", "source", "fleet-conf"], {"source": h})
mk("lplat-nosrc", ["tc-lib", "fleet", "fleet-conf"], {"tc-lib": "a" * 96})
mk("lplat-two", ["tc-lib", "source", "fleet", "fleet-conf"], {"source": h, "tc-lib": "a" * 96})
PYEOF3
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/lplat.json" --locked; [ $rc = 0 ] && grep -q "^R4-REFERENCE-OK: commit cafe0000cafe\.\.\., 1 events from 2 agreeing build(s)" <<<"$out" && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d["events_in_order"]==["source","fleet","fleet-conf"] and list(d["stable_events"])==["source"] and d["rtmr2"]=="4"*96 and d["ci_builds"]==2 and "Locked image" in d["note"] and "tc-lib, tc-conf, jdk" in d["note"] and d["note"].startswith("platform note.") else 1)' "$W/o.json" && chk "a locked run (only the source event left) against two agreeing builds with 4 events: the reference has the run's events and order, the platform values of the run, and a note that names the 3 events covered by the root" ok || chk "the locked reference was not made right: $out" no
cp "$W/o.json" "$W/lref.json"; out="$(python3 "$K/ops/image/test/f1-fleet.py" enforce "$W/run" "$W/lref.json" "$C" 2>&1)"; grep -q 'fleet.tsv has no rows' <<<"$out" && chk "the REAL verifier reads the locked reference and gets past it (it stops only at the empty fleet.tsv)" ok || chk "the verifier did not accept the locked reference: $out" no
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/lplat.json"; [ $rc = 1 ] && grep -q 'the real run measured other events (or in another order)' <<<"$out" && [ ! -e "$W/o.json" ] && chk "control: the same locked run WITHOUT --locked is refused, as before (the two lists must be the same)" ok || chk "a locked run was accepted without --locked: $out" no
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/lplat-extra.json" --locked; [ $rc = 1 ] && grep -q "the real run measured events that the independent builds did not measure: \['zzz'\]" <<<"$out" && [ ! -e "$W/o.json" ] && chk "fault (locked): the run measured an event that the builds did not: refused, and the event is named" ok || chk "extra event not caught: $out" no
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/lplat-src.json" --locked; [ $rc = 1 ] && grep -q 'measured the event source as' <<<"$out" && [ ! -e "$W/o.json" ] && chk "fault (locked): the source event of the run is not the one of the builds: refused" ok || chk "wrong source digest not caught: $out" no
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/lplat-order.json" --locked; [ $rc = 1 ] && grep -q 'the real run measured other events (or in another order)' <<<"$out" && chk "fault (locked): the run's events are in another order than the builds': refused" ok || chk "wrong order not caught: $out" no
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/lplat-nosrc.json" --locked; [ $rc = 1 ] && grep -q 'the real run has no source event' <<<"$out" && chk "fault (locked): a run without a source event is refused" ok || chk "missing source not caught: $out" no
rf --build "$W/a" --build "$W/b" --commit $C --platform "$W/lplat-two.json" --locked; [ $rc = 1 ] && grep -q 'the real run measured other events (or in another order)' <<<"$out" && chk "fault (locked): the run lists tc-lib before source while the builds list source first: refused" ok || chk "swapped order of two kept events not caught: $out" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4F-REHEARSAL-PASS" || { echo "R4F-REHEARSAL-FAIL"; exit 1; }
