variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment     = string
    gcp_project_id  = string
    gcp_region      = string
    tf_state_bucket = string
  })
}

variable "network_config" {
  description = "Network configuration"
  type = object({
    subnet_cidr             = string
    vpc_connector_cidr      = string
    public_project_cidr     = string
    connector_max_instances = number
    connector_min_instances = number
  })
}
