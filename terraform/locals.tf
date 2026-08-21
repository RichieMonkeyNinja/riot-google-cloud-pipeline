# Shared names and lists. Keeping them here avoids repeating the same text in
# each service file.
locals {
  name_prefix = "${var.project_id}-${var.environment}"

  required_services = toset([
    "artifactregistry.googleapis.com",
    "bigquery.googleapis.com",
    "cloudbuild.googleapis.com",
    "cloudscheduler.googleapis.com",
    "composer.googleapis.com",
    "dataproc.googleapis.com",
    "run.googleapis.com",
    "secretmanager.googleapis.com",
    "serviceusage.googleapis.com",
    "storage.googleapis.com",
  ])

  pipeline_roles = toset([
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/dataproc.worker",
    "roles/secretmanager.secretAccessor",
    "roles/storage.objectAdmin",
  ])
}
