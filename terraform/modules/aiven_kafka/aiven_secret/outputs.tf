output "result" {
  value = {
    secrets = merge(
      # Dynamic secrets from for_each
      {
        for key, secret in google_secret_manager_secret.secrets : key => {
          id        = secret.id
          name      = secret.secret_id # Short name
          full_name = secret.name      # Fully qualified name
          version   = try(google_secret_manager_secret_version.versions[key].version, null)
        }
      },
      # Static secrets with hardcoded keys (if you have any static resources)
      # Add any static secret resources here following the same pattern
      # Example:
      # {
      #   "static_secret_name" = {
      #     id        = google_secret_manager_secret.static_secret_name.id
      #     name      = google_secret_manager_secret.static_secret_name.secret_id
      #     full_name = google_secret_manager_secret.static_secret_name.name
      #     version   = google_secret_manager_secret_version.static_secret_version.version
      #   }
      # }
    )
  }
  description = "Secret module outputs including all secret resources"
}
