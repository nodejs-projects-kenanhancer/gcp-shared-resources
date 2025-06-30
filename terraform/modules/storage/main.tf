locals {
  bucket_configs = {
    for key, value in var.storages_config : key => {
      name          = "${value.name}-${var.basic_config.environment}"
      force_destroy = value.force_destroy
    }
  }
}

data "google_project" "current" {
  project_id = var.basic_config.gcp_project_id
}

resource "google_storage_bucket" "bucket" {
  for_each = local.bucket_configs

  name          = each.value.name
  force_destroy = each.value.force_destroy
  location      = var.basic_config.gcp_region
  project       = var.basic_config.gcp_project_id

  labels = var.additional_labels
}

resource "google_storage_bucket" "app_config" {
  name          = "app-config-${var.basic_config.environment}"
  force_destroy = true
  location      = var.basic_config.gcp_region
  project       = var.basic_config.gcp_project_id

  labels = var.additional_labels
}

resource "google_storage_bucket" "cloud_function_source" {
  name          = "cloud-functions-${var.basic_config.environment}"
  force_destroy = true
  location      = var.basic_config.gcp_region
  project       = var.basic_config.gcp_project_id

  labels = var.additional_labels
}
