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
# Install Hyper-V PowerShell module (provides Resize-VHD) on session host
# Using Run Command (not VM extension) to avoid the
# "one CustomScriptExtension per Windows VM" limit.
# -----------------------------------------------------------------------------
resource "azurerm_virtual_machine_run_command" "install_hyperv" {
  name               = "install-hyperv-module"
  virtual_machine_id = var.session_host_vm_id
  location           = var.location

 source {
    script = <<-EOT
      $ErrorActionPreference = "Stop"
      try {
          Write-Host "Enabling Hyper-V Management PowerShell module"
          Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-Management-PowerShell -All -NoRestart
          Write-Host "Scheduling delayed reboot in 60 seconds to activate module"
          shutdown /r /t 60 /c "Hyper-V module activation reboot"
          exit 0
      } catch {
          Write-Error $_
          exit 1
      }
    EOT
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
    azurerm_virtual_machine_run_command.install_hyperv
  ]

  timeouts {
    create = "30m"
  }
}
# =============================================================================
# Phase 3 - FSLogix Auto-Grow Runbook + Webhook
# =============================================================================
resource "azurerm_automation_runbook" "fslogix_autogrow" {
  name                    = "FSLogix-AutoGrow"
  location                = var.location
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  description             = "Auto-grows FSLogix profile VHDXes when usage exceeds 80%"
  runbook_type            = "PowerShell"

  content = file("${path.module}/scripts/fslogix-autogrow.ps1")
}

resource "azurerm_automation_webhook" "fslogix_autogrow_trigger" {
  name                    = "FSLogix-AutoGrow-Trigger"
  resource_group_name     = var.resource_group_name
  automation_account_name = azurerm_automation_account.this.name
  expiry_time             = timeadd(timestamp(), "8760h")
  enabled                 = true
  runbook_name            = azurerm_automation_runbook.fslogix_autogrow.name

  run_on_worker_group     = azurerm_automation_hybrid_runbook_worker_group.this.name

  lifecycle {
    ignore_changes = [expiry_time]
  }
}

# =============================================================================
# Phase 4 - Logic App Scheduler
# =============================================================================
resource "azurerm_logic_app_workflow" "fslogix_scheduler" {
  name                = "lapp-fslogix-autogrow"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_logic_app_trigger_recurrence" "hourly" {
  name         = "hourly-trigger"
  logic_app_id = azurerm_logic_app_workflow.fslogix_scheduler.id
  frequency    = "Hour"
  interval     = 1
}

resource "azurerm_logic_app_action_http" "call_runbook_webhook" {
  name         = "Call-Runbook-Webhook"
  logic_app_id = azurerm_logic_app_workflow.fslogix_scheduler.id
  method       = "POST"
  uri          = azurerm_automation_webhook.fslogix_autogrow_trigger.uri

  depends_on = [azurerm_logic_app_trigger_recurrence.hourly]
}
