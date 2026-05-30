variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "storage_account_name" {
  description = "Globally unique, lowercase, 3-24 chars, alphanumeric"
  type        = string
}
variable "share_name" {
  type    = string
  default = "profiles"
}
variable "share_quota_gb" {
  type    = number
  default = 100
}
variable "fslogix_initial_size_mb" {
  type    = number
  default = 10240
}
variable "session_host_vms" {
  description = "Map of session host name => VM resource ID — FSLogix is installed on every host"
  type        = map(string)
}

variable "dc_vm_id" {
  description = "Resource ID of the DC VM — used to run the AD join Run Command"
  type        = string
}

variable "dc_principal_id" {
  description = "Object ID of the DC managed identity — granted Storage Account Contributor"
  type        = string
}

variable "domain_name" {
  description = "AD DS domain name (e.g. lab.local)"
  type        = string
}

variable "domain_netbios_name" {
  description = "NetBIOS name of the domain (e.g. LAB)"
  type        = string
}

variable "subscription_id" {
  description = "Azure subscription ID — used inside the AD join script"
  type        = string
}

variable "avd_users_group_object_id" {
  description = "Entra ID Object ID of the AVD users group — granted Storage File Data SMB Share Contributor. Leave empty to skip."
  type        = string
  default     = ""
}
variable "tags" {
  type    = map(string)
  default = {}
}