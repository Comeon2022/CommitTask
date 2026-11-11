# CI/CD — Verified Build and Deploy

**Status (2026-11-11):** GitHub Actions Build and Deploy both succeeded in `commitask01` / `europe-west1`. Deployment was verified by live HTTP health response; no GitHub workflow runs Terraform Apply.

## Build: `.github/workflows/docker-build.yml`

A trusted push to `main` starts the build job. GitHub OIDC WIF `github-build` impersonates dedicated `meridian-poc-builder`, whose Artifact Registry Writer access is scoped to repository `meridian-poc`. The job checks out the exact Git SHA, builds `app/Dockerfile`, embeds `SOURCE_COMMIT`, pushes a commit-tagged image and uploads an `image-release` manifest with SHA + immutable digest. No SA JSON keys.

## Deploy: `.github/workflows/cloudrun-deploy.yml`

The isolated `workflow_run` starts after the successful named build. It verifies upstream repository, successful `push`, `main` branch and manifest SHA. Separate WIF `github-deploy` authenticates `meridian-poc-ci-deploy`. This SA has Cloud Run Developer on **`meridian-poc-api` only**, ActAs on the API runtime SA and Artifact Registry Reader on the one repository. The workflow updates the *existing* service using `image@sha256:<digest>`.

The health gate requires HTTP 200 and JSON `commit == expected_sha`, `db == ok` and `secret == ok`. A successful live test reported SHA `8d89261fff66faada4df9a49e25daa8d225d7961`, but this is a historical verification, not a claim about later pushes.

Cloud Run Terraform ignores subsequent changes to the image field so that CI owns the release image. A past PoC Terraform plan showed only a Cloud Run client/scaling metadata in-place diff; **PoC Terraform zero-drift has not been proven**.

## Terraform validation and change control

- `terraform-pr.yml`: credential-free PR validation.
- `terraform-trusted-plan.yml`: manual main-only, dedicated Plan SA and `gcp-plan` GitHub Environment. It uses `-refresh=false`; therefore its output is **not a full live drift audit**.
- Bootstrap and PoC Terraform are applied outside GitHub Actions by authorized identities after reviewing a saved plan.
- `protect main` Ruleset is active with Pull Request requirement, deletion/force-push restrictions, and no bypass actors. At verification its condition matched **all branches** (`~ALL`); change the rule to `refs/heads/main` to restore normal feature branch operation.
- The Ruleset requires **zero** approving reviewers for this solo exercise. It does not guarantee independent review.
- The manual state-reading Plan workflow should have its GitHub Environment restrictions independently verified, since Terraform state includes generated secrets.

## Final smoke checks (PowerShell)

```powershell
gh run list --repo Comeon2022/CommitTask --limit 8

$health = Invoke-RestMethod 'https://meridian-poc-api-egkkxtz23a-ew.a.run.app/health'
$health | ConvertTo-Json
if ($health.db -ne 'ok' -or $health.secret -ne 'ok' -or $health.commit -notmatch '^[0-9a-f]{40}$') {
  throw 'Cloud Run health test failed'
}

gcloud storage buckets get-iam-policy gs://commitask01-tfstate-238671625358 --format=json

gcloud projects get-iam-policy commitask01 --format=json |
  ConvertFrom-Json |
  Select-Object -ExpandProperty bindings |
  Where-Object { $_.role -in @('roles/editor','roles/storage.admin') }
```

Review live IAM output for **no project Editor members**, **no temporary project Storage Admin grant** to the operator, and only the three approved state-bucket bindings. From `terraform/bootstrap`, run `C:\terraform\terraform.exe plan -input=false -detailed-exitcode`; exit 0 means no changes, exit 2 means drift and requires review.

## Known constraints

Private PostgreSQL and two PoC secret reads are live; migration Job/DDL grants and production API authentication are **not** implemented. Do not treat a public successful `/health` response as production security validation.
