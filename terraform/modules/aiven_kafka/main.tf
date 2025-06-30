locals {
  # Replace all hyphens with underscores in both parts
  sanitized_user = replace(var.aiven_config.user_name, "-", "_")
  sanitized_env  = replace(var.basic_config.environment, "-", "_")

  # Combine with single hyphen
  base_username = "${local.sanitized_user}-${local.sanitized_env}"
}

data "aiven_project" "kenan" {
  project = var.aiven_config.project
}

data "aiven_kafka" "kenan_kafka" {
  project      = data.aiven_project.kenan.project
  service_name = var.aiven_config.kafka_service_name
}

resource "aiven-kafka-users_user" "user" {
  project           = data.aiven_project.kenan.project
  service_name      = data.aiven_kafka.kenan_kafka.service_name
  base_username     = local.base_username
  max_cert_age_days = var.aiven_config.max_cert_age_days
}

data "aiven_service_component" "schema_registry" {
  project      = data.aiven_project.kenan.project
  service_name = data.aiven_kafka.kenan_kafka.service_name
  component    = "schema_registry"
  route        = "dynamic"
}
