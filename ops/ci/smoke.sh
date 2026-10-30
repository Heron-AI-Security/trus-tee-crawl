#!/usr/bin/env bash
# ops/ci/smoke.sh: step P3.1 of the mentor's plan. Can CI sign in to Google Cloud, does it hold the rights that the publishing steps need, and not many more?
# It CREATES NOTHING and changes nothing. It runs in GitHub Actions (the workflow ci-smoke) and by hand in Cloud Shell (it then tests YOUR account).
# Settings: ops/ci/ci.env. The rights: ops/ci/permissions.txt. It ends with  CI-SMOKE-OK commit=<commit>  or  CI-SMOKE-FAILED (n).
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=ci.env
. "$HERE/ci.env"
bad=0; say() { echo "$*"; }; ok() { say "   ok:   $*"; }; no() { say "   FAIL: $*"; bad=$((bad+1)); }; warn() { say "   warn: $*"; }
say "== 1. the tools"
if command -v gcloud >/dev/null 2>&1; then ok "$(gcloud --version 2>/dev/null | head -1)"; else no "gcloud is not installed"; fi
if command -v python3 >/dev/null 2>&1; then ok "$(python3 --version 2>&1)"; else no "python3 is not installed"; fi
if command -v curl >/dev/null 2>&1; then ok "curl"; else no "curl is not installed"; fi
say "== 2. who is signed in"
ACC="$(gcloud auth list --filter=status:ACTIVE --format='value(account)' 2>/dev/null | head -1)"
TOKEN="$(gcloud auth print-access-token 2>/dev/null)"
if [ -n "$ACC" ]; then ok "active account: $ACC"
elif [ -n "$TOKEN" ]; then ok "signed in through a credentials file ($(basename "${CLOUDSDK_AUTH_CREDENTIAL_FILE_OVERRIDE:-${GOOGLE_APPLICATION_CREDENTIALS:-unknown}}")); gcloud lists no account, but it has a working access token"
else no "not signed in: no active account and no access token (the sign-in step did not work; read its log)"; fi
if [ -n "${EXPECT_SA:-}" ] && [ -n "$ACC" ]; then
  case "$ACC" in *"$EXPECT_SA"*) ok "it is the expected service account";; *) warn "the expected service account $EXPECT_SA is not the printed account (gcloud may print the federated identity); the rights below are what counts";; esac
fi
say "== 3. the rights of this identity in project $PROJECT_ID (Google is asked which of the listed rights it holds)"
if [ -z "$TOKEN" ]; then no "no access token"; else
  REQ="$(python3 - "$HERE/permissions.txt" <<'PY'
import json, sys
perms = [l.strip().lstrip("!") for l in open(sys.argv[1]) if l.strip() and not l.lstrip().startswith("#")]
print(json.dumps({"permissions": sorted(set(perms))}))
PY
)"
  RESP="$(curl -sS --max-time 60 -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" -d "$REQ" "https://cloudresourcemanager.googleapis.com/v1/projects/${PROJECT_ID}:testIamPermissions" 2>&1)"
  OUT="$(RESP="$RESP" python3 - "$HERE/permissions.txt" <<'PY'
import json, os, sys
lines = [l.strip() for l in open(sys.argv[1]) if l.strip() and not l.lstrip().startswith("#")]
need = [l for l in lines if not l.startswith("!")]; avoid = [l[1:] for l in lines if l.startswith("!")]
try: r = json.loads(os.environ["RESP"])
except ValueError: print("ERROR the answer of Google is not JSON: " + os.environ["RESP"][:200].replace("\n", " ")); sys.exit(0)
if "error" in r: print("ERROR " + str(r["error"].get("message", r["error"]))[:300].replace("\n", " ")); sys.exit(0)
got = set(r.get("permissions", []))
for p in need: print(("HAS " if p in got else "MISSING ") + p)
for p in avoid:
    if p in got: print("EXTRA " + p)
