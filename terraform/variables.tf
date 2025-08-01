variable "provider_versions" {
  type = object({
    github            = string
    google            = string
    terraform         = string
    aiven             = string
    aiven_kafka_users = string
  })
  default = {
    github            = ">= 6.5.0"
    google            = ">= 6.16.0"
    terraform         = ">= 1.5.7"
    aiven             = ">= 4.37.0"
    aiven_kafka_users = "~>2.1.1"
  }
}


variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment     = string
    gcp_project_id  = string
    gcp_region      = string
    tf_state_bucket = string
  })
}

variable "iam_config" {
  description = "Unified IAM configuration"
  type = object({
    project_members = optional(list(object({
      role    = string
      members = list(string)
    })), [])
    bucket_members = optional(list(object({
      buckets = list(string)
      role    = string
      members = list(string)
    })), [])
  })
  default = {}
}

variable "storages_config" {
  description = "Map of storage configurations"
  type = map(object({
    name          = string
    force_destroy = bool
  }))
  default = {}
}

variable "secrets_config" {
  description = "Map of secret configurations including secret names, replication policy, and other settings"
  type = map(object({
    name         = string
    secret_value = optional(string)
    replication = optional(object({
      automatic = optional(bool, false)
      user_managed = optional(object({
        replicas = list(object({
          location = string
        }))
      }))
    }))
    labels      = optional(map(string), {})
    annotations = optional(map(string), {})
    expire_time = optional(string)
  }))
  sensitive = true
  default   = {}
}

variable "topic_config" {
  description = "Map of Pub/Sub topic configurations"
  type = map(object({
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
      name       = optional(string, "")     # Name of the schema, if not provided it will be derived from the topic name
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
  }))
  default = {}
}

variable "bigtable_config" {
  description = "Configuration for Bigtable instances"
  type = map(object({
    instance_name       = string
    zone                = optional(string)
    min_nodes           = optional(number, 3)
    max_nodes           = optional(number, 10)
    cpu_target          = optional(number, 50)
    storage_type        = optional(string, "SSD")
    deletion_protection = optional(bool, true)
    labels              = optional(map(string), {})
    additional_clusters = optional(list(object({
      id           = string
      zone         = string
      min_nodes    = optional(number)
      max_nodes    = optional(number)
      cpu_target   = optional(number)
      storage_type = optional(string)
    })), [])
    tables = list(object({
      name            = string
      column_families = optional(list(string), [])
    }))
  }))
  default = {}
}

# variable "network_config" {
#   description = "Network configuration"
#   type = object({
#     subnet_cidr             = string
#     vpc_connector_cidr      = string
#     public_project_cidr     = string
#     connector_max_instances = number
#     connector_min_instances = number
#   })
# }

# variable "application_config_bucket" {
#   description = "App Config with schema"
#   type        = string
# }

# variable "project_members" {
#   type = object({
#     viewer = list(string)
#     owner  = optional(list(string), [])
#   })
#   description = "Project view members"
# }

# variable "additional_labels" {
#   description = "Additional Resource Labels"
#   type        = map(string)
#   default     = {}
# }

# variable "cloudsql_config" {
#   description = "Configuration for Cloud SQL instance and connection"
#   type = object({
#     machine_type    = string // e.g. db-custom-2-3840
#     machine_edition = string
#     db_name         = string
#     db_admin_user   = string
#   })
# }

# variable "datadog_api_key" {
#   description = "Created via slack /dd-ovo integration. From GH secrets via github actions."
#   type        = string
#   sensitive   = true
# }

# variable "datadog_app_key" {
#   description = "Created via slack /dd-ovo integration. From GH secrets via github actions."
#   type        = string
#   sensitive   = true
# }

# variable "aiven_config" {
#   description = "Kafka Aiven Configuration"
#   type = object({
#     api_token          = string
#     project            = string
#     kafka_service_name = string
#     user_name          = string
#     max_cert_age_days  = number
#   })
#   default = null
# }
