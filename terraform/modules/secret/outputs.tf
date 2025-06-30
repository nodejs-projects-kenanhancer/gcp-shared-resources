# output "result" {
#   value = {
#     secrets = {
#       aiven_kafka_ca_cert = {
#         id        = google_secret_manager_secret.aiven_kafka_ca_cert.id
#         name      = google_secret_manager_secret.aiven_kafka_ca_cert.secret_id # Short name
#         full_name = google_secret_manager_secret.aiven_kafka_ca_cert.name      # Original fully qualified name
#         version   = google_secret_manager_secret_version.aiven_kafka_ca_cert_initial.version
#       },
#       aiven_kafka_cert = {
#         id        = google_secret_manager_secret.aiven_kafka_cert.id
#         name      = google_secret_manager_secret.aiven_kafka_cert.secret_id # Short name
#         full_name = google_secret_manager_secret.aiven_kafka_cert.name      # Original fully qualified name
#         version   = google_secret_manager_secret_version.aiven_kafka_cert_initial.version
#       },
#       aiven_kafka_key = {
#         id        = google_secret_manager_secret.aiven_kafka_key.id
#         name      = google_secret_manager_secret.aiven_kafka_key.secret_id # Short name
#         full_name = google_secret_manager_secret.aiven_kafka_key.name      # Original fully qualified name
#         version   = google_secret_manager_secret_version.aiven_kafka_key_initial.version
#       }
#       aiven_kafka_username = {
#         id        = google_secret_manager_secret.aiven_kafka_username.id
#         name      = google_secret_manager_secret.aiven_kafka_username.secret_id # Short name
#         full_name = google_secret_manager_secret.aiven_kafka_username.name      # Original fully qualified name
#         version   = google_secret_manager_secret_version.aiven_kafka_username_initial.version
#       }
#       aiven_kafka_password = {
#         id        = google_secret_manager_secret.aiven_kafka_password.id
#         name      = google_secret_manager_secret.aiven_kafka_password.secret_id # Short name
#         full_name = google_secret_manager_secret.aiven_kafka_password.name      # Original fully qualified name
#         version   = google_secret_manager_secret_version.aiven_kafka_password_initial.version
#       }
#     }
#   }
#   description = "Secret module outputs"
# }


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
