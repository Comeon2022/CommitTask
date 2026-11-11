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

# Known numeric project ID avoids Cloud Resource Manager API read during
# state recovery. Verify this input against GCP project metadata.
variable "project_number" {
  type        = string
  description = "Numeric GCP project number; used for WIF principalSet IAM members."
  validation {
    condition     = can(regex("^[0-9]+$", var.project_number))
    error_message = "project_number must contain only digits."
  }
}

resource "google_service_account_iam_member" "github_main_plan" {
  service_account_id = google_service_account.ci_plan.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.repository/${var.github_repository_full_name}"
}

output "ci_plan_service_account" {
  value = google_service_account.ci_plan.email
}

output "github_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github_main_plan.name
}

# WIF is bound ONLY to plan-only SA; there is no CI impersonation of deployer.

# Independent GitHub image-build trust. This identity must NOT access Terraform
# state or deploy Cloud Run; its only permission is repository-scoped image push.
resource "google_iam_workload_identity_pool_provider" "github_main_build" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-build"
  display_name                       = "CommitTask main image publisher"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    # Unique mapping: plan provider does not issue this attribute.
    "attribute.pipeline"   = "'main-docker-build'"
  }

  # Authorize only the exact workflow file on protected main, on push.
  attribute_condition = "assertion.repository_id == '${var.github_repository_id}' && assertion.repository_owner_id == '${var.github_owner_id}' && assertion.repository == '${var.github_repository_full_name}' && assertion.ref == 'refs/heads/main' && assertion.event_name == 'push' && assertion.workflow_ref == '${var.github_repository_full_name}/.github/workflows/docker-build.yml@refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account" "ci_builder" {
  project      = var.project_id
  account_id   = "meridian-poc-builder"
  display_name = "Meridian GitHub image publisher (Artifact Registry only)"
  depends_on   = [google_project_service.iam]
}

resource "google_service_account_iam_member" "github_main_build" {
  service_account_id = google_service_account.ci_builder.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.pipeline/main-docker-build"
}

output "ci_builder_service_account" {
  value = google_service_account.ci_builder.email
}

output "github_build_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github_main_build.name
}

# Independent GitHub Cloud Run deployer identity. Build cannot impersonate it.
# The same workflow can trigger two jobs, but each authenticates against a
# different provider/SA, so the builder's short-lived token cannot deploy.
resource "google_service_account" "ci_cloudrun_deployer" {
  project      = var.project_id
  account_id   = "meridian-poc-ci-deploy"
  display_name = "Meridian CI deploy to existing API service only"
  depends_on   = [google_project_service.iam]
}

resource "google_iam_workload_identity_pool_provider" "github_main_deploy" {
  project                            = var.project_id
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-deploy"
  display_name                       = "CommitTask main Cloud Run deployment"

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.repository" = "assertion.repository"
    "attribute.pipeline"   = "'main-cloudrun-deploy'"
  }

  attribute_condition = "assertion.repository_id == '${var.github_repository_id}' && assertion.repository_owner_id == '${var.github_owner_id}' && assertion.repository == '${var.github_repository_full_name}' && assertion.ref == 'refs/heads/main' && assertion.event_name == 'push' && assertion.workflow_ref == '${var.github_repository_full_name}/.github/workflows/docker-build.yml@refs/heads/main'"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }
}

resource "google_service_account_iam_member" "github_main_deploy" {
  service_account_id = google_service_account.ci_cloudrun_deployer.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/projects/${var.project_number}/locations/global/workloadIdentityPools/${google_iam_workload_identity_pool.github.workload_identity_pool_id}/attribute.pipeline/main-cloudrun-deploy"
}

# Grant only the right to attach this one runtime identity, never other SAs.
resource "google_service_account_iam_member" "ci_deploy_act_as_api" {
  service_account_id = google_service_account.identity["api"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.ci_cloudrun_deployer.email}"
}

output "ci_cloudrun_deployer_service_account" {
  value = google_service_account.ci_cloudrun_deployer.email
}
output "github_deploy_workload_identity_provider" {
  value = google_iam_workload_identity_pool_provider.github_main_deploy.name
}
