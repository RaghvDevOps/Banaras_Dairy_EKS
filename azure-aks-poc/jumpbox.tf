# A small Ubuntu VM living INSIDE banaras-vnet's own jumpbox-subnet -- the
# real hybrid-connectivity pattern: instead of running Terraform/kubectl
# from your laptop (over the public internet, hitting AKS's public API
# endpoint), you SSH into a machine that's already inside the private
# network and run everything from there. Same idea as a bastion host in
# AWS, or an on-prem management server with a VPN into the VNet.

resource "azurerm_public_ip" "jumpbox" {
  name                = "banaras-jumpbox-pip"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

resource "azurerm_network_interface" "jumpbox" {
  name                = "banaras-jumpbox-nic"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name

  ip_configuration {
    name                          = "internal"
    subnet_id                     = azurerm_subnet.jumpbox.id
    private_ip_address_allocation = "Dynamic"
    public_ip_address_id          = azurerm_public_ip.jumpbox.id
  }
}

resource "azurerm_linux_virtual_machine" "jumpbox" {
  name                = "banaras-jumpbox"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  # B2s: 2 vCPU / 4GB RAM -- enough headroom to run terraform + az cli +
  # kubectl comfortably. B1s (1 vCPU/1GB) technically works but feels slow.
  # STOP (deallocate) this VM whenever you're not actively using it --
  # compute is billed per-hour while running, storage/networking keep
  # billing even when stopped. `az vm deallocate` or Portal "Stop" button.
  size = "Standard_B2s"

  admin_username                  = "azureuser"
  disable_password_authentication = true
  network_interface_ids           = [azurerm_network_interface.jumpbox.id]

  admin_ssh_key {
    username   = "azureuser"
    public_key = var.vm_ssh_public_key
  }

  os_disk {
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS" # cheapest redundancy -- fine, this VM holds no irreplaceable data
  }

  source_image_reference {
    publisher = "Canonical"
    offer     = "0001-com-ubuntu-server-jammy"
    sku       = "22_04-lts-gen2"
    version   = "latest"
  }

  # Installs az cli, terraform, kubectl, helm on first boot -- see
  # scripts/jumpbox-cloud-init.sh for exactly what runs.
  custom_data = filebase64("${path.module}/scripts/jumpbox-cloud-init.sh")

  # Own Managed Identity -- same concept as the AKS/backend identities in
  # identity.tf, just for a VM instead of a pod. Once this exists, you never
  # type `az login` with a username/password on this box: `az login
  # --identity` picks up the identity automatically.
  identity {
    type = "SystemAssigned"
  }
}

# Owner (not just Contributor) because this VM will run Terraform commands
# that themselves create `azurerm_role_assignment` resources (see
# identity.tf / keyvault.tf) -- that specific permission
# (Microsoft.Authorization/roleAssignments/write) isn't included in
# Contributor. Scoped to just this Resource Group, not the whole
# subscription -- least privilege given what we actually need it to do.
# A tighter alternative for production: Contributor + "User Access
# Administrator" combined, instead of a blanket Owner.
resource "azurerm_role_assignment" "jumpbox_identity_owner" {
  scope                = azurerm_resource_group.poc.id
  role_definition_name = "Owner"
  principal_id         = azurerm_linux_virtual_machine.jumpbox.identity[0].principal_id
}
