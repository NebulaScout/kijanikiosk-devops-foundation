# KijaniKiosk API Server - Desired State Specification

## Identity
- Name: kijanikiosk-api-staging
- Environment tag: staging
- Owner tag: amina

## Compute
- Provider: AWS
- Region: us-east-1
- Instance type: t3.micro
- Operating system: ubuntu-24.04-lts (exact image ID: ami-0f8a61b66d1accaee)
# Note: this becomes a Terraform data source on Tuesday — you will look this up dynamically

## Networking
- VPC: vpc-080d53caa1a4a3c91
- Subnet: subnet-0a36534d5f1e3ea51
- Assign public IP: yes

## Access Control
- SSH access: port 22, source [your IP]/32 only
- HTTP access: port 80, source 0.0.0.0/0
- All other inbound: deny
- All outbound: allow

## Storage
- Root volume: 8GB, type EBS

## Authentication
- SSH key pair name: main-key


## What must NOT exist on this server after provisioning
- No default password authentication
- No services listening other than sshd 
- No world-writable directories outside /tmp

## Open questions (things that will need decisions before Terraform can encode this)
- Should we enable automatic security updates via unattended-upgrades?
- Should we configure a specific firewall (ufw) rule set beyond the basic security group?

## Hardest Decision and Why

The hardest decision during manual provisioning was selecting the exact operating system image for the instance. Choosing Ubuntu 24.04 LTS was straightforward at a high level, but the real uncertainty was making sure the AMI matched the region, the instance requirements, and the security expectations without relying on guesswork in the console. That choice matters because Terraform will force the image to be encoded explicitly, so this is the point where the deployment stops being a vague manual preference and becomes a concrete infrastructure contract that must be correct and repeatable.

Also the spec required me to use ubuntu 22.04 LTS, but the AMI ID I found was for 24.04 LTS. I had to verify that this was the correct image and that it would be supported for the lifetime of the deployment.