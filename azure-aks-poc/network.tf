# Mirrors what we clicked through in the Portal: one VNet, three purpose-
# built subnets (AKS nodes/pods, Application Gateway, Private Endpoints),
# and one NSG on the AKS subnet as a deliberate defense-in-depth example.

resource "azurerm_resource_group" "poc" {
  name     = var.resource_group_name
  location = var.location
}

resource "azurerm_virtual_network" "vnet" {
  name                = "banaras-vnet"
  address_space       = ["10.1.0.0/16"]
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
}

resource "azurerm_subnet" "aks" {
  name                 = "aks-subnet"
  resource_group_name  = azurerm_resource_group.poc.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.1.0/24"]
}

# Application Gateway requires its OWN dedicated, otherwise-empty subnet --
# it can't share a subnet with AKS nodes or anything else.
resource "azurerm_subnet" "appgw" {
  name                 = "appgw-subnet"
  resource_group_name  = azurerm_resource_group.poc.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.2.0/24"]
}

# Reserved for the Private Endpoint demo (Storage Account -> privatelink.blob).
# Not wired to a resource by default in this package -- see docs/README.md
# "Optional: Private Endpoint demo" for the extra block to add.
resource "azurerm_subnet" "endpoints" {
  name                 = "endpoints-subnet"
  resource_group_name  = azurerm_resource_group.poc.name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.1.3.0/24"]
}

resource "azurerm_network_security_group" "aks_subnet_nsg" {
  name                = "aks-subnet-nsg"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name

  # Defense-in-depth: AKS nodes aren't SSH-exposed by default anyway (no
  # public IP on the nodes, Standard LB only forwards ports we open), but an
  # explicit deny is cheap insurance and a good interview talking point.
  # Lower number = higher priority, same idea as Application Gateway routing
  # rule priorities -- left room below it (100) for future higher-priority
  # rules if ever needed.
  security_rule {
    name                       = "Deny-SSH-Internet"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "22"
    source_address_prefix      = "Internet"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "aks_subnet_nsg" {
  subnet_id                 = azurerm_subnet.aks.id
  network_security_group_id = azurerm_network_security_group.aks_subnet_nsg.id
}
