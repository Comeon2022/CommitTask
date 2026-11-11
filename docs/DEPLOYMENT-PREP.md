# Terraform deployment preparation (not deployed yet)

The code in this repository is **in progress**. At this stage only the state-bucket bootstrap and private-network foundation exist. There is no Cloud SQL instance, application, Secret Manager integration, live `/health` endpoint, or CI workflow yet. Do not present this as a finished exercise.

## Prerequisites

- An existing GCP project with active billing.
- A human operator authenticated through `gcloud auth application-default login` with permissions to enable APIs, create buckets, and manage Terraform resources.
- Terraform >= 1.7, Google Cloud SDK and Git.
- An agreed globally unique GCS bucket name. Never commit real credential files or `*.tfstate`.

## Step 1: bootstrap the GCS backend bucket with Terraform

```bash
cd terraform/bootstrap
terraform init
terraform plan -var="project_id=YOUR_PROJECT_ID" -var="state_bucket_name=YOUR_GLOBALLY_UNIQUE_BUCKET"
terraform apply -var="project_id=YOUR_PROJECT_ID" -var="state_bucket_name=YOUR_GLOBALLY_UNIQUE_BUCKET"
```

The bootstrap has **temporary local state**, because Terraform cannot configure a GCS backend in a bucket that does not yet exist. Store the local state securely outside Git and migrate the bootstrap state to protected remote storage before calling the implementation complete. Never delete the bucket while a live Terraform state is stored there.

## Step 2: initialize the PoC remote backend

```bash
cd ../poc
terraform init -backend-config="bucket=YOUR_GLOBALLY_UNIQUE_BUCKET" -backend-config="prefix=meridian/poc"
terraform plan -var="project_id=YOUR_PROJECT_ID"
```

The `backend "gcs" {}` configuration reads the real bucket from the CLI configuration. Backend configuration is intentionally not hardcoded to a personal project. **Do not apply this PoC yet**: the compute, database and secrets components have not been implemented.

## Engineering checkpoints

- `terraform fmt -check -recursive`, `terraform validate` after initializing each root.
- Confirm APIs and IAM for the current Google Terraform provider.
- Cloud SQL must have public IPv4 disabled; use private services access in the initial PoC.
- Cloud Run can use Direct VPC egress, but it will need runtime IAM, a real image, and secret reads.
- `/health` must issue a real SQL query and a real Secret Manager read on each request.
- Avoid injecting secret payload values through Terraform variables: sensitive Terraform values can still be stored in state.
- Migration execution via Cloud Run Job remains a **documented proposal** pending customer confirmation.

## AI evidence

The interview requires a complete, unedited `AI-LOG.md` containing all AI conversations used for this exercise, with only credential/key redaction permitted. Earlier draft logs were incomplete. Export the actual chat transcripts before submitting; do not fabricate omitted messages.

## References

- https://docs.cloud.google.com/sql/docs/postgres/configure-private-ip
- https://docs.cloud.google.com/run/docs/configuring/vpc-direct-vpc
