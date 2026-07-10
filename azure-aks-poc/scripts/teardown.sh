#!/usr/bin/env bash
# Safely tears everything down.
#
# WHY DELETE THE INGRESS FIRST: AGIC actively owns the Application Gateway's
# runtime config (backend pools, listeners, routing rules) once an Ingress
# exists -- Terraform only owns the Gateway resource's shell (see the
# lifecycle.ignore_changes note in appgateway.tf). `terraform destroy` WILL
# still successfully delete the Gateway resource itself either way (unlike
# eks-poc's unmanaged ALB), but removing the Ingress first lets AGIC clean up
# its own config gracefully instead of us yanking the Gateway out from under
# a live routing rule. Cheap insurance, same spirit as eks-poc/teardown.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "${SCRIPT_DIR}")"
cd "${ROOT_DIR}"

RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "")
CLUSTER_NAME=$(terraform output -raw cluster_name 2>/dev/null || echo "")

if [ -n "${CLUSTER_NAME}" ] && kubectl get ingress banaras-ingress >/dev/null 2>&1; then
  echo "=== 1/2: deleting Ingress (lets AGIC clean up its routing config first) ==="
  kubectl delete ingress banaras-ingress --ignore-not-found
  sleep 10
else
  echo "=== 1/2: no Ingress found, skipping (already deleted or cluster never came up) ==="
fi

echo "=== 2/2: terraform destroy ==="
terraform destroy -auto-approve

echo
echo "==> Teardown complete."
echo "==> NOTE: Key Vault soft-delete is auto-purged on destroy (see provider.tf"
echo "    'purge_soft_delete_on_destroy') so the same key_vault_name can be reused"
echo "    immediately on the next 'terraform apply' -- no manual 'az keyvault purge'"
echo "    needed, unlike our first manual GUI pass."
echo "==> The tfstate bootstrap Resource Group (banaras-tfstate-rg) is NOT deleted --"
echo "    it's outside this Terraform state on purpose. Delete manually if you're"
echo "    fully done: az group delete --name banaras-tfstate-rg --yes --no-wait"
