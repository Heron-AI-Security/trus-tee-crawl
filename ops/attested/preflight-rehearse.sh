#!/usr/bin/env bash
# Rehearsal of preflight.sh: a local bare repository stands in for GitHub, so that each failure can be made on purpose.
#   bash ops/attested/preflight-rehearse.sh REPO_DIR       REPO_DIR = a clean clone that contains preflight.sh and its baseline
set -uo pipefail
SRC="$(cd "${1:?usage: $0 REPO_DIR}" && pwd)"; BR="${2:-feat/tee-hadoop-cluster}"; PASS=0; FAILN=0
chk() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  pass: $1"; else FAILN=$((FAILN+1)); echo "  FAIL: $1"; echo "${out:-}" | grep -v "^      " | tail -7 | sed "s/^/        | /"; fi; }
R="$(mktemp -d)"; git clone -q --bare "$SRC" "$R/origin.git" && git -C "$R/origin.git" branch -q -f "$BR" HEAD 2>/dev/null
pf() { ( cd "$1" && bash ops/attested/preflight.sh . "$BR" 2>&1 ); }
fresh() { rm -rf "$R/$1"; git clone -q --branch "$BR" "$R/origin.git" "$R/$1"; }
push_change() { # $1 = shell snippet run in a work clone, $2 = message
  rm -rf "$R/work"; git clone -q --branch "$BR" "$R/origin.git" "$R/work"; ( cd "$R/work" && eval "$1" && git add -A && { git -c user.email=t@t -c user.name=t commit -q -m "$2" >/dev/null 2>&1 || true; } && git push -q origin "$BR" ); }
