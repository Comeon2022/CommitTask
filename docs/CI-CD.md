# GitHub Actions trust boundaries — revised 2026-11-11

**Status:** Terraform source and workflow committed; bootstrap and CI runs NOT executed. GCP project: `commitask` (`924903658971`).

## Pull requests: no cloud credentials

`.github/workflows/terraform-pr.yml` runs only formatting and validation without OIDC or GCP credentials. PR authors can edit code/workflows, so executing their Terraform using privileged credentials is unsafe.

## Approved main-branch plan: read-only identity

`.github/workflows/terraform-trusted-plan.yml` is triggered **manually** by `workflow_dispatch`, checks `refs/heads/main`, and uses GitHub Environment `gcp-plan`. Its short-lived GCP identity is a dedicated `meridian-poc-plan@commitask.iam.gserviceaccount.com`, NOT the full-write Deployer.

Bootstrap creates this SA and grants:
- `roles/viewer` and `roles/iam.securityReviewer` on `commitask` (read-only project metadata/policies).
- `roles/storage.objectViewer` on the **Terraform state bucket only**, to load existing state.
- `roles/iam.workloadIdentityUser` on this **plan SA only**, allowing trusted provider tokens to impersonate it. **No** WIF binding on the deployer SA.

The WIF provider `meridian-github/providers/github-plan` restricts GitHub immutable repository/owner IDs, repository name, `main` branch, and `workflow_dispatch` event. It cannot authenticate from `pull_request`.

**Mandatory protection before enabling the job:** protect `main` with required reviews and restrict merges/force pushes; create `gcp-plan` GitHub Environment with required reviewers and branch deployment restrictions. Only trusted maintainers should be able to approve it. Verify GitHub plan/environment availability and policy in Settings. A workflow in a public repo is not trustworthy merely because it is named "plan".

**Critical trade-off:** Current Terraform State includes two generated secret payloads, so a state-reader can technically obtain sensitive values. Thus plan-only is **read-only, not necessarily read-safe**. No raw plan artifacts or state files may be shared; keep the manual job gated. Production should seed secrets outside Terraform and use finer-grained state segregation before granting PR plans any access.

**Terraform plan permissions:** Predefined Viewer and Security Reviewer roles are starting values, not a proven sufficient set of permissions for every data source/provider refresh. Run the plan and refine with least privilege based on actual errors; do not grant admin roles to make it pass.

## Apply and first release

The **privileged bootstrap root** creates Artifact Registry before the first Docker push; the normal PoC root no longer creates it. Bootstrap grants the deployer `roles/artifactregistry.writer` on this specific repository.

`scripts/prepare-release.ps1` sets short-lived impersonation for **both** GCloud Docker authentication and the Terraform Google provider, confirms the registry exists, builds and pushes from a clean checked-out Git SHA, obtains the immutable digest, and saves the Terraform plan with consistent `container_image`/`deployed_commit`. The GCS backend is initialized with `impersonate_service_account` too.

**No auto-apply in GitHub Actions.** A human reviews/applies the saved plan using the authorized deployer SA. Never run the PoC apply as a human Owner without knowing it.

## Bootstrap Terraform input variables

```hcl
github_repository_full_name = "Comeon2022/CommitTask"
github_repository_id        = "1453727041"
github_owner_id             = "104059889"
```

These are inputs, not hard-coded in the OIDC provider expression. Validate them after repo ownership changes.

## GitHub repository Actions Variables (after bootstrap)

| Variable | Expected value |
| --- | --- |
| `GCP_PROJECT_ID` | `commitask` |
| `GCP_WIF_PROVIDER` | `projects/924903658971/locations/global/workloadIdentityPools/meridian-github/providers/github-plan` |
| `GCP_PLAN_SA` | `meridian-poc-plan@commitask.iam.gserviceaccount.com` |
| `GCS_TF_STATE_BUCKET` | Bucket created by bootstrap |
| `TF_CANDIDATE_FULL_NAME` | Exact candidate name |
| `TF_CONTAINER_IMAGE` | Real published immutable digest |
| `TF_DEPLOYED_COMMIT` | Corresponding real commit SHA |

After bootstrap and first image publishing, run `scripts/configure-github-vars.ps1` with actual values using GitHub CLI. It does not create or approve a GitHub Environment. **Never** set a privileged deployer SA as `GCP_PLAN_SA`.

## Work remaining

- Terraform `fmt/validate`, GCP bootstrap and successful plan execution **not verified yet**.
- Confirm GitHub environment is protected before running cloud plans.
- Confirm service account role and GCS backend read paths by a real plan.
- Reviewer `gcp-hr@comm-it.cloud` may be a **user or Google Group**; the type cannot be inferred from email. Bootstrap now has `reviewer_principal_type`, default `user`, and must be set to `group` if directory ownership confirms it is a group.
- Document AI corrections in the full original conversation transcript before handing over.
