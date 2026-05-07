variable "resource_group_name" {
  type = string
}

variable "location" {
  type = string
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    Environment = "Lab"
    Project     = "AVD-Lab"
    Owner       = "Shabeer"
    CostCenter  = "Learning"
  }
}