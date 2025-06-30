variable "env" {
  description = "Application environment"
  type        = string
}

variable "gcp_project_full" {
  description = "GCP project"
  type        = string
}

variable "datadog_api_key" {
  description = "Created via slack /dd-kenan integration. From GH secrets via github actions."
  type        = string
  sensitive   = true
}

variable "datadog_app_key" {
  description = "Created via slack /dd-kenan integration. From GH secrets via github actions."
  type        = string
  sensitive   = true
}

variable "enabled" {
  description = "Is datadog enabled"
  type        = bool
}
