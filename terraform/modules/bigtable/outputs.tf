output "result" {
  description = "Bigtable instance output"
  value = {
    id          = google_bigtable_instance.instance.id
    name        = google_bigtable_instance.instance.name
    instance_id = google_bigtable_instance.instance.name
    project     = google_bigtable_instance.instance.project
  }
}

output "tables" {
  description = "Bigtable tables output"
  value = {
    for name, table in google_bigtable_table.tables : name => {
      id   = table.id
      name = table.name
    }
  }
}
