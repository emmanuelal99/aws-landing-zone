# Prowler Security Scan: Results and Triage

**Tool:** Prowler 5.44 (open-source cloud security scanner)
**Standard:** CIS AWS Foundations Benchmark v7.0, an industry checklist of security settings
**Access used:** A read-only Auditor role through single sign-on, so the scanner could look but not change anything
**Accounts scanned:** Management (all regions) and Security (London only, because the region lock blocks all other regions)

## Results before and after fixes

| Account | Failed (before → after) | Passed (before → after) |
|---|---|---|
| Management | 75 → 72 | 60 → 61 |
| Security | 27 → 24 | 23 → 26 |

**Why the failure count looks high:** Some checks run once per region. In the management
account, three checks (Security Hub, AWS Config and Access Analyzer) failed in each of
17 regions, which adds up to 51 failures from just three decisions. The number of
separate issues was much smaller.

## Fixed

| Finding | Severity | What was wrong | What was done |
|---|---|---|---|
| IAM user with console password and no MFA | High | An old IAM user from earlier work could sign in to the management account with only a password | User deleted. The management account now has no IAM users. |
| Admin rights through an IAM group | Critical | An old, empty IAM group still had full admin rights attached | Group deleted. Admin rights in the management account dropped from 3 holders to 1 (the single sign-on Admin role). |
| No password policy | Medium | No rules for IAM user passwords in the management and Security accounts | Policy set in both: at least 14 characters, all character types, last 24 passwords blocked, no forced expiry (following current NIST guidance) |
| Account-wide Block Public Access off | High | Any new S3 bucket in the Security account could have been made public | Block Public Access turned on for the whole Security account |
| Unknown delegated administrator | Critical | False alarm: the Security account was made a delegated administrator on purpose (for Access Analyzer), but the scanner did not know it was approved | Scanner settings updated with the approved account, so only unapproved accounts are flagged |
| Account-wide Block Public Access off in other accounts | High | Found by checking the remaining accounts after the Security account scan | Turned on in Dev (and any other account where it was off) before any buckets were created |

## Accepted (with reasons)

| Finding | Severity | Why it is accepted |
|---|---|---|
| Admin policy attached to the single sign-on Admin role | Critical | Some admin access is needed. This is the safest form: temporary sessions, MFA at sign-in, and access granted through a group that can be removed in one place. |
| Root user used recently (management account) | High | The root user was signed in to on purpose to test the root sign-in email alert. The alert worked. |
| Access Analyzer not in every region (management account) | Low | Access Analyzer runs once for the whole organisation from the Security account in London. Workloads are only allowed in London. |
| MFA Delete off on the log bucket | Medium | MFA Delete can only be turned on with root user access keys. The Security account has no root credentials at all, which is a stronger control. Protection comes instead from versioning and a bucket policy that blocks deleting logs or changing the bucket's settings. In production, S3 Object Lock would be used. |

## Deferred (with a plan)

| Finding | Severity | Plan |
|---|---|---|
| Security Hub off | High | Turn on in London only, during the final testing phase, within the 30-day free trial |
| AWS Config off | Medium | Turn on in London for the Dev account, with a rule that checks every resource has the required tags |
| 15 CloudWatch alarms for security events | Medium | Covered differently: EventBridge rules send alerts directly (root sign-in alert already working). The scanner only recognises the CloudWatch method. |
| Log encryption with a customer-managed key (KMS) | Medium | Optional, about $1 per month. Logs are already encrypted by S3, protected from deletion, checked for tampering, and only reachable over secure connections. |
| Access logging on the log bucket | Medium | Optional, low cost. Would record who reads the log files. |
| Logging every S3 file action | Low | Too noisy and costly across all accounts. Better turned on only for the website's media bucket. |
| Root user uses an app-based MFA instead of a hardware key | Critical | Option: replace it with a passkey, which cannot be phished |
| No AWS Support role | Low | Low priority |

## Lessons learned

- **Check the scanner's claims against the live system.** After the old IAM user was
  deleted, the scanner still reported it. AWS only rebuilds the report the scanner reads
  (the IAM credential report) every 4 hours. A direct check showed no IAM users.
- **Two identities can share a name.** An IAM user and a single sign-on user were both
  called "Emmanuel". MFA was on the single sign-on user only, which led to a false belief
  that the IAM user was protected. Each identity had to be checked separately.
- **Deleting a user does not delete its group.** The old admin group stayed behind with
  full admin rights and had to be removed separately.
- **"Turned on" is not the same as "set up correctly".** Several AWS defaults (such as the
  cost alert limit of $100) work technically but do not fit a small account.

- **A clean scan does not mean nothing is wrong.** By default, Prowler skips services
  that have no resources. The management and Dev accounts had no S3 buckets, so the
  account-wide Block Public Access check never ran there, and the setting was missing
  in both. It was found by checking each account directly. Scanner settings and blind
  spots should be understood, not just the results.

## Evidence

Screenshots (with account numbers and emails blurred) are in `evidence/`. Raw scan
reports are not published, because they list every resource and weakness in the accounts.



## Dev account scan (Phase 9)

