# Workload onboarding

This document describes what the landing zone gives every workload, and what a workload must do to run on it. The portfolio application ([secure-django-portfolio](https://github.com/emmanuelal99/secure-django-portfolio)) is the first workload and follows every step below.

## What the platform provides

### Accounts and guardrails

Workloads run in member accounts inside an organisational unit (OU). Every account in an OU inherits that OU's guardrails automatically, with nothing to configure.

| OU | Purpose | Accounts |
|---|---|---|
| Workloads | Applications | Dev |
| Security | Central security services and logs | Security |
| Sandbox | Experiments, with the same guardrails | (empty) |

| Guardrail | Effect on a workload |
|---|---|
| `scp-region-lock` | Only `eu-west-2` can be used. Global services (IAM, CloudFront, Route 53, WAF and others) are exempt. |
| `scp-baseline-deny` | No IAM users or access keys can be created. EC2 instances must carry a `Project` tag at launch. Accounts cannot leave the organisation. |
| `scp-protect-security` | CloudTrail, GuardDuty, Config, Security Hub and Access Analyzer cannot be turned off, except by the Admin break-glass role. |
| `DenyLeaveAndCloseAccount` (root) | No account can leave the organisation or close itself. |
| `tag-policy-standard` | `Project`, `Env` and `Owner` must use exact keys and approved values. Enforced on EC2 instances, volumes, VPCs, subnets and security groups. |

### Identity

Access is given to groups through IAM Identity Center. Nobody signs in with an IAM user.

| Group | Permission set | Where | What it allows |
|---|---|---|---|
| Developers | Developer (4 h) | Dev | Build and run workloads (`PowerUserAccess`). Can pass only approved instance roles to EC2. |
| Developers | PortfolioAdmin (1 h) | Dev | Port forwarding to `Project=Portfolio` instances only. No shell. |
| Security-Audit | Auditor (4 h) | All accounts | Read-only review, including CloudFront function code and cost guardrails. |
| Platform-Admins | Admin (1 h) | All accounts | Full access, for platform changes and break-glass use. |

### Network (Dev account)

| Resource | Name tag | Detail |
|---|---|---|
| VPC | `portfolio-vpc` | `10.0.0.0/16`, DNS support and hostnames on |
| Private subnet | `portfolio-private-a` | `10.0.1.0/24`, `eu-west-2a`. Workloads run here, with no public IP addresses. |
| Public subnet | `portfolio-public-a` | `10.0.0.0/28`. Holds only the NAT gateway when it is switched on. |
| Private route table | `portfolio-private-rt` | Has no internet route by default |
| S3 gateway endpoint | `portfolio-s3-endpoint` | Free, private access to S3 from the private subnet |
| NAT gateway | (created on demand) | Switched on with `scripts/nat-on.sh` and off with `scripts/nat-off.sh` |

The NAT gateway is only needed for deployments, server sessions and admin tunnels. After `nat-on.sh`, the SSM agent can take a few minutes to reconnect; reboot the instance or wait before starting a session.

### Account security settings

Applied in every account, so new resources start secure:

- EBS encryption by default
- IMDSv2 required by default for new instances (Dev)
- S3 Block Public Access at account level
- Password policy (14 characters, complexity, 24 previous passwords blocked)
- ECR scan on push for every repository (Dev)

### Security services

| Service | Coverage |
|---|---|
| GuardDuty | Every account, managed from the Security account. Foundational detection and S3 Protection. |
| CloudTrail | One organisation trail for every account and region, with log file validation. Logs go to a protected bucket in the Security account. |
| IAM Access Analyzer | Delegated to the Security account |

### Cost guardrails

- Monthly budget with email alerts at 80% and 100%
- Daily cost anomaly alerts for any unusual spending of $3 or more, by service

## What a workload must do

1. **Use `eu-west-2`.** Every other region is blocked.
2. **Tag every resource** with `Project`, `Env` and `Owner`, using approved values. A new project name must first be added to `policies/tag/tag-policy-standard.json` and applied through the landing zone Terraform.
3. **Run compute in the private subnet**, with no public IP addresses. Inbound traffic arrives through a managed service, for example a CloudFront VPC origin. Administration uses SSM Session Manager.
4. **Attach any new subnet to `portfolio-private-rt`.** A subnet without an explicit association falls back to the main route table and loses its routes.
5. **Create a least-privilege instance role for the workload.** The role is created with the Admin role. A `PassRole` statement for that role only is then added to the Developer permission set in `terraform/identity.tf`.
6. **Keep secrets in Parameter Store** as SecureString values. Never put secrets in code, images or Terraform state.
7. **Keep the workload in its own repository with its own Terraform state.** Read platform resources with data sources; never manage them.
8. **Turn the NAT gateway off** after every deployment or admin session.

### Reading the platform from a workload

```hcl
data "aws_vpc" "platform" {
  tags = { Name = "portfolio-vpc" }
}

data "aws_subnet" "private_a" {
  vpc_id = data.aws_vpc.platform.id
  tags   = { Name = "portfolio-private-a" }
}
```

A data source only reads. If the platform resource is missing, the plan stops with an error instead of creating or changing anything.

## Onboarding checklist

| Step | Owner | Where |
|---|---|---|
| Add the project's tag values to the tag policy | Platform | `policies/tag/`, landing zone Terraform |
| Create the workload's instance role | Platform (Admin) | Dev account |
| Add a scoped `PassRole` statement to the Developer permission set | Platform | `terraform/identity.tf` |
| Create the workload's repository and Terraform state | Workload | New repository |
| Store secrets in Parameter Store | Workload | Dev account |
| Deploy into the private subnet | Workload | Workload Terraform |
| Record the workload's dependencies on the platform | Workload | `docs/platform-dependencies.md` in the workload repository |

## Not provided by the platform

These are left to each workload, or deferred:

- Custom domains and ACM certificates
- AWS WAF
- Backups (EBS snapshots, AWS Backup)
- Stored VPC flow logs (GuardDuty still analyses network activity)
- Interface VPC endpoints (the NAT gateway is used on demand instead)
- More than one Availability Zone

## Changing the platform

Platform resources change only through this repository. A change is made in code, reviewed in a read-only `terraform plan`, and applied with a write role for the affected account only (see D-008).
