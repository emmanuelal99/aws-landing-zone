# Dev account (default provider)
provider "aws" {
  region  = "eu-west-2"
  profile = var.dev_profile
}

# Management account
provider "aws" {
  alias   = "mgmt"
  region  = "eu-west-2"
  profile = var.mgmt_profile
}

# Security account
provider "aws" {
  alias   = "security"
  region  = "eu-west-2"
  profile = var.security_profile
}
