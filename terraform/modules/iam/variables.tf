variable "basic_config" {
  description = "Basic Configuration"
  type = object({
    environment     = string
    gcp_project_id  = string
    gcp_region      = string
    tf_state_bucket = string
  })
}

variable "iam_config" {
  description = "Unified IAM configuration"
  type = object({
    project_members = optional(list(object({
      role    = string
      members = list(string)
    })), [])
    bucket_members = optional(list(object({
      buckets = list(string)
      role    = string
      members = list(string)
    })), [])
  })
  default = {}
}
