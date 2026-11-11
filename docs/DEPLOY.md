# GCP deployment runbook (PowerShell)

**Status:** Not yet deployed; Terraform has not been validated against a real project. This is a plan, not a successful deployment report.

## Prerequisites

New billing-enabled GCP project; Terraform, Docker, Git and Google Cloud SDK installed. Choose unique GCS bucket name, and ensure the bootstrap **human administrator** has permissions to configure IAM and create infrastructure. No service-account JSON keys.

## Step 1 — bootstrap identities and remote state bucket

```powershell
$ProjectId = "YOUR_GCP_PROJECT_ID"
$Region    = "europe-west1"
$Bucket    = "YOUR_GLOBALLY_UNIQUE_BUCKET_NAME"

gcloud auth login
gcloud auth application-default login
gcloud config set project $ProjectId

cd terraform/bootstrap
terraform init
terraform plan -var="project_id=$ProjectId" -var="state_bucket_name=$Bucket"
terraform apply -var="project_id=$ProjectId" -var="state_bucket_name=$Bucket"
terraform output deployer_service_account
terraform output api_service_account
terraform output developer_service_accounts
```

Bootstrap grants functional roles to the deployer and creates API, migration and three developer SAs. Human developer identities are optional until actual emails are supplied via `developer_emails`. The bootstrap creates a **temporary local state**: keep it secured, do not commit it, and migrate it to protected remote storage as a separate controlled step. The GCS bucket for the PoC is versioned, EU-located, and private.

**Bootstrap administrator must grant the human/CI deployment principal `roles/iam.serviceAccountTokenCreator` on the deployer SA**, not project-wide. In Google Cloud this IAM policy can be managed using the administrator's bootstrap process; do not give the deployer permission to grant itself project-level IAM. The deployer SA does not use a JSON key.

## Step 2 — initialize the PoC under short-lived SA impersonation

```powershell
cd ../poc
$Deployer = "meridian-poc-deployer@$ProjectId.iam.gserviceaccount.com"
$env:GOOGLE_IMPERSONATE_SERVICE_ACCOUNT = $Deployer
terraform init -backend-config="bucket=$Bucket" -backend-config="prefix=meridian/poc"
```

The human caller still needs read/write access to the backend bucket, or a working ADC-backed impersonation flow supported by the Terraform GCS backend. Do not assume `GOOGLE_IMPERSONATE_SERVICE_ACCOUNT` alone authorizes bucket access; verify which principal is accessing the state bucket. Grant GCS object permissions for only the state bucket/prefix as permitted by your organization; avoid broad project Storage Admin.

## Step 3 — bootstrap the container repository with Terraform

```powershell
terraform apply -target=google_artifact_registry_repository.api `
  -var="project_id=$ProjectId" `
  -var="container_image=example.invalid/placeholder" `
  -var="deployed_commit=0123456" `
  -var="candidate_full_name=PLACEHOLDER"
```

This is an intentional `-target` exception: the registry must exist before Docker can push the application image. Subsequent deployments use full plans. Prefer separating the registry into a dedicated bootstrap root in a larger engagement.

## Step 4 — build and push versioned application image

Run from the repository root:

```powershell
cd ../..
$Commit   = (git rev-parse --short=7 HEAD).Trim()
$ImageTag = "$Region-docker.pkg.dev/$ProjectId/meridian-poc/api:$Commit"
gcloud auth configure-docker "$Region-docker.pkg.dev"
docker build -t $ImageTag ./app
docker push $ImageTag
```

Container push requires `roles/artifactregistry.writer` on the target repository for the authenticated **image publisher**. This publisher is not implicitly the Terraform deployer: `gcloud auth configure-docker` uses the local gcloud identity. Track the image digest and set `container_image` to the immutable `...@sha256:...` reference for the final deployment.

## Step 5 — apply and verify

```powershell
cd terraform/poc
terraform fmt -check -recursive
terraform validate
terraform plan `
  -var="project_id=$ProjectId" `
  -var="candidate_full_name=YOUR_EXACT_INTERVIEW_NAME" `
  -var="deployed_commit=$Commit" `
  -var="container_image=$ImageTag" -out=plan.tfplan
terraform apply plan.tfplan
$Url = terraform output -raw health_url
Invoke-RestMethod -Uri $Url
```

The `/health` handler must return a 200 JSON response with correct name/actual commit/region and `db` and `secret` equal to `ok`. Both checks execute per request. Verify SQL has **no PUBLIC IPv4 address**.

## Known issues and risks

- The application authenticates to PostgreSQL as its **runtime service account** using Cloud SQL IAM DB auth, not a password. Both mandatory Secret Manager secrets now exist and are read by the API at runtime: the DB password belongs to a separate built-in PostgreSQL user, and the second secret is a synthetic provider token. See `docs/SECRETS-DESIGN.md`.
- SQL connector requires private route to Cloud SQL and API access to Google Cloud (TCP 443 plus connector's 3307 connection). The project must support Direct VPC egress and Private Google Access.
- The built-in DB user's password and the synthetic provider token are generated by Terraform: both secret values are present in GCS Terraform state and historical bucket versions. This must be revised for a production setting.
- No migration Cloud Run Job or SQL DDL grants yet: developer service accounts cannot execute migrations until that job is deployed and per-job IAM is configured.
- `terraform validate`, real image push and cloud deployment have **not** been executed by the assistant. The infrastructure may need provider/version corrections based on actual validation.
- Public invocation may be prevented by organization policy. Use an approved dedicated evaluation project.
- Keep the environment running until the review, then tear down with Terraform.


## Google Group `db_secret_reader` (optional until directory setup)

The Google Group must exist in Cloud Identity/Google Workspace, with a valid email address such as `db_secret_reader@YOUR_DOMAIN`. A display name alone is not sufficient. In the local `terraform/poc/terraform.tfvars` file set:

```hcl
db_secret_reader_group_email = "db_secret_reader@YOUR_DOMAIN"
```

Terraform attaches `roles/secretmanager.secretAccessor` to **only the DB-password secret** for that group. If the variable is empty, the binding is not created; do not claim group access exists until the IAM policy is applied and verified. Group members do not automatically get VPC or Cloud SQL access.

For the interview's exact two-secret health contract, the Cloud Run SA also reads the DB-password secret (but **never authenticates with it**). In production we would remove this extra permission. Confirm the IAM policy on both secrets before submitting.
