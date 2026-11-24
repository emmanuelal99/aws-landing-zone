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

## F-005: Session Manager not ready straight after the NAT is turned on

**What happened:** After running `nat-on.sh`, `aws ssm start-session` failed with `TargetNotConnected`, even though `describe-instance-information` showed the instance as `Online`.

**Cause:** The SSM agent uses two separate connections. The status connection (which sets `Online`) came back first. The session connection (`ssmmessages`) has its own retry timer, which gets longer after each failed attempt, so it reconnected later.

**Fix:** Rebooting the instance reset both connections. Sessions worked straight after the agent came back.

**Lesson:** `Online` does not mean a session will work. After turning the NAT on, either reboot the instance or wait a few minutes before starting a session.

## F-006: Media images did not load through CloudFront

**What happened:** Images uploaded through the admin page were saved to S3 but showed as broken on the public site.

**Cause 1: wrong S3 address.** The CloudFront S3 origin used the global S3 endpoint (`bucket.s3.amazonaws.com`). S3 answered with `307` and `AuthorizationHeaderMalformed`: the request was signed for `eu-west-2` but reached the `us-east-1` endpoint.
**Fix 1:** The origin was changed to the regional endpoint (`bucket.s3.eu-west-2.amazonaws.com`).

**Cause 2: one wrong character in the bucket policy.** The distribution ID contains the letter `O`. The bucket policy was typed with a zero (`0`), so the `AWS:SourceArn` condition never matched and S3 returned `403 AccessDenied`.
**Fix 2:** The policy was corrected using the ID returned by `aws cloudfront list-distributions`.

**Evidence of the final state:** The image returns `200` through CloudFront and `403` when requested directly from S3. The bucket stays private and is readable only through the distribution.

**Lessons:**
- Always use the regional S3 endpoint for CloudFront origins. In Terraform, use `bucket_regional_domain_name`.
- Never type resource IDs by hand. Copy them from the CLI or console. In Terraform, reference the distribution's `.arn` directly.
- The error came from the policy failing closed: a mistake blocked all access instead of opening it.
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
