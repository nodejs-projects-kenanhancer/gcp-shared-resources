output "result" {
  description = "IAM module outputs"
  value = {
    service_accounts = {
      cloud_function = {
        email      = google_service_account.shared_cloud_function_sa.email
        id         = google_service_account.shared_cloud_function_sa.id
        name       = google_service_account.shared_cloud_function_sa.name
        account_id = google_service_account.shared_cloud_function_sa.account_id
        member     = "serviceAccount:${google_service_account.shared_cloud_function_sa.email}"
      }
    }

    custom_roles = {
      runtime = {
        id          = google_project_iam_custom_role.cloud_function_runtime.id
        role_id     = google_project_iam_custom_role.cloud_function_runtime.role_id
        name        = google_project_iam_custom_role.cloud_function_runtime.name
        title       = google_project_iam_custom_role.cloud_function_runtime.title
        permissions = google_project_iam_custom_role.cloud_function_runtime.permissions
      }
    }

    iam_bindings = {
      shared_sa_default_roles = [
        for k, v in google_project_iam_member.shared_sa_default_roles : {
          project = v.project
          role    = v.role
          member  = v.member
        }
      ]
      project_members = [
        for k, v in google_project_iam_member.project_member_assignments : {
          project = v.project
          role    = v.role
          member  = v.member
        }
      ]
      bucket_members = [
        for k, v in google_storage_bucket_iam_member.bucket_member_assignments : {
          bucket = v.bucket
          role   = v.role
          member = v.member
        }
      ]
      terraform_state_bucket = {
        bucket = google_storage_bucket_iam_member.terraform_state_access.bucket
        role   = google_storage_bucket_iam_member.terraform_state_access.role
        member = google_storage_bucket_iam_member.terraform_state_access.member
      }
    }
  }
}
