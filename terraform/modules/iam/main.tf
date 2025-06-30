locals {
  bucket_permissions = flatten([
    for bucket_key, bucket in var.bucket_configs : [
      for role in bucket.iam_roles : {
        bucket_name = bucket.name
        role        = role
      }
    ]
  ])
  normalized_environment = replace(var.basic_config.environment, "-", "_")
  hashed_environment     = substr(md5(var.basic_config.environment), 0, 8)
  sanitized_account_id = format(
    "%s%s",
    substr(replace(var.basic_config.environment, "[^a-z0-9]", "-"), 0, 19),
    local.hashed_environment
  )
}

data "google_project" "current" {
  project_id = var.basic_config.gcp_project_id
}

# Service Accounts
resource "google_service_account" "shared_cloud_function_sa" {
  account_id   = "sa-${local.sanitized_account_id}"
  display_name = "Shared Service Account for Cloud Functions"
  description  = "Service account used by Cloud Functions deployed from boilerplate"
}

# Custom roles
resource "google_project_iam_custom_role" "cloud_function_runtime" {
  project     = var.basic_config.gcp_project_id
  role_id     = "cloud_function_runtime_role_${local.normalized_environment}"
  title       = "Cloud Function Runtime Role"
  description = "Role for Cloud Function runtime"
  permissions = [
    "cloudfunctions.functions.invoke",
  ]
}

# Project-level role assignments
resource "google_project_iam_member" "runtime_role" {
  project = var.basic_config.gcp_project_id
  role    = google_project_iam_custom_role.cloud_function_runtime.id
  member  = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_secret_access_binding" {
  project = var.basic_config.gcp_project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_pubsub_publisher_binding" {
  project = var.basic_config.gcp_project_id
  role    = "roles/pubsub.publisher"
  member  = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_pubsub_subscriber_binding" {
  project = var.basic_config.gcp_project_id
  role    = "roles/pubsub.subscriber"
  member  = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_pubsub_editor_binding" {
  project = var.basic_config.gcp_project_id
  role    = "roles/pubsub.editor"
  member  = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_eventarc_receiver_binding" {
  project = var.basic_config.gcp_project_id
  role    = "roles/eventarc.eventReceiver"
  member  = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_run_invoker_binding" {
  project = var.basic_config.gcp_project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

resource "google_project_iam_member" "cloud_function_bigtable_access_binding" {
  project = var.basic_config.gcp_project_id
  role    = "roles/bigtable.user" # This role includes bigtable.tables.mutateRows permission
  member  = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

# Bucket-specific permissions
resource "google_storage_bucket_iam_member" "terraform_state_access" {
  bucket = "${var.basic_config.tf_state_bucket}-${var.basic_config.gcp_project_id}"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

resource "google_storage_bucket_iam_member" "bucket_permissions" {
  for_each = { for perm in local.bucket_permissions : "${perm.bucket_name}-${perm.role}" => perm }

  bucket = each.value.bucket_name
  role   = each.value.role
  member = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

resource "google_project_iam_member" "project_view_permissions" {
  for_each = { for idx, sa in var.project_members.viewer : idx => sa }
  project  = var.basic_config.gcp_project_id
  role     = "roles/viewer"
  member   = each.value
}

resource "google_project_iam_member" "project_owner_permissions" {
  for_each = { for idx, sa in var.project_members.owner : idx => sa }
  project  = var.basic_config.gcp_project_id
  role     = "roles/owner"
  member   = each.value
}
