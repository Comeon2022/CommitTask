# GitHub Actions trust boundaries — revised 2026-11-11

**Status:** Initial bootstrap completed and converged per operator report. The new builder identity and build WIF provider are pending an additional bootstrap apply; image-build workflow has not been tested. GCP project: `commitask01` (`238671625358`).

## Pull requests: no cloud credentials

`.github/workflows/terraform-pr.yml` runs only formatting and validation without OIDC or GCP credentials. PR authors can edit code/workflows, so executing their Terraform using privileged credentials is unsafe.

## Approved main-branch plan: read-only identity

`.github/workflows/terraform-trusted-plan.yml` is triggered **manually** by `workflow_dispatch`, checks `refs/heads/main`, and uses GitHub Environment `gcp-plan`. Its short-lived GCP identity is a dedicated `meridian-poc-plan@commitask01.iam.gserviceaccount.com`, NOT the full-write Deployer.

Bootstrap creates this SA and grants:
- `roles/viewer` and `roles/iam.securityReviewer` on `commitask01` (read-only project metadata/policies).
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
| `GCP_PROJECT_ID` | `commitask01` |
| `GCP_WIF_PROVIDER` | `projects/238671625358/locations/global/workloadIdentityPools/meridian-github/providers/github-plan` |
| `GCP_PLAN_SA` | `meridian-poc-plan@commitask01.iam.gserviceaccount.com` |
| `GCS_TF_STATE_BUCKET` | Bucket created by bootstrap |
| `TF_CANDIDATE_FULL_NAME` | Exact candidate name |
| `TF_CONTAINER_IMAGE` | Real published immutable digest |
| `TF_DEPLOYED_COMMIT` | Corresponding real commit SHA |

After bootstrap and first image publishing, run `scripts/configure-github-vars.ps1` with actual values using GitHub CLI. It does not create or approve a GitHub Environment. **Never** set a privileged deployer SA as `GCP_PLAN_SA`.

## Work remaining

- Initial bootstrap apply and no-change plan succeeded per operator; new builder-related bootstrap changes **still need apply**. Terraform PoC `validate` succeeded per operator; image build, CI and application deployment remain unverified.
- Confirm GitHub environment is protected before running cloud plans.
- Confirm service account role and GCS backend read paths by a real plan.
- Google Cloud rejected `user:gcp-hr@comm-it.cloud` and explicitly identified the identity as a **group**; operator corrected `reviewer_principal_type = "group"` and bootstrap reached no changes. Keep this local input value on every subsequent bootstrap plan/apply.
- Document AI corrections in the full original conversation transcript before handing over.


## Review of service account lookups and Secret Manager refresh — 2026-11-11

**Deployer IAM:** The deployer already has `roles/iam.serviceAccountUser` directly on both the API and migration SAs in `terraform/bootstrap/main.tf`. Google's predefined role includes `iam.serviceAccounts.get` for those identities. Therefore the `data.google_service_account` calls should be authorized; adding project-wide `roles/iam.serviceAccountViewer` is unnecessary. This must still be verified by an impersonated Terraform plan.

**Read-only CI plan:** `google_secret_manager_secret_version` resources may require `secretmanager.versions.access` when Terraform refreshes them. The separate plan-only SA deliberately does **not** have this permission. The trusted-main workflow now calls `terraform plan -refresh=false` to compare configuration with saved state without attempting a normal refresh of managed Secret Manager versions. This is a **state-based plan only**, not drift detection, and may not work if a provider schema/state migration requires refresh. Other Terraform data sources may still be read during planning. Verify behavior with a real GitHub Actions run; do not imply the plan has already passed.

**Security limitation:** Because the current Terraform state includes generated secret values, the plan SA's bucket-level Object Viewer already represents sensitive state access. A long-term solution is to seed secrets outside Terraform or use properly supported write-only secret inputs and segregated state, and only then enable richer CI refresh or PR plans. Do not grant Secret Accessor merely to suppress a CI error.

