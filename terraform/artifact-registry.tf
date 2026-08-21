# Artifact Registry is the private Google shelf that stores our Docker images.
# Cloud Run will later pull the ingestion image from this repository.
resource "google_artifact_registry_repository" "lol_pipeline" {
  project       = var.project_id
  location      = var.region
  repository_id = "lol-pipeline"
  description   = "Docker images for the League of Legends learning pipeline."
  format        = "DOCKER"

  depends_on = [google_project_service.required]
}
