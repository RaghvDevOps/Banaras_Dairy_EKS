#!/usr/bin/env bash
# Run this ONCE per Azure subscription, before the first `terraform init`.
# Creates the tiny "bootstrap" Resource Group + Storage Account + Blob
# Container that the main Terraform config uses as its remote state backend.
#
# Why a separate script (not part of the main Terraform config)?
# Same chicken-and-egg problem as eks-poc: Terraform can't store its state
# IN a storage account that Terraform itself hasn't created yet. So the
# backend infra is bootstrapped once, outside the main state, and basically
# never touched again. (Azure's native state-locking, via blob lease, needs
# no separate DynamoDB-equivalent table -- one less resource than AWS.)
#
# Usage: ./scripts/bootstrap_backend.sh

set -euo pipefail

LOCATION="centralindia"
SUBSCRIPTION_ID=$(az account show --query id -o tsv)
RANDOM_SUFFIX=$(echo "${SUBSCRIPTION_ID}" | md5sum | cut -c1-8)

BOOTSTRAP_RG="banaras-tfstate-rg"
STORAGE_ACCOUNT="banarastfstate${RANDOM_SUFFIX}"
CONTAINER_NAME="tfstate"

echo "==> Subscription: ${SUBSCRIPTION_ID}"
echo "==> Target Resource Group: ${BOOTSTRAP_RG}"
echo "==> Target Storage Account: ${STORAGE_ACCOUNT}"
echo

if az group show --name "${BOOTSTRAP_RG}" >/dev/null 2>&1; then
  echo "==> Resource group already exists, skipping creation."
else
  echo "==> Creating resource group..."
  az group create --name "${BOOTSTRAP_RG}" --location "${LOCATION}" >/dev/null
fi

if az storage account show --name "${STORAGE_ACCOUNT}" --resource-group "${BOOTSTRAP_RG}" >/dev/null 2>&1; then
  echo "==> Storage account already exists, skipping creation."
else
  echo "==> Creating storage account (Standard_LRS -- cheapest redundancy, fine for a POC's state file)..."
  az storage account create \
    --name "${STORAGE_ACCOUNT}" \
    --resource-group "${BOOTSTRAP_RG}" \
    --location "${LOCATION}" \
    --sku Standard_LRS \
    --encryption-services blob \
    --min-tls-version TLS1_2 \
    --allow-blob-public-access false >/dev/null
fi

echo "==> Ensuring blob container exists..."
az storage container create \
  --name "${CONTAINER_NAME}" \
  --account-name "${STORAGE_ACCOUNT}" \
  --auth-mode login >/dev/null

BACKEND_FILE="$(dirname "$0")/../backend.hcl"
cat > "${BACKEND_FILE}" <<EOF
resource_group_name  = "${BOOTSTRAP_RG}"
storage_account_name = "${STORAGE_ACCOUNT}"
container_name       = "${CONTAINER_NAME}"
key                  = "azure-aks-poc/terraform.tfstate"
EOF

echo
echo "==> Done. Wrote ${BACKEND_FILE}"
echo "==> Next: terraform init -backend-config=backend.hcl"
