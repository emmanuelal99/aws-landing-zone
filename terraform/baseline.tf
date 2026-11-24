# Account-wide security settings, applied in every account.
# Owned by the landing zone because they protect every workload.

# ---------------------------------------------------------------------------
# Management account
# ---------------------------------------------------------------------------

resource "aws_iam_account_password_policy" "mgmt" {
  provider = aws.mgmt

  minimum_password_length        = 14
  password_reuse_prevention      = 24
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 0 # no forced expiry (NCSC and NIST guidance)
  hard_expiry                    = false
}

resource "aws_s3_account_public_access_block" "mgmt" {
  provider = aws.mgmt

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "mgmt" {
  provider = aws.mgmt
  enabled  = true
}

# ---------------------------------------------------------------------------
# Security account
# ---------------------------------------------------------------------------

resource "aws_iam_account_password_policy" "security" {
  provider = aws.security

  minimum_password_length        = 14
  password_reuse_prevention      = 24
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = false # differs from the other accounts; no IAM users exist
  max_password_age               = 0
  hard_expiry                    = false
}

resource "aws_s3_account_public_access_block" "security" {
  provider = aws.security

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Was off when imported (finding F-009). Enabled through Terraform.
resource "aws_ebs_encryption_by_default" "security" {
  provider = aws.security
  enabled  = true
}

# ---------------------------------------------------------------------------
# Dev account (default provider)
# ---------------------------------------------------------------------------

resource "aws_iam_account_password_policy" "dev" {
  minimum_password_length        = 14
  password_reuse_prevention      = 24
  require_lowercase_characters   = true
  require_uppercase_characters   = true
  require_numbers                = true
  require_symbols                = true
  allow_users_to_change_password = true
  max_password_age               = 0
  hard_expiry                    = false
}

resource "aws_s3_account_public_access_block" "dev" {
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_ebs_encryption_by_default" "dev" {
  enabled = true
}

# Scan every repository in the account when an image is pushed.
resource "aws_ecr_registry_scanning_configuration" "dev" {
  scan_type = "BASIC"

  rule {
    scan_frequency = "SCAN_ON_PUSH"
    repository_filter {
      filter      = "*"
      filter_type = "WILDCARD"
    }
  }
}