PY
)"
  if printf '%s\n' "$OUT" | grep -q '^ERROR '; then no "$(printf '%s\n' "$OUT" | grep '^ERROR ' | head -1)"
  else
    nh="$(printf '%s\n' "$OUT" | grep -c '^HAS ')"; nm="$(printf '%s\n' "$OUT" | grep -c '^MISSING ')"
    if [ "$nm" = 0 ] && [ "$nh" -gt 0 ]; then ok "all $nh needed rights are held"; else no "$nm needed right(s) are missing, $nh are held:"; printf '%s\n' "$OUT" | grep '^MISSING ' | sed 's/^MISSING /           missing: /'; fi
    printf '%s\n' "$OUT" | grep '^EXTRA ' | sed 's/^EXTRA /   warn: not needed, but held (least privilege): /'
  fi
fi
say "== 4. the zone, the machine type and the quota for one dummy-run VM"
Z="$(gcloud compute zones describe "$ZONE" --project "$PROJECT_ID" --format='value(status)' 2>&1)"
if [ "$Z" = UP ]; then ok "zone $ZONE is UP"; else no "zone $ZONE: ${Z:0:200}"; fi
M="$(gcloud compute machine-types describe "$MACHINE_TYPE" --zone "$ZONE" --project "$PROJECT_ID" --format='value(guestCpus,memoryMb)' 2>&1)"
CPUS="$(printf '%s' "$M" | cut -f1)"
if [ -n "$CPUS" ] && [ "$CPUS" -eq "$CPUS" ] 2>/dev/null; then ok "machine type $MACHINE_TYPE: $CPUS vCPU, $(printf '%s' "$M" | cut -f2) MB"; else no "machine type $MACHINE_TYPE: ${M:0:200}"; CPUS=4; fi
Q="$(gcloud compute regions describe "$REGION" --project "$PROJECT_ID" --format=json 2>&1)"
QOUT="$(Q="$Q" CPUS="$CPUS" python3 - <<'PY'
import json, os
try: r = json.loads(os.environ["Q"])
except ValueError: print("ERROR " + os.environ["Q"][:200].replace("\n", " ")); raise SystemExit
q = [x for x in r.get("quotas", []) if x.get("metric") == "C3_CPUS"]
if not q: print("NONE"); raise SystemExit
free = q[0]["limit"] - q[0]["usage"]; print("%s %d %d %d" % ("OK" if free >= int(os.environ["CPUS"]) else "LOW", q[0]["usage"], q[0]["limit"], free))
PY
)"
case "$QOUT" in
  OK*|LOW*)
    read -r qst qused qlimit qfree <<<"$QOUT"
    if [ "$qst" = OK ]; then ok "quota C3_CPUS in $REGION: $qused of $qlimit used, $qfree free (one dummy run needs $CPUS)"; else no "quota C3_CPUS in $REGION: $qused of $qlimit used, only $qfree free (one dummy run needs $CPUS)"; fi;;
  NONE*) warn "no C3_CPUS quota is listed for $REGION: not checked";;
  *) no "the quota of $REGION cannot be read: ${QOUT:0:200}";;
esac
say "== 5. the images of the lab (information; this also shows that the labels of an image can be read)"
L="$(gcloud compute images list --project "$PROJECT_ID" --no-standard-images --filter="name~^${IMAGE_PREFIX}" --format='value(name,status)' 2>&1)"; lrc=$?
if [ $lrc = 0 ]; then ok "$(printf '%s\n' "$L" | grep -c .) image(s) named ${IMAGE_PREFIX}*"; printf '%s\n' "$L" | head -8 | sed 's/^/         /'; else no "the images cannot be listed: ${L:0:200}"; fi
I="$(gcloud compute images describe "$CHECK_IMAGE" --project "$PROJECT_ID" --format=json 2>&1)"; irc=$?
if [ $irc = 0 ]; then say "   info: labels of $CHECK_IMAGE: $(I="$I" python3 -c 'import json,os; print(json.loads(os.environ["I"]).get("labels", {}))')"; else say "   info: image $CHECK_IMAGE cannot be read (${I:0:80}): fine before the first release"; fi
say ""
if [ "$bad" = 0 ]; then say "CI-SMOKE-OK commit=${GITHUB_SHA:-local}"; else say "CI-SMOKE-FAILED ($bad)"; exit 1; fi
