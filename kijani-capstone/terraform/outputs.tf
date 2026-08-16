output "staging_namespace" {
  description = "Namespace created for the KijaniKiosk staging environment."
  value       = kubernetes_namespace_v1.staging.metadata[0].name
}

output "staging_namespace_labels" {
  description = "Labels applied by Terraform to identify the environment and owner."
  value       = kubernetes_namespace_v1.staging.metadata[0].labels
}
