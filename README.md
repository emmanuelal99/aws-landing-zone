# AWS Landing Zone

A secure, multi-account AWS foundation built with AWS Organizations, IAM Identity Center and service control policies, then brought under Terraform. Every account inherits guardrails, threat detection, central logging and cost alerts from the moment it joins.

The first workload running on it is a Django portfolio site: [secure-django-portfolio](https://github.com/emmanuelal99/secure-django-portfolio).

**Evidence:** screenshots of every control working are in the [evidence gallery](docs/evidence/README.md).

## Architecture

```
AWS Organization
├── Root ............................ DenyLeaveAndCloseAccount
├── Security OU ..................... region lock, protect-security, baseline-deny, tag policy
│   └── Security account ............ GuardDuty admin, Access Analyzer admin, CloudTrail log bucket
├── Workloads OU .................... same guardrails
│   └── Dev account ................. VPC, private subnet, S3 endpoint, workloads
└── Sandbox OU ...................... same guardrails (for experiments)

Management account .................. Organizations, Identity Center, org CloudTrail, budgets
```

```
Dev VPC 10.0.0.0/16 (eu-west-2)
├── Public subnet  10.0.0.0/28 ...... NAT gateway only, switched on when needed
├── Private subnet 10.0.1.0/24 ...... workloads, no public IP addresses
├── S3 gateway endpoint ............. private, free access to S3
└── Internet gateway ................ used by the NAT gateway and CloudFront VPC origins
```

## What is built

| Area | Controls | Evidence |
|---|---|---|
| **Accounts** | Separate management, Security and Dev accounts, grouped into OUs. Root user locked down, with a sign-in alert. | [Accounts](docs/evidence/README.md#accounts-and-root-access) |
| **Guardrails** | SCPs: region lock to `eu-west-2`, no IAM users or access keys, no disabling of security services, no leaving the organisation. Tag policy for `Project`, `Env` and `Owner`. | [SCP and tag policy tests](docs/evidence/README.md#guardrails-scps-and-tag-policy) |
| **Identity** | IAM Identity Center only. Access is given to groups, never to users. Admin sessions last 1 hour. No IAM users exist. | [Identity](docs/evidence/README.md#identity) |
| **Threat detection** | GuardDuty in every account, managed from the Security account. IAM Access Analyzer for the whole organisation. | [Threat detection](docs/evidence/README.md#threat-detection) |
| **Logging** | One organisation CloudTrail trail with log file validation. Logs are stored in the Security account, in a bucket that only the break-glass Admin role can weaken. | [Logging](docs/evidence/README.md#logging) |
| **Account defaults** | EBS encryption, IMDSv2, S3 Block Public Access, password policy, ECR scan on push | [Prowler results](docs/evidence/README.md#security-review-prowler) |
| **Network** | Private subnets with no internet route by default. A NAT gateway is created on demand by script and removed after use. | [Network](docs/evidence/README.md#network) |
| **Cost** | Monthly budget alerts at 80% and 100%, daily anomaly alerts for unusual spending of $3 or more | [Cost](docs/evidence/README.md#cost) |

## Infrastructure as code

The environment was first built in the console to understand each service, then imported into Terraform without changing anything (see [D-008](docs/design-decisions.md#d-008-how-the-existing-environment-was-brought-into-terraform)). The import results are in the [evidence gallery](docs/evidence/README.md#terraform-import).

| File | Contents |
|---|---|
| `terraform/organization.tf` | Organisation, OUs and member accounts (protected with `prevent_destroy`) |
| `terraform/policies.tf` | SCPs and the tag policy, read from the JSON files in `policies/` |
| `terraform/identity.tf` | Permission sets, policies and the group-to-account access table |
| `terraform/security_services.tf` | GuardDuty and other delegated administrators |
| `terraform/logging.tf` | Organisation CloudTrail and its protected log bucket |
| `terraform/baseline.tf` | Account-wide security settings in every account |
| `terraform/network.tf` | Dev VPC, subnets, route tables and S3 endpoint |
| `terraform/cost.tf` | Budget and cost anomaly alerts |

**Safe by default:** every Terraform provider uses a read-only audit role unless a write role is chosen on the command line for one account and one change. A normal `terraform plan` can never change anything.

**No private data in the code:** account IDs, email addresses and resource IDs come from references, data sources, or a git-ignored `terraform.tfvars`.

## Security review

The accounts were scanned with [Prowler](https://github.com/prowler-cloud/prowler) against CIS, and every finding was fixed, accepted or deferred with a written reason ([prowler-triage.md](docs/prowler-triage.md)). Screenshots of each scan: [Prowler evidence](docs/evidence/README.md#security-review-prowler).

| Account | Failed before | Failed after |
|---|---|---|
| Management | 75 | 72 |
| Security | 27 | 24 |
| Dev (platform findings) | 28 | 26 (after GuardDuty plan checks were added) |

Some failures are deliberate design choices. For example, `vpc_different_regions` fails because the region lock allows only one region ([D-004](docs/design-decisions.md#d-004-restrict-all-activity-to-eu-west-2)).

## Findings

Problems found while building and importing, each with the cause, the fix and the lesson ([findings.md](docs/findings.md)). Highlights:

- **[F-002](docs/findings.md#f-002-default-cost-anomaly-alert-could-not-fire-for-this-account):** the default cost anomaly alert only fired for spending over $100 **and** 40%, and only emailed the root address.
- **[F-003](docs/findings.md#f-003-region-lock-blocks-investigation-in-other-regions-but-central-logs-keep-the-evidence):** the region lock also blocks read actions in other regions, even for Admin. CloudTrail evidence showed the SCP responsible.
- **[F-007](docs/findings.md#f-007-guardduty-could-not-be-turned-on-in-the-management-account-from-the-security-account):** the Security account could not turn on GuardDuty in the management account. The management account has to enable it first.
- **[F-008](docs/findings.md#f-008-read-only-auditor-role-could-not-read-cloudfront-function-code), [F-010](docs/findings.md#f-010-read-only-auditor-role-could-not-read-budgets-or-cost-anomaly-alerts):** the read-only Auditor role needed specific extra read actions to review CloudFront function code and cost guardrails.
- **[F-009](docs/findings.md#f-009-ebs-encryption-by-default-was-off-in-the-security-account):** EBS encryption by default was off in the Security account. Found while preparing the Terraform import, then fixed through Terraform.

## Design decisions

Each choice is recorded with its reasons and trade-offs ([design-decisions.md](docs/design-decisions.md)):

| ID | Decision |
|---|---|
| [D-001](docs/design-decisions.md#d-001-aws-organizations-built-manually-instead-of-using-aws-control-tower) | AWS Organizations built manually instead of with Control Tower |
| [D-002](docs/design-decisions.md#d-002-using-one-security-account-for-logs-and-security-tooling) | One Security account for security services and logs |
| [D-003](docs/design-decisions.md#d-003-sso-only-human-access-with-no-iam-users) | IAM Identity Center only, no IAM users |
| [D-004](docs/design-decisions.md#d-004-restrict-all-activity-to-eu-west-2) | Region lock to `eu-west-2` for every action |
| [D-005](docs/design-decisions.md#d-005-guardduty-enabled-for-the-whole-organisation-managed-from-the-security-account) | GuardDuty for the whole organisation, with only the plans in use |
| [D-006](docs/design-decisions.md#d-006-prowler-on-demand-instead-of-security-hub-and-aws-config) | Prowler on demand instead of Security Hub and Config, to avoid ongoing cost |
| [D-007](docs/design-decisions.md#d-007-terraform-state-is-stored-locally-one-state-per-project) | Local Terraform state, one state per project |
| [D-008](docs/design-decisions.md#d-008-how-the-existing-environment-was-brought-into-terraform) | How the existing environment was imported into Terraform |

## Running a workload on the platform

[workload-onboarding.md](docs/workload-onboarding.md) explains what the platform provides and what a workload must do, with an onboarding checklist.

## Repository structure

```
policies/scp/       Service control policies (source for Terraform)
policies/tag/       Tag policy (source for Terraform)
policies/resource/  Resource policies, with IDs redacted
scripts/            nat-on.sh and nat-off.sh
terraform/          Terraform code for the whole landing zone
docs/               Design decisions, findings, Prowler triage, onboarding guide
docs/evidence/      Screenshots of each control, with private details covered
```

## Cost

The landing zone and the running portfolio workload cost under $5 a month. The NAT gateway, which is the main cost, exists only while it is in use.
