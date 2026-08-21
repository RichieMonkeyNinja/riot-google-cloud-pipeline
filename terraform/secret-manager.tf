# Terraform creates only the locked box. The actual Riot API-key value is added
# manually later, so it never appears in Terraform state or Git.
resource "google_secret_manager_secret" "riot_api_key" {
  project   = var.project_id
  secret_id = "riot-api-key"

  replication {
    auto {}
  }

  depends_on = [google_project_service.required]
}
