# Builds and pushes the exact checked-out Git commit, then writes a Terraform plan
# with the immutable registry digest and matching SHA. Does not auto-apply.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$CandidateFullName,
  [Parameter(Mandatory=$true)][string]$StateBucket,
  [string]$ProjectId = "commitask",
  [ValidateSet("europe-west1","europe-west3","europe-west4")][string]$Region = "europe-west1"
)
$ErrorActionPreference = "Stop"
$PreviousTerraformImpersonation = $env:GOOGLE_IMPERSONATE_SERVICE_ACCOUNT
$PreviousGcloudImpersonation = $env:CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT
$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
Push-Location $RepoRoot
try {
  $Commit = (& git rev-parse --short=7 HEAD).Trim()
  if ($LASTEXITCODE -ne 0 -or $Commit -notmatch '^[0-9a-f]{7}$') { throw "Could not resolve Git commit" }
  & git diff --quiet HEAD --
  if ($LASTEXITCODE -ne 0) { throw "Dirty tracked working tree: commit changes first." }
  if ($CandidateFullName -match "YOUR_|PLACEHOLDER" -or !$CandidateFullName.Trim()) { throw "Supply actual candidate name" }
  $Deployer = "meridian-poc-deployer@$ProjectId.iam.gserviceaccount.com"
  $env:GOOGLE_IMPERSONATE_SERVICE_ACCOUNT = $Deployer
  $env:CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT = $Deployer
  & gcloud auth print-access-token --impersonate-service-account=$Deployer | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Cannot impersonate deployer; bootstrap operator IAM first." }
  & gcloud artifacts repositories describe meridian-poc --project=$ProjectId --location=$Region --format="value(name)" | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Artifact Registry missing: terraform/bootstrap apply must run first." }
  $Tag = "$Region-docker.pkg.dev/$ProjectId/meridian-poc/api:$Commit"
  & gcloud auth configure-docker "$Region-docker.pkg.dev" --quiet
  if ($LASTEXITCODE -ne 0) { throw "gcloud Docker auth failed" }
  & docker build --label "org.opencontainers.image.revision=$Commit" -t $Tag ./app
  if ($LASTEXITCODE -ne 0) { throw "Docker build failed" }
  & docker push $Tag
  if ($LASTEXITCODE -ne 0) { throw "Docker push failed" }
  $DigestRef = (& docker image inspect $Tag --format '{{index .RepoDigests 0}}').Trim()
  if ($LASTEXITCODE -ne 0 -or $DigestRef -notmatch '^.+@sha256:[a-f0-9]{64}$') {
    throw "Cannot confirm immutable digest after push; refusing Terraform plan"
  }
  if (!$DigestRef.StartsWith("$Region-docker.pkg.dev/$ProjectId/meridian-poc/api@")) {
    throw "Unexpected repository for digest; refusing deployment"
  }
  Push-Location (Join-Path $RepoRoot "terraform/poc")
  try {
    & terraform init -input=false -backend-config="bucket=$StateBucket" -backend-config="prefix=meridian/poc" -backend-config="impersonate_service_account=$Deployer"
    if ($LASTEXITCODE -ne 0) { throw "Terraform backend init failed" }
    & terraform plan -input=false -out=release.tfplan -var="project_id=$ProjectId" -var="region=$Region" -var="candidate_full_name=$CandidateFullName" -var="deployed_commit=$Commit" -var="container_image=$DigestRef"
    if ($LASTEXITCODE -ne 0) { throw "Terraform plan failed" }
  } finally {
    Pop-Location
  }
  Write-Host "Plan created: terraform/poc/release.tfplan"
  Write-Host "Source git SHA: $Commit"
  Write-Host "Pushed immutable image: $DigestRef"
  Write-Host "Review the plan and apply intentionally: terraform -chdir=terraform/poc apply release.tfplan"
} finally {
  $env:GOOGLE_IMPERSONATE_SERVICE_ACCOUNT = $PreviousTerraformImpersonation
  $env:CLOUDSDK_AUTH_IMPERSONATE_SERVICE_ACCOUNT = $PreviousGcloudImpersonation
  Pop-Location
}
