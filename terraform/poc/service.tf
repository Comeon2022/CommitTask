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

resource "google_service_account" "api" {
  account_id   = "meridian-poc-api"
  display_name = "Meridian API runtime identity"
  depends_on   = [google_project_service.required]
}

resource "google_secret_manager_secret_iam_member" "db_access" {
  secret_id = google_secret_manager_secret.database_password.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_secret_manager_secret_iam_member" "token_access" {
  secret_id = google_secret_manager_secret.provider_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.api.email}"
}

resource "google_artifact_registry_repository" "api" {
  location      = var.region
  repository_id = "meridian-poc"
  format        = "DOCKER"
  description   = "Container images for the Meridian evaluation"
  depends_on    = [google_project_service.required]
}

resource "google_cloud_run_v2_service" "api" {
  name                = "meridian-poc-api"
  location            = var.region
  deletion_protection = false
  ingress             = "INGRESS_TRAFFIC_ALL"

  template {
    service_account = google_service_account.api.email

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
      env {
        name  = "DEPLOYED_COMMIT"
        value = var.deployed_commit
      }
      env {
        name  = "DB_HOST"
        value = google_sql_database_instance.postgres.private_ip_address
      }
      env {
        name  = "DB_NAME"
        value = google_sql_database.app.name
      }
      env {
        name  = "DB_USER"
        value = google_sql_user.app.name
      }
      env {
        name  = "DB_PASSWORD_SECRET"
        value = google_secret_manager_secret.database_password.secret_id
      }
      env {
        name  = "PROVIDER_TOKEN_SECRET"
        value = google_secret_manager_secret.provider_token.secret_id
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
    google_secret_manager_secret_version.database_password,
    google_secret_manager_secret_version.provider_token,
    google_secret_manager_secret_iam_member.db_access,
    google_secret_manager_secret_iam_member.token_access,
    google_artifact_registry_repository.api,
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
  value = google_artifact_registry_repository.api.name
}
