#!/usr/bin/env bash
# ops/ci/setup-gcp.sh: the ONE-TIME setup of the Google side of CI (ADR-094, docs/ci-publishing.md):
#   a service account with the roles of ci.env, a Workload Identity pool and provider that admit ONLY this repository and ONLY the tags of ci.env,
#   and the binding that lets that repository act as the service account. No key is created: GitHub proves who it is with a short-lived token.
# Run it in Cloud Shell, as an owner of the project:    bash ops/ci/setup-gcp.sh        (DRY=1 shows the commands and runs none of the changes)
# It is safe to run again: what exists is kept, the provider's condition is updated, and the roles are added again without harm.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci.env
. "$HERE/ci.env"
fail() { echo "SETUP-GCP-FAILED: $*" >&2; exit 1; }
# Google's naming rules, checked here so that a wrong name is refused before any change, and also by DRY=1 (a dry run only prints, it cannot know the rules).
valid() { [[ "$2" =~ $3 ]] || fail "$1 '$2' is not valid: $4"; }
valid CI_SA_NAME "$CI_SA_NAME" '^[a-z][a-z0-9-]{4,28}[a-z0-9]$' "6 to 30 characters, lowercase letters, digits and hyphens, starting with a letter"
valid WIF_POOL "$WIF_POOL" '^[a-z0-9-]{4,32}$' "4 to 32 characters, lowercase letters, digits and hyphens"
valid WIF_PROVIDER "$WIF_PROVIDER" '^[a-z0-9-]{4,32}$' "4 to 32 characters, lowercase letters, digits and hyphens"
case "$WIF_POOL$WIF_PROVIDER" in *gcp-*) fail "WIF_POOL and WIF_PROVIDER must not contain gcp- (Google reserves it)";; esac
valid GITHUB_REPO "$GITHUB_REPO" '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' "it must look like owner/repository"
valid PROJECT_ID "$PROJECT_ID" '^[a-z][a-z0-9-]{4,28}[a-z0-9]$' "6 to 30 characters, lowercase letters, digits and hyphens"
for p in $TAG_PREFIXES; do valid "TAG_PREFIXES entry" "$p" '^[A-Za-z0-9._-]+$' "only letters, digits, dot, underscore and hyphen (a quote would change the provider's condition)"; done
run() { echo "+ $*"; [ "${DRY:-0}" = 1 ] && return 0; "$@" || fail "the command above failed"; }
quiet() { echo "+ $*  (output hidden)"; [ "${DRY:-0}" = 1 ] && return 0; "$@" >/dev/null || fail "the command above failed"; }
ACC="$(gcloud config get-value account 2>/dev/null)"; [ -n "$ACC" ] || fail "no gcloud account is signed in"
PN="$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)' 2>/dev/null)"; [ -n "$PN" ] || fail "project $PROJECT_ID cannot be read by $ACC"
SA="${CI_SA_NAME}@${PROJECT_ID}.iam.gserviceaccount.com"
COND="assertion.repository == '${GITHUB_REPO}'"; T=""
for p in $TAG_PREFIXES; do T="${T:+$T || }assertion.ref.startsWith('refs/tags/${p}')"; done
[ -n "$T" ] || fail "TAG_PREFIXES is empty: the provider would admit no run"
COND="$COND && ($T)"
MAP="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner,attribute.ref=assertion.ref"
echo "account:  $ACC"; echo "project:  $PROJECT_ID (number $PN)"; echo "service account: $SA"; echo "repository: $GITHUB_REPO"; echo "condition: $COND"; [ "${DRY:-0}" = 1 ] && echo "(DRY=1: no change is made)"
echo "== 0. the rights of $ACC for this setup (read-only: nothing is changed; DRY=1 does it too)"
# permission:role that grants it. If a right is missing the setup stops here, before the first change, and prints the command that grants it.
NEEDS=(serviceusage.services.enable:roles/serviceusage.serviceUsageAdmin iam.serviceAccounts.create:roles/iam.serviceAccountAdmin iam.serviceAccounts.setIamPolicy:roles/iam.serviceAccountAdmin resourcemanager.projects.setIamPolicy:roles/resourcemanager.projectIamAdmin iam.workloadIdentityPools.create:roles/iam.workloadIdentityPoolAdmin iam.workloadIdentityPoolProviders.create:roles/iam.workloadIdentityPoolAdmin iam.workloadIdentityPoolProviders.update:roles/iam.workloadIdentityPoolAdmin)
case "$ACC" in *.gserviceaccount.com) MEMBER="serviceAccount:$ACC";; *) MEMBER="user:$ACC";; esac
MYROLES="$(gcloud projects get-iam-policy "$PROJECT_ID" --flatten='bindings[].members' --filter="bindings.members:$MEMBER" --format='value(bindings.role)' 2>/dev/null | tr '\n' ' ')"
echo "   roles of $ACC on the project: ${MYROLES:-(could not be read)}"
TOKEN="$(gcloud auth print-access-token 2>/dev/null)"
if [ -z "$TOKEN" ]; then fail "no access token for $ACC: sign in again (gcloud auth login) and run this again; nothing was changed"; else
  REQ="$(python3 -c 'import json, sys; print(json.dumps({"permissions": [a.split(":")[0] for a in sys.argv[1:]]}))' "${NEEDS[@]}")"
  RESP="$(curl -sS --max-time 60 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$REQ" "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}:testIamPermissions" 2>&1)"
  MISS="$(RESP="$RESP" python3 - "${NEEDS[@]}" <<'PY'
