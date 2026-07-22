variable "aws_region" {
  type        = string
  description = "AWS region to deploy resources"
  default     = "us-east-1"
}

variable "aws_access_key" {
  type        = string
  description = "AWS access key"
}

variable "aws_secret_key" {
  type        = string
  description = "AWS secret key"
}

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

variable "subnet_id" {
  type        = string
  description = "ID of the subnet to deploy the EC2 instance in"
}
