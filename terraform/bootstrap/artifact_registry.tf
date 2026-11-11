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
