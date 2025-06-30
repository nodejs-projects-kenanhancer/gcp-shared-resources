resource "google_sql_database_instance" "silver" {
  name             = "${var.cloudsql_config.db_name}-instance-${var.basic_config.environment}"
  region           = var.basic_config.gcp_region
  database_version = "POSTGRES_17"

  settings {
    tier    = var.cloudsql_config.machine_type
    edition = var.cloudsql_config.machine_edition
    ip_configuration {
      ipv4_enabled                                  = false
      private_network                               = var.cloudsql_config.private_network_self_link
      enable_private_path_for_google_cloud_services = true
    }

    deletion_protection_enabled = false

    backup_configuration {
      enabled                        = true
      start_time                     = "02:00"
      location                       = var.basic_config.gcp_region
      point_in_time_recovery_enabled = true
      backup_retention_settings {
        retained_backups = 45
        retention_unit   = "COUNT"
      }
    }
  }
}

resource "google_sql_database" "silver" {
  name       = var.cloudsql_config.db_name
  instance   = google_sql_database_instance.silver.name
  depends_on = [google_sql_database_instance.silver]
}


resource "random_password" "admin_pwd" {
  length  = 16
  special = true
}

resource "google_sql_user" "admin" {
  name       = var.cloudsql_config.db_admin_user
  instance   = google_sql_database_instance.silver.name
  password   = random_password.admin_pwd.result
  depends_on = [google_sql_database_instance.silver]
}
