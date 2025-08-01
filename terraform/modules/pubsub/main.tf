locals {
  topic_name     = "${var.topic_config.name}-${var.basic_config.environment}"
  schema_name    = "${var.topic_config.schema_config.name}-${var.basic_config.environment}"
  schema_enabled = try(var.topic_config.schema_config.enabled, false)

  dlq_enabled      = try(var.topic_config.dlq_config.enabled, false)
  dlq_topic_name   = "${var.topic_config.name}-dlq-${var.basic_config.environment}"
  default_sub_name = local.dlq_enabled ? "${var.topic_config.name}-default-sub-${var.basic_config.environment}" : null
}

resource "google_pubsub_schema" "event_schema" {
  count = local.schema_enabled ? 1 : 0

  project    = var.basic_config.gcp_project_id
  name       = local.schema_name
  type       = var.topic_config.schema_config.type
  definition = var.topic_config.schema_config.definition
}

resource "google_pubsub_topic" "topic" {
  name                       = local.topic_name
  project                    = var.basic_config.gcp_project_id
  message_retention_duration = var.topic_config.message_retention_duration

  # Regional storage policy
  message_storage_policy {
    allowed_persistence_regions = var.topic_config.message_storage_policy.allowed_persistence_regions
  }

  # Only include schema_settings when schema is enabled
  dynamic "schema_settings" {
    for_each = local.schema_enabled ? [1] : []
    content {
      schema   = google_pubsub_schema.event_schema[0].id
      encoding = var.topic_config.schema_config.encoding
    }
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

  # Message processing timeout before retry
  ack_deadline_seconds = var.topic_config.dlq_config.ack_deadline_seconds

  dead_letter_policy {
    dead_letter_topic     = google_pubsub_topic.dlq_topic[0].id
    max_delivery_attempts = var.topic_config.dlq_config.max_delivery_attempts # Retry attempts before moving to DLQ
  }
}
