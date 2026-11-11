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

resource "google_iam_workload_identity_pool_provider" "github_main_plan" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-plan"
  display_name                       = "CommitTask trusted dispatch"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
  }

  # Only the selected repository, main branch and manual trusted dispatch
  # can exchange an OIDC token; no pull_request event is trusted.
  attribute_condition = "assertion.repository_id == '${var.github_repository_id}' && assertion.repository_owner_id == '${var.github_owner_id}' && assertion.repository == '${var.github_repository_full_name}' && assertion.ref == 'refs/heads/main' && assertion.event_name == 'workflow_dispatch'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

# Plan-only IAM identity, separate from privileged Terraform deployer.
resource "google_service_account" "ci_plan" {
  project      = var.project_id
  account_id   = "meridian-poc-plan"
  display_name = "Meridian trusted read-only CI plan"
  depends_on   = [google_project_service.iam]
}

resource "google_project_iam_member" "ci_plan_project_roles" {
  for_each = toset(["roles/viewer", "roles/iam.securityReviewer"])
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.ci_plan.email}"
}

# Read of state is sensitive: the current PoC state contains generated secrets.
# This binding is only safe for approved trusted-main workflow runs.
resource "google_storage_bucket_iam_member" "ci_plan_state" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.ci_plan.email}"
}

data "google_project" "current" {
  project_id = var.project_id
}

resource "google_service_account_iam_member" "github_main_plan" {
  service_account_id = google_service_account.ci_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${data.google_project.current.number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.repository/${var.github_repository_full_name}"
}

output "ci_plan_service_account" {
  value = google_service_account.ci_plan.email
}

output "github_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github_main_plan.name
}

# WIF is bound ONLY to plan-only SA; there is no CI impersonation of deployer.
