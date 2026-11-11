resource "google_sql_database_instance" "postgres" {
  name                = "meridian-poc-postgres"
  region              = var.region
  database_version    = "POSTGRES_16"
  deletion_protection = false

  settings {
    tier              = "db-f1-micro"
    availability_type = "ZONAL"
    disk_type         = "PD_SSD"
    disk_size         = 10

    ip_configuration {
      ipv4_enabled    = false
      private_network = google_compute_network.app.id
    }

    database_flags {
      name  = "cloudsql.iam_authentication"
      value = "on"
    }

    backup_configuration {
      enabled = true
    }
  }

  depends_on = [google_service_networking_connection.sql]
}

resource "google_sql_database" "app" {
  name     = "meridian"
  instance = google_sql_database_instance.postgres.name
}

# IAM database login uses the *runtime service account* as the PostgreSQL principal.
# Cloud SQL requires removing .gserviceaccount.com from Postgres SA usernames.
resource "google_sql_user" "api_iam" {
  name     = trimsuffix(data.google_service_account.api.email, ".gserviceaccount.com")
  instance = google_sql_database_instance.postgres.name
  type     = "CLOUD_IAM_SERVICE_ACCOUNT"
}

resource "random_password" "provider_token_placeholder" {
  length  = 36
  special = false
}

resource "google_secret_manager_secret" "provider_token" {
  secret_id = "meridian-poc-provider-token"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}

# Synthetic placeholder only; no third-party calls are made in this PoC.
resource "google_secret_manager_secret_version" "provider_token" {
  secret      = google_secret_manager_secret.provider_token.id
  secret_data = random_password.provider_token_placeholder.result
}

output "database_private_ip" {
  value = google_sql_database_instance.postgres.private_ip_address
}

output "database_name" {
  value = google_sql_database.app.name
}