## Keyless GitHub Docker builder — 2026-11-11

**Workflow:** `.github/workflows/docker-build.yml`, triggered by a push to `main` and using only `contents:read` and `id-token:write`. It checks out the source revision, obtains a short-lived Google OAuth token through WIF, builds the `app/Dockerfile`, pushes `europe-west1-docker.pkg.dev/commitask01/meridian-poc/api:<full-git-sha>`, and reports its **immutable digest** and matching commit SHA in the GitHub Actions job summary. No Cloud Run deployment, Terraform state access, Secret Manager permission, long-lived key or Terraform apply.

**New SA:** `meridian-poc-builder@commitask01.iam.gserviceaccount.com`. Bootstrap grants **only** `roles/artifactregistry.writer` at the repository level (`meridian-poc` in `europe-west1`). There are no project-wide roles for this SA.

**Dedicated OIDC provider:** `projects/238671625358/locations/global/workloadIdentityPools/meridian-github/providers/github-build`. This provider validates immutable repo/owner IDs, full repo name, `push` event, `refs/heads/main`, and the exact workflow reference path. Its unique `attribute.pipeline = 'main-docker-build'` prevents the existing `github-plan` provider from accidentally reusing the builder impersonation binding. The builder's `roles/iam.workloadIdentityUser` IAM binding targets **only** this pipeline attribute on this SA. Neither provider can impersonate the deployer using these bindings.

**First-time setup:** An existing project bootstrap was already applied. Therefore:
1. Update the local repository with `git pull origin main` (ensure `terraform/bootstrap/terraform.tfvars` still contains `reviewer_principal_type = "group"` and operator details).
2. Re-run `terraform init`, `validate`, `plan` in `terraform/bootstrap` and review the *additional* proposed resources (builder SA, WIF provider, SA impersonation binding and repository IAM writer).
3. `terraform apply` using an approved saved plan, then verify `terraform plan` gives no changes.
4. From repository root run `gh auth login` if required, then `.\\scripts\\configure-build-vars.ps1`. This sets `GCP_PROJECT_ID`, `GCP_BUILD_SA` and `GCP_BUILD_WIF_PROVIDER` as **nonsecret repository Actions variables**. The connector cannot modify these GitHub settings itself.
5. Protect `main` with required reviews, restrict who can push/merge and alter workflows. The builder relies on **trusted main**. Wait for IAM/WIF policy propagation and inspect the **Build and publish API image (main)** workflow in GitHub Actions; any new main push builds an image. The first committed workflow may fail before bootstrap/variables are configured; **rerun it** after setup or push a reviewed follow-up change.
6. Copy the SHA and digest from the build summary into the **manual, reviewed** PoC Terraform plan. Do not deploy by a mutable tag and do not claim the image has been deployed simply because it was pushed.

**No new GitHub credential secrets required.** No Terraform apply from the build job. `github-plan` remains a distinct, manually invoked read-only state-based plan with `-refresh=false`. The builder must never be given `roles/run.admin`, `roles/cloudsql.admin`, `roles/secretmanager.secretAccessor`, or access to the state bucket.


## Publisher permissions cleanup — 2026-11-11

Once the CI builder was introduced, the former `google_artifact_registry_repository_iam_member.deployer_push` binding became unnecessary and is now **removed from Terraform source**. Only `meridian-poc-builder` receives repository-scoped `roles/artifactregistry.writer` for new images. `meridian-poc-deployer` retains infrastructure deployment permissions but cannot push images through this grant. The next privileged bootstrap `terraform plan` should show the old Deployer Writer binding being destroyed; review and apply that deliberate IAM revocation together with any pending builder resources. Do **not** run `terraform state rm`: the intended outcome is actually to revoke the live IAM member.

