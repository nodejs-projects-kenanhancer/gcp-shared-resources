variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment     = string
    gcp_project_id  = string
    gcp_region      = string
    tf_state_bucket = string
  })
}

variable "additional_labels" {
  description = "Additional Resource Labels"
  type        = map(string)
  default     = {}
}

variable "aiven_config" {
  type = object({
    username    = string
    password    = string
    access_cert = string
    access_key  = string
    ca_cert     = string
  })
  description = "Kafka Aiven Configuration"
  sensitive   = true
}

variable "secrets_config" {
  description = "Map of secret configurations including secret names, replication policy, and other settings"
  type = map(object({
    name         = string
    secret_value = optional(string) # Optional secret value
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
}
