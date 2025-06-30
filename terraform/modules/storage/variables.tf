variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment    = string
    gcp_project_id = string
    gcp_region     = string
  })
}

variable "additional_labels" {
  description = "Additional Resource Labels"
  type        = map(string)
  default     = {}
}

variable "storages_config" {
  description = "Map of storage configurations including bucket names, force destroy settings"
  type = map(object({
    name          = string
    force_destroy = bool
  }))
}
