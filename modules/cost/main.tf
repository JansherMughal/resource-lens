terraform {
  required_providers {
    aws = {
      source                = "hashicorp/aws"
      configuration_aliases = [aws.us_east_1]
    }
  }
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(
    { Component = "cost" },
    var.tags,
  )
  glue_db_name = replace(lower("${local.name_prefix}_cur"), "-", "_")
}

# --- S3: CUR delivery ---

resource "aws_s3_bucket" "cur" {
  bucket = "${local.name_prefix}-cur-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cur" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "cur" {
  bucket = aws_s3_bucket.cur.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  bucket = aws_s3_bucket.cur.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "cur" {
  bucket = aws_s3_bucket.cur.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "cur" {
  bucket = aws_s3_bucket.cur.id

  target_bucket = var.access_logs_bucket_id
  target_prefix = "${local.name_prefix}/cur/"
}

data "aws_iam_policy_document" "cur_bucket_policy" {
  statement {
    sid    = "AllowBillingAndCurDelivery"
    effect = "Allow"

    principals {
      type = "Service"
      identifiers = [
        "billingreports.amazonaws.com",
        "cur.amazonaws.com",
      ]
    }

    actions = [
      "s3:GetBucketAcl",
      "s3:GetBucketPolicy",
      "s3:PutObject",
    ]

    resources = [
      aws_s3_bucket.cur.arn,
      "${aws_s3_bucket.cur.arn}/*",
    ]
  }
}

resource "aws_s3_bucket_policy" "cur" {
  bucket = aws_s3_bucket.cur.id
  policy = data.aws_iam_policy_document.cur_bucket_policy.json
}

# --- S3: Athena query results ---

resource "aws_s3_bucket" "athena_results" {
  bucket = "${local.name_prefix}-athena-results-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-athena-results" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "athena_results" {
  bucket = aws_s3_bucket.athena_results.id

  target_bucket = var.access_logs_bucket_id
  target_prefix = "${local.name_prefix}/athena-results/"
}

# --- Cost & Usage Report (API lives in us-east-1) ---

resource "aws_cur_report_definition" "daily" {
  provider = aws.us_east_1

  report_name                = var.cur_report_name
  time_unit                  = "DAILY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]

  s3_bucket = aws_s3_bucket.cur.bucket
  s3_prefix = "cur/"
  s3_region = data.aws_region.current.name

  depends_on = [aws_s3_bucket_policy.cur]
}

# --- Athena workgroup ---

resource "aws_athena_workgroup" "cost" {
  name = var.athena_workgroup_name

  configuration {
    enforce_workgroup_configuration = true

    result_configuration {
      output_location = "s3://${aws_s3_bucket.athena_results.bucket}/results/"

      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  tags = merge(local.common_tags, { Name = var.athena_workgroup_name })
}

# --- Glue catalog for CUR parquet ---

resource "aws_glue_catalog_database" "cur" {
  name        = local.glue_db_name
  description = "CUR data cataloged for Athena"

  tags = merge(local.common_tags, { Name = local.glue_db_name })
}

data "aws_iam_policy_document" "glue_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_crawler" {
  name               = "${local.name_prefix}-glue-crawler"
  assume_role_policy = data.aws_iam_policy_document.glue_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-glue-crawler" })
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  role       = aws_iam_role.glue_crawler.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

data "aws_iam_policy_document" "glue_cur_s3" {
  statement {
    sid    = "ReadCur"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.cur.arn,
      "${aws_s3_bucket.cur.arn}/cur/*",
    ]
  }
}

resource "aws_iam_role_policy" "glue_cur_s3" {
  name   = "cur-read"
  role   = aws_iam_role.glue_crawler.id
  policy = data.aws_iam_policy_document.glue_cur_s3.json
}

resource "aws_glue_crawler" "cur" {
  name          = "${local.name_prefix}-cur-crawler"
  role          = aws_iam_role.glue_crawler.arn
  database_name = aws_glue_catalog_database.cur.name

  s3_target {
    path = "s3://${aws_s3_bucket.cur.bucket}/cur/"
  }

  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cur-crawler" })

  depends_on = [aws_iam_role_policy.glue_cur_s3]
}

# --- Cost Lambda ---

resource "aws_sqs_queue" "cost_dlq" {
  name                      = "${local.name_prefix}-cost-dlq"
  message_retention_seconds = 1209600

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cost-dlq" })
}

data "aws_iam_policy_document" "cost_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cost" {
  name               = "${local.name_prefix}-cost-lambda"
  assume_role_policy = data.aws_iam_policy_document.cost_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cost-lambda" })
}

resource "aws_iam_role_policy_attachment" "cost_basic" {
  role       = aws_iam_role.cost.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "cost_inline" {
  statement {
    sid    = "Athena"
    effect = "Allow"
    actions = [
      "athena:StartQueryExecution",
      "athena:GetQueryExecution",
      "athena:GetQueryResults",
      "athena:StopQueryExecution",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AthenaResultsRead"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.athena_results.arn,
      "${aws_s3_bucket.athena_results.arn}/*",
    ]
  }

  statement {
    sid    = "CurRead"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:ListBucket",
    ]
    resources = [
      aws_s3_bucket.cur.arn,
      "${aws_s3_bucket.cur.arn}/*",
    ]
  }

  statement {
    sid    = "GlueRead"
    effect = "Allow"
    actions = [
      "glue:GetDatabase",
      "glue:GetTable",
      "glue:GetPartitions",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cost_inline" {
  name   = "cost-access"
  role   = aws_iam_role.cost.id
  policy = data.aws_iam_policy_document.cost_inline.json
}

data "archive_file" "cost_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/cost"
  output_path = "${path.module}/.build/cost.zip"
}

resource "aws_cloudwatch_log_group" "cost_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-cost"
  retention_in_days = 14

  tags = merge(local.common_tags, { Name = "/aws/lambda/${local.name_prefix}-cost" })
}

resource "aws_lambda_function" "cost" {
  function_name = "${local.name_prefix}-cost"
  role          = aws_iam_role.cost.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 60
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.cost_zip.output_path
  source_code_hash = data.archive_file.cost_zip.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.cost_dlq.arn
  }

  environment {
    variables = {
      ATHENA_WORKGROUP = aws_athena_workgroup.cost.name
      ATHENA_DATABASE  = aws_glue_catalog_database.cur.name
      CUR_BUCKET       = aws_s3_bucket.cur.bucket
      RESULTS_BUCKET   = aws_s3_bucket.athena_results.bucket
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cost" })

  depends_on = [aws_cloudwatch_log_group.cost_lambda]
}

# Optional schedule
resource "aws_cloudwatch_event_rule" "cost_schedule" {
  count               = var.cost_lambda_schedule_expression != "" ? 1 : 0
  name                = "${local.name_prefix}-cost-schedule"
  schedule_expression = var.cost_lambda_schedule_expression

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cost-schedule" })
}

resource "aws_cloudwatch_event_target" "cost_lambda" {
  count = var.cost_lambda_schedule_expression != "" ? 1 : 0

  rule      = aws_cloudwatch_event_rule.cost_schedule[0].name
  target_id = "CostLambda"
  arn       = aws_lambda_function.cost.arn
}

resource "aws_lambda_permission" "cost_events" {
  count = var.cost_lambda_schedule_expression != "" ? 1 : 0

  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.cost.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.cost_schedule[0].arn
}
