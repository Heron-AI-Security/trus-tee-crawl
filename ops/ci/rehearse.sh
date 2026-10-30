#!/usr/bin/env bash
# ops/ci/rehearse.sh: the offline rehearsal of step P3.1 (no Google, no GitHub): the safety rules of the workflows, and smoke.sh and setup-gcp.sh against a fake gcloud.
# Usage:  bash ops/ci/rehearse.sh [ROOT]      ROOT is the repository folder (default: two folders above this script).    Ends with  pass: N   fail: M  and CI-REHEARSAL-PASS or CI-REHEARSAL-FAIL.
# shellcheck disable=SC2015   # the chk lines are written as: test && chk ok || chk no (chk never fails, so this is safe)
set -uo pipefail
ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd)" || { echo "CI-REHEARSAL-FAIL: no folder $1"; exit 2; }   # absolute, because the checks below change directory
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
pass=0; fail=0
chk() { if [ "$2" = ok ]; then pass=$((pass+1)); echo "  ok:   $1"; else fail=$((fail+1)); echo "  FAIL: $1"; fi; }
mkdir -p "$W/bin" "$W/stub"; LOG="$W/calls.log"; export LOG STUBDIR="$W/stub"
cat > "$W/bin/gcloud" <<'STUB'
#!/usr/bin/env bash
echo "gcloud $*" >> "$LOG"; S="$STUBDIR"
case "$*" in
  "--version"*) echo "Google Cloud SDK 999.0.0";;
  "auth list"*) echo "${STUB_ACCOUNT-tc-github-ci@training-custody.iam.gserviceaccount.com}";;
  "auth print-access-token"*) [ -f "$S/notoken" ] || echo "ya29.stub";;
  "config get-value account"*) echo "${STUB_ACCOUNT-owner@example.org}";;
  "projects describe"*) [ -f "$S/noproject" ] && exit 1; echo 123456789;;
  "compute zones describe"*) echo "${STUB_ZONE-UP}";;
  "compute machine-types describe"*) printf '4\t16384\n';;
  "compute regions describe"*) cat "$S/region.json";;
  "compute images list"*) echo "tc-img-rel-1 READY"; echo "tc-img-psl-1 READY";;
  "compute images describe"*) if [ -f "$S/noimage" ]; then echo "ERROR: not found"; exit 1; fi; echo '{"labels":{"commit":"16bafb3b19b3ace8c67ff37e8bc50f0463d36453"}}';;
  "projects get-iam-policy"*) echo "roles/editor"; echo "roles/resourcemanager.projectIamAdmin";;
  "services enable"*) :;;
  "iam service-accounts describe"*) [ -f "$S/exists_sa" ];;
  "iam service-accounts create"*) n="$4"; if [ "${#n}" -lt 6 ] || [ "${#n}" -gt 30 ]; then echo "ERROR: (gcloud.iam.service-accounts.create) INVALID_ARGUMENT: The account ID \"$n\" does not have a length between 6 and 30." >&2; exit 1; fi; touch "$S/exists_sa";;
  "iam service-accounts add-iam-policy-binding"*) echo "etag: x";;
  "projects add-iam-policy-binding"*) echo "bindings: x";;
  "iam workload-identity-pools describe"*) [ -f "$S/exists_pool" ];;
  "iam workload-identity-pools create"*) touch "$S/exists_pool";;
  "iam workload-identity-pools providers describe"*) if [[ "$*" == *"--format"* ]]; then echo "projects/123456789/locations/global/workloadIdentityPools/github/providers/nutch-private"; else [ -f "$S/exists_provider" ]; fi;;
  "iam workload-identity-pools providers create-oidc"*|"iam workload-identity-pools providers update-oidc"*) touch "$S/exists_provider";;
  *) echo "stub: unexpected gcloud call: $*" >&2; exit 99;;
