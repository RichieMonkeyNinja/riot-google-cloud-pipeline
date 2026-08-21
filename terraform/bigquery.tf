# BigQuery is where we will run SQL against cleaned, analytics-ready data.
resource "google_bigquery_dataset" "analytics" {
  dataset_id                 = "lol_analytics"
  project                    = var.project_id
  location                   = var.region
  delete_contents_on_destroy = false
  description                = "Analytics-ready League of Legends data."

  depends_on = [google_project_service.required]
}
