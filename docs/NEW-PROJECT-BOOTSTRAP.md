# Fresh project bootstrap — commitask01

**Project ID:** `commitask01` | **Project number:** `238671625358` | **Region:** `europe-west1`

Do not use the deleted legacy local state or run `terraform import` in this new project. No APIs are to be enabled with `gcloud services enable`: `google_project_service` in Terraform owns them. The bootstrap root uses **local state** until explicitly migrated. Never commit `terraform.tfstate`, Terraform plans, credentials or variable files.

## Local setup (Windows PowerShell, from repository root)

```powershell
git pull origin main
Copy-Item .\terraform\bootstrap\terraform.tfvars.example .\terraform\bootstrap\terraform.tfvars
Get-Content .\terraform\bootstrap\terraform.tfvars
gcloud config set project commitask01
gcloud auth login
gcloud auth application-default login
cd terraform/bootstrap
cmd /c "C:\terraform\terraform.exe init"
cmd /c "C:\terraform\terraform.exe validate"
cmd /c "C:\terraform\terraform.exe plan -input=false -out=bootstrap.tfplan"
cmd /c "C:\terraform\terraform.exe show -no-color bootstrap.tfplan"
```

The local `terraform.tfvars` must contain `project_id="commitask01"`, `project_number="238671625358"`, `state_bucket_name="commitask01-tfstate-238671625358"`, `reviewer_principal_type="group"`, `terraform_operator_email="karu.lior@gmail.com"`, and verified GitHub IDs. The project must already have billing enabled and the human administrator must have sufficient bootstrap IAM and API enablement permissions.

**Review plan before apply.** For a truly empty project and state the first plan creates the SA identities, roles, GCS bucket, Artifact Registry repository, OIDC pool/providers, APIs and reviewer Viewer. Verify no replacements/deletes. Then explicitly:

```powershell
cmd /c "C:\terraform\terraform.exe apply bootstrap.tfplan"
cmd /c "C:\terraform\terraform.exe plan -input=false"
```

Keep secure backup of the local state. The state bucket is reserved for the PoC remote backend (prefix `meridian/poc`); bootstrap state is not automatically remote.

## GitHub builder after bootstrap

From repository root:

```powershell
gh auth login
.\scripts\configure-build-vars.ps1
```

This sets only nonsecret Actions variables for `commitask01`. Ensure protected `main` branch; then rerun or trigger the **Build and publish API image (main)** workflow. It uses a dedicated `meridian-poc-builder` SA with only repository-level `roles/artifactregistry.writer` and does not deploy infrastructure. Record its **full Git SHA and immutable image digest** from the Actions summary.

For PoC deployment, invoke the current `scripts/prepare-release.ps1` with `-SourceSha` and `-ImageDigest` plus the StateBucket, candidate name, project ID and region; this creates a Terraform plan but does not execute `apply`. Do not use old documentation that implies the Deployer can push containers. Inspect the plan before applying.

The old `commitask` project may still contain chargeable resources; it is out of scope of this new deployment and is not modified by the workflow.