`scripts/prepare-release.ps1` is now a **plan-only** script. Supply `-SourceSha` (the full 40-character GitHub Actions commit) and `-ImageDigest` (`sha256:...`) from the successful Docker build summary. It constructs the immutable Artifact Registry image URI and creates the PoC Terraform plan, without Docker build, Docker push or assuming the Deployer has Artifact Registry Writer. Confirm the image really exists and corresponds to that SHA before apply.

## Automatic image deployment after a successful Build — 2026-11-11

The original pipeline published the image but did not deploy it. Now **two distinct workflows** implement Build → Deploy:
1. `.github/workflows/docker-build.yml` (push on main) builds and pushes an image tagged with the full Git SHA. It includes `SOURCE_COMMIT` as a Docker build argument, embedded into `/app/source_commit`. It uploads an `image-release` artifact containing SHA and immutable registry digest.
2. `.github/workflows/cloudrun-deploy.yml` runs after the exact build workflow succeeds (`workflow_run`). It checks the triggering run was a successful `push` on `main` in the expected repository, downloads that run's manifest, checks SHA == `workflow_run.head_sha`, and deploys *only* the digest through `gcloud run services update meridian-poc-api --image=<digest>`. It uses an independent OIDC provider restricted to `.github/workflows/cloudrun-deploy.yml`, event `workflow_run`, and main ref. The Build provider is restricted to `docker-build.yml`, event `push`. This makes the trust boundary more meaningful than two jobs in one workflow.

The new `meridian-poc-ci-deploy@commitask01.iam.gserviceaccount.com` SA has **no project-level roles and no Terraform State access**. Bootstrap gives it `roles/artifactregistry.reader` only on `meridian-poc`, `roles/iam.serviceAccountUser` only on runtime SA `meridian-poc-api`, and isolated `roles/iam.workloadIdentityUser` via `github-deploy` provider. The PoC Terraform root gives `roles/run.developer` **only on the existing `meridian-poc-api` Cloud Run service**, not the whole project.

Terraform retains ownership of Cloud Run network, IAM, environment and runtime identity; the image is CI-owned via `lifecycle.ignore_changes = [template[0].containers[0].image]`, so future Terraform plans will not roll back newer image digests. `DEPLOYED_COMMIT` is no longer injected as a service environment variable; the API reads the build SHA embedded in the image so `/health.commit` always corresponds to the actually running image. The `deployed_commit` Terraform variable remains for backward compatibility with the existing release planning scripts, but does not alter the service after the new rollout. A subsequent PoC Terraform plan should show **only the service-scoped IAM grant**. Do not run an old saved Terraform plan or automatically apply with GitHub.

**Activation order:** New source does not grant permissions until applied. Pull main, review+apply Bootstrap Terraform additions (new CI deploy SA, deploy WIF, repository Reader, SA User) using the local privileged identity. Then review+apply PoC Terraform changes (service-scoped Cloud Run Developer, removal of legacy deployed-commit env, lifecycle handoff). From repo root rerun `scripts/configure-build-vars.ps1` to add `GCP_DEPLOY_SA` and `GCP_DEPLOY_WIF_PROVIDER` repository variables. Protect main and both workflow files. Once IAM has propagated, **rerun a successful Build workflow**, or merge a new reviewed push to main; the Deploy workflow should run automatically afterwards. The deploy job checks real `GET /health`, HTTP 200 and matching SHA, `db=ok`, `secret=ok`. A failed health gate marks deployment unsuccessful and does NOT auto-rollback; investigate before retrying.

**Important limitations:** Role scoping does not prevent a trusted deployer from deliberately changing the configuration of its one service, so protect the GitHub main branch and workflows. GitHub `workflow_run` needs `actions:read` to fetch the upstream manifest, but it does not download executable code from the build artifact. Image SHA/digest are public metadata, not secrets. The Cloud Run service must already exist; there is no project-wide Cloud Run create role. This flow has been committed in source but was **not yet applied or tested in the live GCP environment**.
