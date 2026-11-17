#!/usr/bin/env bash
# Rehearsal of build step 2, compare-builds (ops/kits/run-kit/steps/02-compare-builds.sh), run through the REAL run-kit.sh and the real step.
#   bash run-kit-step2-rehearse.sh TREE        (TREE holds ops/; no cloud; toy evidence of two builds and fake comparison tools; a throwaway HOME)
# A good pair of builds passes, and the step prints plain sentences (no old tool marker is shown). Then every check is made to FAIL on purpose, with the message that says what
# differs: an event, the event count, the package versions, the initramfs, a missing or wrong DEBS-OK, a missing or different audit, a missing source commit, the same archive
# for both builds, different recipes, a recipe that cannot be derived, too few events recomputed from the commit, a failed recomputation, and builds that are not finished.
# Mutants of the step (each check removed in turn, and one that shows an old marker) must all be caught by the same cases.
set -u
T="$(cd "${1:?usage: $0 TREE}" && pwd)"; K="$T/ops/kits/run-kit"; W="$(mktemp -d)"; V=1; PASS=0; FAIL=0; trap 'rm -rf "$W"' EXIT
chk() { if [ "$2" = ok ]; then PASS=$((PASS + 1)); [ "$V" = 1 ] && echo "  pass: $1"; else FAIL=$((FAIL + 1)); [ "$V" = 1 ] && echo "  FAIL: $1${3:+ | $3}"; fi; return 0; }   # always 0: it is used in "A && chk ok || chk bad"
[ -f "$K/steps/02-compare-builds.sh" ] || { echo "RUN-KIT-STEP2-REHEARSAL-FAIL: step 2 is missing in $K"; exit 1; }
COMMIT_FULL=0123456789abcdef0123456789abcdef01234567; C9=${COMMIT_FULL:0:9}

mkstepsdir() {  # KITDIR: a step folder whose step list holds step 2 only, and whose files are links to the kit in KITDIR
  rm -rf "$W/sd"; mkdir -p "$W/sd/steps"
  for f in names.sh lib.sh record.sh tools.sh steps-crawl.sh; do ln -s "$1/$f" "$W/sd/$f"; done
  ln -s "$1/steps/02-compare-builds.sh" "$W/sd/steps/02-compare-builds.sh"
  printf 'RK_STEPS=("2|compare-builds|Compare the two builds|steps/02-compare-builds.sh")\n' > "$W/sd/steps-build.sh"
}
setup() {  # a fresh home with the unpacked tree, the commit file, and the evidence of two finished builds, as steps 0 and 1 leave them
  rm -rf "$W/home" "$W/ctl"; mkdir -p "$W/home" "$W/ctl"; B="$W/home/build-$C9"; TR="$B/tree"
  mkdir -p "$TR/ops/image/debs" "$TR/ops/image/test"; printf 'a.deb\nb.deb\nc.deb\n' > "$TR/ops/image/debs/SHA256SUMS"
  WANT="$(sha256sum "$TR/ops/image/debs/SHA256SUMS" | cut -c1-12)"; echo "$COMMIT_FULL" > "$B/commit.txt"
  cat > "$TR/ops/image/test/r4-diff.py" <<'PY'
import sys, os
c = os.path.join(os.path.dirname(os.environ["HOME"]), "ctl"); has = lambda n: os.path.exists(os.path.join(c, n))
out = sys.argv[sys.argv.index("--out") + 1]
L = ["commit recorded: A and B the same", "operating system: same", "packages: A 601, B 600; versions differ" if has("pkg-differ") else "packages: A 601, B 601; all versions equal", "vmlinuz same", "initrd.img-tc  DIFFERENT" if has("initrd-differ") else "initrd.img-tc  same"]
L.append("R4-DIFF: 13 of 15 events identical; different: tc-conf, tc-lib" if has("diff-differ") else ("R4-DIFF: 14 of 14 events identical; different: none" if has("diff-count") else "R4-DIFF: 15 of 15 events identical; different: none"))
print("\n".join(L)); open(out, "w").write("\n".join(L) + "\n")
PY
  cat > "$TR/ops/image/test/r4-derive.py" <<'PY'
import sys, os
c = os.path.join(os.path.dirname(os.environ["HOME"]), "ctl"); has = lambda n: os.path.exists(os.path.join(c, n))
ev = sys.argv[sys.argv.index("--evidence") + 1]; out = sys.argv[sys.argv.index("--out") + 1]
if has("derive-fail"): print("boom"); sys.exit(1)
os.makedirs(out, exist_ok=True); open(os.path.join(out, "install-manifest.tsv"), "w").write("recipe-b\n" if has("recipe-differ") and "/b/" in ev else "recipe\n"); print("R4-DERIVE-OK")
PY
  cat > "$TR/ops/image/test/r4-recompute.py" <<'PY'
import sys, os
c = os.path.join(os.path.dirname(os.environ["HOME"]), "ctl"); has = lambda n: os.path.exists(os.path.join(c, n))
if has("recompute-fail"): print("R4-RECOMPUTE-FAILED: an event differs"); sys.exit(1)
print("R4-RECOMPUTE-OK: %d of 15 stable events equal" % (7 if has("recompute-low") else 8))
PY
  for i in a b; do mkdir -p "$B/$i/r4"; for n in $(seq 1 15); do printf 'ev%s\tdigest%s\n' $n $n; done > "$B/$i/r4/events.tsv"
    h=aaaaaaaaaaaaaaaa; [ "$i" = b ] && h=bbbbbbbbbbbbbbbb
    printf '##### stage ship-source\nship the source archive (%s... 198 MB) to the builder\nDEBS-OK snapshot=20261027T000000Z packages=3 sums=%s openjdk=11\nDEBS-AUDIT-OK sources=1 cache-debs=0 lists=committed-only installed=23 versions=committed\nsource: commit %s\n' "$h" "$WANT" "$COMMIT_FULL" > "$B/$i/console.txt"; done
}

