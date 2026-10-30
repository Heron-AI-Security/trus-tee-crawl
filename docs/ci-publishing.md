# CI: how GitHub Actions signs in to Google Cloud, and why (step P3.1 of the mentor's plan)

**Status check, 30 October 2026.** Step P3.1 is built, ran on the real systems, and is on GitHub (commit `0f235f446`): GitHub Actions signed in to Google Cloud without a key, held all 21 rights that the publishing steps need, and created nothing. Step P3.2 (CI publishes the reference and `release.json` from a dummy run) and P3.3 (CI builds the image) are planned. This document gives the reasoning for the choices, so that anyone can judge them and change them; the decisions are ADR-094 and ADR-095 in [decisions.md](decisions.md), and the report of the whole plan is [mentor-plan-report.md](mentor-plan-report.md).

## 1. What this is, in plain words

The mentor's step 3 says that CI publishes the reference from the dummy run. "CI" is a robot that GitHub runs for us whenever we ask it to. For the robot to run our dummy run it must be allowed into our Google Cloud project, and that is the hard part: how does Google know that the visitor really is our robot and not somebody pretending?

- **The old way is a key.** We would create a secret file that says "whoever holds me is the robot" and store it in GitHub. That is like hiding a spare key under the doormat: it works, but anyone who finds it can use it, nobody notices when it is copied, and it never expires.
- **The way we chose is a visitor badge.** GitHub's front desk hands the robot a badge that says "I am the repository X, running for the tag Y", valid for a few minutes. Google's front desk (Workload Identity Federation) checks the badge against a list that we wrote: this repository only, these tags only. If the badge matches, Google lets the robot act as one limited service account for one hour. No secret file exists anywhere.

## 2. The decision and the reasoning

The mentor's plan does not name a CI system. We compared five ways, and chose the first (ADR-094).

| Option | What it is | For | Against |
|---|---|---|---|
| **A. GitHub Actions with Workload Identity Federation (chosen)** | The robot runs on GitHub's machines and signs in with the badge | No key to leak or rotate; the log is readable by a reviewer in the same place as the code; the condition (repository and tags) is ours; nothing to host | GitHub is trusted for the run (row 217); the setup needs a few one-time steps in Google; private-repository logs are visible to everyone who can read the repository |
| B. GitHub Actions with a service-account key in a secret | The same robot with a stored key | The simplest to set up | A key that can leak and never expires; Google recommends against it; rotation is manual |
| C. Cloud Build inside the project | Google runs the robot | Stays inside Google; no badge to configure | A stranger sees less of it: the log is in our project, not next to the code; one more service to learn |
| D. A self-hosted runner | A machine of ours that GitHub talks to | Full control of the machine | We must patch and trust a machine, and it would sit inside the project with the rights of the robot |
| E. Keep pasting blocks into Cloud Shell | What we did until P2 | No new parts | The published reference would depend on our word; no one else can reproduce a run |

**Why A.** The point of the mentor's step 3 is that a stranger can see how the published reference was made. Option A gives a log next to the code, a trigger that is a visible event (a pushed tag), and a sign-in without a secret. The other options either create a secret (B), hide the log (C), or add a machine to trust (D). The price of A is that we trust GitHub's hosted runners for the publication, and we state that as a limit (row 217).

**Settings that an expert would check, and where we stand.**

- *Pin every action to a full commit hash,* because a tag such as `v3` can be moved by its owner. We read the hashes from GitHub itself and read each action's definition at that commit: `actions/checkout` v7.0.1 and `google-github-actions/auth` v3.0.0, both months old.
- *Give the job the least permission,* here only `contents: read` and `id-token: write`.
- *Never run on a pull request,* because a pull request from a stranger must never obtain a Google token. The workflow starts only from a pushed tag.
- *Admit only what we need in the provider's condition:* the repository and the tag prefixes, not the whole organisation.
- *Check what the account can do, not only that it can sign in:* `ops/ci/smoke.sh` asks Google which of the listed rights the account holds, and warns about rights it does not need.

## 3. How it works

