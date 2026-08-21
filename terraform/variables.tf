variable "project_id" {
  description = "Existing GCP project ID with billing enabled."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{4,28}[a-z0-9]$", var.project_id))
    error_message = "project_id must be a valid GCP project ID."
  }
}

variable "region" {
  description = "GCP region for regional pipeline resources."
  type        = string
  default     = "us-east1"
}

variable "environment" {
  description = "Short environment label included in resource names."
  type        = string
  default     = "dev"
}

variable "enable_composer_demo" {
  description = "Create the chargeable Cloud Composer demo environment. Keep false except while demonstrating Airflow."
  type        = bool
  default     = false
}

variable "composer_image_version" {
  description = "Pinned Cloud Composer 3 image version. Do not use an alias, because aliases can change on a later apply."
  type        = string
  default     = "composer-3-airflow-2.11.1-build.11"
}

variable "ingestion_image" {
  description = "Immutable Artifact Registry image digest for the Riot ingestion Cloud Run Job."
  type        = string

  validation {
    condition     = can(regex("^.+@sha256:[a-f0-9]{64}$", var.ingestion_image))
    error_message = "ingestion_image must be an immutable image digest ending in @sha256:<64 lowercase hex characters>."
  }
}

variable "dbt_image" {
  description = "Immutable Artifact Registry image digest for the dbt Cloud Run Job."
  type        = string

  validation {
    condition     = can(regex("^.+@sha256:[a-f0-9]{64}$", var.dbt_image))
    error_message = "dbt_image must be an immutable image digest ending in @sha256:<64 lowercase hex characters>."
  }
}
