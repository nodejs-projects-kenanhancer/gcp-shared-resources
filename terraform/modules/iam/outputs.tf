output "result" {
  value = {
    service_accounts = {
      cloud_function = {
        email = google_service_account.shared_cloud_function_sa.email
      }
      # github_actions = {
      #   email = coalesce(
      #     data.google_service_account.existing_github_actions_sa.email,
      #     try(google_service_account.github_actions_sa[0].email, null)
      #   )
      #   key = try(google_service_account_key.github_actions_key[0].private_key, null)
      # }
    }
    custom_roles = {
      runtime = google_project_iam_custom_role.cloud_function_runtime.id
    }
  }
  description = "IAM module outputs"
}
