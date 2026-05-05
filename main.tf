module "resource_group" {
  source              = "./modules/resourcegroup"
  resource_group_name = var.resource_group_name
  location            = var.location
}

module "network" {
  source              = "./modules/vnet"
  resource_group_name = var.resource_group_name
  location            = var.location
  vnet_name           = var.vnet_name
  vnet_subnet_count   = var.vnet_subnet_count
  vnet_address_prefix = var.vnet_address_prefix

  depends_on = [module.resource_group]
}