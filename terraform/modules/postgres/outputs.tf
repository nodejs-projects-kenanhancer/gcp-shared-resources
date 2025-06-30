output "instance_connection_name" {
  description = "Cloud SQL connection name"
  value       = google_sql_database_instance.silver.connection_name
}

output "private_ip_address" {
  description = "Private IP assigned to Cloud SQL"
  value       = google_sql_database_instance.silver.private_ip_address
}

output "admin_username" {
  description = "DB admin user"
  value       = google_sql_user.admin.name
}


output "admin_password" {
  description = "Sensitive: generated admin password"
  value       = random_password.admin_pwd.result
  sensitive   = true
}
