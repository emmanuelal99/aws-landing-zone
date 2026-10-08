# Design Decisions

This file explains the main design decisions for the AWS landing zone, including the
alternatives considered, the reasons for each choice and the trade-offs involved. The
landing zone is a personal project: the final environment will be
validated, imported into Terraform and tested before teardown.

## D-001: Build AWS Organizations manually instead of using AWS Control Tower

**Decision:** Build the AWS Organization, OUs, SCPs, organization CloudTrail and central
logging manually using AWS Organizations. The completed environment will then be imported
into Terraform.

**Context:** This is a small production-style landing zone project with four main goals:

- Understand how each security control works
- Keep costs as low as possible
- Import the environment into Terraform
- Make the environment easy to tear down

**Why not Control Tower?**

- **Understanding:** Building the landing zone manually makes it easier to understand and
  explain each SCP, bucket policy, CloudTrail setting and other control.
- **Cost:** Control Tower uses AWS Config as part of its governance model. AWS Config can
  create additional costs, so this project keeps the initial setup smaller and limits
  configuration monitoring.
- **Infrastructure as Code:** Control Tower manages many resources through CloudFormation
  StackSets. Managing the same resources through Terraform would add complexity and could
  create resource drift.
- **Teardown:** Removing a Control Tower environment involves additional steps and managed
  accounts, which is unnecessary for this small project.
- **Design freedom:** Building the environment manually allows the OUs and SCPs to be
  designed specifically for the project.

**Trade-offs:** The project does not have Control Tower features such as automated account
provisioning or a managed control library. Instead, security and configuration are checked
using:

- AWS Organizations and SCPs
- Organization CloudTrail
- IAM Access Analyzer
- Prowler security scans
- `terraform plan` after the environment is imported

**Production approach:** For a larger organisation with many AWS accounts, AWS Control Tower
or Landing Zone Accelerator would be more appropriate. The security concepts used in this
project still apply.

| Control Tower concept | This project |
|---|---|
| Preventive controls | SCPs for region restriction, protection of security services, and blocking long-lived credentials |
| Detective controls | IAM Access Analyzer, EventBridge alerts and Prowler |
| Log Archive account | Security account with the central CloudTrail log bucket |
| Audit account | Security account with delegated security administration and audit access |
| Account Factory | AWS Organizations account creation with OU, tag and SCP controls |

## D-002: Use one Security account for logs and security tooling

**Decision:** A single Security account is used for the central CloudTrail log bucket and
security services.

**Why:** This keeps the project simple and reduces the number of accounts that need to be
managed. It also keeps security logs and tooling separate from the management and workload
accounts.

**Trade-off:** In a larger production environment, logging and security administration
would normally be separated into different accounts. This provides stronger isolation if
one security account is compromised.

## D-003: SSO-only human access with no IAM users

**Decision:** All human access uses IAM Identity Center with MFA and short-lived role
sessions. The management account has no IAM users or IAM groups. A legacy IAM user and
group left over from earlier work were found during the Prowler scan and deleted.

**Why:**

- Avoids long-lived access keys
- Reduces the risk of leaked credentials
- Provides centralised access management
- Makes access easier to review and remove

SCPs do not apply to the AWS management account, so the management account must be
protected separately.

**Break-glass access:** The management account root user is protected with MFA. Root
sign-in activity is monitored with an EventBridge alert.

## D-004: Restrict all activity to eu-west-2

**Decision:** Use an SCP to deny all actions outside eu-west-2 in member accounts, while
allowing required global AWS services.

**Why:**

- Reduces the number of regions that need to be monitored
- Reduces the chance of resources being created in an unexpected region
- Helps keep data in the UK
- Limits where compromised credentials can be used

**Trade-off:** Some AWS services are global or run through us-east-1, so they need specific
exceptions in the SCP. For example, CloudFront and its certificates (ACM) must be allowed
because CloudFront certificates are created in us-east-1. Blocking all actions also means
read-only tasks in other regions, such as viewing CloudTrail Event history in us-east-1,
are denied too.

The management account is not covered by this SCP because SCPs do not apply to the AWS
Organizations management account.
