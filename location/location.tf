variable "resource_prefix" {}
variable "web_server_address_space" {}
# variable "web_server_address_prefix" {}
variable "web_server_name" {}
variable "environment" {}
variable "web_server_count" {}
variable "web_server_subnets" {
  type = list(string)
}
variable "terraform_script_version" {}
variable "domain_name_label" {}


variable "web_server_location" {}
variable "web_server_rg" {}

locals {
  web_server_name   = var.environment == "production" ? "${var.web_server_name}-prod" : "${var.web_server_name}-dev"
  build_environment = var.environment == "production" ? "production" : "development"
}

resource "azurerm_resource_group" "web_server_rg" {
  name     = var.web_server_rg
  location = var.web_server_location

  tags = {
    environment   = local.build_environment
    build-version = var.terraform_script_version
  }
}

resource "azurerm_virtual_network" "web_server_vnet" {
  name                = "${var.resource_prefix}-vnet"
  location            = var.web_server_location
  resource_group_name = azurerm_resource_group.web_server_rg.name
  address_space       = [var.web_server_address_space] 
}

resource "azurerm_subnet" "web_server_subnet" {
  name                 = "${var.resource_prefix}-${substr(var.web_server_subnets[count.index], 0, length(var.web_server_subnets[count.index]) - 3 )}-subnet"
  resource_group_name  = azurerm_resource_group.web_server_rg.name
  virtual_network_name = azurerm_virtual_network.web_server_vnet.name
  address_prefix       = var.web_server_subnets[count.index]
  network_security_group_id = count.index == 0 ? azurerm_network_security_group.web_server_nsg.id : ""
  count                = length(var.web_server_subnets)

}

resource "azurerm_public_ip" "web_server_lb_public_ip" {
  name                = "${var.resource_prefix}-public-ip"
  location            = var.web_server_location
  resource_group_name = azurerm_resource_group.web_server_rg.name
  allocation_method   = var.environment == "production" ? "Static" : "Dynamic"
  domain_name_label   = var.domain_name_label
}

resource "azurerm_network_security_group" "web_server_nsg" {
  name                = "${var.resource_prefix}-nsg"
  location            = var.web_server_location
  resource_group_name = azurerm_resource_group.web_server_rg.name
}

resource "azurerm_network_security_rule" "web_server_nsg_rule_http" {
  access                      = "Allow"
  direction                   = "Inbound"
  name                        = "HTTP Inbound"
  network_security_group_name = azurerm_network_security_group.web_server_nsg.name
  priority                    = 100
  protocol                    = "Tcp"
  resource_group_name         = azurerm_resource_group.web_server_rg.name
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
}

/*
resource "azurerm_network_security_rule" "web_server_nsg_rule_rdp" {
  name                        = "RDP Inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "3389"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.web_server_rg.name
  network_security_group_name = azurerm_network_security_group.web_server_nsg.name
}
*/
resource "azurerm_virtual_machine_scale_set" "web_server" {
  name                  = "${var.resource_prefix}-scale-set"
  location              = var.web_server_location
  resource_group_name   = azurerm_resource_group.web_server_rg.name
  upgrade_policy_mode   = "manual"

  sku {
    capacity = var.web_server_count
    tier = "Standard"
    name = "Standard_B1s"
  }

  storage_profile_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2016-Datacenter-Server-Core-smalldisk"
    version   = "latest"
  }

  storage_profile_os_disk {
    name              = ""
    caching           = "ReadWrite"
    create_option     = "FromImage"
    managed_disk_type = "Standard_LRS"
  }

  os_profile {
    computer_name_prefix  = local.web_server_name
    admin_username        = "webserver"
    admin_password        = "Passw0rd1234"
  }

  os_profile_windows_config {
    provision_vm_agent = true
  }

  network_profile {
    name = "web_server_network_profile"
    primary = true

    ip_configuration {
      name = local.web_server_name
      primary = true
      subnet_id = azurerm_subnet.web_server_subnet[0].id
      load_balancer_backend_address_pool_ids = [azurerm_lb_backend_address_pool.web_server_lb_backend_pool.id]
    }
  }

  extension {
    name                 = "${local.web_server_name}-extension"
    publisher            = "Microsoft.Compute"
    type                 = "CustomScriptExtension"
    type_handler_version = "1.9"

    settings = <<SETTINGS
    {
      "fileUris": ["https://raw.githubusercontent.com/eltimmo/learning/master/azureInstallWebServer.ps1"],
      "commandToExecute": "start powershell -ExecutionPolicy Unrestricted -File azureInstallWebServer.ps1"
    }
    SETTINGS

  }
}

resource "azurerm_lb" "web_server_lb" {
  name                  = "${local.web_server_name}-lb"
  location              = var.web_server_location
  resource_group_name   = azurerm_resource_group.web_server_rg.name

  frontend_ip_configuration {
    name                 = "${local.web_server_name}-lb-frontend-ip"
    public_ip_address_id = azurerm_public_ip.web_server_lb_public_ip.id
  }
}

resource "azurerm_lb_backend_address_pool" "web_server_lb_backend_pool" {
  name                  = "${local.web_server_name}-lb-backend-pool"
  resource_group_name   = azurerm_resource_group.web_server_rg.name
  loadbalancer_id       = azurerm_lb.web_server_lb.id
}

resource "azurerm_lb_probe" "web_server_lb_http_probe" {
  name                  = "${local.web_server_name}-lb-http-probe"
  resource_group_name   = azurerm_resource_group.web_server_rg.name
  loadbalancer_id       = azurerm_lb.web_server_lb.id
  port = 80
  protocol = "Tcp"
}

resource "azurerm_lb_rule" "web_server_lb_http_rule" {
  name                  = "${local.web_server_name}-lb-http-rule"
  resource_group_name   = azurerm_resource_group.web_server_rg.name
  loadbalancer_id       = azurerm_lb.web_server_lb.id
  protocol = "Tcp"
  frontend_port = 80
  backend_port = 80
  frontend_ip_configuration_name = "${local.web_server_name}-lb-frontend-ip"
  probe_id = azurerm_lb_probe.web_server_lb_http_probe.id
  backend_address_pool_id = azurerm_lb_backend_address_pool.web_server_lb_backend_pool.id
}

# List all available extension
# az vm extension image list -l westus2 -o table
# az vm extension image list-names -l westus2 -p Microsoft.Compute -o table
# az vm extension image list-version -l westus2 -p Microsoft.Compute -n CustomScriptExtension -o table
#
