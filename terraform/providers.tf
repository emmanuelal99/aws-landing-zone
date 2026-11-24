# Dev account, read-only during import
provider "aws" {
  region  = "eu-west-2"
  profile = "dev-audit"
}

# Management account, read-only during import
provider "aws" {
  alias   = "mgmt"
  region  = "eu-west-2"
  profile = "mgmt-audit"
}

# Security account, read-only during import
provider "aws" {
  alias   = "security"
  region  = "eu-west-2"
  profile = "sec-audit"
}
