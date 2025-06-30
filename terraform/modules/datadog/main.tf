locals {
  default_datadog_monitor_tags = [
    "domain:FinOps",
    "subdomain:Collections",
    "team:Collections",
    "env:${var.env}",
    "envType:${var.env == "prod" ? "Production" : "NonProduction"}",
    "project:${var.gcp_project_full}"
  ]
}

resource "google_service_account" "datadog_metrics_sa" {
  account_id = "datadog-metrics-sa"
}

resource "google_project_iam_member" "datadog_iam_roles" {
  for_each = toset([
    "roles/monitoring.viewer",
    "roles/compute.viewer",
    "roles/cloudasset.viewer",
    "roles/browser"
  ])
  member  = "serviceAccount:${google_service_account.datadog_metrics_sa.email}"
  project = var.gcp_project_full
  role    = each.key
}

resource "google_service_account_iam_member" "sa_impersonation" {
  service_account_id = google_service_account.datadog_metrics_sa.name
  role               = "roles/iam.serviceAccountTokenCreator"
  member             = "serviceAccount:${datadog_integration_gcp_sts.integration.delegate_account_email}"
}

resource "datadog_integration_gcp_sts" "integration" {
  client_email    = google_service_account.datadog_metrics_sa.email
  automute        = false
  is_cspm_enabled = false
}

resource "datadog_monitor" "DLQ_watcher_Messages_detected_in_DLQ" {
  name                = "DLQ watcher: Messages detected in DLQ - ENV:${var.env}"
  type                = "query alert"
  message             = "@slack-bpc-collections-alerts-${var.env}\n@opsgenie-bpc-collections-${var.env}"
  count               = var.enabled ? 1 : 0
  query               = "max(last_1h):sum:gcp.pubsub.topic.num_retained_messages{topic_id:slv-assessment-v1-dlq*}.weighted() > 1"
  require_full_window = false
  notify_audit        = true
  evaluation_delay    = 300
  monitor_thresholds {
    critical = 1
    warning  = 0
  }
  renotify_interval = 0
  include_tags      = true
  tags              = concat(local.default_datadog_monitor_tags)
}