This section covers the findings that belong to the platform: account-wide settings, identity, threat detection and the shared network. Findings about the portfolio workload itself (CloudFront, the media bucket, the instance, the image) are triaged in the portfolio repository.

### How the scan was run

```bash
prowler aws --profile dev-audit --region eu-west-2 \
  --services ec2 vpc s3 cloudfront ecr ssm iam guardduty \
  --config-file ~/prowler-reports/prowler-config.yaml \
  --output-directory ~/prowler-reports/dev-phase9
```

- **Read-only profile (`dev-audit`):** scanning needs no write access.
- **One region (`eu-west-2`):** the region lock SCP blocks every other region, so scanning them only repeats the same findings.
- **Selected services:** only the services that hold resources in this account.
- **Reports kept outside the repository:** raw reports contain account IDs and resource names and are never committed.

### Results

| Scan | Checks | Failed (platform) | Notes |
|---|---|---|---|
| Before | 187 | 28 | GuardDuty not yet evaluated |
| After | 199 | 26 | 9 fixed. 7 GuardDuty plan checks added once GuardDuty was enabled (see D-005). |

### Fixed

| Finding | Fix | Why |
|---|---|---|
| `ec2_ebs_default_encryption` | EBS encryption by default turned on | Every new volume is encrypted, even if the setting is forgotten at launch |
| `ec2_instance_account_imdsv2_enabled` | Account default: IMDSv2 required, hop limit 2 | New instances start hardened against metadata credential theft |
| `ecr_registry_scan_images_on_push_enabled` | Registry rule: scan every repository on push | Future repositories are scanned without extra setup |
| `iam_password_policy_minimum_length_14`, `_number`, `_symbol`, `_uppercase`, `_lowercase`, `_reuse_24` | Password policy matching the management and Security accounts | No IAM users exist, but the policy is free and keeps all accounts consistent |

Account-wide settings were changed with the Admin role. The Developer role cannot change account-wide security defaults.

### Accepted

| Finding | Reason |
|---|---|
| `iam_aws_attached_policy_no_administrative_privileges`, `iam_role_administratoraccess_policy` (Admin) | An administrator role is required. It is reached only through IAM Identity Center with MFA and is used rarely. |
| `iam_role_administratoraccess_policy` (`OrganizationAccountAccessRole`) | Kept as break-glass access from the management account if IAM Identity Center is unavailable |
| `iam_role_access_not_stale_to_bedrock` (5 roles) | Comes from broad AWS managed policies. No AI services are in use. A Bedrock deny SCP is an option if that changes. |
| `iam_support_role_created` | AWS Support is handled from the management account |
| `iam_password_policy_expires_passwords_within_90_days_or_less` | NCSC and NIST guidance advise against forced password expiry |
| `ec2_networkacl_allow_ingress_any_port`, `_tcp_port_22`, `_tcp_port_3389` | Security groups are the network control. The application security group allows one port from CloudFront only. Custom network ACLs add complexity without adding protection here. |
| `vpc_different_regions` | Required by the region lock SCP (D-004) |
| `vpc_subnet_different_az` | A single Availability Zone keeps cost low. Production would use at least two. |
| `vpc_endpoint_for_ec2_enabled` | Interface endpoints cost money every hour. The NAT is used on demand instead. |
| `ecr_registry_enhanced_scanning_enabled` | Enhanced scanning uses Amazon Inspector at extra cost. Basic scanning plus Trivy at build time covers images. |
| `guardduty_runtime_monitoring_enabled`, `guardduty_eks_runtime_monitoring_enabled` | Runtime Monitoring installs an agent on instances and creates VPC endpoints, which would change the network design (D-005) |
| `guardduty_ai_protection_enabled` | No AI services in use. It adds a CloudTrail service-linked channel to every account (D-005). |
| `guardduty_ec2_malware_protection_enabled` | Extra cost per scan. Foundational detection still raises findings (D-005). |
| `guardduty_eks_audit_log_enabled`, `guardduty_lambda_protection_enabled`, `guardduty_rds_protection_enabled` | No EKS, Lambda or RDS in use. Each can be enabled from the Security account when needed (D-005). |

### Deferred

| Finding | Reason | When |
|---|---|---|
| `vpc_endpoint_connections_trust_boundaries` | The S3 gateway endpoint policy allows all S3 access. With the NAT off, this endpoint is the only path out of the private subnet, so it should be limited to the account's own buckets and the AWS buckets used for ECR layers and packages. The policy needs testing during a deployment. | Terraform phase |
| `vpc_flow_logs_enabled` | GuardDuty already analyses flow log data for threats. Storing flow logs is only needed for forensics and adds cost. | Terraform phase |

### Lessons

- **Some failures are design decisions.** `vpc_different_regions` fails because of the region lock. A scanner checks against general best practice, and triage separates real gaps from deliberate choices.
- **A missing service is not a passing service.** GuardDuty did not appear in the first scan's results table. Its plan checks only appeared once a detector existed. An empty row means "nothing evaluated", not "nothing wrong".
- **Account-wide defaults protect future resources.** The existing instance and volume were already hardened. The fixes make every future instance, volume and repository start hardened too.
