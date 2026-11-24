# Findings

Issues found during landing zone setup and testing, along with their causes and fixes.

## F-001: Look-alike tag keys on an SCP

**Found during:** activating cost allocation tags process.
**Severity:** Low (governance/hygiene, no cost impact; SCPs are not billable).

**Observation:** Cost allocation tags listed `Project ` and `Env ` (trailing space)
alongside the correct keys `Project` and `Env`.

**Investigation:** Searched all accounts with the Resource Groups Tagging API
(management account: all regions; member accounts: eu-west-2 only because of the
region lock SCP). One match: the region lock SCP.

    arn:aws:organizations::<MGMT_ACCOUNT_ID>:policy/<ORG_ID>/service_control_policy/p-xxxxxxxx

**Root cause:** Tag typed with a trailing space at creation. The tag policy did not
catch it because:
1. Tag policies only govern the exact keys they define; `Project ` is a different key.
2. The tag policy is attached to OUs, not the management account where SCPs live.
3. `organizations:policy` is not in `enforced_for`.

**Fix:** Removed the bad keys, added the correct ones, and re-ran the search
(no results). Only the clean keys were activated as cost allocation tags.

**Related:** The SCP inventory also found an untracked root-level SCP
(`DenyLeaveAndCloseAccount`) from earlier work. Verified its content, kept it as a valid
control (blocks member account self-closure, which no other SCP covered), then tagged
it and added it as `policies/scp/scp-deny-leave-and-close.json`.

**Lesson:** Tag policies are preventive for known keys only. A detective control
(AWS Config `required-tags` rule or a scheduled tagging-API sweep) is needed to catch
look-alike keys.

