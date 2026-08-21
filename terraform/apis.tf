# APIs are on/off switches for Google Cloud services. They must be enabled
# before Terraform can create resources from those services.
resource "google_project_service" "required" {
  for_each = local.required_services

  project            = var.project_id
  service            = each.value
  disable_on_destroy = false
}
