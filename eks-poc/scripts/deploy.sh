#!/usr/bin/env bash
# One-command deploy: infra (Terraform) + secrets (SSM -> k8s Secret) +
# app (k8s manifests) + Ingress (ALB). Safe to re-run daily -- every step
# is idempotent.
#
# Prereqs (one-time, per machine): AWS CLI configured, kubectl, helm,
# terraform installed. Backend already bootstrapped (scripts/bootstrap_backend.sh)
# and secrets.auto.tfvars filled in (see secrets.auto.tfvars.example).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${ROOT_DIR}"

echo "=== 1/6: terraform init + apply ==="
terraform init -backend-config=backend.hcl -input=false
terraform apply -auto-approve

CLUSTER_NAME=$(terraform output -raw cluster_name)
REGION=$(terraform output -raw region)
VPC_ID=$(terraform output -raw vpc_id)
DB_USER=$(terraform output -raw db_user)
DB_NAME=$(terraform output -raw db_name)
RECOVERY_DB=$(terraform output -raw recovery_db_name)
SSM_DB_PASSWORD_PATH=$(terraform output -raw ssm_db_password_path)
SSM_GHCR_USER_PATH=$(terraform output -raw ssm_ghcr_username_path)
SSM_GHCR_TOKEN_PATH=$(terraform output -raw ssm_ghcr_token_path)

echo "=== 2/6: point kubectl at the cluster ==="
aws eks update-kubeconfig --name "${CLUSTER_NAME}" --region "${REGION}"

echo "=== 3/6: fetch secrets from SSM Parameter Store ==="
DB_PASSWORD=$(aws ssm get-parameter --name "${SSM_DB_PASSWORD_PATH}" --with-decryption --region "${REGION}" --query "Parameter.Value" --output text)
GHCR_USER=$(aws ssm get-parameter --name "${SSM_GHCR_USER_PATH}" --with-decryption --region "${REGION}" --query "Parameter.Value" --output text)
GHCR_TOKEN=$(aws ssm get-parameter --name "${SSM_GHCR_TOKEN_PATH}" --with-decryption --region "${REGION}" --query "Parameter.Value" --output text)

DATABASE_URL="postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@postgres:5432/${DB_NAME}"
RECOVERY_DATABASE_URL="postgresql+asyncpg://${DB_USER}:${DB_PASSWORD}@postgres:5432/${RECOVERY_DB}"

echo "=== 4/6: create/update Kubernetes secrets (idempotent) ==="
kubectl create secret generic db-credentials \
  --from-literal=POSTGRES_USER="${DB_USER}" \
  --from-literal=POSTGRES_PASSWORD="${DB_PASSWORD}" \
  --from-literal=POSTGRES_DB="${DB_NAME}" \
  --from-literal=RECOVERY_DB="${RECOVERY_DB}" \
  --from-literal=DATABASE_URL="${DATABASE_URL}" \
  --from-literal=RECOVERY_DATABASE_URL="${RECOVERY_DATABASE_URL}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret docker-registry ghcr-secret \
  --docker-server=ghcr.io \
  --docker-username="${GHCR_USER}" \
  --docker-password="${GHCR_TOKEN}" \
  --docker-email="${GHCR_USER}@users.noreply.github.com" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "=== 5/6: deploy the app ==="
kubectl apply -f k8s/postgres.yaml
kubectl apply -f k8s/backend.yaml
kubectl apply -f k8s/frontend.yaml

echo "=== 6/6: AWS Load Balancer Controller + Ingress (ALB) ==="
helm repo add eks https://aws.github.io/eks-charts >/dev/null 2>&1 || true
helm repo update >/dev/null

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName="${CLUSTER_NAME}" \
  --set region="${REGION}" \
  --set vpcId="${VPC_ID}" \
  --set serviceAccount.create=true \
  --set serviceAccount.name=aws-load-balancer-controller \
  --wait

kubectl apply -f k8s/ingress.yaml

echo
echo "==> Waiting for ALB address (this takes ~2-3 min on first create)..."
for i in $(seq 1 40); do
  ADDR=$(kubectl get ingress banaras-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || true)
  if [ -n "${ADDR}" ]; then
    echo
    echo "=================================================="
    echo " App URL: http://${ADDR}"
    echo " Default admin: admin / Admin@123"
    echo "=================================================="
    exit 0
  fi
  sleep 5
done

echo "ALB address not ready yet after ~3 min. Check manually: kubectl get ingress banaras-ingress"
