output "raw_bucket_name" {
  description = "Bucket for unchanged API responses."
  value       = google_storage_bucket.raw.name
}

output "curated_bucket_name" {
  description = "Bucket for cleaned Parquet data."
  value       = google_storage_bucket.curated.name
}

output "dataproc_staging_bucket_name" {
  description = "Temporary Dataproc batch files and driver logs; objects expire after seven days."
  value       = google_storage_bucket.dataproc_staging.name
}

output "pipeline_artifacts_bucket_name" {
  description = "Versioned GCS bucket for reviewed Spark code and future pipeline artifacts."
  value       = google_storage_bucket.pipeline_artifacts.name
}

output "bigquery_dataset_id" {
  description = "BigQuery dataset for analytics tables."
  value       = google_bigquery_dataset.analytics.dataset_id
}

output "pipeline_service_account_email" {
  description = "Identity that later batch jobs will use."
  value       = google_service_account.pipeline.email
}

output "riot_api_key_secret_id" {
  description = "Empty Secret Manager container. Add the API key manually, never through Terraform."
  value       = google_secret_manager_secret.riot_api_key.secret_id
}

output "ingestion_image_repository" {
  description = "Artifact Registry image path for the Riot ingestion container."
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.lol_pipeline.repository_id}"
}

output "cloud_run_ingestion_job_name" {
  description = "Cloud Run Job that ingests the daily Riot Gold I sample."
  value       = google_cloud_run_v2_job.riot_ingestion.name
}

output "cloud_run_dbt_job_name" {
  description = "Cloud Run Job that builds and tests dbt Gold models."
  value       = google_cloud_run_v2_job.dbt_build.name
}

output "cloud_scheduler_ingestion_job_name" {
  description = "Daily Cloud Scheduler trigger for the Riot ingestion job."
  value       = google_cloud_scheduler_job.riot_ingestion_daily.name
}

output "composer_airflow_uri" {
  description = "Cloud Composer Airflow UI address. Null when enable_composer_demo is false."
  value       = try(google_composer_environment.demo[0].config[0].airflow_uri, null)
}

output "composer_dag_gcs_prefix" {
  description = "Managed Composer DAG folder. Null when the demo is disabled."
  value       = try(google_composer_environment.demo[0].config[0].dag_gcs_prefix, null)
}