import json, os, sys
need = [a.split(":", 1) for a in sys.argv[1:]]
try: r = json.loads(os.environ["RESP"])
except ValueError: print("UNKNOWN the answer of Google is not JSON"); sys.exit(0)
if "error" in r: print("UNKNOWN " + str(r["error"].get("message", ""))[:200].replace("\n", " ")); sys.exit(0)
got = set(r.get("permissions", []))
for p, role in need:
    if p not in got: print("MISSING %s %s" % (p, role))
PY
)"
  if printf '%s\n' "$MISS" | grep -q '^UNKNOWN '; then echo "   warn: the rights could not be checked in advance ($(printf '%s\n' "$MISS" | grep '^UNKNOWN ' | head -1 | cut -c9-)); the setup goes on and Google will refuse a missing right"
  elif printf '%s\n' "$MISS" | grep -q '^MISSING '; then
    echo "   $ACC lacks these rights, so NOTHING was changed:"; printf '%s\n' "$MISS" | grep '^MISSING ' | awk '{print "     missing: " $2 "   (granted by " $3 ")"}'
    echo "   Grant the missing role(s) to your account, wait one minute, and run this again:"
    printf '%s\n' "$MISS" | grep '^MISSING ' | awk '{print $3}' | sort -u | while read -r role; do echo "     gcloud projects add-iam-policy-binding $PROJECT_ID --member=\"$MEMBER\" --role=\"$role\" --condition=None"; done
    fail "the account $ACC lacks rights that this setup needs (see above)"
  else echo "   ok: $ACC holds all the rights that this setup needs"; fi
fi
echo "== 1. the services that the sign-in and CI use"
run gcloud services enable iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com cloudresourcemanager.googleapis.com compute.googleapis.com --project "$PROJECT_ID"
echo "== 2. the service account"
if gcloud iam service-accounts describe "$SA" --project "$PROJECT_ID" >/dev/null 2>&1; then echo "   exists: $SA"; else run gcloud iam service-accounts create "$CI_SA_NAME" --project "$PROJECT_ID" --display-name "CI of the attested cluster"; fi
echo "== 3. its roles"
for r in $CI_ROLES; do quiet gcloud projects add-iam-policy-binding "$PROJECT_ID" --member "serviceAccount:$SA" --role "$r" --condition=None; done
echo "== 4. the Workload Identity pool"
if gcloud iam workload-identity-pools describe "$WIF_POOL" --project "$PROJECT_ID" --location global >/dev/null 2>&1; then echo "   exists: $WIF_POOL"; else run gcloud iam workload-identity-pools create "$WIF_POOL" --project "$PROJECT_ID" --location global --display-name "GitHub Actions"; fi
echo "== 5. the provider (it admits only the repository and the tags above)"
if gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" --project "$PROJECT_ID" --location global --workload-identity-pool "$WIF_POOL" >/dev/null 2>&1; then
  run gcloud iam workload-identity-pools providers update-oidc "$WIF_PROVIDER" --project "$PROJECT_ID" --location global --workload-identity-pool "$WIF_POOL" --attribute-mapping "$MAP" --attribute-condition "$COND" --issuer-uri "https://token.actions.githubusercontent.com"
else
  run gcloud iam workload-identity-pools providers create-oidc "$WIF_PROVIDER" --project "$PROJECT_ID" --location global --workload-identity-pool "$WIF_POOL" --display-name "GitHub repository" --attribute-mapping "$MAP" --attribute-condition "$COND" --issuer-uri "https://token.actions.githubusercontent.com"
fi
echo "== 6. the binding: this repository may act as the service account"
quiet gcloud iam service-accounts add-iam-policy-binding "$SA" --project "$PROJECT_ID" --role roles/iam.workloadIdentityUser --member "principalSet://iam.googleapis.com/projects/${PN}/locations/global/workloadIdentityPools/${WIF_POOL}/attribute.repository/${GITHUB_REPO}"
PROV="projects/${PN}/locations/global/workloadIdentityPools/${WIF_POOL}/providers/${WIF_PROVIDER}"
[ "${DRY:-0}" = 1 ] || { got="$(gcloud iam workload-identity-pools providers describe "$WIF_PROVIDER" --project "$PROJECT_ID" --location global --workload-identity-pool "$WIF_POOL" --format='value(name)' 2>/dev/null)"; [ "$got" = "$PROV" ] || fail "the provider is called '$got', expected '$PROV'"; }
echo; echo "Set these three GitHub repository variables (Settings > Secrets and variables > Actions > Variables > New repository variable):"
echo "  GCP_PROJECT_ID       $PROJECT_ID"; echo "  GCP_WIF_PROVIDER     $PROV"; echo "  GCP_SERVICE_ACCOUNT  $SA"
echo "or, with the gh CLI signed in to the repository:"
echo "  gh variable set GCP_PROJECT_ID --repo $GITHUB_REPO --body '$PROJECT_ID'"; echo "  gh variable set GCP_WIF_PROVIDER --repo $GITHUB_REPO --body '$PROV'"; echo "  gh variable set GCP_SERVICE_ACCOUNT --repo $GITHUB_REPO --body '$SA'"
echo "SETUP-GCP-OK"
