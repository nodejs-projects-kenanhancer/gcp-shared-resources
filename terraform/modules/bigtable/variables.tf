variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment    = string
    gcp_project_id = string
    gcp_region     = string
  })
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
