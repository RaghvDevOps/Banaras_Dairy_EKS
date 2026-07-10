terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    # Used purely to insert a short pause after granting ourselves Key Vault
    # RBAC, before writing secrets -- see keyvault.tf for why.
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
  required_version = ">= 1.0.0"

  # Partial backend config on purpose: the storage account name is globally
  # unique and subscription-specific, so it lives in a gitignored backend.hcl
  # (see backend.hcl.example) instead of being hardcoded here. Run:
  #   terraform init -backend-config=backend.hcl
  backend "azurerm" {}
}

provider "azurerm" {
  features {
    key_vault {
      # POC convenience: lets `terraform destroy` actually delete the vault
      # instead of leaving a soft-deleted placeholder that would otherwise
      # need a manual `az keyvault purge` before it can be recreated with
      # the same name. NEVER do this on a real production vault.
      purge_soft_delete_on_destroy               = true
      purge_soft_deleted_certificates_on_destroy = true
      purge_soft_deleted_keys_on_destroy         = true
      purge_soft_deleted_secrets_on_destroy      = true
    }
    resource_group {
      # We import/destroy this RG ourselves outside Terraform's own safety
      # net sometimes (see the sibling azure-teardown/ experiment) -- this
      # just means "don't block destroy just because it still has resources
      # Terraform doesn't know about."
      prevent_deletion_if_contains_resources = false
    }
  }
  subscription_id = var.subscription_id

  # This POC subscription doesn't have permission to auto-register EVERY
  # Resource Provider the azurerm provider knows about (e.g. Microsoft.Devices
  # for IoT Hub, which we never use) -- that caused `terraform import` to
  # time out earlier. We register only what we actually need, manually, via
  # `az provider register --namespace <ns>`.
  resource_provider_registrations = "none"
}

# Gives us the currently logged-in user/service-principal's object ID, so we
# can grant OURSELVES "Key Vault Secrets Officer" via Terraform instead of
# doing it by hand in the Portal like we did the first time around.
data "azurerm_client_config" "current" {}
