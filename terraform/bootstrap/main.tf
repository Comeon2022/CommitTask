terraform {
  required_version = ">= 1.7.0"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 6.0"
    }
  }
}

variable "project_id" {
  type        = string
  description = "An EXISTING Google Cloud project with billing enabled."
}

variable "region" {
  type    = string
  default = "europe-west1"
}

variable "state_bucket_name" {
  type        = string
  description = "Globally unique bucket for the main environment's Terraform state."
}

provider "google" {
  project = var.project_id
  region  = var.region
}

resource "google_project_service" "storage" {
  project            = var.project_id
  service            = "storage.googleapis.com"
  disable_on_destroy = false
}

resource "google_storage_bucket" "terraform_state" {
  project                     = var.project_id
  name                        = var.state_bucket_name
  location                    = "EU"
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.storage]
}

output "state_bucket_name" {
  value = google_storage_bucket.terraform_state.name
}

# Identity bootstrap is run by an explicitly authorized human administrator.
# Do not give the regular Terraform deployer project IAM policy write access.

variable "developer_emails" {
  description = "Map of dev1/dev2/dev3 to real human Google identities; optional until provided."
  type        = map(string)
  default     = {}
  validation {
    condition     = alltrue([for k in keys(var.developer_emails) : contains(["dev1", "dev2", "dev3"], k)])
    error_message = "Only dev1, dev2 and dev3 identities are accepted."
  }
}

locals {
  service_accounts = {
    deployer  = "meridian-poc-deployer"
    api       = "meridian-poc-api"
    migration = "meridian-poc-migration"
    dev1      = "meridian-poc-dev1"
    dev2      = "meridian-poc-dev2"
    dev3      = "meridian-poc-dev3"
  }

  # Each role is narrowly functional, but some are project-scoped predefined
  # administrator roles. Production should further replace these with custom
  # roles and split infrastructure ownership. Deliberately no projectIamAdmin.
  deployer_roles = toset([
    "roles/compute.networkAdmin",
    "roles/servicenetworking.networksAdmin",
    "roles/cloudsql.admin",
    "roles/run.admin",
    "roles/artifactregistry.admin",
    "roles/secretmanager.admin",
    "roles/serviceusage.serviceUsageAdmin",
  ])

  sql_runtime_roles = toset([
    "roles/cloudsql.client",
    "roles/cloudsql.instanceUser",
  ])
}

resource "google_project_service" "iam" {
  project            = var.project_id
  service            = "iam.googleapis.com"
  disable_on_destroy = false
}

resource "google_service_account" "identity" {
  for_each     = local.service_accounts
  account_id   = each.value
  display_name = "Meridian PoC ${each.key} identity"
  depends_on   = [google_project_service.iam]
}

# Scope Terraform state access to this bucket instead of all project storage.
# GCS backend requires object read/write/list/delete in the dedicated state bucket.
resource "google_storage_bucket_iam_member" "deployer_state" {
  bucket = google_storage_bucket.terraform_state.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.identity["deployer"].email}"
}

resource "google_project_iam_member" "deployer" {
  for_each = local.deployer_roles
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.identity["deployer"].email}"
}

# Optional human operator: bootstrap administrator binds one named user
# to the deployer SA, not to every SA in the project.
variable "terraform_operator_email" {
  type        = string
  description = "Existing human Google identity authorized to impersonate the deployer SA. Set during bootstrap."
  default     = ""

  validation {
    condition     = var.terraform_operator_email == "" || can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.terraform_operator_email))
    error_message = "Specify a valid Google account email or leave empty until known."
  }
}

resource "google_service_account_iam_member" "terraform_operator_token_creator" {
  count              = var.terraform_operator_email == "" ? 0 : 1
  service_account_id = google_service_account.identity["deployer"].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${var.terraform_operator_email}"
}

resource "google_service_account_iam_member" "deployer_act_as_api" {
  service_account_id = google_service_account.identity["api"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.identity["deployer"].email}"
}

resource "google_service_account_iam_member" "deployer_act_as_migration" {
  service_account_id = google_service_account.identity["migration"].name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.identity["deployer"].email}"
}

resource "google_project_iam_member" "runtime_sql" {
  for_each = {
    for pair in setproduct(["api", "migration"], local.sql_runtime_roles) :
    "${pair[0]}-${pair[1]}" => {
      identity = pair[0]
      role     = pair[1]
    }
  }
  project = var.project_id
  role    = each.value.role
  member  = "serviceAccount:${google_service_account.identity[each.value.identity].email}"
}

# Each real developer may impersonate ONLY their own developer SA.
# No SA keys are created. Developer SAs receive no direct Cloud SQL access.
resource "google_service_account_iam_member" "developer_impersonation" {
  for_each           = var.developer_emails
  service_account_id = google_service_account.identity[each.key].name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "user:${each.value}"
}

output "deployer_service_account" {
  value = google_service_account.identity["deployer"].email
}

output "api_service_account" {
  value = google_service_account.identity["api"].email
}

output "migration_service_account" {
  value = google_service_account.identity["migration"].email
}

output "developer_service_accounts" {
  value = { for k in ["dev1", "dev2", "dev3"] : k => google_service_account.identity[k].email }
}
