# Bootstrap image repository before any Docker push or PoC apply.
# This root is owned by the privileged bootstrap operator.
resource "google_project_service" "artifactregistry" {
  project            = var.project_id
  service            = "artifactregistry.googleapis.com"
  disable_on_destroy = false
}

resource "google_artifact_registry_repository" "api" {
  project       = var.project_id
  location      = var.region
  repository_id = "meridian-poc"
  format        = "DOCKER"
  description   = "Meridian evaluation container images"
  depends_on    = [google_project_service.artifactregistry]
}

output "artifact_repository" {
  value = google_artifact_registry_repository.api.id
}

# The authorized release operator uses short-lived deployer credentials when
# Docker pushes to this exact repository. No project-wide publisher grant.
resource "google_artifact_registry_repository_iam_member" "deployer_push" {
  project    = var.project_id
  location   = google_artifact_registry_repository.api.location
  repository = google_artifact_registry_repository.api.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.identity["deployer"].email}"
}
