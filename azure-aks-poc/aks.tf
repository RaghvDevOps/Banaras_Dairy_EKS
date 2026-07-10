resource "azurerm_kubernetes_cluster" "aks" {
  name                = "banaras-aks"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  dns_prefix          = "banaras-aks-dns"

  # Free tier (no SLA) -- fine for a POC, real production uses "Standard".
  sku_tier = "Free"

  default_node_pool {
    name                 = "agentpool"
    vm_size              = "Standard_D2ads_v5" # B-series wasn't available in this region/subscription's quota
    vnet_subnet_id       = azurerm_subnet.aks.id
    auto_scaling_enabled = true
    min_count            = 1
    max_count            = 2
    os_disk_size_gb      = 128
    max_pods             = 110
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.aks.id]
  }

  # Azure CNI (NOT kubenet): every pod gets a real, routable IP from the
  # VNet's own address space -- this is the whole point of the networking
  # lesson. network_data_plane "azure" + network_policy "calico" is what the
  # Portal wizard picked for us when Azure CNI + a network policy engine
  # were both selected.
  network_profile {
    network_plugin     = "azure"
    network_data_plane = "azure"
    network_policy     = "calico"
    load_balancer_sku  = "standard"
  }

  # Workload Identity + OIDC issuer: lets pod ServiceAccounts federate with
  # Azure AD Managed Identities (see identity.tf) instead of static keys.
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # Secrets Store CSI Driver addon -- mounts Key Vault secrets into pods as
  # files/env, backing the SecretProviderClass in k8s/secretproviderclass.yaml.
  key_vault_secrets_provider {
    secret_rotation_enabled = false
  }

  azure_policy_enabled = true

  # AGIC (Application Gateway Ingress Controller) addon, wired to the App
  # Gateway we manage in appgateway.tf. This is the Terraform equivalent of
  # `az aks enable-addons -a ingress-appgw --appgw-id ...` we ran by hand.
  ingress_application_gateway {
    gateway_id = azurerm_application_gateway.appgw.id
  }

  depends_on = [
    azurerm_role_assignment.aks_identity_network_contributor,
  ]
}
