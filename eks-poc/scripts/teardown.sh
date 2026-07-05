#!/usr/bin/env bash
# Safely tears everything down, in the RIGHT order.
#
# WHY ORDER MATTERS: the ALB, its target groups, and its security group are
# created by the AWS Load Balancer Controller (via the Kubernetes Ingress
# object) -- Terraform has NEVER heard of them, they're not in its state.
# If we run `terraform destroy` first, Terraform tries to delete the VPC's
# subnets/security-groups, but the ALB's network interfaces (ENIs) are still
# attached to them -> AWS blocks it with a DependencyViolation error, and
# you're left with an orphaned ALB silently costing money.
#
# So: delete the Ingress FIRST, wait for the real AWS ALB to actually
# disappear, THEN run terraform destroy.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${ROOT_DIR}"

REGION=$(terraform output -raw region 2>/dev/null || echo "ap-south-1")
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")

if [ -n "${CLUSTER_NAME}" ] && kubectl get ingress banaras-ingress >/dev/null 2>&1; then
  echo "=== 1/3: deleting Ingress (triggers ALB Controller to delete the real ALB) ==="
  kubectl delete ingress banaras-ingress --ignore-not-found

  echo "==> Waiting for the ALB + its security group to actually disappear..."
  for i in $(seq 1 30); do
    REMAINING=$(aws resourcegroupstaggingapi get-resources \
      --region "${REGION}" \
      --tag-filters "Key=elbv2.k8s.aws/cluster,Values=${CLUSTER_NAME}" \
      --query "ResourceTagMappingList[].ResourceARN" --output text 2>/dev/null || true)
    if [ -z "${REMAINING}" ]; then
      echo "==> Confirmed: no AWS resources tagged for this cluster remain."
      break
    fi
    echo "  still cleaning up (attempt $i/30): ${REMAINING}"
    sleep 10
  done
else
  echo "=== 1/3: no Ingress found, skipping (already deleted or cluster never came up) ==="
fi

echo "=== 2/3: uninstalling ALB Controller helm release ==="
helm uninstall aws-load-balancer-controller -n kube-system 2>/dev/null || true

echo "=== 3/3: terraform destroy ==="
terraform destroy -auto-approve

echo
echo "==> Teardown complete. Note: SSM parameters ARE deleted too (they're"
echo "    part of the same Terraform state). That's fine -- the real values"
echo "    still live in your local secrets.auto.tfvars, so the next"
echo "    deploy.sh run just recreates them with the same values."
