# Design Decisions

Key decisions made while building this landing zone, with alternatives considered.

## D-001: AWS Organizations built manually instead of using AWS Control Tower

**Decision:** Building the AWS Organization, OUs, SCPs, organization CloudTrail and central
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
- **Cost:** Control Tower uses AWS Config as part of its governance model; however, AWS Config can
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
provisioning or a managed control library. Rather, security and configuration are checked
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

**Evidence:** [organisation structure](evidence/README.md#accounts-and-root-access)

## D-002: Using one Security account for logs and security tooling

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

**Evidence:** [Identity Center, MFA and group access](evidence/README.md#identity)

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

**Evidence:** [SCP test B](evidence/README.md#guardrails-scps-and-tag-policy), [F-003 central logs](evidence/README.md#logging)

## D-005: GuardDuty enabled for the whole organisation, managed from the Security account

**Decision:** GuardDuty is enabled in eu-west-2 for every account in the organisation. The Security account is the delegated administrator, so all findings are viewed and managed there. Auto-enable is set for all accounts, so a new account joins with GuardDuty already on.

**Enabled:** foundational detection (CloudTrail management events, VPC flow logs and DNS logs) and S3 Protection. Together these cover everything that runs today.

**Not enabled:** each of these can be turned on from the Security account when a workload needs it.

- EKS audit logs, RDS login events and Lambda network logs: no EKS, RDS or Lambda is in use.
- Runtime Monitoring (EC2, ECS, EKS): it installs an agent on servers and creates VPC endpoints, which would change the network design and add cost.
- Malware Protection for EC2: extra cost per scan. Foundational detection still raises findings.
- AI Protection: no AI services are in use, and it adds a CloudTrail service-linked channel to every account.

**Why the Security account:** threat detection is managed outside the management account, which follows the same separation as D-002.

**Management account:** it cannot be enrolled by the delegated administrator and had to turn GuardDuty on itself first (F-007).

**Cost control:** each account has a 30-day free trial. The GuardDuty Usage page is reviewed before the trial ends.

**Evidence:** [GuardDuty members, plans and sample findings](evidence/README.md#threat-detection)

## D-006: Prowler on demand instead of Security Hub and AWS Config

**Decision:** Security settings are checked with Prowler, run on demand with the read-only Auditor role, instead of turning on AWS Security Hub and AWS Config across the organisation.

**Why:**

- Security Hub and Config are charged for every check and every recorded resource change, in every account and every region where they run. For a short-lived project with a small budget, they would be one of the largest ongoing costs.
- Prowler is free, runs the same CIS benchmark checks, and needs only read access.
- GuardDuty and the organisation CloudTrail trail still run all the time, so threat detection and the audit trail do not depend on scans.

**Trade-offs:**

- Settings that drift between scans are not noticed until the next scan.
- There is no history of how each resource's settings changed over time (the AWS Config timeline).
- Prowler's Security Hub and AWS Config checks fail. They are deferred, each with a plan, in [prowler-triage.md](prowler-triage.md#deferred-with-a-plan).
- `scp-protect-security` already stops Config and Security Hub from being turned off, so they are protected as soon as they are turned on.

**In production:** Security Hub and Config would be enabled for the whole organisation, with the Security account as delegated administrator, the CIS standard turned on, and findings from every account collected in eu-west-2.

**Evidence:** [Prowler scans before and after fixes](evidence/README.md#security-review-prowler)

## D-007: Terraform state is stored locally, one state per project

**Decision:** Each project has its own Terraform state file, kept on the local machine and never committed: one for the landing zone and one for the portfolio workload.

**Why two states:**

- A `terraform destroy` in the portfolio cannot touch the landing zone, and the reverse.
- Each project can be planned, reviewed and changed on its own, the same way a platform team and an application team work.
- The portfolio reads the landing zone network through data sources (by tag) and never manages it.

**Why local state:**

- The environment is short-lived and will be torn down after the project.
- A remote backend needs its own bucket and access controls to be set up first, which adds work without adding value for a single operator.

**Risks and how they are handled:**

| Risk | Handling |
|---|---|
| State contains account IDs, email addresses and every resource setting | `*.tfstate`, `*.tfstate.*` and `*.tfvars` are git-ignored; the disk is encrypted |
| State could contain secrets | Parameter Store SecureString values are deliberately not managed by Terraform |
| Losing the state file | Terraform keeps a backup copy; every resource can be imported again |
| No locking | One operator only |

**In production:** state would live in an S3 backend in a dedicated account, with versioning, KMS encryption, state locking (`use_lockfile`), and access limited to the deployment roles.

## D-008: How the existing environment was brought into Terraform

**Decision:** Everything built in the console was imported into Terraform without changing it, using read-only roles, in small stages.

**How:**

1. **Read-only by default.** Each AWS profile is a Terraform variable whose default is an audit (read-only) role. A write role is chosen on the command line for one account and one change only, for example `-var security_profile=sec-admin`. A normal `terraform plan` can never change anything.
2. **Inventory first.** Before each stage, read-only CLI commands listed exactly what existed. Only existing resources were imported; missing settings were recorded as gaps.
3. **Import blocks and generated code.** `import` blocks with `terraform plan -generate-config-out` produced a first draft of the code. The draft was then rewritten by hand: computed and empty values removed, IDs replaced with references, and comments added.
4. **Import as found, change separately.** Every import had to show `0 to change` before it was applied. Gaps found during inventory (for example F-009) were imported as they were and fixed afterwards as separate, reviewed changes.
5. **Saved plans.** Each import was applied from a saved plan (`-out`), so exactly the reviewed actions were carried out, once.
6. **Verify, then tidy.** After each import, a second plan had to show `No changes`. The temporary `imports.tf` was then deleted before committing.

**What the code avoids:**

- **No IDs typed by hand.** Resources refer to each other (for example, a bucket policy uses the distribution's `.arn`). This prevents the mistake in finding P-002 of the portfolio project.
- **No account IDs or email addresses in public code.** They come from resources, data sources, or the git-ignored `terraform.tfvars`.
- **Protected resources.** The organisation, member accounts, the CloudTrail log bucket and the Admin permission set have `prevent_destroy`, so a careless plan cannot remove them.

**Deliberately not managed by Terraform:**

| Item | Reason |
|---|---|
| The management account itself | Terraform runs from it, and it cannot be closed or removed like a member account |
| Member GuardDuty detectors | Controlled by the organisation setting "auto-enable ALL"; managing them one by one would conflict |
| GuardDuty per-plan settings | Not reliably importable; can be adopted later by applying the same values |
| Identity Center users and groups | Personal data; groups are looked up by name instead |
| IMDS account defaults | Cannot be imported; managing them requires a write |
| Parameter Store values | Secrets would be stored in plain text in the state (D-007) |

**Evidence:** [Terraform import results](evidence/README.md#terraform-import)
