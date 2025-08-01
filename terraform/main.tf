module "iam_resources" {
  source     = "./modules/iam"
  depends_on = [module.storage_resources]

  basic_config = var.basic_config
  iam_config   = var.iam_config
}

module "storage_resources" {
  source = "./modules/storage"

  basic_config    = var.basic_config
  storages_config = var.storages_config
}

module "secret_resources" {
  source = "./modules/secret"

  basic_config   = var.basic_config
  secrets_config = var.secrets_config
}

module "pubsub_resources" {
  source   = "./modules/pubsub"
  for_each = var.topic_config

  basic_config = var.basic_config
  topic_config = each.value
}

module "bigtable_resources" {
  source   = "./modules/bigtable"
  for_each = var.bigtable_config

  basic_config      = var.basic_config
  bigtable_config   = each.value
}

# module "network_resources" {
#   source = "./modules/network"

#   basic_config   = var.basic_config
#   network_config = var.network_config
# }

# module "cloudsql_resources" {
#   source = "./modules/postgres"

#   basic_config    = var.basic_config
#   cloudsql_config = var.cloudsql_config
# }

# module "datadog" {
#   source           = "./modules/datadog"
#   enabled          = var.basic_config.enable_datadog
#   datadog_api_key  = var.datadog_api_key
#   datadog_app_key  = var.datadog_app_key
#   env              = var.basic_config.environment
#   gcp_project_full = var.basic_config.gcp_project_id
# }

# module "aiven_kafka_resources" {
#   count  = var.aiven_config != null ? 1 : 0
#   source = "./modules/aiven_kafka"

#   basic_config = var.basic_config
#   aiven_config = var.aiven_config
# }
