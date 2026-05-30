resource "azurerm_storage_account" "this" {
  name                            = var.storage_account_name
  resource_group_name             = var.resource_group_name
  location                        = var.location
  account_tier                    = "Premium"
  account_replication_type        = "LRS"
  account_kind                    = "FileStorage"
  allow_nested_items_to_be_public = false
  https_traffic_only_enabled      = true
  min_tls_version                 = "TLS1_2"
  tags                            = var.tags
}

resource "azurerm_storage_share" "profiles" {
  name               = var.share_name
  storage_account_id = azurerm_storage_account.this.id
  quota              = var.share_quota_gb
  enabled_protocol   = "SMB"
}

locals {
  ou_dc_path = join(",", [for part in split(".", var.domain_name) : "DC=${part}"])

  ad_join_script = templatefile("${path.module}/scripts/join-storage-to-ad.ps1.tftpl", {
    subscription_id      = var.subscription_id
    resource_group_name  = var.resource_group_name
    storage_account_name = var.storage_account_name
    share_name           = var.share_name
    domain_netbios_name  = var.domain_netbios_name
    ou_dc_path           = local.ou_dc_path
  })

  fslogix_script = templatefile("${path.module}/scripts/install-fslogix.ps1.tftpl", {
    share_path      = "\\\\${azurerm_storage_account.this.name}.file.core.windows.net\\${azurerm_storage_share.profiles.name}"
    size_in_mbs     = var.fslogix_initial_size_mb
    storage_account = azurerm_storage_account.this.name
    storage_key_b64 = base64encode(azurerm_storage_account.this.primary_access_key)
  })
}

# Scoped to resource group so AzFilesHybrid can call Get-AzResourceGroup (validation check)
# and Get-AzStorageAccountKey — both require resource group level read access
resource "azurerm_role_assignment" "dc_storage_contributor" {
  scope                = "/subscriptions/${var.subscription_id}/resourceGroups/${var.resource_group_name}"
  role_definition_name = "Storage Account Contributor"
  principal_id         = var.dc_principal_id
}

# AVD users get SMB share access (optional — skipped if group ID not provided)
resource "azurerm_role_assignment" "fslogix_users_share" {
  count                = var.avd_users_group_object_id != "" ? 1 : 0
  scope                = "${azurerm_storage_account.this.id}/fileServices/default/fileshares/${azurerm_storage_share.profiles.name}"
  role_definition_name = "Storage File Data SMB Share Contributor"
  principal_id         = var.avd_users_group_object_id
}

# Run on DC: installs AzFilesHybrid, joins storage account to AD DS, sets NTFS permissions
resource "azurerm_virtual_machine_run_command" "join_storage_to_ad" {
  name               = "setup-storage-ad-auth"
  virtual_machine_id = var.dc_vm_id
  location           = var.location

  source {
    script = local.ad_join_script
  }

  depends_on = [
    azurerm_storage_share.profiles,
    azurerm_role_assignment.dc_storage_contributor
  ]

  timeouts {
    create = "90m"
    update = "90m"
  }
}

resource "azurerm_virtual_machine_extension" "install_fslogix" {
  for_each = var.session_host_vms

  name                       = "install-fslogix"
  virtual_machine_id         = each.value
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(local.fslogix_script, "UTF-16LE")}"
  })

  timeouts {
    create = "60m"
    update = "60m"
    delete = "30m"
  }
}