# IAM Identity Center: who can sign in to which account, with which role.
# Access is always given to groups, never to individual users. Users and group
# membership are managed in the console; groups are looked up here by name.

data "aws_ssoadmin_instances" "this" {
  provider = aws.mgmt
}

locals {
  sso_instance_arn  = tolist(data.aws_ssoadmin_instances.this.arns)[0]
  identity_store_id = tolist(data.aws_ssoadmin_instances.this.identity_store_ids)[0]
}

data "aws_identitystore_group" "this" {
  provider          = aws.mgmt
  for_each          = toset(["Platform-Admins", "Security-Audit", "Developers"])
  identity_store_id = local.identity_store_id

  alternate_identifier {
    unique_attribute {
      attribute_path  = "DisplayName"
      attribute_value = each.value
    }
  }
}

# ---------------------------------------------------------------------------
# Permission sets. The most powerful roles have the shortest sessions.
# ---------------------------------------------------------------------------

resource "aws_ssoadmin_permission_set" "admin" {
  provider         = aws.mgmt
  name             = "Admin"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT1H"

  # Removing the Admin role could lock everyone out of the accounts.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_ssoadmin_permission_set" "auditor" {
  provider         = aws.mgmt
  name             = "Auditor"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
}

resource "aws_ssoadmin_permission_set" "developer" {
  provider         = aws.mgmt
  name             = "Developer"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT4H"
}

resource "aws_ssoadmin_permission_set" "portfolio_admin" {
  provider         = aws.mgmt
  name             = "PortfolioAdmin"
  instance_arn     = local.sso_instance_arn
  session_duration = "PT1H"
}

# ---------------------------------------------------------------------------
# AWS managed policies
# ---------------------------------------------------------------------------

resource "aws_ssoadmin_managed_policy_attachment" "admin_administrator" {
  provider           = aws.mgmt
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.admin.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ssoadmin_managed_policy_attachment" "auditor_security_audit" {
  provider           = aws.mgmt
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/SecurityAudit"
}

resource "aws_ssoadmin_managed_policy_attachment" "auditor_view_only" {
  provider           = aws.mgmt
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/job-function/ViewOnlyAccess"
}

resource "aws_ssoadmin_managed_policy_attachment" "developer_power_user" {
  provider           = aws.mgmt
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn
  managed_policy_arn = "arn:aws:iam::aws:policy/PowerUserAccess"
}

# ---------------------------------------------------------------------------
# Inline policies
# ---------------------------------------------------------------------------

# Read-only extras the managed policies leave out (findings F-008 and F-010).
resource "aws_ssoadmin_permission_set_inline_policy" "auditor" {
  provider           = aws.mgmt
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.auditor.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ReadCloudFrontFunctionCode"
        Effect   = "Allow"
        Action   = ["cloudfront:DescribeFunction", "cloudfront:GetFunction"]
        Resource = "*"
      },
      {
        Sid      = "ReadCostGuardrails"
        Effect   = "Allow"
        Action   = ["budgets:ViewBudget", "budgets:ListTagsForResource", "ce:GetAnomalyMonitors", "ce:GetAnomalySubscriptions", "ce:ListTagsForResource"]
        Resource = "*"
      }
    ]
  })
}

# Developers can attach only the portfolio instance role, and only to EC2.
resource "aws_ssoadmin_permission_set_inline_policy" "developer" {
  provider           = aws.mgmt
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.developer.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "PassPortfolioEc2RoleOnly"
        Effect    = "Allow"
        Action    = "iam:PassRole"
        Resource  = "arn:aws:iam::${aws_organizations_account.dev.id}:role/portfolio-ec2-role"
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      },
      {
        Sid      = "SeeInstanceProfiles"
        Effect   = "Allow"
        Action   = ["iam:ListInstanceProfiles", "iam:GetInstanceProfile"]
        Resource = "*"
      }
    ]
  })
}

# Tunnel-only: port forwarding to Portfolio-tagged instances, no shell.
resource "aws_ssoadmin_permission_set_inline_policy" "portfolio_admin" {
  provider           = aws.mgmt
  instance_arn       = local.sso_instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.portfolio_admin.arn

  inline_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "TunnelOnlyToPortfolioInstances"
        Effect   = "Allow"
        Action   = "ssm:StartSession"
        Resource = "arn:aws:ec2:eu-west-2:*:instance/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/Project" = "Portfolio" }
          BoolIfExists = { "ssm:SessionDocumentAccessCheck" = "true" }
        }
      },
      {
        Sid      = "PortForwardingDocumentOnly"
        Effect   = "Allow"
        Action   = "ssm:StartSession"
        Resource = "arn:aws:ssm:eu-west-2::document/AWS-StartPortForwardingSession"
      },
      {
        # Imported as found. Limiting this to the caller's own sessions is a
        # planned follow-up change.
        Sid      = "EndOwnSessions"
        Effect   = "Allow"
        Action   = ["ssm:TerminateSession", "ssm:ResumeSession"]
        Resource = "arn:aws:ssm:*:*:session/*"
      },
      {
        Sid      = "FindTheInstance"
        Effect   = "Allow"
        Action   = ["ec2:DescribeInstances", "ssm:DescribeInstanceInformation"]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Account assignments: the whole access model in one table.
# ---------------------------------------------------------------------------

locals {
  account_ids = {
    mgmt     = aws_organizations_organization.this.master_account_id
    security = aws_organizations_account.security.id
    dev      = aws_organizations_account.dev.id
  }

  permission_set_arns = {
    admin           = aws_ssoadmin_permission_set.admin.arn
    auditor         = aws_ssoadmin_permission_set.auditor.arn
    developer       = aws_ssoadmin_permission_set.developer.arn
    portfolio_admin = aws_ssoadmin_permission_set.portfolio_admin.arn
  }

  assignments = {
    "admin-mgmt"          = { permission_set = "admin", group = "Platform-Admins", account = "mgmt" }
    "admin-security"      = { permission_set = "admin", group = "Platform-Admins", account = "security" }
    "admin-dev"           = { permission_set = "admin", group = "Platform-Admins", account = "dev" }
    "auditor-mgmt"        = { permission_set = "auditor", group = "Security-Audit", account = "mgmt" }
    "auditor-security"    = { permission_set = "auditor", group = "Security-Audit", account = "security" }
    "auditor-dev"         = { permission_set = "auditor", group = "Security-Audit", account = "dev" }
    "developer-dev"       = { permission_set = "developer", group = "Developers", account = "dev" }
    "portfolio_admin-dev" = { permission_set = "portfolio_admin", group = "Developers", account = "dev" }
  }
}

resource "aws_ssoadmin_account_assignment" "this" {
  provider = aws.mgmt
  for_each = local.assignments

  instance_arn       = local.sso_instance_arn
  permission_set_arn = local.permission_set_arns[each.value.permission_set]
  principal_type     = "GROUP"
  principal_id       = data.aws_identitystore_group.this[each.value.group].group_id
  target_type        = "AWS_ACCOUNT"
  target_id          = local.account_ids[each.value.account]
}
