# A service account is a robot identity used by later pipeline jobs. IAM roles
# state exactly what that robot is allowed to do.
resource "google_service_account" "pipeline" {
  project      = var.project_id
  account_id   = "lol-pipeline"
  display_name = "League of Legends learning pipeline"
}

resource "google_project_iam_member" "pipeline" {
  for_each = local.pipeline_roles

  project = var.project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.pipeline.email}"
}

# Composer is the foreman: it tells managed services when to work. The existing
# pipeline account remains the worker identity used inside Cloud Run and
# Dataproc, so Composer never receives Secret Manager access.
resource "google_cloud_run_v2_job_iam_member" "composer_ingestion_invoker" {
  count = var.enable_composer_demo ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.riot_ingestion.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_cloud_run_v2_job_iam_member" "composer_dbt_invoker" {
  count = var.enable_composer_demo ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.dbt_build.name
  role     = "roles/run.invoker"
  member   = "serviceAccount:${google_service_account.composer[0].email}"
}

# The Airflow Cloud Run operator reads each job definition while executing it.
# Viewer is read-only and is bound to each specific job, not the whole project.
resource "google_cloud_run_v2_job_iam_member" "composer_ingestion_viewer" {
  count = var.enable_composer_demo ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.riot_ingestion.name
  role     = "roles/run.viewer"
  member   = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_cloud_run_v2_job_iam_member" "composer_dbt_viewer" {
  count = var.enable_composer_demo ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_job.dbt_build.name
  role     = "roles/run.viewer"
  member   = "serviceAccount:${google_service_account.composer[0].email}"
}

# Cloud Run job invocation returns a long-running operation. The Airflow
# operator polls that operation, but roles/run.invoker does not include
# run.operations.get. Keep invoke access scoped to each job above and grant
# only this single read permission at project scope for operation polling.
resource "google_project_iam_custom_role" "composer_cloud_run_operation_reader" {
  count = var.enable_composer_demo ? 1 : 0

  project     = var.project_id
  role_id     = "composerCloudRunOperationReader"
  title       = "Composer Cloud Run operation reader"
  description = "Lets the Composer demo poll Cloud Run operations it started."
  permissions = ["run.operations.get"]
}

resource "google_project_iam_member" "composer_cloud_run_operation_reader" {
  count = var.enable_composer_demo ? 1 : 0

  project = var.project_id
  role    = google_project_iam_custom_role.composer_cloud_run_operation_reader[0].name
  member  = "serviceAccount:${google_service_account.composer[0].email}"
}

# Dataproc Serverless needs the caller to submit and monitor a batch. This is
# scoped to the project because Dataproc batches are regional project resources.
resource "google_project_iam_member" "composer_dataproc_editor" {
  count = var.enable_composer_demo ? 1 : 0

  project = var.project_id
  role    = "roles/dataproc.editor"
  member  = "serviceAccount:${google_service_account.composer[0].email}"
}

# The DAG explicitly asks Dataproc to run as lol-pipeline. "Act as" is the
# narrow permission that lets Composer use that one worker identity.
resource "google_service_account_iam_member" "composer_pipeline_user" {
  count = var.enable_composer_demo ? 1 : 0

  service_account_id = google_service_account.pipeline.name
  role               = "roles/iam.serviceAccountUser"
  member             = "serviceAccount:${google_service_account.composer[0].email}"
}

# BigQuery job creation is a project-level permission; table writes are limited
# to this one learning dataset rather than the whole project.
resource "google_project_iam_member" "composer_bigquery_job_user" {
  count = var.enable_composer_demo ? 1 : 0

  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.composer[0].email}"
}

resource "google_bigquery_dataset_iam_member" "composer_bigquery_data_editor" {
  count = var.enable_composer_demo ? 1 : 0

  project    = var.project_id
  dataset_id = google_bigquery_dataset.analytics.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.composer[0].email}"
}

# Airflow lists the input Parquet files before it submits the load job.
resource "google_storage_bucket_iam_member" "composer_curated_reader" {
  count = var.enable_composer_demo ? 1 : 0

  bucket = google_storage_bucket.curated.name
  role   = "roles/storage.objectViewer"
  member = "serviceAccount:${google_service_account.composer[0].email}"
}
