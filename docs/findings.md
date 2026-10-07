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

## F-002: Default cost anomaly alert could not fire for this account

**Found during:** Cost Anomaly Detection setup process
**Severity:** Medium (a detective control that looked enabled but was effectively off)

**Observation:** AWS auto-created `Default-Services-Monitor` with a subscription
threshold of `$100 AND 40%`, sent only to the root account email.

**Root cause:** AWS defaults are sized for accounts with meaningful spend. With a
baseline of pennies per day, an anomaly would need to exceed $100 *and* 40% before
alerting, by which point a leaked-credential or forgotten-resource incident would
already be costly. Alerts also went to an inbox not monitored day to day.

**Remediation:** Renamed the monitor (`portfolio-services-monitor`) and subscription
(`portfolio-anomaly-alerts`), set a single absolute threshold of $3 (percentage removed
to avoid alert fatigue on a near-zero baseline), added a monitored inbox, and applied
the standard tags. Monitor history was kept by editing instead of recreating.

**Lesson:** "Enabled" is not the same as "effective". Defaults must be checked against
the environment's actual risk profile.
