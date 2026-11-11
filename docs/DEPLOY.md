# GCP deployment runbook (PowerShell)

**Status:** Not yet deployed; Terraform has not been validated against a real project. This is a plan, not a successful deployment report.

## Confirmed identifiers

Project ID: `commitask01`; Project Number: `238671625358`; region: `europe-west1`. These were supplied by the project owner. No actual cloud resources have been inspected or deployed.

## Prerequisites

New billing-enabled GCP project; Terraform, Docker, Git and Google Cloud SDK installed. Choose unique GCS bucket name, and ensure the bootstrap **human administrator** has permissions to configure IAM and create infrastructure. No service-account JSON keys.

## Step 1 — bootstrap identities and remote state bucket

```powershell
$ProjectId = "commitask01"
$Region    = "europe-west1"
$Bucket    = "YOUR_GLOBALLY_UNIQUE_BUCKET_NAME"

gcloud auth login
gcloud auth application-default login
gcloud config set project $ProjectId

cd terraform/bootstrap
terraform init
terraform plan -var="project_id=$ProjectId" -var="state_bucket_name=$Bucket" -var="github_repository_full_name=Comeon2022/CommitTask" -var="github_repository_id=1453727041" -var="github_owner_id=104059889"
terraform apply -var="project_id=$ProjectId" -var="state_bucket_name=$Bucket" -var="terraform_operator_email=YOUR_USER@YOUR_DOMAIN" -var="github_repository_full_name=Comeon2022/CommitTask" -var="github_repository_id=1453727041" -var="github_owner_id=104059889"
terraform output deployer_service_account
terraform output api_service_account
terraform output developer_service_accounts
```

Bootstrap grants functional roles to the deployer, creates API, migration, three developer SAs and the regional Artifact Registry repository. Human developer identities are optional until actual emails are supplied via `developer_emails`. The bootstrap creates a **temporary local state**: keep it secured, do not commit it, and migrate it to protected remote storage as a separate controlled step. The GCS state bucket is versioned, **`EU` multi-region**, and private (an intentional resilience exception). Both Terraform roots permit only `europe-west1`, `europe-west3`, or `europe-west4`, defaulting to `europe-west1`. All deployed regional application resources must use the same selected region. See `docs/REGION-DESIGN.md` for global GCP exceptions.

**Bootstrap now includes an optional `terraform_operator_email` input.** Set this to the human Google account running Terraform. Bootstrap binds `roles/iam.serviceAccountTokenCreator` **only on** `meridian-poc-deployer`, not at project scope. If left empty, nobody gets local impersonation through this Terraform resource; local runs require a separate authorized IAM binding. The deployer SA does not use a JSON key.

## Step 2 — initialize the PoC under short-lived SA impersonation

```powershell
cd ../poc
$Deployer = "meridian-poc-deployer@$ProjectId.iam.gserviceaccount.com"
$env:GOOGLE_IMPERSONATE_SERVICE_ACCOUNT = $Deployer
terraform init -backend-config="bucket=$Bucket" -backend-config="prefix=meridian/poc"
```

The human caller still needs read/write access to the backend bucket, or a working ADC-backed impersonation flow supported by the Terraform GCS backend. Do not assume `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` alone authorizes bucket access; verify which principal is accessing the state bucket. Grant GCS object permissions for only the state bucket/prefix as permitted by your organization; avoid broad project Storage Admin.

## Step 3 — verify that Artifact Registry already exists

The `meridian-poc` Docker repository is now defined in **`terraform/bootstrap/artifact_registry.tf`**, created as part of the initial privileged bootstrap apply in Step 1. No `terraform -target` is needed.

```powershell
gcloud artifacts repositories describe meridian-poc --project=commitask01 --location=$Region
```

If absent, rerun **bootstrap Terraform** after checking its plan. Never push the application image before the repository exists.

## Step 4 — release with keyless deployer impersonation

