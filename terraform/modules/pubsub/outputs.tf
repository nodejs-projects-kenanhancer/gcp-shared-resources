output "result" {
  description = "Pub/Sub topic output"
  value = {
    id       = google_pubsub_topic.topic.id
    name     = google_pubsub_topic.topic.name
    topic_id = google_pubsub_topic.topic.name
    project  = google_pubsub_topic.topic.project

    # Schema information
    schema_id   = google_pubsub_schema.event_schema.id
    schema_name = google_pubsub_schema.event_schema.name

    # DLQ information
    dlq_enabled           = local.dlq_enabled
    dlq_topic_id          = local.dlq_enabled ? google_pubsub_topic.dlq_topic[0].id : null
    dlq_topic_name        = local.dlq_enabled ? google_pubsub_topic.dlq_topic[0].name : null
    dlq_subscription_id   = local.dlq_enabled ? google_pubsub_subscription.default_subscription[0].id : null
    dlq_subscription_name = local.dlq_enabled ? google_pubsub_subscription.default_subscription[0].name : null
  }
}
