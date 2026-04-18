data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(
    { Component = "storage" },
    var.tags,
  )

  cors_origin = startswith(var.cloudfront_domain_name, "https://") ? var.cloudfront_domain_name : "https://${var.cloudfront_domain_name}"
}

# --- Amplify storage bucket ---

resource "aws_s3_bucket" "amplify_storage" {
  bucket = "${local.name_prefix}-amplify-storage-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-amplify-storage" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "amplify_storage" {
  bucket = aws_s3_bucket.amplify_storage.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "amplify_storage" {
  bucket = aws_s3_bucket.amplify_storage.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "amplify_storage" {
  bucket = aws_s3_bucket.amplify_storage.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "amplify_storage" {
  bucket = aws_s3_bucket.amplify_storage.id

  target_bucket = var.access_logs_bucket_id
  target_prefix = "${local.name_prefix}/amplify-storage/"
}

resource "aws_s3_bucket_cors_configuration" "amplify_storage" {
  bucket = aws_s3_bucket.amplify_storage.id

  cors_rule {
    allowed_headers = ["*"]
    allowed_methods = ["GET", "PUT", "POST", "DELETE", "HEAD"]
    allowed_origins = [local.cors_origin]
    expose_headers  = ["ETag"]
    max_age_seconds = 3000
  }
}

# --- IAM: Amplify service role (S3 access) ---

data "aws_iam_policy_document" "amplify_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["amplify.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "amplify" {
  name               = "${local.name_prefix}-amplify"
  assume_role_policy = data.aws_iam_policy_document.amplify_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-amplify" })
}

data "aws_iam_policy_document" "amplify_s3" {
  statement {
    sid    = "AmplifyStorage"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation",
    ]
    resources = [
      aws_s3_bucket.amplify_storage.arn,
      "${aws_s3_bucket.amplify_storage.arn}/*",
    ]
  }
}

resource "aws_iam_role_policy" "amplify_s3" {
  name   = "amplify-storage"
  role   = aws_iam_role.amplify.id
  policy = data.aws_iam_policy_document.amplify_s3.json
}

# Bucket policy: allow the Amplify service role (bidirectional trust with IAM policy above).
data "aws_iam_policy_document" "amplify_bucket_policy" {
  statement {
    sid    = "AllowAmplifyServiceRole"
    effect = "Allow"

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.amplify.arn]
    }

    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
    ]

    resources = [
      aws_s3_bucket.amplify_storage.arn,
      "${aws_s3_bucket.amplify_storage.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "amplify_storage" {
  bucket = aws_s3_bucket.amplify_storage.id
  policy = data.aws_iam_policy_document.amplify_bucket_policy.json

  depends_on = [aws_iam_role_policy.amplify_s3]
}

# --- Amplify app + branch ---

resource "aws_amplify_app" "this" {
  name       = "${local.name_prefix}-app"
  repository = var.amplify_repository_url != "" ? var.amplify_repository_url : null

  iam_service_role_arn = aws_iam_role.amplify.arn

  # Build spec is maintained in the repository (amplify.yml). Placeholder for apps without repo.
  build_spec = <<-EOT
    version: 1
    frontend:
      phases:
        build:
          commands:
            - echo "Replace with amplify.yml from your repository"
      artifacts:
        baseDirectory: /
        files:
          - '**/*'
  EOT

  environment_variables = var.amplify_connect_to_web_ui_bucket ? {
    WEB_UI_BUCKET = var.web_ui_bucket_id
  } : {}

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-amplify-app" })
}

resource "aws_amplify_branch" "main" {
  app_id      = aws_amplify_app.this.id
  branch_name = "main"

  enable_auto_build = var.amplify_repository_url != "" ? true : false

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-amplify-main" })
}
