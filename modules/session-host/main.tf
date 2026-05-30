

resource "azurerm_network_interface" "sh" {
  name                = "nic-${var.vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Dynamic"
  }
}

resource "azurerm_windows_virtual_machine" "sh" {
  name                  = var.vm_name
  computer_name         = var.vm_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.sh.id]
  tags                  = var.tags

  os_disk {
    name                 = "osdisk-${var.vm_name}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsDesktop"
    offer     = "Windows-11"
    sku       = "win11-23h2-avd"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

# -----------------------------------------------------------------------------
# Domain Join via JsonADDomainExtension
# -----------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "domain_join" {
  name                       = "domain-join"
  virtual_machine_id         = azurerm_windows_virtual_machine.sh.id
  publisher                  = "Microsoft.Compute"
  type                       = "JsonADDomainExtension"
  type_handler_version       = "1.3"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    Name    = var.domain_name
    User    = var.domain_admin_user
    Restart = "true"
    Options = "3"  # JOIN_DOMAIN + ACCT_CREATE
  })

  protected_settings = jsonencode({
    Password = var.domain_admin_password
  })

  timeouts {
    create = "30m"
  }
}

# -----------------------------------------------------------------------------
# AVD Agent install + host pool registration via DSC
# -----------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "avd_dsc" {
  name                       = "AddSessionHost"
  virtual_machine_id         = azurerm_windows_virtual_machine.sh.id
  publisher                  = "Microsoft.Powershell"
  type                       = "DSC"
  type_handler_version       = "2.73"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    modulesUrl            = var.avd_dsc_config_url
    configurationFunction = "Configuration.ps1\\AddSessionHost"
    properties = {
      hostPoolName          = var.host_pool_name
      aadJoin               = false
    }
  })

  protected_settings = jsonencode({
    properties = {
      registrationInfoToken = var.registration_token
    }
  })

  timeouts {
    create = "60m"
  }

  depends_on = [azurerm_virtual_machine_extension.domain_join]
}

# -----------------------------------------------------------------------------
# Hybrid Azure AD Join — force immediate Entra ID registration after domain join
# Without this, the scheduled task can take hours to run automatically
# -----------------------------------------------------------------------------
resource "azurerm_virtual_machine_run_command" "hybrid_join" {
  name               = "trigger-hybrid-aad-join"
  virtual_machine_id = azurerm_windows_virtual_machine.sh.id
  location           = var.location

  source {
    script = <<-EOT
      $ErrorActionPreference = "Stop"
      Start-Transcript "C:\Windows\Temp\hybrid-join.log" -Append -Force
      try {
          Write-Host "Waiting 60s for domain join to fully settle..."
          Start-Sleep -Seconds 60

          Write-Host "Triggering Hybrid Azure AD Join..."
          & dsregcmd /join
          Start-Sleep -Seconds 30

          Write-Host "=== Hybrid Join Status ==="
          $status = dsregcmd /status
          $status | Select-String "AzureAdJoined|DomainJoined|WorkplaceJoined"

          $azJoined = ($status | Select-String "AzureAdJoined\s*:\s*YES").Count -gt 0
          $domJoined = ($status | Select-String "DomainJoined\s*:\s*YES").Count -gt 0

          if ($azJoined -and $domJoined) {
              Write-Host "SUCCESS: Hybrid Azure AD Join confirmed."
          } else {
              Write-Host "WARNING: Join may still be pending. Check dsregcmd /status after login."
          }

          Stop-Transcript
          exit 0
      } catch {
          Write-Host "ERROR: $_"
          Stop-Transcript
          exit 1
      }
    EOT
  }

  depends_on = [azurerm_virtual_machine_extension.avd_dsc]

  timeouts {
    create = "30m"
  }
}

# -----------------------------------------------------------------------------
# Auto-shutdown
# -----------------------------------------------------------------------------
resource "azurerm_dev_test_global_vm_shutdown_schedule" "sh" {
  virtual_machine_id    = azurerm_windows_virtual_machine.sh.id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone
  tags                  = var.tags

  notification_settings {
    enabled = false
  }
}
