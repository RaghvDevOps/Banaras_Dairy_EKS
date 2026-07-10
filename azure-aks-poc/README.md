# Banaras Dairy on AKS -- Terraform POC

The Terraform-managed rebuild of the exact Azure POC we built by hand in the Portal on
2026-07-08 (see `React-Application-Dex/Resume_GenAI_Devops/Azure_DevOps_AIFoundry_Interview_Prep/`
for the GUI lab notes and Q&A log this is based on). Mirrors the structure and philosophy of the
sibling `../eks-poc/` (AWS) project so the two can be compared file-by-file.

## What this creates

| Layer | Resource | AWS equivalent (see `eks-poc/`) |
|---|---|---|
| Network | VNet `banaras-vnet` (10.1.0.0/16) + 3 subnets (aks/appgw/endpoints) | VPC + public/private subnets |
| Network | NSG on `aks-subnet` (deny SSH inbound) | Security Group |
| Compute | AKS cluster, Azure CNI, autoscaling 1-2 nodes | EKS cluster, managed node group |
| Identity | 2x User-Assigned Managed Identity + Workload Identity/OIDC federation | IRSA (IAM Roles for Service Accounts) |
| Secrets | Key Vault (db creds + GHCR creds) + Secrets Store CSI Driver | SSM Parameter Store, pulled by `deploy.sh` |
| Ingress | Application Gateway + AGIC addon | AWS Load Balancer Controller + ALB |

## Prerequisites

- Azure CLI, logged in: `az login`
- terraform >= 1.0, kubectl
- `Microsoft.KeyVault` and `Microsoft.ContainerService` resource providers registered on the
  subscription (one-time): `az provider register --namespace Microsoft.KeyVault`

## First-time setup

```bash
cd azure-aks-poc
./scripts/bootstrap_backend.sh          # creates the remote state storage account (once)
cp secrets.auto.tfvars.example secrets.auto.tfvars   # fill in real db/GHCR values
./scripts/deploy.sh                     # terraform apply + full app deploy in one shot
```

## Cleanup

```bash
./scripts/teardown.sh
```

## Gotchas learned the hard way (from the manual GUI pass) that this codifies

1. **Resource Provider registration timeouts.** The `azurerm` provider tries to auto-register
   every RP it supports on init; our POC subscription doesn't have permission for all of them
   (e.g. `Microsoft.Devices`), which hung `terraform import` for real. Fixed via
   `resource_provider_registrations = "none"` in `provider.tf` -- we register what we need
   ourselves via `az provider register`.
2. **Key Vault RBAC propagation delay.** `az keyvault secret set` failed with `Forbidden` even
   right after the Portal showed the role assigned. Codified as a 30s `time_sleep` between the
   role assignment and the first secret write in `keyvault.tf`.
3. **Key Vault soft-delete blocks name reuse.** A destroyed vault reserves its name for up to 90
   days unless purged. `provider.tf`'s `purge_soft_delete_on_destroy = true` auto-purges on
   `terraform destroy` so this package can be destroyed/recreated freely during learning.
4. **AGIC "owns" the live Application Gateway config.** Once `k8s/ingress.yaml` is applied, AGIC
   rewrites the Gateway's listeners/backend pools/rules directly via the Azure API -- Terraform
   never sees those changes. `appgateway.tf` uses `lifecycle.ignore_changes` on exactly those
   blocks so `terraform plan` doesn't fight AGIC on every run (see comment there for the full
   explanation).
5. **AKS needs Network Contributor on the VNet *before* cluster creation**, not after -- Azure
   CNI plugs node/pod NICs directly into the subnet at creation time. `aks.tf` has an explicit
   `depends_on` for this.

## Cost notes (Pay-As-You-Go, not free trial)

- AKS control plane: free (Free tier SKU). You only pay for the underlying VMs (`Standard_D2ads_v5`
  x1-2, autoscaled), their disks, and the Standard Load Balancer.
- Application Gateway (Standard_v2, capacity 1): billed hourly + per-GB processed, roughly
  the single biggest line item in this POC -- **the #1 resource to destroy promptly after
  demoing**, unlike a plain `LoadBalancer` Service which is far cheaper.
- Key Vault: free at this transaction volume (10k free operations/month).
- Managed Identities: free.
- NSG, VNet, subnets: free (VNet/subnet/NSG are pure networking config, never billed directly).

## Optional: Private Endpoint demo (not wired up here)

To reproduce the Private Endpoint + Private DNS pattern from the GUI lab (the strongest
interview artifact for the JD's "hybrid connectivity for AI workloads" requirement), add a
`azurerm_storage_account` with `public_network_access_enabled = false` plus an
`azurerm_private_endpoint` targeting `endpoints-subnet` and sub-resource `blob`, with
`private_dns_zone_group` auto-linking `privatelink.blob.core.windows.net`. Left out of the base
package so the core AKS-in-VNet lesson stays the focus; add it as a follow-up exercise.
