locals {
  normalized_environment = replace(var.basic_config.environment, "-", "_")
  hashed_environment     = substr(md5(var.basic_config.environment), 0, 8)
  sanitized_account_id = format(
    "%s%s",
    substr(replace(var.basic_config.environment, "[^a-z0-9]", "-"), 0, 19),
    local.hashed_environment
  )

  # Flatten project members for easier iteration
  project_member_assignments = flatten([
    for pm in var.iam_config.project_members : [
      for member in pm.members : {
        role   = pm.role
        member = member
      }
    ]
  ])

  # Flatten bucket members for easier iteration
  bucket_member_assignments = flatten([
    for bm in var.iam_config.bucket_members : [
      for bucket in bm.buckets : [
        for member in bm.members : {
          bucket = "${bucket}-${var.basic_config.environment}"
          role   = bm.role
          member = member
        }
      ]
    ]
  ])

  # Define default roles for the shared service account
  shared_sa_default_roles = [
    "projects/${var.basic_config.gcp_project_id}/roles/cloud_function_runtime_role_${local.normalized_environment}",
    "roles/secretmanager.secretAccessor",
    "roles/pubsub.publisher",
    "roles/pubsub.subscriber",
    "roles/pubsub.editor",
    "roles/eventarc.eventReceiver",
    "roles/run.invoker",
    "roles/bigtable.user"
  ]
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

# Default project-level role assignments for shared service account
resource "google_project_iam_member" "shared_sa_default_roles" {
  for_each = toset(local.shared_sa_default_roles)

  project = var.basic_config.gcp_project_id
  role    = each.value
  member  = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}

# Dynamic project-level role assignments from iam_config
resource "google_project_iam_member" "project_member_assignments" {
  for_each = {
    for idx, assignment in local.project_member_assignments :
    "${assignment.role}-${assignment.member}" => assignment
  }

  project = var.basic_config.gcp_project_id
  role    = each.value.role
  member  = each.value.member
}

# Bucket-specific permissions from iam_config
resource "google_storage_bucket_iam_member" "bucket_member_assignments" {
  for_each = {
    for idx, assignment in local.bucket_member_assignments :
    "${assignment.bucket}-${assignment.role}-${assignment.member}" => assignment
  }

  bucket = each.value.bucket
  role   = each.value.role
  member = each.value.member
}

# Bucket-specific permissions
resource "google_storage_bucket_iam_member" "terraform_state_access" {
  bucket = "${var.basic_config.tf_state_bucket}-${var.basic_config.gcp_project_id}"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
}
