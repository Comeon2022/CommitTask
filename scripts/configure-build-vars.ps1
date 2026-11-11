# Set non-secret GitHub Actions repository variables for CI image publishing and isolated Cloud Run deployment.
# Requires GitHub CLI authenticated with repo variable write permissions.
# Run after bootstrap Terraform apply has created builder and Cloud Run deploy SAs + distinct WIF providers.
[CmdletBinding()]
param()
$ErrorActionPreference = "Stop"
$Repository = "Comeon2022/CommitTask"
$Vars = @{
  GCP_PROJECT_ID         = "commitask01"
  GCP_BUILD_SA           = "meridian-poc-builder@commitask01.iam.gserviceaccount.com"
  GCP_BUILD_WIF_PROVIDER = "projects/238671625358/locations/global/workloadIdentityPools/meridian-github/providers/github-build"
  GCP_DEPLOY_SA           = "meridian-poc-ci-deploy@commitask01.iam.gserviceaccount.com"
  GCP_DEPLOY_WIF_PROVIDER = "projects/238671625358/locations/global/workloadIdentityPools/meridian-github/providers/github-deploy"
}
& gh auth status
if ($LASTEXITCODE -ne 0) { throw "Run gh auth login first." }
foreach ($entry in $Vars.GetEnumerator()) {
  & gh variable set $entry.Key --repo $Repository --body $entry.Value
  if ($LASTEXITCODE -ne 0) { throw "Failed setting $($entry.Key)" }
  Write-Host "Configured $($entry.Key)"
}
Write-Host "Variables configured; protect main branch and rerun or trigger a new push to main."
