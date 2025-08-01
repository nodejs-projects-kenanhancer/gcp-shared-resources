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
}

resource "google_secret_manager_secret_version" "aiven_kafka_password_initial" {
  secret      = google_secret_manager_secret.aiven_kafka_password.id
  secret_data = var.aiven_config.password

  # Use create_before_destroy to ensure the new version is created before the old one is destroyed
  lifecycle {
    replace_triggered_by = [null_resource.aiven_trigger]
  }
}
