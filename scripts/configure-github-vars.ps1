# Configure non-sensitive GitHub Actions variables after GCP bootstrap.
# Run in Windows PowerShell after: gh auth login; gcloud auth login;
# terraform -chdir=terraform/bootstrap apply (as the authorized bootstrap operator).
# Does NOT create GCP resources, GitHub Environment, or IAM roles.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$StateBucket,
  [Parameter(Mandatory=$true)][string]$CandidateFullName,
  [Parameter(Mandatory=$true)][string]$ContainerImage,
  [Parameter(Mandatory=$true)][string]$DeployedCommit
)
$ErrorActionPreference = "Stop"
$Repository = "Comeon2022/CommitTask"
$ProjectId = "commitask"
$ProjectNumber = "924903658971"
$Deployer = "meridian-poc-deployer@$ProjectId.iam.gserviceaccount.com"
$Provider = "projects/$ProjectNumber/locations/global/workloadIdentityPools/meridian-github/providers/github-pr"

if ($StateBucket -match 'YOUR_|REPLACE|PLACEHOLDER' -or
    $ContainerImage -match 'YOUR_|REPLACE|PLACEHOLDER' -or
    $CandidateFullName -match 'YOUR_|REPLACE|PLACEHOLDER' -or
    $DeployedCommit -notmatch '^[0-9a-f]{7,40}$') {
  throw "Supply actual state bucket, candidate, built image and matching git SHA."
}
if ($ContainerImage -notmatch '^europe-west1-docker\.pkg\.dev/commitask/meridian-poc/') {
  throw "Container image must be in europe-west1 / commitask / meridian-poc."
}
foreach ($cmd in @("gh", "gcloud")) {
  if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { throw "$cmd is not installed." }
}
& gh auth status
if ($LASTEXITCODE -ne 0) { throw "Run gh auth login first." }
$ActualId = (& gcloud projects describe $ProjectNumber --format="value(projectId)").Trim()
if ($LASTEXITCODE -ne 0 -or $ActualId -ne $ProjectId) { throw "Project ID/number mismatch or GCP access denied." }
# Ensure WIF exists. Names can be constructed before creation, but that isn't proof of existence.
& gcloud iam workload-identity-pools providers describe github-pr --project=$ProjectId --location=global --workload-identity-pool=meridian-github --format="value(name)" | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Run/bootstrap Terraform WIF provider before configuring variables." }

$Vars = @{
  GCP_PROJECT_ID = $ProjectId
  GCP_WIF_PROVIDER = $Provider
  GCP_DEPLOYER_SA = $Deployer
  GCS_TF_STATE_BUCKET = $StateBucket
  TF_CANDIDATE_FULL_NAME = $CandidateFullName
  TF_CONTAINER_IMAGE = $ContainerImage
  TF_DEPLOYED_COMMIT = $DeployedCommit
}
foreach ($key in $Vars.Keys) {
  & gh variable set $key --repo $Repository --body $Vars[$key]
  if ($LASTEXITCODE -ne 0) { throw "Failed to set GitHub Actions variable: $key" }
  Write-Host "Configured $key"
}
Write-Host "GitHub repository variables created. Next: create/restrict Environment gcp-plan; test PR."
