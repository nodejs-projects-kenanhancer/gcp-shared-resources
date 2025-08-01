variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment     = string
    gcp_project_id  = string
    gcp_region      = string
    tf_state_bucket = string
  })
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
