output "result" {
  value = {
    aiven_config = {
      username            = aiven-kafka-users_user.user.username
      password            = aiven-kafka-users_user.user.password
      access_cert         = aiven-kafka-users_user.user.access_cert
      access_key          = aiven-kafka-users_user.user.access_key
      ca_cert             = data.aiven_project.kenan.ca_cert
      schema_registry_uri = "https://${aiven-kafka-users_user.user.username}:${aiven-kafka-users_user.user.password}@${data.aiven_service_component.schema_registry.host}:${data.aiven_service_component.schema_registry.port}"
    },
  }
  description = "Aiven module outputs"
  sensitive   = true
}
