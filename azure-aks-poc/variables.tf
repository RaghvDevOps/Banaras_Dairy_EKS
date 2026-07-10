# Non-secret knobs. Secrets are NEVER hardcoded here -- see secrets.tf /
# secrets.auto.tfvars.example for how those are supplied.

variable "subscription_id" {
  description = "Azure subscription to deploy into (the free POC subscription)."
  type        = string
  default     = "ed298f6c-43d7-4057-89f3-d1cbdde27e30"
}

variable "location" {
  description = "Azure region for all resources."
  type        = string
  default     = "centralindia"
}

variable "resource_group_name" {
  description = "Name of the resource group holding the whole POC."
  type        = string
  default     = "banaras-azure-poc"
}

variable "key_vault_name" {
  description = <<-EOT
    Key Vault names are globally unique across ALL of Azure, AND a deleted
    vault stays "soft-deleted" and reserves its name for up to 90 days
    (unless purged). If you destroy-and-recreate this stack often, either
    bump this to a new suffix or run:
      az keyvault purge --name <old-name> --location centralindia
    before re-applying with the same name.
  EOT
  type        = string
  default     = "banaras-kv-rvs2"
}

variable "ghcr_username" {
  description = "GitHub username used to pull private images from GHCR."
  type        = string
  sensitive   = true
}

variable "ghcr_token" {
  description = "GitHub Personal Access Token (read:packages scope) for pulling private GHCR images."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Password for the self-hosted Postgres app user (banaras_admin). POC-grade -- rotate before any real use."
  type        = string
  sensitive   = true
}

# db_user / db_name / recovery_db_name are deliberately NOT variables here --
# they're non-secret constants, defined once as locals in outputs.tf so
# scripts/deploy.sh (and this config) share a single source of truth,
# exactly like eks-poc does with its own outputs.tf.

variable "allowed_ssh_source_ip" {
  description = <<-EOT
    Your current public IP in CIDR form (e.g. "49.36.XX.XX/32"), used to lock
    down SSH to the jumpbox VM to ONLY you. Find yours with:
      curl ifconfig.me
    then append "/32". No default on purpose -- forces you to set this
    explicitly in secrets.auto.tfvars rather than accidentally leaving SSH
    open to the whole internet.
  EOT
  type        = string
}

variable "vm_ssh_public_key" {
  description = <<-EOT
    Your SSH PUBLIC key contents (not the private key!), used as the
    jumpbox VM's login credential (password auth is disabled). Get yours
    with (PowerShell/bash):
      cat ~/.ssh/id_rsa.pub
    or generate a new pair first with: ssh-keygen -t rsa -b 4096
  EOT
  type        = string
}
