#!/bin/bash
# Runs automatically on first boot (via Azure VM custom_data -> cloud-init).
# Installs everything needed to run this repo's Terraform + deploy scripts
# from inside the VM: az cli, terraform, kubectl, git, helm.
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get install -y ca-certificates curl apt-transport-https lsb-release gnupg unzip git jq

# Azure CLI (official Microsoft repo)
curl -sL https://aka.ms/InstallAzureCLIDeb | bash

# Terraform (official HashiCorp repo)
curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update -y
apt-get install -y terraform

# kubectl (official Kubernetes repo)
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor -o /usr/share/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /" \
  | tee /etc/apt/sources.list.d/kubernetes.list
apt-get update -y
apt-get install -y kubectl

# Helm (official install script)
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

echo "==> Jumpbox provisioning complete." > /var/log/jumpbox-cloud-init-done.log
