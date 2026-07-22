output "api_server_ip" {
  description = "Public IP of the API server"
  value       = module.app_server["api"].public_ip
}

output "payments_server_ip" {
  description = "Public IP of the Payments server"
  value       = module.app_server["payments"].public_ip
}

output "logs_server_ip" {
  description = "Public IP of the Logs server"
  value       = module.app_server["logs"].public_ip
}
