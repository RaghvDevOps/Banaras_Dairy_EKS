# Non-secret DB constants -- single source of truth, so scripts/deploy.sh
# doesn't hardcode these separately from what postgres.yaml expects. Same
# pattern as eks-poc/outputs.tf.
locals {
  db_user          = "banaras_admin"
  db_name          = "banaras_dairy"
  recovery_db_name = "banaras_dairy_recovery"
}

output "resource_group_name" {
  value = azurerm_resource_group.poc.name
}

output "cluster_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "location" {
  value = azurerm_resource_group.poc.location
}

output "vnet_id" {
  value = azurerm_virtual_network.vnet.id
}

output "oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.aks.oidc_issuer_url
}

output "backend_identity_client_id" {
  description = "Goes into the ServiceAccount's azure.workload.identity/client-id annotation."
  value       = azurerm_user_assigned_identity.backend.client_id
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "app_gateway_public_ip" {
  value = azurerm_public_ip.appgw.ip_address
}

output "jumpbox_public_ip" {
  value = azurerm_public_ip.jumpbox.ip_address
}

output "jumpbox_ssh_command" {
  value = "ssh azureuser@${azurerm_public_ip.jumpbox.ip_address}"
}

output "db_user" {
  value = local.db_user
}

output "db_name" {
  value = local.db_name
}

output "recovery_db_name" {
  value = local.recovery_db_name
}
