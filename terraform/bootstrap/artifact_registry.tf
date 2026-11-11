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

# GitHub Actions builder can push images ONLY to this Docker repository.
# No project-wide Artifact Registry role, Cloud Run permissions or state access.
resource "google_artifact_registry_repository_iam_member" "github_builder_push" {
  project    = var.project_id
  location   = google_artifact_registry_repository.api.location
  repository = google_artifact_registry_repository.api.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.ci_builder.email}"
}

# Deploy job only pulls the immutable image from this one repository.
resource "google_artifact_registry_repository_iam_member" "ci_deploy_image_read" {
  project    = var.project_id
  location   = google_artifact_registry_repository.api.location
  repository = google_artifact_registry_repository.api.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.ci_cloudrun_deployer.email}"
}
