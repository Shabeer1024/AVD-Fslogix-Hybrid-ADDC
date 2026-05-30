# AVD + FSLogix + Hybrid Azure AD Join — Phase 1 & 2

> Fully automated Azure Virtual Desktop lab with FSLogix profile containers, AD DS authentication for Azure Files, and Hybrid Azure AD Join. Zero manual steps — everything deployed via Terraform and PowerShell Run Commands.

[![Terraform](https://img.shields.io/badge/Terraform-1.5+-7B42BC?logo=terraform&logoColor=white)](https://www.terraform.io/)
[![Azure](https://img.shields.io/badge/Azure-Virtual_Desktop-0089D6?logo=microsoftazure&logoColor=white)](https://azure.microsoft.com/products/virtual-desktop)
[![PowerShell](https://img.shields.io/badge/PowerShell-5.1+-5391FE?logo=powershell&logoColor=white)](https://docs.microsoft.com/powershell)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

---

## What This Project Solves

Most AVD + FSLogix guides still tell you to:
- RDP into the DC manually and run `Join-AzStorageAccount` by hand
- Set NTFS permissions manually via `icacls`
- Trigger `dsregcmd /join` manually on every session host
- Wait and hope Entra Connect syncs before hybrid join works

**That works once. It does not scale, cannot be reproduced, and is not infrastructure as code.**

This project automates every single step — from VM deployment to AD DS domain join for Azure Files to Hybrid Azure AD Join — with zero manual intervention after `terraform apply`.

---

## Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                        Azure Subscription                         │
│                                                                    │
│  ┌────────────────────────┐    ┌──────────────────────────────┐  │
│  │  Microsoft Entra ID    │    │  Azure Files (Premium)        │  │
│  │  (Hybrid Join)         │    │  Identity-based access        │  │
│  │  AzureAdJoined: YES    │    │  AD DS Kerberos auth          │  │
│  └────────────┬───────────┘    └──────────────┬───────────────┘  │
│               │                               │                   │
│  ┌────────────▼───────────────────────────────▼───────────────┐  │
│  │                    AVD Host Pool                            │  │
│  │   sh01, sh02 ... shNN  (Windows 11 23H2)                   │  │
│  │   - Domain joined to lab.local                             │  │
│  │   - Hybrid Azure AD Joined (auto via Run Command)          │  │
│  │   - FSLogix installed and configured                       │  │
│  └────────────────────────────────────────────────────────────┘  │
│                                                                    │
│  ┌─────────────────────────────────────────────────────────────┐  │
│  │  Domain Controller  dc01  (Windows Server 2022)             │  │
│  │  - AD DS forest lab.local                                   │  │
│  │  - SystemAssigned managed identity                          │  │
│  │  - Entra Connect installer pre-downloaded                   │  │
│  │  - AD DS auth for Azure Files automated via Run Command     │  │
│  └─────────────────────────────────────────────────────────────┘  │
└──────────────────────────────────────────────────────────────────┘
```

---

## What Gets Deployed

| Module | Resources |
|--------|-----------|
| **resourcegroup** | Resource Group |
| **vnet** | VNet (10.0.0.0/16), DC subnet, AVD subnet, NSG with RDP rule |
| **dc** | Windows Server 2022 DC, AD DS forest `lab.local`, VNet DNS update, Entra Connect download, SystemAssigned managed identity |
| **avd-core** | Host Pool (Pooled/BreadthFirst), Workspace, Desktop Application Group, Registration Token |
| **session-host** | Windows 11 AVD VMs (count-based), domain join, AVD DSC registration, Hybrid AAD join (retry loop), FSLogix install, auto-shutdown |
| **fslogix-storage** | Premium FileStorage account, profiles share, AD DS auth (fully automated), NTFS permissions, RBAC assignment |

**Total: ~29 Azure resources across 6 modules**

---

## Key Automation Features

### 1. Automated AD DS Authentication for Azure Files
No manual RDP. No hand-running scripts. Terraform:
- Assigns `Storage Account Contributor` to the DC managed identity
- Runs a PowerShell Run Command on the DC that:
  - Installs `Az.Accounts` + `Az.Storage` modules
  - Downloads AzFilesHybrid
  - Authenticates via `Connect-AzAccount -Identity` (managed identity — no passwords)
  - Cleans up stale AD computer objects by SPN
  - Runs `Join-AzStorageAccount`
  - Sets NTFS permissions (`Domain Users: Modify`, `Domain Admins: Full`)

```
Portal result: Identity-based access → Configured (Windows AD)
```

### 2. Scalable Session Hosts
Set `sh_count = N` to deploy N session hosts. Each one automatically gets:
- Domain joined to `lab.local`
- Registered in the AVD host pool
- Hybrid Azure AD Joined (`DomainJoined: YES` + `AzureAdJoined: YES`)
- FSLogix installed and configured

```hcl
sh_count = 3   # deploys sh01, sh02, sh03
```

### 3. Hybrid Azure AD Join with Retry Loop
New session hosts run `dsregcmd /join` with a retry loop that waits up to 20 minutes for Entra Connect to sync the computer object — no manual intervention needed even if sync is delayed.

### 4. Cache-Safe Run Commands
Azure Run Commands cache execution results by name. This project embeds the MD5 hash of each script in the resource name:
```hcl
name = "setup-ad-${substr(md5(local.ad_join_script), 0, 8)}"
```
When the script changes, the name changes, the cache is busted — fresh execution every time.

---

## Repository Structure

```
.
├── main.tf                          # Composes all modules
├── variables.tf                     # Root inputs
├── outputs.tf                       # Key outputs (IPs, passwords, tokens)
├── provider.tf                      # AzureRM provider (az login auth)
├── terraform.tfvars.example         # Template — copy to terraform.tfvars
│
└── modules/
    ├── resourcegroup/               # Resource Group
    ├── vnet/                        # VNet + subnets + NSG
    ├── dc/                          # DC VM + AD DS install + Entra Connect download
    │   └── scripts/
    │       └── install-ad.ps1.tftpl
    ├── avd-core/                    # Host Pool + Workspace + App Group
    ├── session-host/                # Win11 VM + domain join + AVD agent + hybrid join
    └── fslogix-storage/             # Storage + share + AD DS auth + NTFS
        └── scripts/
            ├── install-fslogix.ps1.tftpl
            └── join-storage-to-ad.ps1.tftpl
```

---

## Quick Start

### Prerequisites

- Azure subscription with Contributor access
- Terraform >= 1.5
- Azure CLI

### 1. Clone and configure

```bash
git clone https://github.com/Shabeer1024/AVD-Fslogix-Hybrid-ADDC.git
cd AVD-Fslogix-Hybrid-ADDC

cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values
```

### 2. Login to Azure

```bash
az login
az account set --subscription "YOUR-SUBSCRIPTION-ID"
```

### 3. Deploy

```bash
terraform init
terraform plan
terraform apply
```

Expected deploy time: **~35 minutes**

### 4. Get outputs

```bash
terraform output                              # show all outputs
terraform output -raw dc_admin_password       # DC admin password
terraform output -raw avd_registration_token  # host pool token
```

---

## Post-Deployment Steps

### Configure Microsoft Entra Connect (required for Hybrid Join)

```
RDP to dc01 (IP from: terraform output dc_public_ip)
Username: labadmin
Password: terraform output -raw dc_admin_password

Desktop → AzureADConnect.msi → Run wizard:
  1. Customize → Install
  2. Password Hash Sync
  3. Connect to Entra ID with Global Admin
  4. Connect to lab.local
  5. Optional features → check "Hybrid Azure AD join"
  6. SCP → tick lab.local → Install
```

### Force sync after deploy

```powershell
# On DC — syncs new computer objects immediately
Import-Module ADSync
Start-ADSyncSyncCycle -PolicyType Delta
```

### Verify Hybrid Join on session hosts

```powershell
# On sh01 or sh02
dsregcmd /status

# Expected:
# AzureAdJoined  : YES
# DomainJoined   : YES
```

### Verify FSLogix

```
Login via AVD client → check share:
\\stfslogix<name>.file.core.windows.net\profiles\

Should see: LAB_username_S-1-5-...\Profile_username.vhdx
```

---

## Scaling Session Hosts

```hcl
# terraform.tfvars
sh_count = 3   # change from 2 to 3
```

```bash
terraform apply
# Only sh03 is created — sh01 and sh02 are untouched
```

---

## Destroy and Recreate

```bash
# Destroy all resources
terraform destroy

# Wait 3 minutes (Azure holds storage account name briefly)
# Then redeploy
terraform apply
```

> **Note:** Destroying the storage account deletes all FSLogix user profile VHDXes permanently. In production, back up profiles before destroying.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `SkuNotAvailable: Standard_B2s` | No capacity in region | Change `dc_vm_size`/`sh_vm_size` to `Standard_D2s_v3` |
| `File is not supported for the account` | Wrong storage kind | Use `account_kind = "FileStorage"` with `Premium` tier |
| `Provided resource group does not exist` in Run Command | Managed identity scoped too narrowly | Scope role assignment to resource group, not storage account |
| `AD object already exists` error | Stale AD computer object from previous join | Script auto-detects by SPN and removes it |
| Azure Run Command returns cached old result | Same Run Command name reused | Script name includes MD5 hash — changes with script content |
| `AzureAdJoined: NO` after deploy | Entra Connect hasn't synced yet | Run `Start-ADSyncSyncCycle -PolicyType Delta` on DC, then `dsregcmd /join` on session host |
| `Cannot change configuration — sync in progress` | Entra Connect wizard open | Close wizard, kill `AzureADConnect` process, retry |
| `The string is missing the terminator` in Run Command | Double quotes in PowerShell script break JSON encoding | Use single quotes + string concatenation throughout |
| Storage account name unavailable after destroy | Azure soft-delete hold | Wait 3 minutes before reapplying |

---

## AVD Identity Models — Three Phases

| Phase | Model | DC Required | Entra Connect | Azure Files Auth | Repo |
|-------|-------|-------------|---------------|-----------------|------|
| 1 & 2 | Hybrid AD DS | Yes | Yes | AD DS Kerberos | **This repo** |
| 3 | Cloud-only | No | No | Entra Kerberos | [AVD-FSLogix-Without-Domain-Controllers](https://github.com/Shabeer1024/AVD-FSLogix-Without-Domain-Controllers) |

---

## What This Project Demonstrates

**Infrastructure as Code**
- Multi-module Terraform with count-based scaling
- Local state management with `az login` authentication
- Idempotent module design (safe to run multiple times)

**Azure Architecture**
- AD DS + Entra ID hybrid identity model
- Azure Virtual Desktop full stack deployment
- FSLogix profile container with AD DS authentication
- System-Assigned Managed Identity for passwordless automation

**Automation Engineering**
- PowerShell Run Commands triggered from Terraform
- MD5 hash-based naming to bust Azure Run Command cache
- Retry loops for eventual-consistency operations (Entra Connect sync)
- Idempotent scripts with pre-flight cleanup

**Real Problems Solved**
- Azure Run Command caching behavior and how to work around it
- JSON encoding breaking double-quoted PowerShell strings
- Stale AD computer objects blocking storage account re-joins
- Hybrid join timing dependency on Entra Connect sync cycle

---

## Author

**Shabeer S** — Azure Cloud Enthusiast ☁️ | CloudOps  | Exploring Azure Administration | AVD Specialist | AZ-700 | AZ-140 | Terraform | Azure Networking | Modern Workspace | ITIL V4 |

- 13+ years enterprise IT (EUC → Cloud Engineer transition)
- Specialising in AVD, FSLogix, Azure Networking, and Infrastructure as Code
- GitHub: [@Shabeer1024](https://github.com/Shabeer1024)
- LinkedIn: [linkedin.com/in/shabeer-s-82690a156](https://linkedin.com/in/shabeer-s-82690a156)

---

## License

MIT — see [LICENSE](./LICENSE)

---

*If this helped you, give it a ⭐ — and feel free to open an issue or PR.*
