# =============================================================================
# Automation Account + Hybrid Worker on Session Host
# =============================================================================

resource "azurerm_automation_account" "this" {
  name                = var.automation_account_name
  location            = var.location
  resource_group_name = var.resource_group_name
  sku_name            = "Basic"
  tags                = var.tags

  identity {
    type = "SystemAssigned"
  }
}

resource "azurerm_automation_hybrid_runbook_worker_group" "this" {
  name                    = var.hybrid_worker_group_name
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
}

resource "random_uuid" "worker_id" {}

resource "azurerm_automation_hybrid_runbook_worker" "sh01" {
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  worker_group_name       = azurerm_automation_hybrid_runbook_worker_group.this.name
  vm_resource_id          = var.session_host_vm_id
  worker_id               = random_uuid.worker_id.result
}

# -----------------------------------------------------------------------------
#  Install Hyper-V PowerShell module (provides Resize-VHD) on session host
# -----------------------------------------------------------------------------
locals {
  hyperv_script = <<-EOT
    $ErrorActionPreference = "Stop"
    Start-Transcript "C:\Windows\Temp\install-hyperv.log" -Append -Force
    try {
        Write-Host "Enabling Hyper-V Management PowerShell module"
        Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -All -NoRestart
        Write-Host "Feature enabled. Verifying Resize-VHD..."
        Import-Module Hyper-V -ErrorAction SilentlyContinue
        if (Get-Command Resize-VHD -ErrorAction SilentlyContinue) {
            Write-Host "Resize-VHD available - SUCCESS"
        } else {
            Write-Host "Resize-VHD not yet loaded - reboot may be needed but not critical"
        }
        Stop-Transcript
        exit 0
    } catch {
        Write-Error $_
        Stop-Transcript
        exit 1
    }
  EOT
}

resource "azurerm_virtual_machine_extension" "install_hyperv" {
  name                       = "install-hyperv-module"
  virtual_machine_id         = var.session_host_vm_id
  publisher                  = "Microsoft.Compute"
  type                       = "CustomScriptExtension"
  type_handler_version       = "1.10"
  auto_upgrade_minor_version = true

  protected_settings = jsonencode({
    commandToExecute = "powershell.exe -ExecutionPolicy Unrestricted -EncodedCommand ${textencodebase64(local.hyperv_script, "UTF-16LE")}"
  })

  timeouts {
    create = "30m"
  }
}

# -----------------------------------------------------------------------------
# Install HybridWorkerForWindows extension on session host
# -----------------------------------------------------------------------------
resource "azurerm_virtual_machine_extension" "hybrid_worker" {
  name                       = "HybridWorkerExtension"
  virtual_machine_id         = var.session_host_vm_id
  publisher                  = "Microsoft.Azure.Automation.HybridWorker"
  type                       = "HybridWorkerForWindows"
  type_handler_version       = "1.1"
  auto_upgrade_minor_version = true

  settings = jsonencode({
    AutomationAccountURL = azurerm_automation_account.this.hybrid_service_url
  })

  depends_on = [
    azurerm_automation_hybrid_runbook_worker.sh01,
    azurerm_virtual_machine_extension.install_hyperv
  ]

  timeouts {
    create = "30m"
  }
}
