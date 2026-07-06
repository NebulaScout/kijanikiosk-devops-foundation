#!/bin/bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TERRAFORM_DIR="$ROOT_DIR/terraform"
ANSIBLE_DIR="$ROOT_DIR/ansible"
INVENTORY_FILE="$ANSIBLE_DIR/inventory.ini"

cleanup() {
    rm -f "$ROOT_DIR/.pipeline_inventory.tmp" "$ROOT_DIR/.pipeline_outputs.json"
}

trap cleanup EXIT

echo "Terraform Apply"

cd "$TERRAFORM_DIR"

terraform init

terraform plan -out=tfplan

terraform apply -auto-approve tfplan

API_IP=$(terraform output -raw api_server_ip)
PAYMENTS_IP=$(terraform output -raw payments_server_ip)
LOGS_IP=$(terraform output -raw logs_server_ip)

echo "Generating Inventory"

cd "$ANSIBLE_DIR"

cat > inventory.ini << EOF
[kijanikiosk]
api-staging ansible_host=${API_IP}
payments-staging ansible_host=${PAYMENTS_IP}
logs-staging ansible_host=${LOGS_IP}

[kijanikiosk:vars]
ansible_user=ubuntu
ansible_ssh_private_key_file=~/.ssh/main-key.pem
ansible_python_interpreter=/usr/bin/python3
EOF

echo "Running Ansible"
cd "$ANSIBLE_DIR"

ansible-playbook -i inventory.ini kijanikiosk.yml

echo "Pipeline Complete"