suite() {  # DIR: all the checks against the kit in DIR
  local D="$1" o rc
  mkstepsdir "$D"
  rk() { env HOME="$W/home" PATH="$PATH" RK_STEPS_DIR="$W/sd" bash "$D/run-kit.sh" build --commit "$COMMIT_FULL" --until compare-builds "$@" 2>&1; }
  refused() { [ "$rc" = 1 ] && printf '%s' "$o" | grep -q "^STEP 2 FAILED" && printf '%s' "$o" | grep -qF -- "COMPARE-FAILED: $1"; }
  scen() { touch "$W/ctl/$1"; }
  t() {  # NAME TEXT: the run must be refused with TEXT
    o="$(rk)"; rc=$?; refused "$2" && chk "$1" ok || chk "$1" bad "exit $rc: $(printf '%s' "$o" | grep -E 'COMPARE-FAILED|tool says' | head -2 | tr '\n' ' ' | cut -c1-260)"
  }
  setup; o="$(rk)"; rc=$?
  [ "$rc" = 0 ] && printf '%s' "$o" | grep -q "^STEP 2 DONE: the two builds of commit $C9 agree: all 15 events identical, the same 3 committed packages, the same recipe, 8 of 15 events recomputed from the commit alone, and the archives differ" && chk "a good pair of builds passes, and the result sentence says what was checked" ok || chk "a good pair of builds passes (exit $rc)" bad "$(printf '%s' "$o" | tail -4 | tr '\n' ' ' | cut -c1-300)"
  ! printf '%s' "$o" | grep -qE 'R4-|DERIVE|RECOMPUTE' && chk "the step shows plain sentences only: no marker of an older tool" ok || chk "the step shows plain sentences only: no marker of an older tool" bad "$(printf '%s' "$o" | grep -E 'R4-|DERIVE|RECOMPUTE' | head -2 | tr '\n' ' ')"
  [ -s "$B/compare.txt" ] && grep -q "events: all 15 identical" "$B/compare.txt" && grep -q "source archives: A (aaaaaaaaaaaaaaaa, B (bbbbbbbbbbbbbbbb" "$B/compare.txt" && [ -s "$B/diff.txt" ] && chk "compare.txt (a part of the build record) and diff.txt are written" ok || chk "compare.txt (a part of the build record) and diff.txt are written" bad
  setup; rm "$B/a/r4/events.tsv"; o="$(rk)"; rc=$?; refused "build A has no measurements yet" && chk "a build that has no measurements yet is refused, and named" ok || chk "a build that has no measurements yet is refused, and named" bad "exit $rc"
  setup; scen diff-differ; t "an event that differs is refused, and the tool's line is shown" "the two builds are not identical in every event"
  setup; scen diff-count; t "a comparison that covered another number of events than build A measured is refused" "the comparison covered 14 events but build A measured 15"
  setup; scen pkg-differ; t "package versions that differ are refused" "the package versions of the two builds differ"
  setup; scen initrd-differ; t "an initramfs that differs is refused" "the initramfs of the two builds differ"
  setup; sed -i '/^DEBS-OK/d' "$B/b/console.txt"; t "a build without DEBS-OK in its log is refused" "build B has no DEBS-OK in its log"
  setup; sed -i 's/packages=3/packages=2/' "$B/b/console.txt"; t "a build that installed another number of packages than committed is refused" "build B did not install the committed set"
  setup; sed -i 's/sums=[0-9a-f]*/sums=000000000000/' "$B/a/console.txt"; t "a build that installed another set (other sums) than committed is refused" "build A did not install the committed set"
  setup; sed -i '/^DEBS-AUDIT-OK/d' "$B/a/console.txt"; t "a build without the audit line is refused" "build A has no DEBS-AUDIT-OK"
  setup; sed -i 's/installed=23/installed=24/' "$B/b/console.txt"; t "two audits that differ are refused" "the audits of the two builds differ"
  setup; sed -i '/^source: commit/d' "$B/a/console.txt"; t "a build that did not record the commit as its source is refused" "build A did not record 'source: commit $COMMIT_FULL'"
  setup; sed -i 's/bbbbbbbbbbbbbbbb/aaaaaaaaaaaaaaaa/' "$B/b/console.txt"; t "the same archive shipped to both builds is refused (the check would prove nothing)" "build A and build B shipped the same archive"
  setup; scen recipe-differ; t "two different recipes are refused" "the two builds give different recipes"
  setup; scen derive-fail; t "a recipe that cannot be derived is refused" "the recipe of build A could not be derived"
  setup; scen recompute-low; t "fewer events recomputed from the commit than the proven 8 are refused" "only 7 of 15 events can be recomputed from the commit alone"
  setup; scen recompute-fail; t "a failed recomputation is refused, with the tool's last lines shown" "the recomputation from the commit failed"
}

