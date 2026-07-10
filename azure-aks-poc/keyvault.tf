resource "azurerm_key_vault" "kv" {
  name                = var.key_vault_name
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  sku_name            = "standard"

  # RBAC (not the legacy access-policy model) -- so "who can read/write
  # secrets" is governed by normal Azure role assignments below, same as
  # every other resource in this file.
  rbac_authorization_enabled = true

  # 7 days = the Azure MINIMUM (can't go lower). Kept short deliberately so
  # that if this POC gets destroyed/recreated often, the soft-delete window
  # blocking name reuse (see variables.tf note on key_vault_name) is as
  # short as legally possible. Real production would use 90 days +
  # purge_protection_enabled = true.
  soft_delete_retention_days = 7
  purge_protection_enabled   = false
}

# Grants OURSELVES (the identity running `terraform apply`) permission to
# write secrets -- this is the exact "Forbidden / ForbiddenByRbac" step we
# had to do by hand in the Portal the first time, now codified.
resource "azurerm_role_assignment" "self_kv_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

# RBAC role assignments in Azure AD take a little while to actually
# propagate to the data plane -- this is precisely the delay that caused
# our manual `az keyvault secret set` to fail with Forbidden even though the
# Portal already showed the role assigned. A short sleep here avoids the
# exact same race condition in an automated `terraform apply`.
resource "time_sleep" "wait_for_kv_rbac" {
  depends_on      = [azurerm_role_assignment.self_kv_secrets_officer]
  create_duration = "30s"
}

resource "azurerm_key_vault_secret" "db_password" {
  name         = "db-password"
  value        = var.db_password
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}

resource "azurerm_key_vault_secret" "postgres_user" {
  name         = "postgres-user"
  value        = local.db_user
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}

resource "azurerm_key_vault_secret" "postgres_db" {
  name         = "postgres-db"
  value        = local.db_name
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}

resource "azurerm_key_vault_secret" "recovery_db" {
  name         = "recovery-db"
  value        = local.recovery_db_name
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}

# GHCR credentials also live in Key Vault (not typed raw into kubectl like
# our first manual pass) -- deploy.sh reads these back at deploy time, same
# pattern as eks-poc's SSM Parameter Store pull.
resource "azurerm_key_vault_secret" "ghcr_username" {
  name         = "ghcr-username"
  value        = var.ghcr_username
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}

resource "azurerm_key_vault_secret" "ghcr_token" {
  name         = "ghcr-token"
  value        = var.ghcr_token
  key_vault_id = azurerm_key_vault.kv.id
  depends_on   = [time_sleep.wait_for_kv_rbac]
}

# The backend pod's Workload Identity gets READ-ONLY access to secrets --
# it should never be able to write/delete, only fetch what it needs.
resource "azurerm_role_assignment" "backend_kv_secrets_user" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.backend.principal_id
}
