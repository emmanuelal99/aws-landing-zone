# Cost guardrails for the whole organisation (management account).

# Monthly budget: emails at 80% and 100% of actual spend.
resource "aws_budgets_budget" "monthly" {
  provider = aws.mgmt

  name              = "landing-zone-monthly-cost"
  budget_type       = "COST"
  limit_amount      = "15.0"
  limit_unit        = "USD"
  time_unit         = "MONTHLY"
  time_period_start = "2026-09-01_00:00"

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.budget_alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    notification_type          = "ACTUAL"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    subscriber_email_addresses = var.budget_alert_emails
  }

  tags = { Project = "Portfolio", Env = "Management", Owner = "Emmy" }

  # "metrics" (UnblendedCost, the AWS default) is not set here: this provider
  # only accepts it together with a filter_expression. AWS keeps the current value.
  lifecycle {
    ignore_changes = [metrics]
  }
}

# Learns each service's normal spending pattern and flags unusual changes.
resource "aws_ce_anomaly_monitor" "services" {
  provider = aws.mgmt

  name              = "portfolio-services-monitor"
  monitor_type      = "DIMENSIONAL"
  monitor_dimension = "SERVICE"

  tags = { Project = "Portfolio", Env = "Management", Owner = "Emmy" }
}

# Daily summary of any anomaly with a total impact of $3 or more (finding F-002).
resource "aws_ce_anomaly_subscription" "alerts" {
  provider = aws.mgmt

  name             = "portfolio-anomaly-alerts"
  frequency        = "DAILY"
  monitor_arn_list = [aws_ce_anomaly_monitor.services.arn]

  dynamic "subscriber" {
    for_each = var.anomaly_alert_emails
    content {
      type    = "EMAIL"
      address = subscriber.value
    }
  }

  threshold_expression {
    dimension {
      key           = "ANOMALY_TOTAL_IMPACT_ABSOLUTE"
      match_options = ["GREATER_THAN_OR_EQUAL"]
      values        = ["3"]
    }
  }

  tags = { Project = "Portfolio", Env = "Management", Owner = "Emmy" }
}
