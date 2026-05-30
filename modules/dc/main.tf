locals {
  install_script = templatefile("${path.module}/scripts/install-ad.ps1.tftpl", {
    domain_name            = var.domain_name
    netbios_name           = upper(split(".", var.domain_name)[0])
    safe_mode_password_b64 = base64encode(var.safe_mode_password)
  })
}

resource "azurerm_public_ip" "dc" {
  name                = "pip-${var.vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  tags                = var.tags
}

resource "azurerm_network_interface" "dc" {
  name                = "nic-${var.vm_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = var.private_ip_address
    public_ip_address_id          = azurerm_public_ip.dc.id
  }
}

resource "azurerm_windows_virtual_machine" "dc" {
  name                  = var.vm_name
  computer_name         = var.vm_name
  location              = var.location
  resource_group_name   = var.resource_group_name
  size                  = var.vm_size
  admin_username        = var.admin_username
  admin_password        = var.admin_password
  network_interface_ids = [azurerm_network_interface.dc.id]
  tags                  = var.tags

  os_disk {
    name                 = "osdisk-${var.vm_name}"
    caching              = "ReadWrite"
    storage_account_type = "Standard_LRS"
  }

  source_image_reference {
    publisher = "MicrosoftWindowsServer"
    offer     = "WindowsServer"
    sku       = "2022-datacenter-g2"
    version   = "latest"
  }

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_virtual_machine_extension" "install_ad" {
  name                       = "install-ad"
  virtual_machine_id         = azurerm_windows_virtual_machine.dc.id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(local.install_script, "UTF-16LE")}"
  })

  timeouts {
    create = "45m"
    update = "45m"
    delete = "15m"
  }
}

resource "azurerm_virtual_network_dns_servers" "this" {
  virtual_network_id = var.virtual_network_id
  dns_servers        = [var.private_ip_address]

  depends_on = [azurerm_virtual_machine_extension.install_ad]
}

# -----------------------------------------------------------------------------
# Download Microsoft Entra Connect after DC promotion
# Run manually: double-click AzureADConnect.msi on the DC desktop
# Then configure Hybrid Azure AD Join in the Entra Connect wizard
# -----------------------------------------------------------------------------
resource "azurerm_virtual_machine_run_command" "download_entra_connect" {
  name               = "download-entra-connect"
  virtual_machine_id = azurerm_windows_virtual_machine.dc.id
  location           = var.location

  source {
    script = <<-EOT
      $ErrorActionPreference = "Stop"
      Start-Transcript "C:\Windows\Temp\entra-connect-download.log" -Append -Force
      try {
          $dest = "C:\Users\Public\Desktop\AzureADConnect.msi"
          if (Test-Path $dest) {
              Write-Host "Entra Connect installer already exists at $dest"
          } else {
              Write-Host "Downloading Microsoft Entra Connect..."
              $url = "https://download.microsoft.com/download/B/0/0/B00291D0-5A83-4DE7-86F5-980BC00DE05A/AzureADConnect.msi"
              Invoke-WebRequest -Uri $url -OutFile $dest -UseBasicParsing
              Write-Host "Download complete: $dest"
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

  depends_on = [azurerm_virtual_network_dns_servers.this]

  timeouts {
    create = "30m"
  }
}

resource "azurerm_dev_test_global_vm_shutdown_schedule" "dc" {
  virtual_machine_id    = azurerm_windows_virtual_machine.dc.id
  location              = var.location
  enabled               = true
  daily_recurrence_time = var.auto_shutdown_time
  timezone              = var.auto_shutdown_timezone
  tags                  = var.tags

  notification_settings {
    enabled = false
  }
}
