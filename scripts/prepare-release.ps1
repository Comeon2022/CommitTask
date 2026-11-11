# Create a reviewed Terraform plan from the EXACT commit SHA and digest
# reported by the GitHub Actions Docker build. Never builds or pushes locally.
# Requires Bootstrap completed, Terraform and authorized keyless deployer access.
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$CandidateFullName,
  [Parameter(Mandatory=$true)][string]$StateBucket,
  [Parameter(Mandatory=$true)][string]$SourceSha,
  [Parameter(Mandatory=$true)][string]$ImageDigest,
  [string]$ProjectId = "commitask",
  [ValidateSet("europe-west1","europe-west3","europe-west4")][string]$Region = "europe-west1"
)
$ErrorActionPreference = "Stop"
if ($SourceSha -notmatch '^[0-9a-f]{40}$') { throw "Use the full 40-character Git SHA from GitHub Actions." }
if ($ImageDigest -notmatch '^sha256:[a-f0-9]{64}$') { throw "Use sha256:<64 hex> digest from GitHub Actions." }
if ([string]::IsNullOrWhiteSpace($CandidateFullName) -or $CandidateFullName -match "YOUR_|PLACEHOLDER") { throw "Specify exact candidate full name." }
if ($StateBucket -match "YOUR_|PLACEHOLDER" -or [string]::IsNullOrWhiteSpace($StateBucket)) { throw "Specify existing state bucket." }
$Deployer = "meridian-poc-deployer@$ProjectId.iam.gserviceaccount.com"
$ImageRef = "$Region-docker.pkg.dev/$ProjectId/meridian-poc/api@$ImageDigest"
$OldImpersonation = $env:GOOGLE_IMPERSONATE_SERVICE_ACCOUNT
$env:GOOGLE_IMPERSONATE_SERVICE_ACCOUNT = $Deployer
try {
  # Only plan/apply permissions are needed. No Docker or Artifact Registry Writer.
  & gcloud auth print-access-token --impersonate-service-account=$Deployer | Out-Null
  if ($LASTEXITCODE -ne 0) { throw "Cannot impersonate deployer; verify Bootstrap IAM." }
  $PoCDir = (Resolve-Path (Join-Path $PSScriptRoot "../terraform/poc")).Path
  Push-Location $PoCDir
  try {
    $Terraform = (Get-Command terraform.exe -ErrorAction Stop).Source
    # Windows PowerShell argument parsing may differ by installation; use cmd
    # with a simple backend init first.
    & cmd /c "$Terraform init -input=false -backend-config=bucket=$StateBucket -backend-config=prefix=meridian/poc -backend-config=impersonate_service_account=$Deployer"
    if ($LASTEXITCODE -ne 0) { throw "Terraform init failed" }
    # Terraform -var strings do not contain spaces except the candidate name.
    # Use environment variables for all Terraform inputs to avoid CLI quoting.
    $env:TF_VAR_project_id = $ProjectId
    $env:TF_VAR_region = $Region
    $env:TF_VAR_candidate_full_name = $CandidateFullName
    $env:TF_VAR_deployed_commit = $SourceSha
    $env:TF_VAR_container_image = $ImageRef
    & cmd /c "$Terraform plan -input=false -out=release.tfplan"
    if ($LASTEXITCODE -ne 0) { throw "Terraform plan failed" }
  } finally { Pop-Location }
  Write-Host "Image: $ImageRef"
  Write-Host "Commit: $SourceSha"
  Write-Host "Review terraform/poc/release.tfplan and apply explicitly using deployer impersonation."
} finally {
  $env:GOOGLE_IMPERSONATE_SERVICE_ACCOUNT = $OldImpersonation
  foreach ($key in @("TF_VAR_project_id","TF_VAR_region","TF_VAR_candidate_full_name","TF_VAR_deployed_commit","TF_VAR_container_image")) {
    Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
  }
}
