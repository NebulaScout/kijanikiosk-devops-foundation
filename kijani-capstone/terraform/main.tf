terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.30, < 3.0"
    }
  }
}

provider "kubernetes" {
  config_path    = pathexpand(var.kubeconfig_path)
  config_context = var.kubeconfig_context != "" ? var.kubeconfig_context : null
}

# Terraform owns the namespace lifecycle. Workloads and namespace guardrails are
# configured separately by Ansible after this resource has been created.
resource "kubernetes_namespace_v1" "staging" {
  metadata {
    name = var.staging_namespace

    labels = {
      "app.kubernetes.io/part-of" = "kijani-kiosk"
      "kijani.io/environment"     = "staging"
      "kijani.io/managed-by"      = "terraform"
    }
  }
}