**Evidence:** [look-alike tag keys](evidence/README.md#guardrails-scps-and-tag-policy)

## F-002: Default cost anomaly alert could not fire for this account

**Found during:** Cost Anomaly Detection setup process
**Severity:** Medium (a detective control that looked enabled but was effectively off)

**Observation:** AWS auto-created `Default-Services-Monitor` with a subscription
threshold of `$100 AND 40%`, sent only to the root account email.

**Root cause:** AWS defaults are sized for accounts with meaningful spend. With daily costs of only pennies, an anomaly would need to exceed $100 and 40% before triggering an alert, meaning a leaked credential or forgotten resource could already become costly.

**Fix:** Renamed the monitor (`portfolio-services-monitor`) and subscription
(`portfolio-anomaly-alerts`), set a single absolute threshold of $3 (percentage removed
to avoid alert fatigue on a near-zero baseline), added a monitored inbox, and applied
the standard tags. Monitor history was kept by editing instead of recreating.

**Lesson:** "Enabled" is not the same as "effective". Defaults must be checked against
the environment's actual risk profile.

**Evidence:** [cost anomaly alerts](evidence/README.md#cost)

## F-003: Region lock blocks investigation in other regions, but central logs keep the evidence

**Found during:** checking that blocked actions are logged
**Severity:** Informational (the control works as designed; the trade-off is recorded)

**What happened:** In the Dev account, the Admin role tried to view CloudTrail Event
history in us-east-1. The request was denied four times by the region lock SCP, even
though Admin has full permissions. A separate test with the Developer role trying to
list networks (DescribeVpcs) in us-east-1 was also denied.

**What the logs showed:** All five denied actions were found in the organisation's
central log bucket in the Security account, recording who tried, what they tried,
when, and why it was denied. Each error message also named the exact SCP that blocked the action (the region lock), which confirms that the block came from the organisation-wide rule, not from missing IAM permissions.

**Why this matters:**
- SCPs limit every role in a member account, including Admin.
- The region lock blocks reading as well as creating, so even viewing data in other
  regions is denied.
- The people being monitored cannot reach the evidence. Logs are stored in a separate
  account that Dev users cannot access, change or delete.

**Trade-off:** Investigating activity in another region cannot be done from inside a
member account. It must be done from the central log bucket in the Security account.

**Evidence:** [denied calls in the central log bucket](evidence/README.md#logging), [SCP test B](evidence/README.md#guardrails-scps-and-tag-policy)

## F-004: Private subnet not associated with its route table

**Found during:** Step 6.7 (Session Manager connection failed with TargetNotConnected)
**Severity:** Low (availability issue; failed safe)

**What happened:** The SSM agent could not reach Systems Manager ("i/o timeout").
Diagnosis showed the NAT, internet gateway, security group and DNS were all correct,
but the private subnet had never been associated with portfolio-private-rt. It was
silently using the VPC's main route table, which only has the local route.

**Fix:** Associated portfolio-private-a with portfolio-private-rt and rebooted. The
agent registered within minutes.

**Lesson:** Subnets without an explicit association use the main route table. Keeping
the main route table local-only means this mistake fails safe (no internet access)
rather than exposing the subnet.

**Evidence:** [private route table association](evidence/README.md#network)

## F-005 and F-006: moved to the portfolio repository

These two findings are about the portfolio workload, not the platform, so they are recorded with the workload:

- **F-005** is now [P-001: Session Manager not ready straight after the NAT is turned on](https://github.com/emmanuelal99/secure-django-portfolio/blob/main/docs/findings.md#p-001-session-manager-not-ready-straight-after-the-nat-is-turned-on)
- **F-006** is now [P-002: Media images did not load through CloudFront](https://github.com/emmanuelal99/secure-django-portfolio/blob/main/docs/findings.md#p-002-media-images-did-not-load-through-cloudfront)

The numbers F-005 and F-006 are not reused.

## F-007: GuardDuty could not be turned on in the management account from the Security account

**Found during:** adding every account to GuardDuty from the Security account (the delegated administrator)
**Severity:** Medium (the account with the most power in the organisation was not monitored)

**What happened:** The Dev account joined GuardDuty automatically, but adding the management account as a member from the Security account failed.

**Cause:** The delegated administrator can manage member accounts, but it cannot turn GuardDuty on in the management account. "Auto-enable" applies to member accounts only. The management account has to create its own GuardDuty detector first.

**Fix:** A detector was created in the management account with its own Admin role:

```bash
aws guardduty create-detector --enable --profile mgmt-admin
```

The management account was then added as a member from the Security account, and is now managed there with the other accounts.

**Evidence:** [GuardDuty members and plans](evidence/README.md#threat-detection)

**Lesson:** The management account is a special case for many organisation features. SCPs do not apply to it either (D-004). After turning on any organisation-wide service, the management account should be checked on its own.

## F-008: Read-only Auditor role could not read CloudFront function code

**What happened:** The Terraform import of the portfolio workload, run with the read-only `dev-audit` profile, failed with `AccessDenied` on `cloudfront:DescribeFunction`.

**Cause:** AWS read-only managed policies leave out the actions that return CloudFront function code, because function code can contain sensitive logic.

**Fix:** Two read-only actions, `cloudfront:DescribeFunction` and `cloudfront:GetFunction`, were added to the Auditor permission set's inline policy. The Auditor still cannot change or publish functions.

**Lesson:** Read-only roles may need specific extra read permissions to review resources that contain code. Adding only the exact actions needed keeps the import read-only without widening access.

## F-009: EBS encryption by default was off in the Security account

**What happened:** While taking stock of account-wide settings for the Terraform import, EBS encryption by default was found to be **off** in the Security account. It was on in the management and Dev accounts.

**Risk:** No volumes existed in the Security account, so nothing was unencrypted. Any volume created later would have been unencrypted unless encryption was chosen by hand.

**How it was handled:**

1. The setting was **imported as found** (`enabled = false`), so the import recorded reality exactly.
2. The code was changed to `enabled = true` and reviewed in a **read-only** plan first, which showed exactly one change.
3. The change was applied with a **write role for the Security account only** (`-var security_profile=sec-admin`). The other accounts stayed on their read-only roles.
4. The result was confirmed independently with the read-only role, and a final plan showed no changes.

**Lessons:**

- Taking inventory for infrastructure as code finds configuration gaps that were missed during manual setup.
- Import first, change second. Keeping the two apart makes every change visible and reviewable.
- Read-only access is the default for Terraform in this project. Write access is chosen per account, per change.

## F-010: Read-only Auditor role could not read budgets or cost anomaly alerts

**What happened:** While taking stock of the cost guardrails for the Terraform import, the read-only `mgmt-audit` profile returned `AccessDenied` on `budgets:ViewBudget`, `ce:GetAnomalyMonitors` and `ce:GetAnomalySubscriptions`.

**Cause:** The Auditor permission set uses the AWS managed policies `SecurityAudit` and `ViewOnlyAccess`. Both leave out billing and cost data, which AWS treats as a separate area of access.

**Fix:** A second statement, `ReadCostGuardrails`, was added to the Auditor inline policy with five read-only actions: `budgets:ViewBudget`, `budgets:ListTagsForResource`, `ce:GetAnomalyMonitors`, `ce:GetAnomalySubscriptions` and `ce:ListTagsForResource`. The Auditor can review the guardrails but cannot change them, and has no access to invoices or payment details.

**Lessons:**

- This is the same pattern as F-008: read-only managed policies have deliberate gaps, and some reviews need specific extra read actions.
- Adding only the exact actions needed keeps the role narrow. A broad policy such as `Billing` or `ReadOnlyAccess` would also have fixed the error, but would have given far more access than the task needed.
