terraform {
  required_providers {
    
    datadog = {
      version = "= 3.65.0" # latest at time of writing https://registry.terraform.io/providers/datadog/datadog/latest/docs
      source  = "DataDog/datadog"
    }

    google = {
      version = "= 6.39.0" # latest at time of writing https://registry.terraform.io/providers/hashicorp/google/latest/docs
      source  = "hashicorp/google"
    }
  }
}

provider "datadog" {
  api_key = var.datadog_api_key
  app_key = var.datadog_app_key
}