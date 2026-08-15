variable "kubeconfig_path" {
  description = "Path to the kubeconfig used to manage the target Kubernetes cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kubeconfig_context" {
  description = "Optional kubeconfig context."
  type        = string
  default     = ""
}

variable "staging_namespace" {
  description = "Dedicated namespace for pre-production KijaniKiosk workloads."
  type        = string
  default     = "kijani-staging"
}
