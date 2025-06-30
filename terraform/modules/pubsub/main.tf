locals {
  schema_name = split(".", basename(var.avro_schema_path))[0]

  # DLQ configuration helpers
  dlq_enabled      = try(var.topic_config.dlq_config.enabled, false)
  topic_name       = "${var.topic_config.name}-${var.basic_config.environment}"
  dlq_topic_name   = local.dlq_enabled ? "${var.topic_config.name}-dlq-${var.basic_config.environment}" : null
  default_sub_name = local.dlq_enabled ? "${var.topic_config.name}-default-sub-${var.basic_config.environment}" : null
}

data "google_storage_bucket_object_content" "schema_file" {
  name   = var.avro_schema_path
  bucket = var.bucket_config_name
}

resource "google_pubsub_schema" "event_schema" {
  name       = "${var.topic_config.name}-${local.schema_name}-${var.basic_config.environment}"
  type       = "AVRO"
  definition = data.google_storage_bucket_object_content.schema_file.content
}

resource "google_pubsub_topic" "topic" {
  name    = local.topic_name
  project = var.basic_config.gcp_project_id
  labels  = var.additional_labels

  message_retention_duration = var.topic_config.message_retention_duration

  # Regional storage policy
  message_storage_policy {
    allowed_persistence_regions = var.topic_config.message_storage_policy.allowed_persistence_regions
  }

  schema_settings {
    schema   = google_pubsub_schema.event_schema.id
    encoding = "JSON"
  }
}

# Grant roles to a servie account member
resource "google_pubsub_topic_iam_member" "editor" {
  for_each = { for idx, sa in var.topic_config.publish_members : idx => sa }
  project  = var.basic_config.gcp_project_id
  topic    = google_pubsub_topic.topic.id

  role   = "roles/pubsub.publisher"
  member = "serviceAccount:${each.value}"
}

resource "google_project_iam_member" "schema_viewer" {
  for_each = {
    for idx, sa in var.topic_config.publish_members : idx => sa
  }

  project = var.basic_config.gcp_project_id
  role    = "roles/pubsub.viewer"
  member  = "serviceAccount:${each.value}"
}

# Dead Letter Queue Topic (conditional)
resource "google_pubsub_topic" "dlq_topic" {
  count      = local.dlq_enabled ? 1 : 0
  depends_on = [google_pubsub_topic.topic]

  name    = local.dlq_topic_name
  project = var.basic_config.gcp_project_id

  labels = var.additional_labels

  # Message TTL in seconds (e.g., "86400s" = 1 day)
  message_retention_duration = var.topic_config.dlq_config.message_retention_duration

  # Same regional policy as main topic
  message_storage_policy {
    allowed_persistence_regions = var.topic_config.message_storage_policy.allowed_persistence_regions
  }

  # No schema for DLQ - messages already validated by main topic
}

# Default Subscription with DLQ policy
resource "google_pubsub_subscription" "default_subscription" {
  count      = local.dlq_enabled ? 1 : 0
  depends_on = [google_pubsub_topic.dlq_topic]

  name    = local.default_sub_name
  topic   = google_pubsub_topic.topic.name
  project = var.basic_config.gcp_project_id

  labels = var.additional_labels

  # Message processing timeout before retry
  ack_deadline_seconds = var.topic_config.dlq_config.ack_deadline_seconds

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq_topic[0].id
    max_delivery_attempts = var.topic_config.dlq_config.max_delivery_attempts # Retry attempts before moving to DLQ
  }
}
