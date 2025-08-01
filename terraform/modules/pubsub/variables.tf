variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment    = string
    gcp_project_id = string
    gcp_region     = string
  })
}

variable "topic_config" {
  description = "Map of Pub/Sub topic configurations"
  type = object({
    name            = string
    publish_members = optional(list(string), [])
    message_storage_policy = optional(object({
      allowed_persistence_regions = list(string)
      }), {
      allowed_persistence_regions = ["europe-north1"] # Default value
    })
    labels = optional(map(string), {})

    # Message TTL in seconds (e.g., "86400s" = 1 day)
    message_retention_duration = optional(string) # default to null (7 days)

    schema_config = optional(object({
      enabled    = optional(bool, false)
      name       = optional(string, "")   # Name of the schema, if not provided it will be derived from the topic name
      type       = optional(string, "AVRO") # AVRO or PROTOCOL_BUFFER  
      encoding   = optional(string, "JSON") # value can be "BINARY" or "JSON"
      definition = optional(string, null)
    }), {})

    # Simplified DLQ configuration
    dlq_config = optional(object({
      enabled                    = optional(bool, false)
      message_retention_duration = optional(string, "2678400s") # Message TTL in seconds (e.g., "2678400s" = 31 days)
      max_delivery_attempts      = optional(number, 10)         # Retry attempts before moving to DLQ
      ack_deadline_seconds       = optional(number, 60)         # Message processing timeout before retry (default 60 seconds)
    }), {})
  })
}
