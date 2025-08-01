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

resource "google_secret_manager_secret" "secrets" {
  for_each = local.secret_configs

  secret_id = each.value.name
  project   = var.basic_config.gcp_project_id

  # Make the entire replication block dynamic
  dynamic "replication" {
    for_each = each.value.replication != null ? [each.value.replication] : []

    content {
      dynamic "auto" {
        for_each = try(replication.value.automatic, false) ? [1] : []
        content {}
      }

      dynamic "user_managed" {
        # Pass the actual user_managed object, not just [1]
        for_each = try(replication.value.user_managed, null) != null ? [replication.value.user_managed] : []

        content {
          dynamic "replicas" {
            for_each = user_managed.value.replicas

            content {
              location = replicas.value.location
            }
          }
        }
      }
    }
  }

  labels      = lookup(each.value, "labels", {})
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
