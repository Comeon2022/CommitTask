# Deployment runbook (Windows PowerShell)

**Status:** Code committed; not deployed or validated against a real GCP project. All cloud resource definitions live in Terraform. Container builds produce an artifact, not an independently managed cloud resource.

## Prerequisites

Google Cloud project with billing enabled, `gcloud`, Terraform 1.7+, Docker, Git; account with sufficient GCP permissions for the PoC. You should use synthetic data and a disposable, isolated project. Cloud SQL can incur charges.

## 1. Authenticate and select your project

```powershell
$ProjectId = "YOUR_GCP_PROJECT_ID"
$Region = "europe-west1"
$Bucket = "YOUR_GLOBALLY_UNIQUE_GCS_BUCKET_NAME"

gcloud auth login
gcloud auth application-default login
gcloud config set project $ProjectId
```

## 2. Bootstrap remote Terraform state through Terraform

```powershell
cd terraform/bootstrap
terraform init
terraform apply -var="project_id=$ProjectId" -var="state_bucket_name=$Bucket"
```

**Important:** bootstrap creates a *local* Terraform state until you configure a remote backend for bootstrap itself. Protect and preserve this state outside the repository. The PoC below uses the new GCS backend. GCS bucket versioning and public access prevention are enabled.

## 3. Initialize PoC backend and create the Artifact Registry repository first

```powershell
cd ../poc
terraform init -backend-config="bucket=$Bucket" -backend-config="prefix=meridian/poc"
terraform apply -target=google_artifact_registry_repository.api -var="project_id=$ProjectId" -var="container_image=example.invalid/placeholder" -var="deployed_commit=0123456" -var="candidate_full_name=PLACEHOLDER"
```

The single targeted apply is a **bootstrap exception** to resolve the image-build dependency. Subsequent runs should use regular full `terraform plan` and `apply`, not `-target`.

## 4. Build and push the container image

Run from the repository root:

```powershell
cd ../..
$Commit = (git rev-parse --short=7 HEAD).Trim()
$ImageTag = "$Region-docker.pkg.dev/$ProjectId/meridian-poc/api:$Commit"

gcloud auth configure-docker "$Region-docker.pkg.dev"
docker build -t $ImageTag ./app
docker push $ImageTag
```

For repeatable deployment, use a digest pinned to the pushed image. Retrieve the immutable digest from Artifact Registry/Docker and set `container_image` to `.../api@sha256:...`. Avoid relying solely on a mutable tag.

## 5. Deploy PoC

```powershell
cd terraform/poc
terraform plan -var="project_id=$ProjectId" -var="candidate_full_name=YOUR_EXACT_INTERVIEW_NAME" -var="deployed_commit=$Commit" -var="container_image=$ImageTag" -out=plan.tfplan
terraform apply plan.tfplan
terraform output health_url
```

The tag above works for an initial smoke test; pin the digest for the final review deployment. Use the real SHA associated with the image's source revision.

## 6. Verify

```powershell
$Health = (terraform output -raw health_url)
Invoke-RestMethod -Uri $Health
gcloud sql instances describe meridian-poc-postgres --project=$ProjectId --format="json(ipAddresses)"
```

Expected: `/health` returns exact fields `candidate,commit,region,db,secret` with db/secret = ok **after actual checks**. Cloud SQL must have no PUBLIC IPv4 address. Deliberately test missing secret/database permissions in a safe non-production environment and restore IAM afterwards.

## Constraints and known gaps

- Terraform creates synthetic API-token and DB-password versions. **Their plaintext values are present in Terraform state**, including GCS object versions; restrict access tightly and protect the bootstrap state. This is a PoC trade-off, not an ideal production secret-seeding process.
- Application reads both secrets at runtime using its dedicated service account and checks the database on each health call. Secrets do not appear in app environment variables or source.
- The API is public because the exercise requires a public health URL. It exposes only `/health`; production would consider protected endpoints, ingress/load balancer policies, and operational security.
- `Cloud Run Job` developer migrations are still an **architecture proposal**, not implemented in Terraform yet. See `docs/DEVELOPER-MIGRATIONS.md`.
- No CI workflow is present yet. No Terraform `validate` or live deployment has run here.
- Public `allUsers` invoker may be blocked by organization policy; use a separate test project or explicitly approved public ingress configuration.
- For repeatable main configuration, avoid manually editing cloud resources. Infrastructure definitions and modifications belong in Terraform.
- Free trial credit does not guarantee zero cost: set a budget alert and tear down after review.

See `CLARIFICATIONS.md`, `ASSUMPTIONS.md` and the exercise PDF.
