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



variable "ingress" {
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = []
}

variable "egress" {
  type = list(object({
    description = string
    from_port   = number
    to_port     = number
    protocol    = string
    cidr_blocks = list(string)
  }))
  default = [{
    description = "Default egress rule"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }]
}

variable "ami_id" {
  type        = string
  description = "AMI ID to use for the EC2 instance"
}

variable "subnet_id" {
  type        = string
  description = "ID of the subnet to deploy the EC2 instance in"
}

variable "name" {
  type        = string
  description = "Name tag for the EC2 instance"
}

variable "vpc_security_group_ids" {
  type        = list(string)
  description = "List of security group IDs to attach"
  default     = []
}
