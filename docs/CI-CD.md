# CI/CD preparation — GitHub Actions, not GitLab CI

**Status:** GCP project identifiers supplied by operator: **Project ID `commitask`**, **Project Number `924903658971`**. Cloud bootstrap, WIF creation and pipeline execution have NOT been verified.

This exercise explicitly uses **GitHub Actions**, and the repository is `Comeon2022/CommitTask` on GitHub. The workflow is at `.github/workflows/terraform-pr.yml`. If the team decides to migrate to GitLab later, this must be redesigned for GitLab's OIDC issuer, project claims and `.gitlab-ci.yml`; the current GitHub workflow cannot run in GitLab unchanged.

## Design

- PR `validate` job: `terraform fmt -check -recursive`, `terraform init -backend=false`, `terraform validate` for both roots. No cloud credentials.
- PR `plan` job: **same-repository PRs only**; uses OIDC via `google-github-actions/auth@v3`, impersonates `meridian-poc-deployer`, initializes the existing GCS state backend, and runs `terraform plan -lock=false`.
- No `terraform apply` in GitHub Actions. Bootstrap and first deployments are operator-driven until tested.
- WIF trust is scoped to GitHub immutable repository ID **1453727041**, owner ID **104059889**, and PR event. The Terraform provider name is emitted by `terraform/bootstrap` as `github_workload_identity_provider`.
- The `gcp-plan` GitHub Environment **must be created and restricted to approved maintainers as required reviewers** before enabling the cloud plan job. GitHub environment protection availability depends on repository/plan. The workflow itself cannot create that policy.
- This is a PoC tradeoff: the PR `plan` uses the infrastructure deployer SA with write-capable roles. A production pipeline should have a separate `terraform-plan` identity with read-only resource permissions and carefully scoped GCS state access. Do not allow untrusted PR authors to execute or modify authenticated jobs.

## Setup after the GCP project exists

1. Run **bootstrap Terraform** using a privileged human administrator. Bootstrap enables IAM/ST​S/IAM Credentials, creates identities and role bindings, and creates a GitHub WIF provider.
2. Record `terraform output github_workload_identity_provider`; its path contains the **numeric GCP project number**, not merely the project ID.
3. Configure the protected GitHub Environment `gcp-plan` under repository Settings -> Environments. Add required reviewers and restrict who can approve.
4. In repository Settings -> Secrets and variables -> Actions -> **Variables**, configure the following (these are identifiers, **not** credentials):

| GitHub Actions variable | Purpose |
| --- | --- |
| `GCP_PROJECT_ID` | `commitask` |
| `GCP_WIF_PROVIDER` | After bootstrap, `projects/924903658971/locations/global/workloadIdentityPools/meridian-github/providers/github-pr` |
| `GCP_DEPLOYER_SA` | `meridian-poc-deployer@commitask.iam.gserviceaccount.com` |
| `GCS_TF_STATE_BUCKET` | Globally unique state bucket created by bootstrap |
| `TF_CANDIDATE_FULL_NAME` | Exact interview candidate name |
| `TF_CONTAINER_IMAGE` | Built/pushed Artifact Registry image reference (ideally digest) |
| `TF_DEPLOYED_COMMIT` | Real short source SHA corresponding to the image |

5. Initialize PoC state and make the *first deployment* using `docs/DEPLOY.md`; PR plans can then inspect existing state.
6. Open an internal PR changing Terraform; confirm validate passes and, after environment approval, plan completes. Open a PR from a fork to confirm the authenticated job is skipped.
7. Keep sensitive plan outputs private: Terraform plans can include secret-related diffs. **Do not upload plaintext plan artifacts or post raw plans to public PR comments.**

## Current limits

- The original exercise requires keeping full AI conversation transcripts in `AI-LOG.md`. That is not completed here.
- This pipeline depends on GCP and GitHub Environment configuration; neither is presently verified.
- `terraform plan -lock=false` skips state locking: acceptable for a read-only PR plan in this PoC, **not** for applies.
- GitHub Actions `pull_request` workflow changes from trusted same-repository branches need code review. Do not enable the cloud plan job for arbitrary contributors.
- `terraform validate` and formatting checks still need an actual run; failures must be corrected before submission.
- Avoid GCP SA JSON keys in GitHub secrets. Workload Identity Federation is the intended authentication method.

References:
- https://github.com/google-github-actions/auth
- https://docs.cloud.google.com/iam/docs/workload-identity-federation-with-deployment-pipelines
- https://developer.hashicorp.com/terraform/language/backend/gcs


## Known project identities and safe local setup

The GitHub Actions **repository variables are not created by committing files**. The authenticated GitHub connector currently does not expose repository Actions variable or Environment management, so no change to GitHub Settings has been made here.

Once bootstrap and container build/push are complete, use:

```powershell
.\\scripts\\configure-github-vars.ps1 -StateBucket "ACTUAL_BUCKET_NAME" `\n  -CandidateFullName "ACTUAL_COMMIT_NAME" `\n  -ContainerImage "europe-west1-docker.pkg.dev/commitask/meridian-poc/api@sha256:ACTUAL_DIGEST" `\n  -DeployedCommit "ACTUAL_SHORT_GIT_SHA"
```

This script checks the project ID/number pairing and existence of the WIF provider, then writes **non-secret identifiers** using `gh variable set`. Create the protected `gcp-plan` environment via GitHub Settings before running authenticated plans. The Project Number is used in the WIF provider resource path; the Project ID is used in email and Artifact Registry references.
