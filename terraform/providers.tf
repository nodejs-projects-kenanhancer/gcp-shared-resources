terraform {
  required_providers {
    github = {
      version = ">= 6.5.0" # latest at time of writing https://registry.terraform.io/providers/integrations/github/latest/docs
      source  = "integrations/github"
    }

    google = {
      version = ">= 6.16.0" # latest at time of writing https://registry.terraform.io/providers/hashicorp/google/latest/docs
      source  = "hashicorp/google"
    }
  }

  required_version = ">=1.10.5" # (terraform version) latest at time of writing, set in github actions shared-* files, https://www.terraform.io/downloads.html
}

# GCP
provider "google" {
  project = var.basic_config.gcp_project_id
  region  = var.basic_config.gcp_region
}
