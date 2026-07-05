variable "vm_ip" {
  type        = string
  description = "IP of the Multipass VM (multipass info kijanikiosk-api | grep IPv4)"
}

variable "environment" {
  type    = string
  default = "staging"
}
