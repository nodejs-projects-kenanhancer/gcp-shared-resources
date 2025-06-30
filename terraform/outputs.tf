output "iam_resources" {
  value     = module.iam_resources
  sensitive = true
}

output "storage_resources" {
  value = module.storage_resources
}

output "network_resources" {
  value = module.network_resources
}

output "aiven_kafka_resources" {
  value     = module.aiven_kafka_resources
  sensitive = true
}

output "secret_resources" {
  value = module.secret_resources
}

output "pubsub_resources" {
  value = module.pubsub_resources
}

output "bigtable_resources" {
  value = module.bigtable_resources
}