1. We push a tag that starts with `ci-smoke-` (later also `publish-ref-`). The tag is the trigger and the record of what was run.
2. GitHub starts the workflow from the file inside that tag, and the job asks GitHub for an identity token (the badge). This is allowed only because the workflow has the permission `id-token: write`.
3. The action `google-github-actions/auth` sends the badge to Google. Google's provider checks its condition: the repository must be `Heron-AI-Security/nutch-private` and the tag must start with an allowed prefix.
4. If the badge passes, Google lets the repository act as the service account `tc-github-ci`, and returns a token that lives for about an hour.
5. `gcloud` is told to use the credentials with the same command that Google's own `setup-gcloud` action runs, and `ops/ci/smoke.sh` checks the rights, the zone, the machine type, the quota and the image labels.

## 4. The security model

**What the CI can do.** It acts as `tc-github-ci@training-custody.iam.gserviceaccount.com` with the roles `roles/compute.instanceAdmin.v1` and `roles/compute.storageAdmin` in the project `training-custody`: it can create, read and delete VMs and disks and create and label images, and it cannot change IAM, create service accounts or keys, or create firewall rules. One extra right is held: `compute.projects.setCommonInstanceMetadata` (project-wide metadata, which includes SSH keys); it comes with the instance-admin role, and `smoke.sh` prints a warning about it (row 218).

**Who can start it.** Anyone who can push a tag that starts with `ci-smoke-` or `publish-ref-` to this repository. That is the same group that can push code, which is the insider model of ADR-070; stronger guards (tag protection rules, a deployment environment with required reviewers) depend on the GitHub plan and are listed in section 6 (row 215).

**The guards that exist now.**

| Guard | Where |
|---|---|
| Only this repository and only the listed tag prefixes are admitted | the provider's condition, made by `ops/ci/setup-gcp.sh` from `ops/ci/ci.env` |
| Only this repository may act as the service account | the binding made by the same script |
| No key, no stored secret | the workflow has no secret; the rehearsal fails if one appears |
| The workflow cannot be started by a pull request | its only triggers are a pushed tag and a manual run; the rehearsal fails otherwise |
| Every action is pinned to a full commit hash | checked by the rehearsal |
| Minimal permissions, no expression inside a shell script, a job timeout, a pinned runner image | checked by the rehearsal |
| The account's rights are checked from outside | `ops/ci/smoke.sh` asks Google, and warns about extra rights |

## 5. Where each setting lives, and how to change it

Nothing is written into a script that you would have to hunt for. Every value is in one file or in one GitHub variable.

| What you want to change | Where | How |
|---|---|---|
| The project, region, zone, machine type | `ops/ci/ci.env` (or an environment variable of the same name) | Edit the line, then run `ops/ci/setup-gcp.sh` again if the project changed |
| The repository that is admitted | `GITHUB_REPO` in `ops/ci/ci.env` | Edit it and run the setup again: it updates the provider's condition and the binding |
| Which tags may use the identity | `TAG_PREFIXES` in `ops/ci/ci.env`, and the `tags:` of the workflow | Change both; the rehearsal fails if a workflow tag is not admitted |
| The service account's roles | `CI_ROLES` in `ops/ci/ci.env`, and the list in `ops/ci/permissions.txt` | Change both together; the smoke test then shows what is missing or extra. A custom role that leaves out `compute.projects.setCommonInstanceMetadata` is the way to remove the extra right |
| The rights that CI must hold, or must not | `ops/ci/permissions.txt` (a line that starts with `!` is a right that CI must not need) | Edit the list |
| The three values that the workflow reads | the GitHub repository variables `GCP_PROJECT_ID`, `GCP_WIF_PROVIDER`, `GCP_SERVICE_ACCOUNT` | Settings, Secrets and variables, Actions, Variables; the setup script prints the values |
| The runner image and the action versions | `.github/workflows/ci-smoke.yml` | Change the version and the commit hash together; read the new action's definition first |

## 6. How to set it up (one time) and how to run it

**Set up the Google side.** The account that runs the setup needs more rights than the CI will ever have. With `roles/editor` and `roles/resourcemanager.projectIamAdmin` it also needs `roles/iam.serviceAccountAdmin` and `roles/iam.workloadIdentityPoolAdmin`. The setup checks this first, changes nothing if a right is missing, and prints the exact command that grants it. Then:

