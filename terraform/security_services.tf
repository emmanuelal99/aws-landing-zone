# Organisation security services, run from the Security account (D-002, D-005).

# ---------------------------------------------------------------------------
# Delegation: the management account hands each service to the Security account
# ---------------------------------------------------------------------------

resource "aws_guardduty_organization_admin_account" "this" {
  provider         = aws.mgmt
  admin_account_id = aws_organizations_account.security.id
}

resource "aws_organizations_delegated_administrator" "access_analyzer" {
  provider          = aws.mgmt
  account_id        = aws_organizations_account.security.id
  service_principal = "access-analyzer.amazonaws.com"
}

resource "aws_organizations_delegated_administrator" "iam" {
  provider          = aws.mgmt
  account_id        = aws_organizations_account.security.id
  service_principal = "iam.amazonaws.com"
}

# ---------------------------------------------------------------------------
# GuardDuty administrator (Security account)
# ---------------------------------------------------------------------------

resource "aws_guardduty_detector" "security" {
  provider                     = aws.security
  enable                       = true
  finding_publishing_frequency = "SIX_HOURS"
}

# Every current and future account is enabled automatically. Member detectors
# are controlled by this setting, so they are not managed one by one here.
# Per-plan settings (S3 on, Runtime Monitoring off, ...) follow D-005.
resource "aws_guardduty_organization_configuration" "this" {
  provider                         = aws.security
  detector_id                      = aws_guardduty_detector.security.id
  auto_enable_organization_members = "ALL"
}
