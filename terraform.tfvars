resource_group_name = "AVD-Lab"
location            = "Southeast Asia"

tags = {
  Environment = "Lab"
  Project     = "AVD_Lab"
  Owner       = "Shabeer"
}

vnet_name          = "Vnet01"
vnet_address_space = ["10.0.0.0/16"]

subnets = {
  dc  = { address_prefixes = ["10.0.1.0/24"] }
  avd = { address_prefixes = ["10.0.2.0/24"] }
}

nsg_name        = "nsg-avd-lab"
admin_source_ip = "49.206.132.127"   # Your public IP — update with: curl ifconfig.me

sh_vm_name = "sh01"
sh_vm_size = "Standard_D2s_v3"





dc_vm_name             = "dc01"
dc_vm_size             = "Standard_D2s_v3"
dc_admin_username      = "labadmin"
dc_private_ip          = "10.0.1.4"
domain_name            = "lab.local"
auto_shutdown_time     = "2300"
auto_shutdown_timezone = "India Standard Time"


fslogix_storage_account_name = "stfslogixshabeer1024"  