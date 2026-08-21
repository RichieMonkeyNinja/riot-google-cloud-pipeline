# Cloud Storage holds files. Raw keeps the original API response; curated keeps
# cleaned data produced by our future PySpark job.
resource "google_storage_bucket" "raw" {
  name                        = "${local.name_prefix}-lol-raw"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age                = 90
      with_state         = "ARCHIVED"
      matches_prefix     = ["match-details/"]
      num_newer_versions = 1
    }
  }

  depends_on = [google_project_service.required]
}

resource "google_storage_bucket" "curated" {
  name                        = "${local.name_prefix}-lol-curated"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  depends_on = [google_project_service.required]
}

# Permanent, versioned home for executable pipeline code. This is intentionally
# separate from the seven-day Dataproc staging bucket: Composer and Dataproc
# must be able to find the same reviewed script after staging files expire.
resource "google_storage_bucket" "pipeline_artifacts" {
  name                        = "${local.name_prefix}-pipeline-artifacts"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  versioning {
    enabled = true
  }

  depends_on = [google_project_service.required]
}

# Terraform calculates the local file checksum. When this source changes, it
# uploads a new GCS object generation at the fixed URI used by both Dataproc
# and the Airflow DAG.
resource "google_storage_bucket_object" "transform_matches" {
  name         = "pyspark/transform_matches.py"
  bucket       = google_storage_bucket.pipeline_artifacts.name
  source       = "${path.module}/../src/transform_matches.py"
  content_type = "text/x-python"
}

# Dataproc Serverless uses this bucket for submitted code, temporary job
# configuration, and driver output. It is separate from learning data and
# automatically cleaned after enough time to investigate a failed batch.
resource "google_storage_bucket" "dataproc_staging" {
  name                        = "${local.name_prefix}-dataproc-staging"
  project                     = var.project_id
  location                    = var.region
  uniform_bucket_level_access = true
  public_access_prevention    = "enforced"
  force_destroy               = false

  lifecycle_rule {
    action {
      type = "Delete"
    }
    condition {
      age = 7
    }
  }

  depends_on = [google_project_service.required]
}
