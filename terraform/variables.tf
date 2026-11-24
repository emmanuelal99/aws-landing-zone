# AWS CLI profiles used by each provider. The defaults are read-only (audit)
# roles, so a normal "terraform plan" can never change anything. A write role
# is chosen on purpose, one account at a time, only when applying a change:
#   terraform plan -var security_profile=sec-admin -out=change.tfplan

variable "dev_profile" {
  description = "AWS CLI profile for the Dev account"
  type        = string
  default     = "dev-audit"
}

variable "mgmt_profile" {
  description = "AWS CLI profile for the management account"
  type        = string
  default     = "mgmt-audit"
}

variable "security_profile" {
  description = "AWS CLI profile for the Security account"
  type        = string
  default     = "sec-audit"
}
