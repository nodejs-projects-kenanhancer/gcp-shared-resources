output "result" {
  description = "Pub/Sub topic output"
  value = {
    id       = google_pubsub_topic.topic.id
    name     = google_pubsub_topic.topic.name
    topic_id = google_pubsub_topic.topic.name
    project  = google_pubsub_topic.topic.project

    # Schema information (conditional)
    schema_enabled = local.schema_enabled
    schema_id      = local.schema_enabled ? google_pubsub_schema.event_schema[0].id : null
    schema_name    = local.schema_enabled ? google_pubsub_schema.event_schema[0].name : null

    # DLQ information (conditional)
    dlq_enabled           = local.dlq_enabled
    dlq_topic_id          = local.dlq_enabled ? google_pubsub_topic.dlq_topic[0].id : null
    dlq_topic_name        = local.dlq_enabled ? google_pubsub_topic.dlq_topic[0].name : null
    dlq_subscription_id   = local.dlq_enabled ? google_pubsub_subscription.default_subscription[0].id : null
    dlq_subscription_name = local.dlq_enabled ? google_pubsub_subscription.default_subscription[0].name : null
  }
}