From repository root, after operator impersonation has been granted in Bootstrap, run the controlled script:

```powershell
.\scripts\prepare-release.ps1 -CandidateFullName "YOUR_ACTUAL_COMMIT_NAME" `
  -StateBucket $Bucket -ProjectId commitask01 -Region $Region
```

The script checks the registry, sets `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` and `CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT` to `meridian-poc-deployer@commitask01.iam.gserviceaccount.com`, validates impersonation, builds from a clean Git commit, pushes, resolves an immutable image digest and creates a **saved** Terraform plan. It does not apply. The Docker push is performed via short-lived deployer credentials and its repository-specific Artifact Registry Writer permission.

Inspect the saved plan before applying:

```powershell
terraform -chdir=terraform/poc show release.tfplan
terraform -chdir=terraform/poc apply release.tfplan
terraform -chdir=terraform/poc output health_url
```

**Important:** A later shell may need to set `$env:GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` again (and reinitialize with GCS backend impersonation) before applying. Do not run as a human Owner by accident. `terraform show` on a plan may expose sensitive details; do not paste output into PR comments.

The `/health` handler must return a 200 JSON response with correct name/actual commit/region and `db` and `secret` equal to `ok`. Both checks execute per request. Verify SQL has **no PUBLIC IPv4 address**.

## Known issues and risks

- The application authenticates to PostgreSQL as its **runtime service account** using Cloud SQL IAM DB auth, not a password. Both mandatory Secret Manager secrets now exist and are read by the API at runtime: the DB password belongs to a separate built-in PostgreSQL user, and the second secret is a synthetic provider token. See `docs/SECRETS-DESIGN.md`.
- SQL connector requires private route to Cloud SQL and API access to Google Cloud (TCP 443 plus connector's 3307 connection). The project must support Direct VPC egress and Private Google Access.
- The built-in DB user's password and the synthetic provider token are generated by Terraform: both secret values are present in GCS Terraform state and historical bucket versions. This must be revised for a production setting.
- No migration Cloud Run Job or SQL DDL grants yet: developer service accounts cannot execute migrations until that job is deployed and per-job IAM is configured.
- `terraform validate`, real image push and cloud deployment have **not** been executed by the assistant. The infrastructure may need provider/version corrections based on actual validation.
- Public invocation may be prevented by organization policy. Use an approved dedicated evaluation project.
- Keep the environment running until the review, then tear down with Terraform.


## Future Google Group design (NOT implemented)

We propose a Cloud Identity/Google Workspace group named `db_secret_reader` for selected human users to read **only** the DB-password secret. This currently requires directory provisioning and a verified group email, so **no Google Group membership, IAM policy binding, or related Terraform variable exists**. Do not configure a placeholder email. See `docs/SECRETS-DESIGN.md`.

## GitHub Actions

The GitHub Actions PR workflow remains **credential-free**. A separate `workflow_dispatch` Plan from approved `main` uses `meridian-poc-plan` read-only SA, with no deployer impersonation or apply. See `docs/CI-CD.md` for required GitHub Environment protections. See `docs/CI-CD.md`.


## Granting Commit reviewer access

The bootstrap Terraform root creates a project-level `roles/viewer` IAM binding for `gcp-hr@comm-it.cloud`. The identity can inspect GCP resources but has no permission from that role to access Secret Manager secret **payloads** or Terraform state **objects**. After applying bootstrap, verify with:

```powershell
gcloud projects get-iam-policy commitask01 --flatten="bindings[].members" --filter="bindings.role=roles/viewer AND bindings.members=gcp-hr@comm-it.cloud" --format="table(bindings.role,bindings.members)"
```

The command checks policy membership; it is not an authorization simulator. Confirm the external user can actually access the project with their Google identity and only add service-specific read roles if required for the review.


## Release provenance

The release script binds one checked-out Git SHA and immutable image digest in the same saved plan. See Step 4 above and `docs/CI-CD.md`.