1. `DRY=1 bash ops/ci/setup-gcp.sh` shows what it will do and checks your rights; it changes nothing.
2. `bash ops/ci/setup-gcp.sh` creates the service account, binds its roles, creates the pool and the provider with the condition, and binds the repository to the service account. It is safe to run again.
3. Set the three GitHub repository variables that it prints.
4. **Take the two temporary roles away again** from the account that ran the setup (`gcloud projects remove-iam-policy-binding PROJECT --member=user:YOU --role=ROLE --condition=None` for each); they are only needed to run the setup (row 219).

**Run the check.** Check that GitHub Actions are on for the repository before you push the tag (a push made while they are off is not replayed). Push a tag that starts with `ci-smoke-` on the commit to check; the run appears under Actions with the name `ci-smoke` (a run started by a tag is named after the workflow, not after the commit). A green run ends with `CI-SMOKE-OK commit=` and the 40 characters of the commit.

**Other guards that can be added** (they depend on the GitHub plan, and none is needed to run): tag protection rules so that only some people can push the allowed tags; a deployment environment with required reviewers; a separate Google project for CI so that its rights cannot reach the cluster's VMs.

## 7. What the smoke test checks

`ops/ci/smoke.sh` creates nothing. It checks the tools (`gcloud`, `python3`, `curl`), who is signed in, which of the 21 listed rights the identity holds and which unwanted rights it also holds, that the zone is up, that the machine type `c3-standard-4` exists and that the quota `C3_CPUS` has room for one dummy run (4 CPUs), and that the lab's images and the labels of `tc-img-rel-1` can be read. It ends with `CI-SMOKE-OK commit=<commit>` or `CI-SMOKE-FAILED (n)`. It can also be run by hand in Cloud Shell, where it tests your account, not the CI account.

## 8. The first run, and what went wrong on the way

**The result (30 October 2026).** The run `ci-smoke #1` on the tag `ci-smoke-0f235f446` passed in 23 seconds: signed in as the service account, all 21 needed rights held, one extra right (`compute.projects.setCommonInstanceMetadata`), 24 of 24 C3 CPUs free, the zone up, 17 images listed, and the labels of `tc-img-rel-1` readable. The two temporary roles of the account that ran the setup were removed afterwards (Google answered `Updated IAM policy` for each).

**What went wrong before it, and what it taught us.**

| Symptom | Cause | What changed |
|---|---|---|
| The setup failed at its first command | The service account name `tc-ci` had 5 characters, and Google needs 6 to 30; our fake `gcloud` could not know that | The default is `tc-github-ci`; every name is validated before any command; the fake enforces the rule |
| The setup stopped after it had created the account | The account that ran it lacked the right to create the pool | The setup checks the rights first, also in a dry run, and prints the grant command |
| A scenario test passed for the wrong reason | A marker file from one scenario leaked into the next | Every scenario starts clean |
| Found before the run: `gcloud` might list no account | The sign-in action does not register one; Google's own companion action runs a login command | The workflow runs that command and the smoke test accepts a working token |
| No run started for the first tag | The tag was pushed while GitHub Actions were off | The tag was deleted and pushed again |
| The GitHub check failed once | An old `ci-code.zip` was in the Cloud Shell home and the verifier compares it too | The old zip was removed |

## 9. Limits, and what comes next

Rows 215 to 220 of [limitations-and-trust.md](limitations-and-trust.md) list the limits of this design: who can start a run (215), that CI does not yet build the image (216), that GitHub is trusted for the run (217), the extra project-wide right (218), the temporary roles of the setup (219), and that the rights were checked by Google's answer and not yet by creating a VM (220).

**Next.** P3.2: a tag `publish-ref-<commit>` starts a workflow that signs in as above, runs the dummy run of the sealed image of that commit (no SSH is needed), builds the reference, runs the release checks, and publishes the files as the assets of a GitHub release, with their SHA-256 sums. P3.3: building the image in CI.
