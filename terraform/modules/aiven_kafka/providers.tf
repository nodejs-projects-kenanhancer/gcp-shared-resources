terraform {
  required_providers {
    aiven = {
      version = "= 4.0.0-rc3" # latest at time of writing https://registry.terraform.io/providers/aiven/aiven/latest/docs
      source  = "aiven/aiven"
    }

    aiven-kafka-users = {
      source  = "terraform.kenan.org.uk/pe/aiven-kafka-users"
      version = "~>2.1.1"
    }
  }

  required_version = ">=1.10.5" # (terraform version) latest at time of writing, set in github actions shared-* files, https://www.terraform.io/downloads.html
}

provider "aiven-kafka-users" {
  api_token = var.aiven_config.api_token
}

provider "aiven" {
  api_token = var.aiven_config.api_token
}
