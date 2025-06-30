output "result" {
  value = {
    buckets = merge(
      # Dynamic buckets from for_each
      {
        for key, bucket in google_storage_bucket.bucket : key => {
          id          = bucket.id
          name        = bucket.name
          url         = bucket.url
          bucket_name = bucket.name
        }
      },
      # Static buckets with hardcoded keys (if you have any static resources)
      # Add any static secret resources here following the same pattern
      {
        "app_config" = {
          id          = google_storage_bucket.app_config.id
          name        = google_storage_bucket.app_config.name
          url         = google_storage_bucket.app_config.url
          bucket_name = google_storage_bucket.app_config.name
        },
        "cloud_function_source" = {
          id          = google_storage_bucket.cloud_function_source.id
          name        = google_storage_bucket.cloud_function_source.name
          url         = google_storage_bucket.cloud_function_source.url
          bucket_name = google_storage_bucket.cloud_function_source.name
        }
      }
    )
  }
  description = "Storage module outputs including all bucket resources"
}
