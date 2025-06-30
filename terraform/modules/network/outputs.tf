output "result" {
  value = {
    vpc_connector = {
      name      = google_vpc_access_connector.connector.name
      id        = google_vpc_access_connector.connector.id
      region    = google_vpc_access_connector.connector.region
      self_link = google_vpc_access_connector.connector.self_link
    }
    network = {
      name      = google_compute_network.vpc_network.name
      id        = google_compute_network.vpc_network.id
      self_link = google_compute_network.vpc_network.self_link
    }
    subnet = {
      name      = google_compute_subnetwork.subnet.name
      id        = google_compute_subnetwork.subnet.id
      self_link = google_compute_subnetwork.subnet.self_link
    }
    router = {
      name      = google_compute_router.router.name
      id        = google_compute_router.router.id
      self_link = google_compute_router.router.self_link
    }
  }
  description = "VPC connector module outputs"
}
