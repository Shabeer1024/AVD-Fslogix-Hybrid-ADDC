resource "azurerm_resource_group" "AVD-Lab" {
  name     = var.resource_group_name
  location = var.location
}