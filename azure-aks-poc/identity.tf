# Two SEPARATE user-assigned identities, on purpose -- same split we did by
# hand: one is the AKS control plane's own "badge" to talk to the VNet, the
# other is OUR pod's badge to talk to Key Vault. Never reuse one identity
# for both -- that would give every pod in the cluster the AKS control
# plane's network permissions too (over-privileged, fails least-privilege).

resource "azurerm_user_assigned_identity" "aks" {
  name                = "banaras-aks-identity"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
}

# AKS needs this BEFORE cluster creation: with Azure CNI, the cluster has to
# plug node/pod NICs directly into our VNet's subnet, which requires Network
# Contributor on the VNet (or at least the subnet). Without it, cluster
# creation fails trying to join aks-subnet.
resource "azurerm_role_assignment" "aks_identity_network_contributor" {
  scope                = azurerm_virtual_network.vnet.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.aks.principal_id
}

# The backend pod's own identity -- federated (via OIDC) to the
# `banaras-backend-sa` Kubernetes ServiceAccount so it can fetch DB creds
# from Key Vault without any static key ever existing.
resource "azurerm_user_assigned_identity" "backend" {
  name                = "banaras-backend-identity"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
}

# The actual OIDC trust record: "trust tokens issued by THIS AKS cluster's
# issuer, specifically for ServiceAccount banaras-backend-sa in namespace
# default." This is a config record, not a secret -- nothing to rotate here.
resource "azurerm_federated_identity_credential" "backend" {
  name                = "banaras-backend-fed-cred"
  resource_group_name = azurerm_resource_group.poc.name
  parent_id           = azurerm_user_assigned_identity.backend.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.aks.oidc_issuer_url
  subject             = "system:serviceaccount:default:banaras-backend-sa"
}
