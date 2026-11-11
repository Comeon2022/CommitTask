# Workload Identity Federation for GitHub Actions (PR plan only).
# GitHub repository identity is immutable by ID, protecting against repo-name reuse.
# This is provisioned by privileged bootstrap Terraform, never by the deployer.
data "google_project" "current" {
  project_id = var.project_id
}

resource "google_project_service" "sts" {
  project            = var.project_id
  service            = "sts.googleapis.com"
  disable_on_destroy = false
}

resource "google_project_service" "iamcredentials" {
  project            = var.project_id
  service            = "iamcredentials.googleapis.com"
  disable_on_destroy = false
}

resource "google_iam_workload_identity_pool" "github" {
  project                   = var.project_id
  workload_identity_pool_id = "meridian-github"
  display_name              = "Meridian GitHub Actions"
  depends_on = [
    google_project_service.iam,
    google_project_service.sts,
    google_project_service.iamcredentials,
  ]
}

resource "google_iam_workload_identity_pool_provider" "github_pr" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-pr"
  display_name                       = "CommitTask PR plans"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Only the selected repository and PR event can exchange an OIDC token.
  # The GitHub workflow additionally refuses forks and has no auto-apply.
  attribute_condition = "assertion.repository_id == '1453727041' && assertion.repository_owner_id == '104059889' && assertion.event_name == 'pull_request'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_pr_deployer" {
  service_account_id = google_service_account.identity["deployer"].name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.repository/Comeon2022/CommitTask"
}

output "github_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github_pr.name
}

# This PR workflow uses the deployer SA for read-only Terraform plan operations.
# A separate plan-only identity is recommended for production. No automatic apply.
