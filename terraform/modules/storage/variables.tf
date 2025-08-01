variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment    = string
    gcp_project_id = string
    gcp_region     = string
  })
}

variable "storages_config" {
  description = "Map of storage configurations"
  type = map(object({
    name          = string
    force_destroy = bool
  }))
  default = {}
}