echo "=== 1. the happy path: a fresh clone of the latest commit"
fresh a; out="$(pf "$R/a")"; echo "$out" | tail -3 | cut -c1-170
chk "PREFLIGHT-OK on the latest commit, with the sweep and every facts list at its baseline" $(grep -q '^PREFLIGHT-OK' <<<"$out"; echo $?)
echo "=== 2. faults: it must refuse, and say why"
push_change 'echo "x" >> docs/README.md' "docs: a later commit"
out="$(pf "$R/a")"; chk "a working copy that is behind GitHub is refused (the head was remembered, not looked at)" $(grep -q '^PREFLIGHT-FAILED' <<<"$out" && grep -q 'but GitHub has' <<<"$out"; echo $?)
fresh b; echo "local" >> "$R/b/docs/README.md"; out="$(pf "$R/b")"; chk "local changes are refused" $(grep -q 'there are local changes' <<<"$out" && grep -q '^PREFLIGHT-FAILED' <<<"$out"; echo $?)
push_change 'python3 - <<"PY"
p = "docs/milestone-plan.md"; s = open(p).read(); s = s.replace("step 5.3 and the rest of step 5.2 open", "5.2 and 5.3 open"); open(p, "w").write(s)
PY' "docs: a stale summary"
fresh c; out="$(pf "$R/c")"; chk "a stale status summary is refused by the sweep" $(grep -q '^PREFLIGHT-FAILED' <<<"$out" && grep -q 'still says\|does not contain' <<<"$out"; echo $?)
push_change 'python3 - <<"PY"
p = "docs/milestone-plan.md"; s = open(p).read(); s = s.replace("5.2 and 5.3 open", "step 5.3 and the rest of step 5.2 open"); open(p, "w").write(s)
PY' "docs: the summary is right again"
fresh d; out="$(pf "$R/d")"; chk "once the summary is right again the preflight passes (the sweep, not luck)" $(grep -q '^PREFLIGHT-OK' <<<"$out"; echo $?)
push_change 'python3 - <<"PY"
import glob
t = open("ops/attested/docs-facts-m513.tsv").read().split("\n"); d = [l for l in t if l and not l.startswith("#")][0].split("\t")
p = d[2].replace("@docs:", "") if d[2].startswith("@docs:") else d[0]
s = open(p).read(); i = s.index(d[1]) if d[1] in s else -1
print("quoted text found:", i >= 0)
open(p, "w").write(s.replace(d[1], d[1][:-3] + "XXX", 1))
PY' "docs: a quoted phrase changes"
fresh e; out="$(pf "$R/e")"; chk "a document that an earlier facts list quotes was changed: the baseline comparison refuses it" $(grep -q '^PREFLIGHT-FAILED' <<<"$out" && grep -q 'baseline says' <<<"$out"; echo $?)
push_change 'git -c user.email=t@t -c user.name=t revert --no-edit HEAD >/dev/null' "docs: the quoted phrase is restored"
fresh e2; out="$(pf "$R/e2")"; chk "with the quoted phrase restored the preflight passes again (the failure was that change and nothing else)" $(grep -q '^PREFLIGHT-OK' <<<"$out"; echo $?)
push_change 'cp ops/attested/docs-facts-m513.tsv ops/attested/docs-facts-zz.tsv' "chore: a new facts list"
fresh f; out="$(pf "$R/f")"; chk "a facts list that is not in the baseline is refused until it is added" $(grep -q 'docs-facts-zz.tsv is not in the baseline' <<<"$out"; echo $?)
push_change 'git rm -q ops/attested/docs-facts-zz.tsv' "chore: the new list is removed again"
push_change 'rm -f ops/attested/docs-status-expected.tsv' "chore: the expected-status file is gone"
fresh g; out="$(pf "$R/g")"; chk "a missing expected-status file is refused (the sweep cannot be skipped by deleting its rules)" $(grep -q 'is missing' <<<"$out" && grep -q '^PREFLIGHT-FAILED' <<<"$out"; echo $?)
push_change 'git checkout -q HEAD~1 -- ops/attested/docs-status-expected.tsv' "chore: the rules file is back"
fresh h2; out="$(cd "$R/h2" && bash ops/attested/preflight.sh . no-such-branch 2>&1)"; chk "a wrong branch name or no network is refused, not skipped" $(grep -q 'cannot fetch' <<<"$out"; echo $?)
echo "=== 3. the audit of every file of docs/ refuses what it must (and passes again once the fault is undone)"
REV='git -c user.email=t@t -c user.name=t revert --no-edit HEAD >/dev/null'
push_change 'python3 - <<"PY"
p = "docs/run-comparison.md"; s = open(p).read(); s = s.replace("(run-1-pilot.md)", "(run-1-pilotXX.md)", 1); open(p, "w").write(s)
PY' "docs: a broken link"
fresh i1; out="$(pf "$R/i1")"; chk "a link to a file that does not exist is refused" $(grep -q 'link to a file that does not exist' <<<"$out" && grep -q '^PREFLIGHT-FAILED' <<<"$out"; echo $?)
push_change "$REV" "docs: the link is right again"
push_change 'python3 - <<"PY"
p = "docs/README.md"; L = open(p).read().split("\n"); L = [l for l in L if "(session-start.md)" not in l]; open(p, "w").write("\n".join(L))
PY' "docs: a file missing from the index"
fresh i2; out="$(pf "$R/i2")"; chk "a file of docs/ that the index does not list is refused" $(grep -q 'the docs index does not list session-start.md' <<<"$out"; echo $?)
push_change "$REV" "docs: the index is right again"
push_change 'python3 - <<"PY"
p = "docs/guide-pitfalls-and-lessons.md"; s = open(p).read(); s = s.replace("29. For everything after the pilot", "28. For everything after the pilot", 1); open(p, "w").write(s)
PY' "docs: a repeated number"
fresh i3; out="$(pf "$R/i3")"; chk "a numbered list that repeats a number is refused" $(grep -q 'a numbered list goes from 28 to 28' <<<"$out"; echo $?)
push_change "$REV" "docs: the number is right again"
push_change 'python3 - <<"PY"
p = "docs/run-comparison.md"; s = open(p).read(); s = s.rstrip("\n") + "\n\n### 9.9 A heading that the contents list does not have\n"; open(p, "w").write(s)
PY' "docs: a heading missing from the contents list"
fresh i4; out="$(pf "$R/i4")"; chk "a heading that the contents list does not have is refused" $(grep -q 'the contents list does not have: 9.9' <<<"$out"; echo $?)
push_change "$REV" "docs: the heading is removed again"
push_change 'python3 - <<"PY"
p = "docs/run-comparison.md"; s = open(p).read(); s = s.replace("| Wall time of the crawl | 709 s | 770 s | 736 s |", "| Wall time of the crawl | 709 s | 770 s | 736 s | extra |", 1); open(p, "w").write(s)
PY' "docs: a table row with an extra column"
fresh i5; out="$(pf "$R/i5")"; chk "a table row with a different number of columns is refused" $(grep -q 'a table row has' <<<"$out"; echo $?)
push_change "$REV" "docs: the row is right again"
# the known numbering gap (ops/attested/docs-known-gaps.tsv): tolerated exactly, refused in every other case
push_change 'python3 - <<"PY"
p = "docs/decisions.md"; L = open(p).read().split("\n"); L = [l for l in L if not l.startswith("| 108 |")]; open(p, "w").write("\n".join(L))
PY' "docs: ADR-108 is not in the ADR index"
fresh j1; out="$(pf "$R/j1")"; chk "an ADR section that the ADR index does not list is refused" $(grep -q 'ADR sections and the ADR index differ' <<<"$out" && grep -q '^PREFLIGHT-FAILED' <<<"$out"; echo $?)
push_change "$REV" "docs: the index row is back"
push_change 'git rm -q ops/attested/docs-known-gaps.tsv' "chore: the known gap list is gone"
fresh j2; out="$(pf "$R/j2")"; chk "without the known gap list the numbering gaps are refused (the list is what tolerates them)" $(grep -q 'ADR sections are not continuous' <<<"$out" && grep -q 'numbers are missing' <<<"$out" && grep -q '^PREFLIGHT-FAILED' <<<"$out"; echo $?)
push_change "$REV" "chore: the known gap list is back"
push_change 'python3 - <<"PY"
p = "docs/decisions.md"; s = open(p).read(); s = s.rstrip("\n") + "\n\n## ADR-110: A new entry that leaves ADR-109 missing\n\nx\n"; s = s.replace("\n| 108 | ", "\n| 108 | ", 1); i = s.index("\n| 108 | "); j = s.index("\n", i + 1); s = s[:j] + "\n| 110 | A new entry | Accepted |" + s[j:]; open(p, "w").write(s)
PY' "docs: ADR-110 is added and ADR-109 is missing"
fresh j3; out="$(pf "$R/j3")"; chk "a gap that the list does not name (ADR-109) is refused" $(grep -q 'ADR sections are not continuous: missing \[109\]' <<<"$out"; echo $?)
push_change "$REV" "docs: the number is right again"
push_change 'python3 - <<"PY"
p = "docs/decisions.md"; s = open(p).read(); i = s.index("## ADR-108:"); s = s[:i] + "## ADR-100: A restored entry\n\nx\n\n" + s[i:]; s = s.replace("\n| 108 | ", "\n| 100 | A restored entry | Accepted |\n| 108 | ", 1); open(p, "w").write(s)
PY' "docs: ADR-100 is restored but the list still names it"
fresh j4; out="$(pf "$R/j4")"; chk "a number of the known gap list that exists now is refused (a restore must remove its line)" $(grep -q 'docs-known-gaps.tsv names ADR numbers that exist now' <<<"$out"; echo $?)
push_change "$REV" "docs: ADR-100 is removed again"
fresh i6; out="$(pf "$R/i6")"; chk "after every fault is undone the preflight passes again, and it prints the report of every file" $(grep -q '^PREFLIGHT-OK' <<<"$out" && grep -q 'run-comparison.md ' <<<"$out"; echo $?)
echo; echo "pass: $PASS   fail: $FAILN"; [ "$FAILN" = 0 ] && echo "REHEARSAL-PASS: preflight.sh passes on the real state and refuses all 16 faults; $PASS checks" || echo "REHEARSAL-FAIL"
