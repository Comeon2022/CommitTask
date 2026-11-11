variable "container_image" {
  type        = string
  description = "Immutable Artifact Registry image URI, preferably pinned by digest."
}

variable "deployed_commit" {
  type        = string
  description = "Short SHA of the source Git commit built into container_image."

  validation {
    condition     = can(regex("^[0-9a-f]{7,40}$", var.deployed_commit))
    error_message = "Provide the real deployed Git commit SHA, 7-40 lowercase hex characters."
  }
}

variable "candidate_full_name" {
  type        = string
  description = "Exact name given to Commit interview reviewers."
}

# Service accounts and project-level IAM are created by the privileged bootstrap root.
# Regular infrastructure deployment cannot grant itself project IAM roles.
data "google_service_account" "api" {
  account_id = "meridian-poc-api"
  project    = var.project_id
}

data "google_service_account" "migration" {
  account_id = "meridian-poc-migration"
  project    = var.project_id
}

# The API reads the database-password secret to satisfy the exercise's literal
# runtime secret-read requirement; its SQL login STILL uses IAM, never this password.
resource "google_secret_manager_secret_iam_member" "db_password_api_access" {
  secret_id = google_secret_manager_secret.db_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "token_access" {
  secret_id = google_secret_manager_secret.provider_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${data.google_service_account.api.email}"
}

resource "google_cloud_run_v2_service" "api" {
  name                = "meridian-poc-api"
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  # Terraform owns the service network, runtime SA, secrets and environment.
  # The CI deployment workflow owns only the container image digest. Prevent
  # Terraform from reverting a newer immutable digest on a later infra plan.
  lifecycle {
    ignore_changes = [template[0].containers[0].image]
  }

  template {
    service_account = data.google_service_account.api.email

    scaling {
      min_instance_count = 0
      max_instance_count = 2
    }

    containers {
      image = var.container_image

      ports {
        container_port = 8080
      }

      env {
        name  = "PROJECT_ID"
        value = var.project_id
      }
      env {
        name  = "REGION"
        value = var.region
      }
      env {
        name  = "CANDIDATE"
        value = var.candidate_full_name
      }
      # Compatibility for the already-running pre-CI image. New builds report
      # the SHA embedded in /app/source_commit, ignoring this older fallback.
      # Retain until the first automatic deploy succeeds to avoid boot failure.
      env {
        name  = "DEPLOYED_COMMIT"
        value = var.deployed_commit
      }
      env {
        name  = "INSTANCE_CONNECTION_NAME"
        value = google_sql_database_instance.postgres.connection_name
      }
      env {
        name  = "DB_NAME"
        value = google_sql_database.app.name
      }
      env {
        name  = "DB_IAM_USER"
        value = google_sql_user.api_iam.name
      }
      env {
        name  = "PROVIDER_TOKEN_SECRET"
        value = google_secret_manager_secret.provider_token.secret_id
      }
      env {
        name  = "DB_PASSWORD_SECRET"
        value = google_secret_manager_secret.db_password.secret_id
      }
    }

    vpc_access {
      egress = "PRIVATE_RANGES_ONLY"

      network_interfaces {
        network    = google_compute_network.app.name
        subnetwork = google_compute_subnetwork.app.name
        tags       = ["meridian-api"]
      }
    }
  }

  depends_on = [
    google_secret_manager_secret_version.provider_token,
    google_secret_manager_secret_version.db_password,
    google_secret_manager_secret_iam_member.db_password_api_access,
    google_secret_manager_secret_iam_member.token_access,
  ]
}

resource "google_cloud_run_v2_service_iam_member" "public_health" {
  project  = var.project_id
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

output "health_url" {
  value = "${google_cloud_run_v2_service.api.uri}/health"
}

output "artifact_registry_repository" {
  value = "${var.region}-docker.pkg.dev/${var.project_id}/meridian-poc"
}

# Only this existing Cloud Run service may be deployed by GitHub Actions.
# No project-wide Cloud Run permissions; CI cannot create other services.
resource "google_cloud_run_v2_service_iam_member" "ci_deploy_existing_api" {
  project  = var.project_id
  location = google_cloud_run_v2_service.api.location
  name     = google_cloud_run_v2_service.api.name
  role     = "roles/run.developer"
  member   = "serviceAccount:meridian-poc-ci-deploy@${var.project_id}.iam.gserviceaccount.com"
}
