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
  description = "Kafka Aiven Configuration"
  type = object({
    api_token          = string
    project            = string
    kafka_service_name = string
    user_name          = string
    max_cert_age_days  = number
  })
}
