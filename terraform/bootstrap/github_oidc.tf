# Workload Identity Federation for GitHub Actions (future trusted main-branch only).
# Repo identifiers are parameterized and checked by immutable ID.
# This is provisioned by privileged bootstrap Terraform, never by the deployer.
variable "github_repository_full_name" {
  type        = string
  description = "Trusted GitHub repo owner/name."
}

variable "github_repository_id" {
  type        = string
  description = "Immutable numeric GitHub repository ID."
}

variable "github_owner_id" {
  type        = string
  description = "Immutable numeric GitHub owner ID."
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
  display_name                       = "CommitTask trusted dispatch"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Only the selected repository and PR event can exchange an OIDC token.
  # The GitHub workflow additionally refuses forks and has no auto-apply.
  attribute_condition = "assertion.repository_id == '${var.github_repository_id}' && assertion.repository_owner_id == '${var.github_owner_id}' && assertion.repository == '${var.github_repository_full_name}' && assertion.ref == 'refs/heads/main' && assertion.event_name == 'workflow_dispatch'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# SAFETY HOLD:
# No Workload Identity User impersonation grant is created for the deployer here.
# The PR workflow is credential-free. Future privileged workflows must have a
# separate vetted identity and environment/branch approvals before IAM grants.

output "github_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github_pr.name
}

# The provider alone does not grant GCP permissions. No authenticated CI job is active.