esac
STUB
cat > "$W/bin/curl" <<'STUB'
#!/usr/bin/env bash
echo "curl $*" >> "$LOG"
if [ -f "$STUBDIR/iam.json" ]; then cat "$STUBDIR/iam.json"; exit 0; fi
# no prepared answer: every requested right is granted, except those listed in the file deny
body=""; while [ $# -gt 0 ]; do [ "$1" = "-d" ] && body="$2"; shift; done
BODY="$body" python3 - "$STUBDIR/deny" <<'PY'
import json, os, sys
deny = set(open(sys.argv[1]).read().split()) if os.path.exists(sys.argv[1]) else set()
if os.path.exists(os.path.dirname(sys.argv[1]) + "/apierror"): print(json.dumps({"error": {"message": "Cloud Resource Manager API has not been used in project 1 before"}})); raise SystemExit
print(json.dumps({"permissions": [p for p in json.loads(os.environ["BODY"])["permissions"] if p not in deny]}))
PY
STUB
chmod +x "$W/bin/gcloud" "$W/bin/curl"
# ---------------------------------------------------------------- A. the safety rules of every CI workflow
echo "== A. the safety rules of the workflows (.github/workflows/ci-*.yml)"
shopt -s nullglob; WF=("$ROOT"/.github/workflows/ci-*.yml); shopt -u nullglob
[ "${#WF[@]}" -gt 0 ] && chk "there is at least one CI workflow" ok || chk "no CI workflow found" no
for f in "${WF[@]}"; do
  b="$(basename "$f")"
  res="$(python3 - "$f" <<'PY'
import re, sys, yaml
t = open(sys.argv[1]).read(); d = yaml.safe_load(t); on = d.get(True, d.get("on", {})); out = {}
uses = re.findall(r"^\s*-?\s*uses:\s*(\S+)", t, re.M)
out["pinned"] = bool(uses) and all(re.fullmatch(r"[\w./-]+@[0-9a-f]{40}", u) for u in uses)
out["trigger"] = isinstance(on, dict) and set(on) <= {"push", "workflow_dispatch"} and "tags" in (on.get("push") or {}) and "branches" not in (on.get("push") or {})
p = d.get("permissions", {}); out["perms"] = isinstance(p, dict) and set(p) <= {"contents", "id-token"} and p.get("contents") in ("read", "write") and p.get("id-token") in ("write", None)
out["nosecrets"] = "secrets." not in t
steps = [s for j in d["jobs"].values() for s in j.get("steps", [])]
out["nocred"] = all(s.get("with", {}).get("persist-credentials") is False for s in steps if str(s.get("uses", "")).startswith("actions/checkout@"))
out["timeout"] = all("timeout-minutes" in j for j in d["jobs"].values())
out["noinject"] = all("${{" not in s.get("run", "") for s in steps)
out["runner"] = all(not str(j.get("runs-on", "")).endswith("latest") for j in d["jobs"].values())
out["concurrency"] = "concurrency" in d
out["cleanup"] = ("publish-ref.sh" not in t) or any(str(s.get("if", "")).strip() in ("always()", "${{ always() }}") and "instances delete" in s.get("run", "") for s in steps)
order = [("auth" if str(s.get("uses", "")).startswith("google-github-actions/auth@") else "login" if ("auth login" in s.get("run", "") and "--cred-file" in s.get("run", "") and "GOOGLE_GHA_CREDS_PATH" in s.get("run", "")) else "") for s in steps]
out["login"] = ("auth" not in order) or ("login" in order and order.index("login") > order.index("auth"))
print(" ".join("%s=%s" % (k, v) for k, v in out.items()))
PY
)"
  for k in pinned:"every action is pinned to a full commit hash" trigger:"it starts only by a pushed tag (no pull request, no branch push)" perms:"the permissions are only contents and id-token" nosecrets:"no stored secret is used (the sign-in has no key)" nocred:"checkout does not keep the token" timeout:"every job has a timeout" noinject:"no expression is written into a shell script (no injection)" runner:"the runner image is pinned, not 'latest'" concurrency:"runs cannot overlap" cleanup:"a workflow that makes VMs always deletes the ones it left behind (an if: always() step)" login:"after the sign-in, gcloud is signed in with the credentials file (as Google's setup-gcloud does)"; do
    key="${k%%:*}"; msg="${k#*:}"; case " $res " in *" $key=True "*) chk "$b: $msg" ok;; *) chk "$b: $msg" no;; esac
  done
