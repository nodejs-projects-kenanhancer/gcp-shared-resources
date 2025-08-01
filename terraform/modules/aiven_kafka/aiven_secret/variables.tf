variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment     = string
    gcp_project_id  = string
    gcp_region      = string
    tf_state_bucket = string
  })
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
