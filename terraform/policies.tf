# Organisation guardrails: SCPs and the tag policy, and where they are attached.
# Policy content is read from the JSON files in ../policies, so the documented
# policies and the live policies are always the same files.

locals {
  policies_dir = "${path.module}/../policies"

  # Every OU gets the same guardrails.
  guardrail_ous = {
    security  = aws_organizations_organizational_unit.security.id
    workloads = aws_organizations_organizational_unit.workloads.id
    sandbox   = aws_organizations_organizational_unit.sandbox.id
  }

  policy_tags = { Project = "Portfolio", Env = "Management", Owner = "Emmy" }
}

# ---------------------------------------------------------------------------
# Service control policies
# ---------------------------------------------------------------------------

resource "aws_organizations_policy" "region_lock" {
  provider    = aws.mgmt
  name        = "scp-region-lock"
  description = "Deny all regional actions outside eu-west-2; global services exempt"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${local.policies_dir}/scp/scp-region-lock.json")
  tags        = local.policy_tags
}

resource "aws_organizations_policy" "protect_security" {
  provider    = aws.mgmt
  name        = "scp-protect-security"
  description = "Prevent disabling logging and threat detection, except by the Admin break-glass role"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${local.policies_dir}/scp/scp-protect-security.json")
  tags        = local.policy_tags
}

resource "aws_organizations_policy" "baseline_deny" {
  provider    = aws.mgmt
  name        = "scp-baseline-deny"
  description = "Deny leaving the org, long-lived IAM credentials, and untagged EC2 instances"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${local.policies_dir}/scp/scp-baseline-deny.json")
  tags        = local.policy_tags
}

resource "aws_organizations_policy" "deny_leave_and_close" {
  provider    = aws.mgmt
  name        = "DenyLeaveAndCloseAccount"
  description = "Prevents member accounts from leaving the organization and self closure"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${local.policies_dir}/scp/scp-deny-leave-and-close.json")
  tags        = local.policy_tags
}

# ---------------------------------------------------------------------------
# Tag policy
# ---------------------------------------------------------------------------

resource "aws_organizations_policy" "tag_standard" {
  provider    = aws.mgmt
  name        = "tag-policy-standard"
  description = "Standard tag keys and allowed values (Project, Owner, Env); enforces exact casing and values on EC2 resources"
  type        = "TAG_POLICY"
  content     = file("${local.policies_dir}/tag/tag-policy-standard.json")
  tags        = local.policy_tags
}

# ---------------------------------------------------------------------------
# Attachments: one block per policy, repeated for every OU with for_each
# ---------------------------------------------------------------------------

resource "aws_organizations_policy_attachment" "region_lock" {
  provider  = aws.mgmt
  for_each  = local.guardrail_ous
  policy_id = aws_organizations_policy.region_lock.id
  target_id = each.value
}

resource "aws_organizations_policy_attachment" "protect_security" {
  provider  = aws.mgmt
  for_each  = local.guardrail_ous
  policy_id = aws_organizations_policy.protect_security.id
  target_id = each.value
}

resource "aws_organizations_policy_attachment" "baseline_deny" {
  provider  = aws.mgmt
  for_each  = local.guardrail_ous
  policy_id = aws_organizations_policy.baseline_deny.id
  target_id = each.value
}

resource "aws_organizations_policy_attachment" "tag_standard" {
  provider  = aws.mgmt
  for_each  = local.guardrail_ous
  policy_id = aws_organizations_policy.tag_standard.id
  target_id = each.value
}

# Attached at the root so it covers every OU and every account added later.
resource "aws_organizations_policy_attachment" "deny_leave_and_close" {
  provider  = aws.mgmt
  policy_id = aws_organizations_policy.deny_leave_and_close.id
  target_id = aws_organizations_organization.this.roots[0].id
}
