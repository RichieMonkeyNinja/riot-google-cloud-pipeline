# Cloud Composer is Google's managed Airflow. It is deliberately optional:
# the environment costs money while running, so create it only for a demo and
# turn enable_composer_demo back to false to remove it afterwards.

# This is Composer's robot identity, separate from the data-pipeline identity.
# For the UI/safe-demo DAG, Composer needs only its standard worker role.
resource "google_service_account" "composer" {
  count = var.enable_composer_demo ? 1 : 0

  project      = var.project_id
  account_id   = "lol-composer"
  display_name = "League of Legends Composer demo"
}

resource "google_project_iam_member" "composer_worker" {
  count = var.enable_composer_demo ? 1 : 0

  project = var.project_id
  role    = "roles/composer.worker"
  member  = "serviceAccount:${google_service_account.composer[0].email}"
}

# The exact image is pinned on purpose. A version alias could silently upgrade
# Airflow when Terraform is applied again, making another student's result less
# reproducible.
resource "google_composer_environment" "demo" {
  provider = google-beta
  count    = var.enable_composer_demo ? 1 : 0

  name    = "lol-airflow-demo"
  project = var.project_id
  region  = var.region

  config {
    software_config {
      image_version = var.composer_image_version

      # The DAG reads these values at import time. They contain resource names,
      # not credentials. The default DAG run still stops at its safety gate.
      env_variables = {
        GCP_PROJECT_ID            = var.project_id
        GCP_REGION                = var.region
        RAW_BUCKET                = google_storage_bucket.raw.name
        CURATED_BUCKET            = google_storage_bucket.curated.name
        DATAPROC_STAGING_BUCKET   = google_storage_bucket.dataproc_staging.name
        PIPELINE_ARTIFACTS_BUCKET = google_storage_bucket.pipeline_artifacts.name
        PIPELINE_SERVICE_ACCOUNT  = google_service_account.pipeline.email
        BQ_DATASET                = google_bigquery_dataset.analytics.dataset_id
        INGESTION_JOB_NAME        = google_cloud_run_v2_job.riot_ingestion.name
        DBT_JOB_NAME              = google_cloud_run_v2_job.dbt_build.name
      }
    }

    node_config {
      service_account = google_service_account.composer[0].email
    }
  }

  depends_on = [
    google_project_service.required,
    google_project_iam_member.composer_worker,
  ]
}

# Terraform copies the reviewed DAG into Composer's managed DAG bucket after
# the environment exists. Students cloning this repository do not need to make
# a manual upload or discover a hidden bucket name.
resource "google_storage_bucket_object" "composer_demo_dag" {
  count = var.enable_composer_demo ? 1 : 0

  bucket = split(
    "/",
    trimprefix(google_composer_environment.demo[0].config[0].dag_gcs_prefix, "gs://"),
  )[0]
  name         = "dags/lol_end_to_end.py"
  source       = "${path.module}/../airflow/dags/lol_end_to_end.py"
  content_type = "text/x-python"

  depends_on = [google_composer_environment.demo]
}
