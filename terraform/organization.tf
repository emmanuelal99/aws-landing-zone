# AWS Organization: structure and member accounts (managed from the management account).
# The management account itself is not managed here: Terraform runs from it.

resource "aws_organizations_organization" "this" {
  provider = aws.mgmt

  feature_set = "ALL"

  # AWS services trusted to work across the organisation.
  aws_service_access_principals = [
    "access-analyzer.amazonaws.com",
    "account.amazonaws.com",
    "cloudtrail.amazonaws.com",
    "guardduty.amazonaws.com",
    "iam.amazonaws.com",
    "sso.amazonaws.com",
  ]

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
  ]

  # Deleting the organisation would remove every guardrail and account link.
  lifecycle {
    prevent_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Organisational units
# ---------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "security" {
  provider  = aws.mgmt
  name      = "Security"
  parent_id = aws_organizations_organization.this.roots[0].id

  tags = { Project = "Portfolio", Env = "Security", Owner = "Emmy" }
}

resource "aws_organizations_organizational_unit" "workloads" {
  provider  = aws.mgmt
  name      = "Workloads"
  parent_id = aws_organizations_organization.this.roots[0].id

  tags = { Project = "Portfolio", Env = "Workloads", Owner = "Emmy" }
}

# Empty for now: a place for experiments, with the same guardrails.
resource "aws_organizations_organizational_unit" "sandbox" {
  provider  = aws.mgmt
  name      = "Sandbox"
  parent_id = aws_organizations_organization.this.roots[0].id

  tags = { Project = "Portfolio", Env = "Sandbox", Owner = "Emmy" }
}

# ---------------------------------------------------------------------------
# Member accounts
# Terraform must never remove or close an account: prevent_destroy blocks any
# plan that would delete them, and close_on_deletion stays false.
# ---------------------------------------------------------------------------

resource "aws_organizations_account" "security" {
  provider          = aws.mgmt
  name              = "Security"
  email             = var.security_account_email
  parent_id         = aws_organizations_organizational_unit.security.id
  close_on_deletion = false

  tags = { Project = "Portfolio", Env = "Security", Owner = "Emmy" }

  lifecycle {
    prevent_destroy = true
    # Only used when an account is created; AWS does not return them.
    ignore_changes = [role_name, iam_user_access_to_billing]
  }
}

resource "aws_organizations_account" "dev" {
  provider          = aws.mgmt
  name              = "Dev"
  email             = var.dev_account_email
  parent_id         = aws_organizations_organizational_unit.workloads.id
  close_on_deletion = false

  tags = { Project = "Portfolio", Env = "Dev", Owner = "Emmy" }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = [role_name, iam_user_access_to_billing]
  }
}
