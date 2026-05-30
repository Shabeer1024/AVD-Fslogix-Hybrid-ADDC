
output "dc_vm_name" {
  value = module.domain_controller.vm_name
}

output "dc_private_ip" {
  value = module.domain_controller.private_ip_address
}

output "dc_public_ip" {
  value = module.domain_controller.public_ip_address
}

output "dc_admin_username" {
  value = module.domain_controller.admin_username
}

output "dc_admin_password" {
  description = "Retrieve with: terraform output -raw dc_admin_password"
  value       = random_password.dc_admin.result
  sensitive   = true
}

output "dc_domain_name" {
  value = module.domain_controller.domain_name
}

output "avd_workspace_name" {
  value = module.avd_core.workspace_name
}

output "avd_host_pool_name" {
  value = module.avd_core.host_pool_name
}

output "avd_app_group_name" {
  value = module.avd_core.app_group_name
}

output "avd_registration_token" {
  description = "Used by session hosts to register with the pool. Sensitive."
  value       = module.avd_core.registration_token
  sensitive   = true
}

output "session_host_names" {
  value = [for sh in module.session_host : sh.vm_name]
}

output "session_host_private_ips" {
  value = [for sh in module.session_host : sh.private_ip_address]
}

output "fslogix_storage_account" { value = module.fslogix_storage.storage_account_name }
output "fslogix_share_unc"       { value = module.fslogix_storage.share_unc }
output "fslogix_share_quota_gb"  { value = module.fslogix_storage.share_quota_gb }
