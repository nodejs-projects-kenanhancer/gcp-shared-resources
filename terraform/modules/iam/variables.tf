variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment     = string
    gcp_project_id  = string
    gcp_region      = string
    tf_state_bucket = string
  })
}

variable "bucket_configs" {
  type = map(object({
    name      = string
    iam_roles = list(string)
  }))
}

variable "project_members" {
  type = object({
    viewer = list(string)
    owner  = optional(list(string), [])
  })
  description = "Project members"
}
