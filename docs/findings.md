# Findings

Issues discovered while building and testing the landing zone, with root cause and remediation.

## F-001: Look-alike tag keys on an SCP

**Found during:** activating cost allocation tags process.
**Severity:** Low (governance/hygiene, no cost impact; SCPs are not billable)

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

**Remediation:** Removed the bad keys, added the correct ones, and re-ran the search
(no results). Only the clean keys were activated as cost allocation tags.

**Related:** The SCP inventory also found an untracked root-level SCP
(`DenyLeaveAndCloseAccount`) from earlier work. Verified its content, kept it as a valid
control (blocks member account self-closure, which no other SCP covered), then tagged
it and added it as `policies/scp/scp-deny-leave-and-close.json`.

**Lesson:** Tag policies are preventive for known keys only. A detective control
(AWS Config `required-tags` rule or a scheduled tagging-API sweep) is needed to catch
look-alike keys.