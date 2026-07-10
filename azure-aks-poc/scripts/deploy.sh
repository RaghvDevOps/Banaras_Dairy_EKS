#!/usr/bin/env bash
# One-command deploy: infra (Terraform) + secrets (Key Vault -> k8s Secret /
# CSI mount) + app (k8s manifests) + Ingress (AGIC / Application Gateway).
# Safe to re-run daily -- every step is idempotent.
#
# Prereqs (one-time, per machine): Azure CLI configured (`az login`),
# kubectl, terraform installed. Backend already bootstrapped
# (scripts/bootstrap_backend.sh) and secrets.auto.tfvars filled in (see
# secrets.auto.tfvars.example).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${ROOT_DIR}"

echo "=== 1/7: terraform init + apply ==="
terraform init -backend-config=backend.hcl -input=false
terraform apply -auto-approve

RESOURCE_GROUP=$(terraform output -raw resource_group_name)
CLUSTER_NAME=$(terraform output -raw cluster_name)
KEY_VAULT_NAME=$(terraform output -raw key_vault_name)
TENANT_ID=$(terraform output -raw tenant_id)
BACKEND_CLIENT_ID=$(terraform output -raw backend_identity_client_id)

echo "=== 2/7: point kubectl at the cluster ==="
az aks get-credentials --resource-group "${RESOURCE_GROUP}" --name "${CLUSTER_NAME}" --overwrite-existing

echo "=== 3/7: render + apply the Workload Identity ServiceAccount + SecretProviderClass ==="
sed "s|__BACKEND_CLIENT_ID__|${BACKEND_CLIENT_ID}|g" k8s/serviceaccount.yaml.tpl | kubectl apply -f -
sed -e "s|__BACKEND_CLIENT_ID__|${BACKEND_CLIENT_ID}|g" \
    -e "s|__KEY_VAULT_NAME__|${KEY_VAULT_NAME}|g" \
    -e "s|__TENANT_ID__|${TENANT_ID}|g" \
    k8s/secretproviderclass.yaml.tpl | kubectl apply -f -

echo "=== 4/7: fetch GHCR creds from Key Vault, create the image pull secret ==="
GHCR_USER=$(az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name ghcr-username --query value -o tsv)
GHCR_TOKEN=$(az keyvault secret show --vault-name "${KEY_VAULT_NAME}" --name ghcr-token --query value -o tsv)

kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USER}" \
  --docker-password="${GHCR_TOKEN}" \
  --docker-email="${GHCR_USER}@users.noreply.github.com" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== 5/7: deploy the app ==="
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/backend.yaml
kubectl apply -f k8s/frontend.yaml

echo "=== 6/7: wait for db-credentials Secret to materialize from the CSI mount ==="
# The Secret only gets created once a pod actually mounts the CSI volume --
# it doesn't exist just because the SecretProviderClass was applied. Backend
# pods above will be stuck until this shows up (usually <30s).
for i in $(seq 1 20); do
  if kubectl get secret db-credentials >/dev/null 2>&1; then
    echo "==> db-credentials Secret is present."
    break
  fi
  sleep 3
done

echo "=== 7/7: Ingress (Application Gateway via AGIC) ==="
kubectl apply -f k8s/ingress.yaml

echo
echo "==> Waiting for Application Gateway address (this takes ~2-3 min on first create)..."
APPGW_IP=$(terraform output -raw app_gateway_public_ip)
for i in $(seq 1 40); do
  ADDR=$(kubectl get ingress banaras-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || true)
  if [ -n "${ADDR}" ]; then
    echo
    echo "=================================================="
    echo " App URL: http://${ADDR}"
    echo " (Same as static Application Gateway IP: ${APPGW_IP})"
    echo " Default admin: admin / Admin@123"
    echo "=================================================="
    exit 0
  fi
  sleep 5
done

echo "Ingress address not ready yet after ~3 min. Check manually: kubectl get ingress banaras-ingress"
echo "Application Gateway static IP (should match once ready): ${APPGW_IP}"
