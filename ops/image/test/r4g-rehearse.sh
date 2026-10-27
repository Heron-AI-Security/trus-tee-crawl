#!/usr/bin/env bash
# Step R4 rehearsal (no cloud, seconds): the collection policy must not depend on the DAY of the build. keytool prints a "Creation date" line per certificate (the day on which the JDK's store was generated on that
# machine); two builders of two days had the same 120 certificates and made two different policies, so tc-conf, and with it the reference, changed with the day.   bash r4g-rehearse.sh KITDIR
set -uo pipefail
K="$(cd "${1:?usage: $0 KITDIR}" && pwd)"; POL="$K/ops/image/rootfs/usr/local/lib/tc/tc-policy.py"; W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT; P=0; F=0
chk() { if [ "$2" = ok ]; then echo "   ok:   $1"; P=$((P+1)); else echo "   FAIL: $1"; F=$((F+1)); fi; }
say() { echo; echo "== $*"; }
[ -f "$POL" ] || { echo "  FAIL: no $POL"; exit 2; }
# a fake keytool that prints the REAL format, with the creation date, the certificate bytes and the alias taken from files
mkkt() { # $1 name, $2 date, $3 first certificate, $4 second certificate, $5 alias of the first, $6 entry type of the first (default trustedCertEntry)
  cat > "$W/$1" <<KT
#!/usr/bin/env bash
cat <<'EOT'
Alias name: $5
Creation date: $2
Entry type: ${6:-trustedCertEntry}

-----BEGIN CERTIFICATE-----
$3
-----END CERTIFICATE-----

Alias name: bbb
Creation date: $2
Entry type: trustedCertEntry

-----BEGIN CERTIFICATE-----
$4
-----END CERTIFICATE-----
EOT
KT
  chmod +x "$W/$1"
}
mkpol() { python3 -B "${3:-$POL}" "$W/$1" "$W/$2.json" > "$W/$2.out" 2>&1; }
say "the same certificates on two different days"
mkkt day26 "Oct 26, 2026" QUJD REVG aaa; mkkt day27 "Oct 27, 2026" QUJD REVG aaa
mkpol day26 p26; rc1=$?; mkpol day27 p27; rc2=$?
[ $rc1 = 0 ] && [ $rc2 = 0 ] && cmp -s "$W/p26.json" "$W/p27.json" && chk "the policy of the two days is BYTE-IDENTICAL (the build day no longer reaches the policy)" ok || chk "the policies differ by the day: $(cat $W/p26.out $W/p27.out | tr '\n' ' ')" no
[ "$(sha256sum < "$W/p26.json")" = "$(sha256sum < "$W/p27.json")" ] && grep -q '^policy sha256:[0-9a-f]\{64\}, 2 anchors' "$W/p26.out" && cmp -s "$W/p26.out" "$W/p27.out" && chk "the printed policy hash (the one that the bake shows and that every receipt names) is the same on both days" ok || chk "the printed hash differs by the day" no
say "the fix removes only the date lines: anything else still changes the policy"
mkkt other_cert "Oct 27, 2026" QUJD R0hJ aaa; mkpol other_cert p_cert
mkkt other_alias "Oct 27, 2026" QUJD REVG zzz; mkpol other_alias p_alias
mkkt other_entry "Oct 27, 2026" QUJD REVG aaa PrivateKeyEntry; mkpol other_entry p_entry
python3 - "$W/p27.json" "$W/p_cert.json" "$W/p_alias.json" "$W/p_entry.json" > "$W/props.txt" 2>&1 <<'PYEOF'
import json, sys
a, c, l, e = [json.load(open(x)) for x in sys.argv[1:5]]; ta, tc, tl, te = a["trust_anchors"], c["trust_anchors"], l["trust_anchors"], e["trust_anchors"]
ok = lambda m, x: print(("PASS " if x else "FAIL ") + m)
ok("another certificate changes the set hash and the file hash", ta["anchor_set_sha256"] != tc["anchor_set_sha256"] and ta["file_sha256"] != tc["file_sha256"])
ok("another alias (text outside the date lines) changes the file hash and not the set hash: only the date lines are removed", ta["file_sha256"] != tl["file_sha256"] and ta["anchor_set_sha256"] == tl["anchor_set_sha256"])
ok("another entry type (text outside the date lines) also changes the file hash: nothing but the date lines is removed", ta["file_sha256"] != te["file_sha256"] and ta["anchor_set_sha256"] == te["anchor_set_sha256"])
ok("the policy keeps its structure: the count, the source and both hashes are there", ta["count"] == 2 and "keytool -list -rfc -cacerts" in ta["source"] and ta["file_sha256"].startswith("sha256:") and ta["anchor_set_sha256"].startswith("sha256:"))
PYEOF
[ "$(grep -c '^PASS' "$W/props.txt")" = 4 ] && chk "another certificate, another alias and another entry type still change the policy, and the structure is kept (4 properties)" ok || chk "a property failed: $(grep FAIL "$W/props.txt" | tr '\n' '|')$(head -c 200 "$W/props.txt")" no
python3 - "$W/p27.json" "$W/day27" > "$W/indep.txt" 2>&1 <<'PYEOF'
import hashlib, json, re, subprocess, sys
p = json.load(open(sys.argv[1])); raw = subprocess.run([sys.argv[2]], capture_output=True).stdout
text = b"".join(l for l in raw.splitlines(True) if not l.startswith(b"Creation date:"))
print("PASS" if p["trust_anchors"]["file_sha256"] == "sha256:" + hashlib.sha256(text).hexdigest() else "FAIL the file hash is not the hash of the text without the date lines")
PYEOF
grep -q '^PASS' "$W/indep.txt" && chk "file_sha256 is the SHA-256 of the keytool text without its Creation date lines (recomputed here by another method, not by the tool)" ok || chk "$(cat $W/indep.txt)" no
say "the control: the OLD behavior (the fix removed from a copy of the tool) must make the day show"
sed 's/"file_sha256": sha(text)/"file_sha256": sha(pem)/' "$POL" > "$W/old-policy.py"
grep -q 'sha(pem)}' "$W/old-policy.py" && mkpol day26 o26 "$W/old-policy.py" && mkpol day27 o27 "$W/old-policy.py"
cmp -s "$W/o26.json" "$W/o27.json" && chk "CONTROL FAILED: the old behavior gives the same policy on two days, so this test cannot see the defect" no || chk "control: without the fix the two days give two different policies (the defect that was found: the test fails for the old behavior)" ok
say "faults"
printf '#!/usr/bin/env bash\ntrue\n' > "$W/empty"; chmod +x "$W/empty"; mkpol empty pe; rc=$?
[ $rc != 0 ] && grep -q 'no CA certificates in the JDK store' "$W/pe.out" && [ ! -e "$W/pe.json" ] && chk "fault: a JDK store without certificates gives no policy and says why" ok || chk "empty store not refused: $(cat $W/pe.out | head -c 200)" no
printf '#!/usr/bin/env bash\nexit 1\n' > "$W/broken"; chmod +x "$W/broken"; mkpol broken pb; rc=$?
[ $rc != 0 ] && [ ! -e "$W/pb.json" ] && chk "fault: a keytool that fails gives no policy" ok || chk "failing keytool not refused" no
echo; echo "pass: $P   fail: $F"; [ "$F" = 0 ] && echo "R4G-REHEARSAL-PASS" || { echo "R4G-REHEARSAL-FAIL"; exit 1; }
