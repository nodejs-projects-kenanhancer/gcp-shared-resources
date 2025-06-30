locals {
  secret_configs = nonsensitive({
    for key, value in var.secrets_config : key => {
      name         = "${value.name}-${var.basic_config.environment}"
      secret_value = value.secret_value
      replication  = value.replication
      labels       = value.labels
      annotations  = value.annotations
      expire_time  = value.expire_time
    }
  })
}

resource "null_resource" "aiven_trigger" {
  triggers = {
    username         = sha256(var.aiven_config.username)
    password         = sha256(var.aiven_config.password)
    ca_cert_hash     = sha256(var.aiven_config.ca_cert)
    access_cert_hash = sha256(var.aiven_config.access_cert)
    access_key_hash  = sha256(var.aiven_config.access_key)
  }
}

resource "google_secret_manager_secret" "aiven_kafka_ca_cert" {
  secret_id = "aiven-kafka-ca-cert-${var.basic_config.environment}"
  project   = var.basic_config.gcp_project_id
  replication {
    user_managed {
      replicas {
        location = var.basic_config.gcp_region
      }
    }
  }

  labels = var.additional_labels
}

resource "google_secret_manager_secret_version" "aiven_kafka_ca_cert_initial" {
  secret      = google_secret_manager_secret.aiven_kafka_ca_cert.id
  secret_data = var.aiven_config.ca_cert

  # Use create_before_destroy to ensure the new version is created before the old one is destroyed
  lifecycle {
    replace_triggered_by = [null_resource.aiven_trigger]
  }
}

resource "google_secret_manager_secret" "aiven_kafka_cert" {
  secret_id = "aiven-kafka-cert-${var.basic_config.environment}"
  project   = var.basic_config.gcp_project_id
  replication {
    user_managed {
      replicas {
        location = var.basic_config.gcp_region
      }
    }
  }

  labels = var.additional_labels
}

resource "google_secret_manager_secret_version" "aiven_kafka_cert_initial" {
  secret      = google_secret_manager_secret.aiven_kafka_cert.id
  secret_data = var.aiven_config.access_cert

  # Use create_before_destroy to ensure the new version is created before the old one is destroyed
  lifecycle {
    replace_triggered_by = [null_resource.aiven_trigger]
  }
}

resource "google_secret_manager_secret" "aiven_kafka_key" {
  secret_id = "aiven-kafka-key-${var.basic_config.environment}"
  project   = var.basic_config.gcp_project_id
  replication {
    user_managed {
      replicas {
        location = var.basic_config.gcp_region
      }
    }
  }

  labels = var.additional_labels
}

resource "google_secret_manager_secret_version" "aiven_kafka_key_initial" {
  secret      = google_secret_manager_secret.aiven_kafka_key.id
  secret_data = var.aiven_config.access_key

  # Use create_before_destroy to ensure the new version is created before the old one is destroyed
  lifecycle {
    replace_triggered_by = [null_resource.aiven_trigger]
  }
}

resource "google_secret_manager_secret" "aiven_kafka_username" {
  secret_id = "aiven-kafka-username-${var.basic_config.environment}"
  project   = var.basic_config.gcp_project_id
  replication {
    user_managed {
      replicas {
        location = var.basic_config.gcp_region
      }
    }
  }

  labels = var.additional_labels
}

resource "google_secret_manager_secret_version" "aiven_kafka_username_initial" {
  secret      = google_secret_manager_secret.aiven_kafka_username.id
  secret_data = var.aiven_config.username

  # Use create_before_destroy to ensure the new version is created before the old one is destroyed
  lifecycle {
    replace_triggered_by = [null_resource.aiven_trigger]
  }
}

resource "google_secret_manager_secret" "aiven_kafka_password" {
  secret_id = "aiven-kafka-password-${var.basic_config.environment}"
  project   = var.basic_config.gcp_project_id
  replication {
    user_managed {
      replicas {
        location = var.basic_config.gcp_region
      }
    }
  }

  labels = var.additional_labels
}

resource "google_secret_manager_secret_version" "aiven_kafka_password_initial" {
  secret      = google_secret_manager_secret.aiven_kafka_password.id
  secret_data = var.aiven_config.password

  # Use create_before_destroy to ensure the new version is created before the old one is destroyed
  lifecycle {
    replace_triggered_by = [null_resource.aiven_trigger]
  }
}

resource "google_secret_manager_secret" "secrets" {
  for_each = local.secret_configs

  secret_id = each.value.name
  project   = var.basic_config.gcp_project_id

  replication {
    dynamic "auto" {
      for_each = try(each.value.replication.automatic, false) ? [1] : []
      content {}
    }

    dynamic "user_managed" {
      for_each = try(each.value.replication.user_managed, null) != null ? [1] : []
      content {
        dynamic "replicas" {
          for_each = each.value.replication.user_managed.replicas
          content {
            location = replicas.value.location
          }
        }
      }
    }
  }

  labels      = merge(var.additional_labels, lookup(each.value, "labels", {}))
  annotations = each.value.annotations
  expire_time = each.value.expire_time
}

resource "null_resource" "secret_version_trigger" {
  for_each = { for key, value in local.secret_configs : key => value if value.secret_value != null }

  triggers = {
    secret_value_hash = sha256(each.value.secret_value) # Track changes based on the secret_value hash
  }
}

resource "google_secret_manager_secret_version" "versions" {
  for_each = { for key, value in local.secret_configs : key => value if value.secret_value != null }

  secret      = google_secret_manager_secret.secrets[each.key].id
  secret_data = each.value.secret_value

  lifecycle {
    create_before_destroy = true
    replace_triggered_by  = [null_resource.secret_version_trigger[each.key]] # Triggers replacement when the secret value changes
  }
}
