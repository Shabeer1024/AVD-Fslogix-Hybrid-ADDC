output "vm_id" {
  value = azurerm_windows_virtual_machine.dc.id
}

output "vm_name" {
  value = azurerm_windows_virtual_machine.dc.name
}

output "private_ip_address" {
  value = azurerm_network_interface.dc.private_ip_address
}

output "public_ip_address" {
  value = azurerm_public_ip.dc.ip_address
}

output "admin_username" {
  value = var.admin_username
}

output "domain_name" {
  value = var.domain_name
}

output "principal_id" {
  value = azurerm_windows_virtual_machine.dc.identity[0].principal_id
}
