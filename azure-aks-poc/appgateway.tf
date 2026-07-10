# Application Gateway (Layer 7 LB / AWS ALB equivalent) that AGIC will
# manage the runtime config of (listeners, backend pools, routing rules) as
# soon as we apply k8s/ingress.yaml against the cluster.
#
# IMPORTANT GOTCHA (the reason for the lifecycle.ignore_changes block below):
# once AGIC is live, it rewrites this Application Gateway's backend pools /
# HTTP settings / listeners / routing rules directly via the Azure API EVERY
# time an Ingress resource changes in the cluster -- Terraform never sees
# those changes. Without ignore_changes, the next `terraform plan` would see
# "drift" and try to overwrite AGIC's config back to this placeholder,
# fighting the controller and breaking the live app. We only let Terraform
# own the Gateway's existence/SKU/IP/subnet -- AGIC owns everything inside it.
# (Same class of problem as the AWS ALB Controller in eks-poc, just Azure
# lets Terraform keep owning the Gateway resource itself instead of never
# knowing about it at all.)

resource "azurerm_public_ip" "appgw" {
  name                = "banaras-appgw-pip"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name
  allocation_method   = "Static"
  sku                 = "Standard"
}

locals {
  appgw_frontend_ip_name   = "appgw-frontend-ip"
  appgw_frontend_port_name = "appgw-frontend-port"
  appgw_backend_pool_name  = "appgw-default-backend-pool"
  appgw_http_setting_name  = "appgw-default-http-setting"
  appgw_listener_name      = "appgw-default-listener"
  appgw_routing_rule_name  = "appgw-default-routing-rule"
}

resource "azurerm_application_gateway" "appgw" {
  name                = "banaras-appgw"
  location            = azurerm_resource_group.poc.location
  resource_group_name = azurerm_resource_group.poc.name

  # v2 SKU: needed for AGIC support + autoscaling capability. capacity=1 is
  # a fixed (not autoscaled) instance count -- cheapest option for a POC;
  # production would use autoscale_configuration { min_capacity, max_capacity }.
  sku {
    name     = "Standard_v2"
    tier     = "Standard_v2"
    capacity = 1
  }

  gateway_ip_configuration {
    name      = "appgw-ip-config"
    subnet_id = azurerm_subnet.appgw.id
  }

  frontend_port {
    name = local.appgw_frontend_port_name
    port = 80
  }

  frontend_ip_configuration {
    name                 = local.appgw_frontend_ip_name
    public_ip_address_id = azurerm_public_ip.appgw.id
  }

  # Placeholder pool/settings/listener/rule -- required for `terraform apply`
  # to succeed on first create (Azure won't create an empty Gateway), but
  # AGIC completely rewrites all of this the moment k8s/ingress.yaml is
  # applied. Don't hand-edit these expecting it to change live routing.
  backend_address_pool {
    name = local.appgw_backend_pool_name
  }

  backend_http_settings {
    name                  = local.appgw_http_setting_name
    cookie_based_affinity = "Disabled"
    port                  = 80
    protocol              = "Http"
    request_timeout       = 60
  }

  http_listener {
    name                           = local.appgw_listener_name
    frontend_ip_configuration_name = local.appgw_frontend_ip_name
    frontend_port_name             = local.appgw_frontend_port_name
    protocol                       = "Http"
  }

  # Priority: lower number = higher priority (same convention as the NSG
  # rule above). 100 leaves room below it for any future higher-priority
  # rule AGIC or we add later.
  request_routing_rule {
    name                       = local.appgw_routing_rule_name
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = local.appgw_listener_name
    backend_address_pool_name  = local.appgw_backend_pool_name
    backend_http_settings_name = local.appgw_http_setting_name
  }

  lifecycle {
    ignore_changes = [
      tags,
      backend_address_pool,
      backend_http_settings,
      http_listener,
      probe,
      request_routing_rule,
      url_path_map,
      frontend_port,
      redirect_configuration,
    ]
  }
}
