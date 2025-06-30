locals {
  # Define static bucket IAM roles if they aren't in var.storages_config.
  default_iam_roles = {
    "app_config"            = ["roles/storage.objectViewer"],
    "cloud_function_source" = ["roles/storage.objectCreator"]
  }

  iam_bucket_configs = {
    for key, value in module.storage_resources.result.buckets : key => {
      name = value.bucket_name
      # If the key exists in var.storages_config, use those roles, otherwise use defaults or empty array
      iam_roles = contains(keys(var.storages_config), key) ? var.storages_config[key].iam_roles : lookup(local.default_iam_roles, key, [])
    }
  }
}

module "storage_resources" {
  source = "./modules/storage"

  basic_config      = var.basic_config
  storages_config   = var.storages_config
  additional_labels = var.additional_labels
}

module "iam_resources" {
  source     = "./modules/iam"
  depends_on = [module.storage_resources]

  basic_config   = var.basic_config
  bucket_configs = local.iam_bucket_configs

  project_members = var.project_members
}

module "aiven_kafka_resources" {
  source = "./modules/aiven_kafka"

  basic_config = var.basic_config
  aiven_config = var.aiven_config
}

module "secret_resources" {
  source     = "./modules/secret"
  depends_on = [module.aiven_kafka_resources]

  basic_config      = var.basic_config
  aiven_config      = module.aiven_kafka_resources.result.aiven_config
  secrets_config    = var.secrets_config
  additional_labels = var.additional_labels
}

module "network_resources" {
  source = "./modules/network"

  basic_config      = var.basic_config
  network_config    = var.network_config
}

module "pubsub_resources" {
  source   = "./modules/pubsub"
  for_each = var.pubsub_topics_config

  basic_config       = var.basic_config
  topic_config       = each.value
  additional_labels  = var.additional_labels
  avro_schema_path   = var.pubsub_avro_schema_path
  bucket_config_name = var.application_config_bucket
}

module "bigtable_resources" {
  source   = "./modules/bigtable"
  for_each = var.bigtable_instances_config

  basic_config      = var.basic_config
  bigtable_config   = each.value
  additional_labels = var.additional_labels
}
