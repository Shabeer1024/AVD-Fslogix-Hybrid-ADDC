variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "vnet_name" {
  description = "Name of the virtual network"
  type        = string
}

variable "vnet_address_space" {
  description = "Address space for the VNet"
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnets to create. Key = subnet short name."
  type = map(object({
    address_prefixes = list(string)
  }))
}

variable "nsg_name" {
  description = "Name of the NSG to attach to all subnets"
  type        = string
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}

variable "admin_source_ip" {
  description = "Your public IP (or CIDR) — used as the source for the RDP allow rule. Find with: curl ifconfig.me"
  type        = string

  validation {
    condition     = can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}(/[0-9]{1,2})?$", var.admin_source_ip))
    error_message = "admin_source_ip must be an IPv4 address or CIDR (e.g. '1.2.3.4' or '1.2.3.4/32')."
  }
}
variable "dc_vm_name" {
  description = "Name of the DC VM (<=15 chars)"
  type        = string
  default     = "dc01"
}

variable "dc_vm_size" {
  description = "DC VM SKU"
  type        = string
  default     = "Standard_D2s_v3"
}

variable "dc_admin_username" {
  description = "Local administrator username on the DC"
  type        = string
  default     = "labadmin"
}

variable "dc_private_ip" {
  description = "Static private IP for the DC"
  type        = string
  default     = "10.0.1.4"
}

variable "domain_name" {
  description = "AD DS domain name to create"
  type        = string
  default     = "lab.local"
}

variable "auto_shutdown_time" {
  description = "Daily VM auto-shutdown time HHMM"
  type        = string
  default     = "2300"
}

variable "auto_shutdown_timezone" {
  description = "Windows timezone ID"
  type        = string
  default     = "India Standard Time"
}

variable "sh_count" {
  description = "Number of session hosts to deploy in the host pool"
  type        = number
  default     = 1
}

variable "sh_vm_size" {
  description = "Session host VM SKU"
  type        = string
  default     = "Standard_B2s"
}

variable "fslogix_storage_account_name" {
  description = "Globally unique, lowercase, 3-24 chars"
  type        = string
}
variable "avd_users_group_object_id" {
  description = "Entra ID Object ID of the AVD users group for SMB share access. Find in: Entra ID > Groups > your group > Overview > Object ID. Leave empty to skip RBAC assignment."
  type        = string
  default     = ""
}

variable "fslogix_share_quota_gb" {
  type    = number
  default = 100
}
variable "fslogix_initial_size_mb" {
  type    = number
  default = 10240
}