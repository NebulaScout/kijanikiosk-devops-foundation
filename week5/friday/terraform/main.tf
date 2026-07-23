terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.53.0"
    }
  }
}

provider "aws" {
  region     = var.aws_region
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}


data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

module "server_sg" {
  source      = "./modules/security_group"
  name        = "server_sg"
  description = "Security group for EC2 instances"

  ingress = [
    { from_port = 22, to_port = 22, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    { from_port = 80, to_port = 80, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    { from_port = 443, to_port = 443, protocol = "tcp", cidr_blocks = ["0.0.0.0/0"] },
    { from_port = -1, to_port = -1, protocol = "icmp", cidr_blocks = ["0.0.0.0/0"] },
  ]

  egress = [
    { from_port = 0, to_port = 0, protocol = "-1", cidr_blocks = ["0.0.0.0/0"] },
  ]

  tags = {
    Name = "server_sg"
  }
}

locals {
  servers = {
    api = {
      instance_type = var.instance_type
    }
    payments = {
      instance_type = var.instance_type
    }
    logs = {
      instance_type = var.instance_type
    }
  }
}

module "app_server" {
  source = "./modules/app_server"

  for_each               = local.servers
  name                   = each.key
  ami_id                 = data.aws_ami.ubuntu.id
  instance_type          = each.value.instance_type
  key_name               = var.key_name
  subnet_id              = var.subnet_id
  vpc_security_group_ids = [module.server_sg.id]
  environment            = var.environment
}
