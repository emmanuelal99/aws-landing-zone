# Evidence

Screenshots of the landing zone controls working. Account IDs, email addresses, organisation and instance IDs, IP addresses, ARNs and file paths are covered with solid boxes or masked as `XXXXXXXXXXXX`.

The reasons behind each control are in [design-decisions.md](../design-decisions.md). Problems found while building are in [findings.md](../findings.md).

| Section | Related |
|---|---|
| [Accounts and root access](#accounts-and-root-access) | [D-001](../design-decisions.md#d-001-aws-organizations-built-manually-instead-of-using-aws-control-tower), [D-002](../design-decisions.md#d-002-using-one-security-account-for-logs-and-security-tooling) |
| [Guardrails: SCPs and tag policy](#guardrails-scps-and-tag-policy) | [D-004](../design-decisions.md#d-004-restrict-all-activity-to-eu-west-2), [F-001](../findings.md#f-001-look-alike-tag-keys-on-an-scp) |
| [Identity](#identity) | [D-003](../design-decisions.md#d-003-sso-only-human-access-with-no-iam-users) |
| [Logging](#logging) | [D-002](../design-decisions.md#d-002-using-one-security-account-for-logs-and-security-tooling), [F-003](../findings.md#f-003-region-lock-blocks-investigation-in-other-regions-but-central-logs-keep-the-evidence) |
| [Threat detection](#threat-detection) | [D-005](../design-decisions.md#d-005-guardduty-enabled-for-the-whole-organisation-managed-from-the-security-account), [F-007](../findings.md#f-007-guardduty-could-not-be-turned-on-in-the-management-account-from-the-security-account) |
| [Cost](#cost) | [F-002](../findings.md#f-002-default-cost-anomaly-alert-could-not-fire-for-this-account) |
| [Network](#network) | [F-004](../findings.md#f-004-private-subnet-not-associated-with-its-route-table) |
| [Security review: Prowler](#security-review-prowler) | [D-006](../design-decisions.md#d-006-prowler-on-demand-instead-of-security-hub-and-aws-config), [prowler-triage.md](../prowler-triage.md) |
| [Terraform import](#terraform-import) | [D-007](../design-decisions.md#d-007-terraform-state-is-stored-locally-one-state-per-project), [D-008](../design-decisions.md#d-008-how-the-existing-environment-was-brought-into-terraform) |

---

## Accounts and root access

![Organisation structure](organization-structure.png)
**Organisation structure: Security, Workloads and Sandbox OUs**

![Management account root user](root-mfa-no-access-keys.png)
**Management account root user: MFA on, no access keys**

![Member account root credentials](member-root-credentials-removed.png)
**Member accounts: root user credentials removed**

![Root sign-in alert](root-sign-in-alert.png)
**Root sign-in alert email**

> A test sign-in with the root user sent this alert email. Root is kept for break-glass use only, so any root sign-in should raise an alert.

---

## Guardrails: SCPs and tag policy

![Policy types enabled](policy-types-enabled.png)
**SCPs and tag policies enabled for the organisation**

![Policies on the Dev account](workloads-ou-policies.png)
**Policies applied to the Dev account, inherited from Root and the Workloads OU**

![SCP test A](scp-test-a-no-iam-users.png)
**SCP test A: Admin cannot create an IAM user**

![SCP test B](scp-test-b-region-lock.png)
**SCP test B: region lock blocks us-east-1, allows eu-west-2**

![SCP test C](scp-test-c-protect-security.png)
**SCP test C: only Admin can delete a CloudTrail trail**

> The Developer role is blocked by the SCP. For Admin, `TrailNotFoundException` means the SCP let the call through and AWS then found no trail with that test name. Nothing was deleted.

![SCP test D](scp-test-d-ec2-project-tag.png)
**SCP test D: an EC2 instance cannot launch without a `Project` tag**

> Both launches used `--dry-run`, so no instance was created. `DryRunOperation` means the request would have succeeded.

![Tag policy test E](tag-policy-test-e.png)
**Tag policy test E: wrong tag value rejected, correct value accepted**

> `Project=portfolio` (lower case) was rejected with `TagPolicyViolation`. With `Project=Portfolio`, the request passed the tag policy and only failed because a group with the same test name already existed. The test group was then deleted.

![Effective tag policy](effective-tag-policy.png)
**Effective tag policy for the Dev account**

![Look-alike tag keys](f-001-tag-key-typos.png)
**F-001: look-alike tag keys with a trailing space**

---

## Identity

![Identity Center region](identity-center-london.png)
**IAM Identity Center created in Europe (London)**

![MFA settings](mfa-every-sign-in.png)
**MFA required at every sign-in**

![Permission sets](permission-sets.png)
**Permission sets: Admin, Auditor, Developer and PortfolioAdmin**

![Dev account assignments](dev-account-group-assignments.png)
**Dev account access given to groups only**

---

## Logging

![Organisation trail](org-cloudtrail.png)
**Organisation CloudTrail trail: all accounts, all regions, log file validation on**

![Denied calls in central logs](f-003-central-logs-denied-calls.png)
**F-003: calls denied by the region lock, found in the central log bucket**

> Four CloudTrail lookups by Admin and one VPC listing by Developer, all in us-east-1, all denied by the SCP. The records were read from the log bucket in the Security account, which Dev users cannot reach.

---

## Threat detection

![GuardDuty members and features](guardduty-members-features.png)
**GuardDuty: management and Dev accounts enabled as members, and the plans turned on in Dev**

![GuardDuty sample findings](guardduty-sample-findings.png)
**GuardDuty sample findings seen from the Security account with the Auditor role**

> These are `[SAMPLE]` findings, generated on purpose to check that findings from member accounts reach the Security account. They were archived after the test.

![Access Analyzer](access-analyzer-organization.png)
**IAM Access Analyzer with the whole organisation as the zone of trust**

---

## Cost

![Budget](budget.png)
**Monthly budget: $15**

![Budget alerts](budget-alerts.png)
**Budget alerts at 80% and 100%**

![Cost anomaly alerts](cost-anomaly-alerts.png)
**F-002: cost anomaly alerts at $3, sent daily**

---

## Network

![Dev VPC resource map](dev-vpc-resource-map.png)
**Dev VPC: public and private subnets, route tables, internet gateway and S3 endpoint**

![Private route table](f-004-private-route-table.png)
**F-004: private subnet associated with `portfolio-private-rt`**

> Taken while the NAT gateway was switched on. When it is off, the `0.0.0.0/0` route is removed and only the S3 endpoint and local routes remain.

---

## Security review: Prowler

![Management account before](prowler-management-before.png)
**Management account: before fixes (75 failed)**

![Management account after](prowler-management-after.png)
**Management account: after fixes (72 failed)**

![Security account before](prowler-security-before.png)
**Security account: before fixes (27 failed)**

![Security account after](prowler-security-after.png)
**Security account: after fixes (24 failed)**

![Dev account before](prowler-dev-before.png)
**Dev account: before fixes (50 failed)**

![Dev account after](prowler-dev-after.png)
**Dev account: after fixes (47 failed)**

> The Dev scan includes the portfolio workload. 26 of the 47 open findings belong to the platform and are triaged in [prowler-triage.md](../prowler-triage.md#dev-account-scan-phase-9). The rest are triaged in the portfolio repository. The 7 GuardDuty failures in the "after" scan are plan checks that only appear once GuardDuty is on; most of these plans are off on purpose (D-005).

---

## Terraform import

![Network import](terraform-network-no-changes.png)
**Network imported: no changes**

![Account settings import](terraform-account-settings-imported.png)
**Account-wide settings imported in three accounts: 0 added, 0 changed**

![Organisation import](terraform-organization-imported.png)
**Organisation, OUs and accounts imported, followed by a full plan with no changes**
