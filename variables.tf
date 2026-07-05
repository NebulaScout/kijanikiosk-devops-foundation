# variable "vm_ip" {
#   type        = string
#   description = "IP of the Multipass VM (multipass info kijanikiosk-api | grep IPv4)"
# }

variable "environment" {
  type    = string
  default = "staging"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"

}

variable "key_name" {
  type        = string
  description = "Name of the SSH key pair"
}

variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources"

}

variable "aws_access_key" {
  type        = string
  description = "AWS access key"
}

variable "aws_secret_key" {
  type        = string
  description = "AWS secret key"
}

variable "owner" {
  type        = string
  description = "Owner of the resources"

}

variable "ingress" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "egress" {
  type = list(object({
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = [{
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }]
}
