# Organisation CloudTrail. The trail is defined in the management account and
# writes to a bucket in the Security account, so even an administrator of the
# management account cannot quietly delete the evidence.

locals {
  mgmt_account_id = aws_organizations_organization.this.master_account_id

  # Built as text rather than referencing aws_cloudtrail.org.arn: the bucket
  # policy must exist before the trail, so the policy cannot depend on the trail.
  org_trail_arn = "arn:aws:cloudtrail:eu-west-2:${local.mgmt_account_id}:trail/org-trail"
}

# ---------------------------------------------------------------------------
# Trail (management account)
# ---------------------------------------------------------------------------

resource "aws_cloudtrail" "org" {
  provider = aws.mgmt

  name                          = "org-trail"
  s3_bucket_name                = aws_s3_bucket.cloudtrail_logs.id
  is_organization_trail         = true
  is_multi_region_trail         = true
  include_global_service_events = true
  enable_log_file_validation    = true # signed digest files detect edited or deleted logs
  enable_logging                = true

  # Management events only. Data events (for example S3 object reads) are not
  # recorded, to keep cost low.
  advanced_event_selector {
    name = "Management events selector"

    field_selector {
      field  = "eventCategory"
      equals = ["Management"]
    }
  }

  tags = { Project = "Portfolio", Env = "Management", Owner = "Emmy" }

  depends_on = [aws_s3_bucket_policy.cloudtrail_logs]
}

# ---------------------------------------------------------------------------
# Log bucket (Security account)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "cloudtrail_logs" {
  provider         = aws.security
  bucket           = "portfolio-org-cloudtrail-logs--${aws_organizations_account.security.id}-eu-west-2-an"
  bucket_namespace = "account-regional"

  tags = { Project = "Portfolio", Env = "Security", Owner = "Emmy" }

  # The audit record for every account. Removing it must be a deliberate edit.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_public_access_block" "cloudtrail_logs" {
  provider = aws.security
  bucket   = aws_s3_bucket.cloudtrail_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "cloudtrail_logs" {
  provider = aws.security
  bucket   = aws_s3_bucket.cloudtrail_logs.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cloudtrail_logs" {
  provider = aws.security
  bucket   = aws_s3_bucket.cloudtrail_logs.id

  rule {
    bucket_key_enabled       = true
    blocked_encryption_types = ["SSE-C"]

    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_versioning" "cloudtrail_logs" {
  provider = aws.security
  bucket   = aws_s3_bucket.cloudtrail_logs.id

  versioning_configuration {
    status     = "Enabled"
    mfa_delete = "Disabled"
  }
}

resource "aws_s3_bucket_policy" "cloudtrail_logs" {
  provider = aws.security
  bucket   = aws_s3_bucket.cloudtrail_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudTrailAclCheck"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:GetBucketAcl"
        Resource  = aws_s3_bucket.cloudtrail_logs.arn
        Condition = { StringEquals = { "aws:SourceArn" = local.org_trail_arn } }
      },
      {
        Sid       = "CloudTrailWriteManagementAccount"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${local.mgmt_account_id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.org_trail_arn
            "s3:x-amz-acl"  = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "CloudTrailWriteOrganization"
        Effect    = "Allow"
        Principal = { Service = "cloudtrail.amazonaws.com" }
        Action    = "s3:PutObject"
        Resource  = "${aws_s3_bucket.cloudtrail_logs.arn}/AWSLogs/${aws_organizations_organization.this.id}/*"
        Condition = {
          StringEquals = {
            "aws:SourceArn" = local.org_trail_arn
            "s3:x-amz-acl"  = "bucket-owner-full-control"
          }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "s3:*"
        Resource  = [aws_s3_bucket.cloudtrail_logs.arn, "${aws_s3_bucket.cloudtrail_logs.arn}/*"]
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
      {
        # Only the Admin break-glass role can delete logs or weaken the bucket.
        Sid       = "DenyLogDeletionExceptBreakGlass"
        Effect    = "Deny"
        Principal = "*"
        Action = [
          "s3:DeleteObject",
          "s3:DeleteObjectVersion",
          "s3:DeleteBucket",
          "s3:PutBucketPolicy",
          "s3:PutBucketVersioning",
        ]
        Resource = [aws_s3_bucket.cloudtrail_logs.arn, "${aws_s3_bucket.cloudtrail_logs.arn}/*"]
        Condition = {
          ArnNotLike = { "aws:PrincipalArn" = "arn:aws:iam::*:role/aws-reserved/sso.amazonaws.com/*AWSReservedSSO_Admin_*" }
        }
      }
    ]
  })
}
