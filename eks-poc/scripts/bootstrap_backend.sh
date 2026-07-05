#!/usr/bin/env bash
# Run this ONCE per AWS account, before the first `terraform init`.
# Creates the S3 bucket (state storage) + DynamoDB table (state locking)
# that the main Terraform config uses as its remote backend.
#
# Why a separate script (not part of the main Terraform config)?
# Chicken-and-egg problem: Terraform can't store its state IN an S3 bucket
# that Terraform itself hasn't created yet. So the backend infra is
# bootstrapped once, outside the main state, and basically never touched
# again.
#
# Usage: ./scripts/bootstrap_backend.sh

set -euo pipefail

REGION="ap-south-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET_NAME="banaras-dairy-eks-tfstate-${ACCOUNT_ID}"
DYNAMODB_TABLE="banaras-dairy-eks-tf-lock"

echo "==> Account ID: ${ACCOUNT_ID}"
echo "==> Target S3 bucket: ${BUCKET_NAME}"
echo "==> Target DynamoDB table: ${DYNAMODB_TABLE}"
echo

# --- S3 bucket for state -----------------------------------------------
if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "==> S3 bucket already exists, skipping creation."
else
  echo "==> Creating S3 bucket..."
  aws s3api create-bucket \
    --bucket "${BUCKET_NAME}" \
    --region "${REGION}" \
    --create-bucket-configuration LocationConstraint="${REGION}"

  # Versioning: lets us recover a previous state if something corrupts it.
  aws s3api put-bucket-versioning \
    --bucket "${BUCKET_NAME}" \
    --versioning-configuration Status=Enabled

  # Block all public access -- state file can contain sensitive values.
  aws s3api put-public-access-block \
    --bucket "${BUCKET_NAME}" \
    --public-access-block-configuration \
    BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

  # Default encryption at rest.
  aws s3api put-bucket-encryption \
    --bucket "${BUCKET_NAME}" \
    --server-side-encryption-configuration \
    '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'
fi

# --- DynamoDB table for state locking ------------------------------------
# PROVISIONED with 5/5 capacity (not PAY_PER_REQUEST) so this stays inside
# the DynamoDB "Always Free" tier (25 RCU / 25 WCU, forever, not just 12mo).
if aws dynamodb describe-table --table-name "${DYNAMODB_TABLE}" --region "${REGION}" >/dev/null 2>&1; then
  echo "==> DynamoDB lock table already exists, skipping creation."
else
  echo "==> Creating DynamoDB lock table..."
  aws dynamodb create-table \
    --table-name "${DYNAMODB_TABLE}" \
    --attribute-definitions AttributeName=LockID,AttributeType=S \
    --key-schema AttributeName=LockID,KeyType=HASH \
    --provisioned-throughput ReadCapacityUnits=5,WriteCapacityUnits=5 \
    --region "${REGION}"

  echo "==> Waiting for table to become ACTIVE..."
  aws dynamodb wait table-exists --table-name "${DYNAMODB_TABLE}" --region "${REGION}"
fi

# --- Write backend.hcl ----------------------------------------------------
BACKEND_FILE="$(dirname "$0")/../backend.hcl"
cat > "${BACKEND_FILE}" <<EOF
bucket         = "${BUCKET_NAME}"
key            = "eks-poc/terraform.tfstate"
region         = "${REGION}"
dynamodb_table = "${DYNAMODB_TABLE}"
encrypt        = true
EOF

echo
echo "==> Done. Wrote ${BACKEND_FILE}"
echo "==> Next: terraform init -backend-config=backend.hcl"
