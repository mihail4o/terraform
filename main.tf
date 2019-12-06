variable "client_id" {}
variable "client_secret" {}
variable "tenant_id" {}
variable "subscription_id" {}

variable "resource_prefix" {}
# variable "web_server_address_prefix" {}
variable "web_server_name" {}
variable "environment" {}
variable "web_server_count" {}
variable "terraform_script_version" {}
variable "domain_name_label" {}

variable "web_server_rg" {}

provider "azurerm" {
  version         = "1.36"
  client_id       = var.client_id
  tenant_id       = var.tenant_id
  client_secret   = var.client_secret
  subscription_id = var.subscription_id
}

module "location_us2w" {
  source = "./location"

  web_server_location = "westus2"
  web_server_rg = "${var.web_server_rg}-us2w"
  resource_prefix = "${var.resource_prefix}-us2w"
  web_server_address_space = "1.0.0.0/22"
  web_server_name = var.web_server_name
  environment = var.environment
  web_server_count = var.web_server_count
  web_server_subnets = ["1.0.1.0/24", "1.0.2.0/24"]
  domain_name_label = var.domain_name_label
  terraform_script_version = var.terraform_script_version
}

module "location_eu1w" {
  source = "./location"

  web_server_location = "westeurope"
  web_server_rg = "${var.web_server_rg}-eu1w"
  resource_prefix = "${var.resource_prefix}-eu1w"
  web_server_address_space = "2.0.0.0/22"
  web_server_name = var.web_server_name
  environment = var.environment
  web_server_count = var.web_server_count
  web_server_subnets = ["2.0.1.0/24", "2.0.2.0/24"]
  domain_name_label = var.domain_name_label
  terraform_script_version = var.terraform_script_version
}

resource "azurerm_traffic_manager_profile" "trafic_manager" {
  name = "${var.resource_prefix}-traffic-manager"
  resource_group_name = module.location_us2w.web_server_rg_name
  traffic_routing_method = "Weighted"
  dns_config {
    relative_name = var.domain_name_label
    ttl = 100
  }
  monitor_config {
    port = 80
    protocol = "http"
    path = "/"
  }
}

resource "azurerm_traffic_manager_endpoint" "traffic_manager_us2w" {
  name = "${var.resource_prefix}-us2w-endpoint"
  resource_group_name = module.location_us2w.web_server_rg_name
  profile_name = azurerm_traffic_manager_profile.trafic_manager.name
  target_resource_id = module.location_us2w.web_server_lb_public_ip_id
  type = "azureEndpoints"
  weight = 100
}

resource "azurerm_traffic_manager_endpoint" "traffic_manager_eu1w" {
  name = "${var.resource_prefix}-eu1w-endpoint"
  resource_group_name = module.location_us2w.web_server_rg_name
  profile_name = azurerm_traffic_manager_profile.trafic_manager.name
  target_resource_id = module.location_eu1w.web_server_lb_public_ip_id
  type = "azureEndpoints"
  weight = 100
}