resource "google_compute_network" "vpc_network" {
  name                    = "vpc-${var.basic_config.environment}"
  project                 = var.basic_config.gcp_project_id
  auto_create_subnetworks = false

  description = "VPC Network for ${var.basic_config.environment} environment"
}

resource "google_compute_subnetwork" "subnet" {
  name          = "subnet-${var.basic_config.environment}"
  project       = var.basic_config.gcp_project_id
  region        = var.basic_config.gcp_region
  network       = google_compute_network.vpc_network.id
  ip_cidr_range = var.network_config.subnet_cidr

  description = "Subnet for ${var.basic_config.environment} environment"

  depends_on = [google_compute_network.vpc_network]
}

resource "google_vpc_access_connector" "connector" {
  name          = "con-${var.basic_config.environment}"
  project       = var.basic_config.gcp_project_id
  region        = var.basic_config.gcp_region
  network       = google_compute_network.vpc_network.name
  ip_cidr_range = var.network_config.vpc_connector_cidr

  min_instances = var.network_config.connector_min_instances # Google requires at least 2 for high availability
  # Use max_instances if you want to control costs by limiting the number of VMs that can be created
  max_instances = var.network_config.connector_max_instances
  # OR
  # Use max_throughput if you want to ensure a specific bandwidth regardless of the number of instances needed
  # max_throughput = 300  # In Mbps

  depends_on = [google_compute_network.vpc_network]
}

resource "google_compute_address" "subnet_private" {
  name   = "${google_compute_subnetwork.subnet.name}-address"
  region = google_compute_subnetwork.subnet.region
}

resource "google_compute_router" "router" {
  name        = "router-${var.basic_config.environment}"
  project     = var.basic_config.gcp_project_id
  region      = var.basic_config.gcp_region
  network     = google_compute_network.vpc_network.id
  description = "Cloud Router for ${var.basic_config.environment} environment"

  depends_on = [google_compute_network.vpc_network]
}

resource "google_compute_router_nat" "nat_gateway" {
  name                               = "nat-gateway-${var.basic_config.environment}"
  project                            = var.basic_config.gcp_project_id
  router                             = google_compute_router.router.name
  region                             = var.basic_config.gcp_region
  nat_ip_allocate_option             = "MANUAL_ONLY"
  nat_ips                            = [google_compute_address.subnet_private.self_link]
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.subnet.id
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }

  # Enable logging for troubleshooting connectivity issues
  log_config {
    enable = true
    # filter = "ERRORS_ONLY"
    filter = "ALL" # Log all traffic initially, change to ERRORS_ONLY after confirming functionality
  }

  depends_on = [google_compute_network.vpc_network]
}

# module "public_kenan_network" {
#   source       = "terraform.kenan.org.uk/pe/public-kenan/google"
#   version      = "~> 4.0"
#   network      = google_compute_network.vpc_network.name
#   project_cidr = var.network_config.public_project_cidr

#   depends_on = [google_compute_network.vpc_network]
# }
