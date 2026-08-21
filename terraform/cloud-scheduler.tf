# This separate robot can start the ingestion job, but cannot read Riot keys or
# write GCS data. Keeping trigger and pipeline identities separate is safer.
resource "google_service_account" "scheduler" {
  project      = var.project_id
  account_id   = "lol-ingestion-scheduler"
  display_name = "Daily League ingestion scheduler"
}

resource "google_cloud_run_v2_job_iam_member" "scheduler_invoker" {
  project  = var.project_id
  location = google_cloud_run_v2_job.riot_ingestion.location
  name     = google_cloud_run_v2_job.riot_ingestion.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.scheduler.email}"
}

# Cloud Scheduler calls the Google Cloud Run API once per day. Google APIs use
# an OAuth token, not an OIDC token.
resource "google_cloud_scheduler_job" "riot_ingestion_daily" {
  name             = "lol-riot-ingestion-daily"
  description      = "Start the Riot Gold I ingestion Cloud Run Job every day."
  region           = var.region
  schedule         = "0 2 * * *"
  time_zone        = "Asia/Kuala_Lumpur"
  attempt_deadline = "180s"

  http_target {
    http_method = "POST"
    uri         = "https://run.googleapis.com/v2/projects/${var.project_id}/locations/${var.region}/jobs/${google_cloud_run_v2_job.riot_ingestion.name}:run"
    body        = base64encode("{}")

    headers = {
      "Content-Type" = "application/json"
    }

    oauth_token {
      service_account_email = google_service_account.scheduler.email
      scope                 = "https://www.googleapis.com/auth/cloud-platform"
    }
  }

  retry_config {
    retry_count = 1
  }

  depends_on = [google_cloud_run_v2_job_iam_member.scheduler_invoker]
}
