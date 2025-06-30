variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment    = string
    gcp_project_id = string
    gcp_region     = string
    tf_state_bucket = string
  })
}

variable "cloudsql_config" {
  description = "Configuration for Cloud SQL instance and connection"
  type = object({
    machine_type              = string // e.g. db-custom-2-3840
    machine_edition           = string
    db_name                   = string
    db_admin_user             = string
    private_network_self_link = optional(string)
  })
}

