# A Cloud Run Job is a run-to-completion container, not a web server. It uses
# the existing pipeline robot identity to read Secret Manager and write raw GCS
# files, then exits.
resource "google_cloud_run_v2_job" "riot_ingestion" {
  name                = "lol-riot-ingestion"
  location            = var.region
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.pipeline.email
      timeout         = "900s"
      max_retries     = 1

      containers {
        image = var.ingestion_image
        args = [
          "--project-id", var.project_id,
          "--raw-bucket", google_storage_bucket.raw.name,
          "--player-count", "10",
          "--matches-per-player", "20",
          "--request-delay-seconds", "1.3",
          "--secret-id", google_secret_manager_secret.riot_api_key.secret_id,
        ]

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }
    }
  }

  depends_on = [google_project_service.required]
}

# dbt runs after BigQuery has loaded the Silver tables. It shares the existing
# pipeline identity for this learning project; a production system would use a
# separate least-privilege analytics-transformation service account.
resource "google_cloud_run_v2_job" "dbt_build" {
  name                = "lol-dbt-build"
  location            = var.region
  deletion_protection = false

  template {
    template {
      service_account = google_service_account.pipeline.email
      timeout         = "900s"
      max_retries     = 1

      containers {
        image = var.dbt_image

        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }

        resources {
          limits = {
            cpu    = "1"
            memory = "512Mi"
          }
        }
      }
    }
  }

  depends_on = [google_project_service.required]
}

# Let the job's identity pull only from this private image repository.
resource "google_artifact_registry_repository_iam_member" "pipeline_image_reader" {
  project    = var.project_id
  location   = google_artifact_registry_repository.lol_pipeline.location
  repository = google_artifact_registry_repository.lol_pipeline.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.pipeline.email}"
}