done
# ---------------------------------------------------------------- B. the files agree with each other
echo "== B. the files agree with each other"
( . "$ROOT/ops/ci/ci.env"
  python3 - "$ROOT" "$TAG_PREFIXES" <<'PY' > "$W/agree.txt"
import glob, re, sys, yaml
root, prefixes = sys.argv[1], sys.argv[2].split()
tags = []
for f in glob.glob(root + "/.github/workflows/ci-*.yml"):
    d = yaml.safe_load(open(f)); tags += (d.get(True, d.get("on", {})).get("push") or {}).get("tags", [])
print("tags_admitted", bool(tags) and all(any(t.startswith(p) for p in prefixes) for t in tags))
perms = [l.strip().lstrip("!") for l in open(root + "/ops/ci/permissions.txt") if l.strip() and not l.lstrip().startswith("#")]
print("perm_names", bool(perms) and all(re.fullmatch(r"[a-z]+\.[A-Za-z]+\.[A-Za-z]+", p) for p in perms))
print("perm_unique", len(perms) == len(set(perms)))
PY
  echo "roles $(for r in $CI_ROLES; do case "$r" in roles/*) :;; *) echo bad;; esac; done | grep -c bad)" >> "$W/agree.txt"
  [[ "$CI_SA_NAME" =~ ^[a-z][a-z0-9-]{4,28}[a-z0-9]$ ]] && echo "sa_name 1" >> "$W/agree.txt"
  [[ "$WIF_POOL" =~ ^[a-z0-9-]{4,32}$ && "$WIF_PROVIDER" =~ ^[a-z0-9-]{4,32}$ && "$WIF_POOL$WIF_PROVIDER" != *gcp-* ]] && echo "wif_names 1" >> "$W/agree.txt" )