echo "== the checks of step 2 on a good pair of builds and on every defect"; suite "$K"
REAL_FAIL=$FAIL; REAL_PASS=$PASS
echo "== the mutants (each check removed in turn; each one must be caught by at least one check above)"
V=0; MC=0; MT=0
mutant() {  # NAME OLD NEW: replaces the exact text OLD of the step by NEW
  local name="$1"; rm -rf "$W/m"; mkdir -p "$W/m/steps"; cp "$K"/*.sh "$W/m/"; cp "$K"/steps/*.sh "$W/m/steps/"
  python3 - "$W/m/steps/02-compare-builds.sh" "$2" "$3" <<'PY' || { echo "  FAIL: the mutant '$name' changed nothing (the rehearsal is out of date)"; REAL_FAIL=$((REAL_FAIL + 1)); return; }
import sys
p, old, new = sys.argv[1:4]; s = open(p).read()
if old not in s: sys.exit(3)
open(p, "w").write(s.replace(old, new, 1))
PY
  PASS=0; FAIL=0; suite "$W/m"; MT=$((MT + 1))
  if [ "$FAIL" -gt 0 ]; then MC=$((MC + 1)); echo "  pass: the mutant '$name' is caught ($FAIL check(s) fail)"; else echo "  FAIL: the mutant '$name' is NOT caught"; REAL_FAIL=$((REAL_FAIL + 1)); fi
}
mutant "builds without measurements are accepted"        '[ -s "$BD/$i/r4/events.tsv" ] && [ -s "$BD/$i/console.txt" ] || fail'   'true || fail'
mutant "differing events are accepted"                   'grep -Eq "$RK_M_EVENTS_EQUAL" "$BD/compare-tool.out" ||'               'true ||'
mutant "another event count is accepted"                 '[ "$N" = "$NEV" ] ||'                                                    'true ||'
mutant "differing package versions are accepted"         'grep -q "$RK_M_PACKAGES_EQUAL" "$BD/compare-tool.out" ||'               'true ||'
mutant "a differing initramfs is accepted"               'grep -q "$RK_M_INITRD_SAME" "$BD/compare-tool.out" ||'                  'true ||'
mutant "a missing DEBS-OK is accepted"                   '[ -n "$L" ] || fail "build ${i^^} has no DEBS-OK in its log"'            'true'
mutant "another installed set is accepted"               '*) fail "build ${i^^} did not install the committed set'                ': "build ${i^^} did not install the committed set'
mutant "a missing audit is accepted"                     '[ -n "$LA" ] || fail "build ${i^^} has no DEBS-AUDIT-OK'                 'true || fail "build ${i^^} has no DEBS-AUDIT-OK'
mutant "differing audits are accepted"                   '[ "$AU_A" = "$AU_B" ] || fail'                                           'true || fail'
mutant "a missing source commit is accepted"             'grep -a -q "^source: commit $COMMIT" "$BD/$i/console.txt" 2>/dev/null &&'  'true &&'
mutant "the same archive for both builds is accepted"    '[ -n "$SA" ] && [ -n "$SB" ] && [ "$SA" != "$SB" ] || fail'              'true || fail'
mutant "differing recipes are accepted"                  'cmp -s "$BD/a/recipe/install-manifest.tsv" "$BD/b/recipe/install-manifest.tsv" ||'  'true ||'
mutant "a recipe that cannot be derived is accepted"     '2>&1 || fail "the recipe of build'                                       '2>&1 || : "the recipe of build'
mutant "too few recomputed events are accepted"          '[ "$RN" -ge "$MIN_RECOMPUTED" ] || fail'                                 'true || fail'
mutant "a failed recomputation is accepted"              '[ -n "$L" ] || { tail -3'                                                'true || { tail -3'
mutant "an old tool marker is shown to the user"         'grep -E "commit recorded|operating|packages:|initrd|vmlinuz"'            'grep -E "commit recorded|operating|packages:|initrd|vmlinuz|^R4-DIFF"'
V=1; PASS=$REAL_PASS; FAIL=$REAL_FAIL
echo; echo "checks of step 2: $REAL_PASS passed; mutants caught: $MC of $MT"
if [ "$FAIL" = 0 ]; then echo "RUN-KIT-STEP2-REHEARSAL-OK"; else echo "RUN-KIT-STEP2-REHEARSAL-FAIL: $FAIL problem(s)"; exit 1; fi
