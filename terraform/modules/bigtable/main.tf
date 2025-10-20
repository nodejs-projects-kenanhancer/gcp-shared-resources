resource "google_bigtable_instance" "instance" {
  name    = "${var.bigtable_config.instance_name}-${var.basic_config.environment}"
  project = var.basic_config.gcp_project_id

  # Main cluster configuration
  cluster {
    cluster_id = "${var.bigtable_config.instance_name}-${var.basic_config.environment}"
    zone       = var.bigtable_config.zone != null ? var.bigtable_config.zone : "${var.basic_config.gcp_region}-a"

    autoscaling_config {
      min_nodes  = var.bigtable_config.min_nodes
      max_nodes  = var.bigtable_config.max_nodes
      cpu_target = var.bigtable_config.cpu_target
    }

    storage_type = var.bigtable_config.storage_type
  }

  # Additional clusters configuration
  dynamic "cluster" {
    for_each = var.bigtable_config.additional_clusters
    content {
      cluster_id = "${var.bigtable_config.instance_name}-${cluster.value.id}-${var.basic_config.environment}"
      zone       = cluster.value.zone

      # Ensuring min_nodes and max_nodes are always set with proper defaults
      autoscaling_config {
        min_nodes = coalesce(
          lookup(cluster.value, "min_nodes", null),
          lookup(var.bigtable_config, "min_nodes", 3)
        )
        max_nodes = coalesce(
          lookup(cluster.value, "max_nodes", null),
          lookup(var.bigtable_config, "max_nodes", 10)
        )
        cpu_target = coalesce(
          lookup(cluster.value, "cpu_target", null),
          lookup(var.bigtable_config, "cpu_target", 50)
        )
      }

      storage_type = cluster.value.storage_type
    }
  }

  deletion_protection = var.bigtable_config.deletion_protection
  labels              = var.bigtable_config.labels
}

resource "google_bigtable_table" "tables" {
  for_each      = { for table in var.bigtable_config.tables : table.name => table }
  name          = "${each.value.name}-${var.basic_config.environment}"
  instance_name = google_bigtable_instance.instance.name
  project       = var.basic_config.gcp_project_id

  dynamic "column_family" {
    for_each = each.value.column_families
    content {
      family = column_family.value
    }
  }
}