grep -q "^tags_admitted True" "$W/agree.txt" && chk "every tag that starts a workflow is admitted by the provider (TAG_PREFIXES)" ok || chk "a workflow tag is not admitted by TAG_PREFIXES" no
grep -q "^perm_names True" "$W/agree.txt" && chk "every listed right looks like a Google permission name" ok || chk "a listed right has a wrong name" no
grep -q "^perm_unique True" "$W/agree.txt" && chk "no right is listed twice" ok || chk "a right is listed twice" no
grep -q "^roles 0" "$W/agree.txt" && chk "every role in ci.env is a role name (roles/...)" ok || chk "a role in ci.env is not a roles/... name" no
grep -q "^sa_name 1" "$W/agree.txt" && chk "the default service account name has 6 to 30 characters (Google's rule)" ok || chk "the default service account name breaks Google's rule" no
grep -q "^wif_names 1" "$W/agree.txt" && chk "the default pool and provider names follow Google's rules" ok || chk "a default pool or provider name breaks Google's rules" no
# ---------------------------------------------------------------- C. smoke.sh against the fake gcloud
echo "== C. smoke.sh (it must change nothing)"
mkiam() { python3 - "$ROOT/ops/ci/permissions.txt" "$1" "$2" > "$W/stub/iam.json" <<'PY'
import json, sys
lines = [l.strip() for l in open(sys.argv[1]) if l.strip() and not l.lstrip().startswith("#")]
got = [l for l in lines if not l.startswith("!")]
mode, arg = sys.argv[2], sys.argv[3]
if mode == "missing": got.remove(arg)
if mode == "extra": got.append(arg)
if mode == "error": print(json.dumps({"error": {"message": arg}})); raise SystemExit
print(json.dumps({"permissions": got}))
PY
}
region() { echo "{\"quotas\":[{\"metric\":\"C3_CPUS\",\"limit\":24,\"usage\":$1},{\"metric\":\"CPUS\",\"limit\":24,\"usage\":0}]}" > "$W/stub/region.json"; }
smoke() { : > "$LOG"; rm -f "$W/stub/notoken" "$W/stub/noimage"; ( cd "$W" && env PATH="$W/bin:$PATH" GITHUB_SHA="abc123def" EXPECT_SA="tc-github-ci@training-custody.iam.gserviceaccount.com" "$@" bash "$ROOT/ops/ci/smoke.sh" ) > "$W/out.txt" 2>&1; echo $?; }
mkiam all x; region 0; rc=$(smoke); [ "$rc" = 0 ] && grep -q "CI-SMOKE-OK commit=abc123def" "$W/out.txt" && chk "everything in order: CI-SMOKE-OK with the commit" ok || chk "the good case fails: rc=$rc" no
grep -q -E "gcloud .*(create|delete|update|insert|add-iam|set-iam|remove|attach|stop|start|reset)" "$LOG" && chk "smoke.sh called a gcloud command that changes something" no || chk "smoke.sh calls only reading gcloud commands (it creates nothing)" ok
grep -c "^curl " "$LOG" | grep -q "^1$" && chk "it asked Google about the rights exactly once" ok || chk "the number of curl calls is not 1" no
mkiam missing compute.images.setIamPolicy; region 0; rc=$(smoke); [ "$rc" = 1 ] && grep -q "missing: compute.images.setIamPolicy" "$W/out.txt" && grep -q "CI-SMOKE-FAILED" "$W/out.txt" && chk "a missing right fails and is named" ok || chk "missing right: rc=$rc" no
mkiam extra compute.firewalls.create; region 0; rc=$(smoke); [ "$rc" = 0 ] && grep -q "warn: not needed, but held (least privilege): compute.firewalls.create" "$W/out.txt" && chk "an extra right is a warning, not a failure" ok || chk "extra right: rc=$rc" no
mkiam error "Cloud Resource Manager API has not been used in project 1 before"; region 0; rc=$(smoke); [ "$rc" = 1 ] && grep -q "API has not been used" "$W/out.txt" && chk "Google's refusal is shown with its reason" ok || chk "refusal: rc=$rc" no
mkiam all x; region 0; rc=$(smoke STUB_ACCOUNT=); [ "$rc" = 0 ] && grep -q "signed in through a credentials file" "$W/out.txt" && chk "no account listed but a working token: signed in (this is what GitHub may show)" ok || chk "no account, token ok: rc=$rc" no
mkiam all x; region 0; : > "$LOG"; touch "$W/stub/notoken"; ( cd "$W" && env PATH="$W/bin:$PATH" STUB_ACCOUNT= bash "$ROOT/ops/ci/smoke.sh" ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 1 ] && grep -q "FAIL: not signed in: no active account and no access token" "$W/out.txt" && chk "neither an account nor a token fails with a clear message" ok || chk "not signed in: rc=$rc" no
mkiam all x; region 0; rc=$(smoke STUB_ZONE=DOWN); [ "$rc" = 1 ] && grep -q "zone us-central1-a: DOWN" "$W/out.txt" && chk "a zone that is not UP fails" ok || chk "zone: rc=$rc" no
mkiam all x; region 22; rc=$(smoke); [ "$rc" = 1 ] && grep -q "only 2 free" "$W/out.txt" && chk "too little C3 quota fails" ok || chk "quota: rc=$rc" no
mkiam all x; echo '{"quotas":[{"metric":"CPUS","limit":24,"usage":0}]}' > "$W/stub/region.json"; rc=$(smoke); [ "$rc" = 0 ] && grep -q "no C3_CPUS quota is listed" "$W/out.txt" && chk "an unlisted C3 quota is a warning" ok || chk "no C3 quota: rc=$rc" no
mkiam all x; region 0; : > "$LOG"; rm -f "$W/stub/noimage"; touch "$W/stub/noimage"; ( cd "$W" && env PATH="$W/bin:$PATH" bash "$ROOT/ops/ci/smoke.sh" ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 0 ] && grep -q "CI-SMOKE-OK commit=local" "$W/out.txt" && grep -q "info: image tc-img-rel-1 cannot be read" "$W/out.txt" && chk "no image yet is information only; outside CI the commit reads 'local'" ok || chk "no image: rc=$rc" no
mkiam all x; region 0; : > "$LOG"; touch "$W/stub/notoken"; ( cd "$W" && env PATH="$W/bin:$PATH" bash "$ROOT/ops/ci/smoke.sh" ) > "$W/out.txt" 2>&1; rc=$?; [ "$rc" = 1 ] && grep -q "no access token" "$W/out.txt" && chk "no access token fails" ok || chk "no token: rc=$rc" no
# ---------------------------------------------------------------- D. setup-gcp.sh against the fake gcloud
echo "== D. setup-gcp.sh"
rm -f "$W/stub/iam.json" "$W/stub/deny" "$W/stub/apierror" "$W/stub/notoken" "$W/stub/noimage"   # nothing may leak from the scenarios of C
setup() { : > "$LOG"; ( cd "$W" && env PATH="$W/bin:$PATH" "$@" bash "$ROOT/ops/ci/setup-gcp.sh" ) > "$W/out.txt" 2>&1; echo $?; }
rm -f "$W/stub/exists_"* "$W/stub/noproject"; rc=$(setup); L="$(cat "$LOG")"
[ "$rc" = 0 ] && grep -q "^SETUP-GCP-OK" "$W/out.txt" && chk "a fresh project: SETUP-GCP-OK" ok || chk "fresh setup: rc=$rc" no
for need in "services enable" "service-accounts create tc-github-ci" "workload-identity-pools create github" "providers create-oidc nutch-private" "roles/compute.instanceAdmin.v1" "roles/compute.storageAdmin" "--role roles/iam.workloadIdentityUser"; do case "$L" in *"$need"*) chk "it runs: $need" ok;; *) chk "missing in the calls: $need" no;; esac; done
case "$L" in *"principalSet://iam.googleapis.com/projects/123456789/locations/global/workloadIdentityPools/github/attribute.repository/Heron-AI-Security/nutch-private"*) chk "the binding admits exactly this repository (principalSet by repository)" ok;; *) chk "the binding is not by repository" no;; esac
case "$L" in *"assertion.repository == 'Heron-AI-Security/nutch-private' && (assertion.ref.startsWith('refs/tags/ci-smoke-') || assertion.ref.startsWith('refs/tags/publish-ref-'))"*) chk "the provider's condition names the repository and only the tag prefixes" ok;; *) chk "the provider's condition is wrong: $(grep -o "attribute-condition.*" "$LOG" | head -1 | cut -c1-120)" no;; esac
grep -q -E "keys create|credentials_json|--impersonate" "$LOG" && chk "a key or a credentials file is created" no || chk "no service account key is ever created" ok
grep -q "GCP_WIF_PROVIDER     projects/123456789/locations/global/workloadIdentityPools/github/providers/nutch-private" "$W/out.txt" && grep -q "GCP_SERVICE_ACCOUNT  tc-github-ci@training-custody.iam.gserviceaccount.com" "$W/out.txt" && grep -q "GCP_PROJECT_ID       training-custody" "$W/out.txt" && chk "it prints the three repository variables" ok || chk "the variables are not printed" no
touch "$W/stub/exists_sa" "$W/stub/exists_pool" "$W/stub/exists_provider"; rc=$(setup); L="$(cat "$LOG")"
[ "$rc" = 0 ] && ! grep -q -E "service-accounts create|pools create|create-oidc" "$LOG" && grep -q "update-oidc" "$LOG" && chk "run again: nothing is created twice, the provider's condition is updated" ok || chk "second run: rc=$rc" no
rm -f "$W/stub/exists_"*; rc=$(setup DRY=1)
[ "$rc" = 0 ] && grep -q "DRY=1" "$W/out.txt" && ! grep -q -E "gcloud (services enable|iam service-accounts (create|add)|iam workload-identity-pools (create|providers (create|update))|projects add)" "$LOG" && chk "DRY=1 shows the commands and changes nothing" ok || chk "DRY=1: rc=$rc" no
touch "$W/stub/noproject"; rc=$(setup); [ "$rc" = 1 ] && grep -q "SETUP-GCP-FAILED" "$W/out.txt" && ! grep -q -E "services enable" "$LOG" && chk "a project that cannot be read stops everything before any change" ok || chk "no project: rc=$rc" no
rm -f "$W/stub/noproject"; rc=$(setup TAG_PREFIXES=" "); [ "$rc" = 1 ] && grep -q "TAG_PREFIXES is empty" "$W/out.txt" && chk "an empty tag list is refused (the provider would admit no run)" ok || chk "empty tags: rc=$rc" no
rm -f "$W/stub/exists_"*; rc=$(setup GITHUB_REPO=other-org/other-repo PROJECT_ID=other-project TAG_PREFIXES="release-"); L="$(cat "$LOG")"
case "$L" in *"attribute.repository/other-org/other-repo"*"assertion.repository == 'other-org/other-repo' && (assertion.ref.startsWith('refs/tags/release-'))"*|*"assertion.repository == 'other-org/other-repo' && (assertion.ref.startsWith('refs/tags/release-'))"*"attribute.repository/other-org/other-repo"*) [ "$rc" = 0 ] && chk "a changed repository, project and tag list flow through (nothing is hard-coded in the script)" ok || chk "settings change: rc=$rc" no;; *) chk "a changed setting did not flow through" no;; esac
rm -f "$W/stub/exists_"*
echo "== E. the rights of the account that runs the setup are checked BEFORE any change"
echo "iam.workloadIdentityPools.create" > "$W/stub/deny"; rc=$(setup); L="$(cat "$LOG")"
[ "$rc" = 1 ] && grep -q "missing: iam.workloadIdentityPools.create   (granted by roles/iam.workloadIdentityPoolAdmin)" "$W/out.txt" && grep -q 'gcloud projects add-iam-policy-binding training-custody --member="user:owner@example.org" --role="roles/iam.workloadIdentityPoolAdmin" --condition=None' "$W/out.txt" && ! grep -q -E "services enable|service-accounts create|add-iam-policy-binding" "$LOG" && chk "a missing right stops the setup before ANY change and prints the command that grants it" ok || chk "preflight: rc=$rc, changes: $(grep -c -E 'services enable|service-accounts create|add-iam-policy-binding' "$LOG")" no
rc=$(setup DRY=1); [ "$rc" = 1 ] && grep -q "missing: iam.workloadIdentityPools.create" "$W/out.txt" && chk "a dry run finds the missing right too (that is what a dry run is for)" ok || chk "dry run with a missing right: rc=$rc" no
printf 'iam.workloadIdentityPools.create\niam.serviceAccounts.create\n' > "$W/stub/deny"; rc=$(setup)
[ "$rc" = 1 ] && [ "$(grep -c 'add-iam-policy-binding training-custody --member' "$W/out.txt")" = 2 ] && grep -q "roles/iam.serviceAccountAdmin" "$W/out.txt" && chk "two missing rights give each role once (no repeated command)" ok || chk "two roles: rc=$rc" no
printf "iam.workloadIdentityPools.create\niam.workloadIdentityPoolProviders.create\niam.workloadIdentityPoolProviders.update\n" > "$W/stub/deny"; rc=$(setup)
[ "$rc" = 1 ] && [ "$(grep -c "add-iam-policy-binding training-custody --member" "$W/out.txt")" = 1 ] && [ "$(grep -c "missing: " "$W/out.txt")" = 3 ] && chk "three missing rights of one role: all three are named, the role is granted by ONE command" ok || chk "one role, three rights: rc=$rc" no
rm -f "$W/stub/deny"; touch "$W/stub/notoken"; rc=$(setup); [ "$rc" = 1 ] && grep -q "no access token for owner@example.org" "$W/out.txt" && ! grep -q -E "services enable|service-accounts create|add-iam-policy-binding" "$LOG" && chk "no access token stops the setup before any change" ok || chk "no token: rc=$rc" no
rm -f "$W/stub/deny" "$W/stub/notoken"; touch "$W/stub/apierror"; rc=$(setup); [ "$rc" = 0 ] && grep -q "warn: the rights could not be checked in advance" "$W/out.txt" && chk "if Google cannot answer (an API not enabled yet) the setup warns and goes on" ok || chk "api error: rc=$rc" no
rm -f "$W/stub/apierror" "$W/stub/exists_"*; rc=$(setup); grep -q "ok: owner@example.org holds all the rights that this setup needs" "$W/out.txt" && grep -q "roles of owner@example.org on the project: roles/editor roles/resourcemanager.projectIamAdmin" "$W/out.txt" && [ "$rc" = 0 ] && chk "with all rights it says so, shows the roles of the account, and goes on" ok || chk "all rights: rc=$rc" no
rm -f "$W/stub/exists_"*
for bad in "CI_SA_NAME=tc-ci:CI_SA_NAME 'tc-ci' is not valid" "CI_SA_NAME=Tc_Ci_Name:CI_SA_NAME 'Tc_Ci_Name' is not valid" "WIF_POOL=ab:WIF_POOL 'ab' is not valid" "WIF_PROVIDER=gcp-x1:must not contain gcp-" "GITHUB_REPO=no-slash:GITHUB_REPO 'no-slash' is not valid" "TAG_PREFIXES=x'y:TAG_PREFIXES entry"; do
  var="${bad%%:*}"; msg="${bad#*:}"; rc=$(setup DRY=1 "$var")
  [ "$rc" = 1 ] && grep -q "$msg" "$W/out.txt" && ! grep -q "services enable" "$LOG" && chk "a wrong name is refused before any command, even with DRY=1: $var" ok || chk "wrong name accepted: $var (rc=$rc)" no
done
echo; echo "pass: $pass   fail: $fail"
if [ "$fail" = 0 ]; then echo "CI-REHEARSAL-PASS"; else echo "CI-REHEARSAL-FAIL"; exit 1; fi
