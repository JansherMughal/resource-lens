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
    { Component = "web_ui" },
    var.tags,
  )
}

# --- S3 Web UI bucket (CloudFront OAC; no static website hosting) ---

resource "aws_s3_bucket" "webui" {
  bucket = "${local.name_prefix}-webui-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-webui" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "webui" {
  bucket = aws_s3_bucket.webui.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "webui" {
  bucket = aws_s3_bucket.webui.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "webui" {
  bucket = aws_s3_bucket.webui.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "webui" {
  bucket = aws_s3_bucket.webui.id

  target_bucket = var.access_logs_bucket_id
  target_prefix = "${local.name_prefix}/webui/"
}

# --- CloudFront OAC ---

resource "aws_cloudfront_origin_access_control" "webui" {
  name                              = "${local.name_prefix}-webui-oac"
  description                       = "OAC for Web UI bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# --- WAF (CloudFront scope must be created in us-east-1) ---

resource "aws_wafv2_web_acl" "webui" {
  count    = var.enable_waf ? 1 : 0
  provider = aws.us_east_1

  name        = "${local.name_prefix}-webui-waf"
  description = "Managed rules for CloudFront distribution"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.name_prefix}-webui-waf"
    sampled_requests_enabled   = true
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 10

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-common"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "AWSManagedRulesAmazonIpReputationList"
    priority = 20

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${local.name_prefix}-iprep"
      sampled_requests_enabled   = true
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-webui-waf" })
}

# --- CloudFront distribution ---

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  is_ipv6_enabled     = true
  comment             = "${local.name_prefix} Web UI"
  default_root_object = "index.html"
  price_class         = var.cloudfront_price_class

  web_acl_id = var.enable_waf ? aws_wafv2_web_acl.webui[0].arn : null

  origin {
    domain_name              = aws_s3_bucket.webui.bucket_regional_domain_name
    origin_id                = "s3-webui"
    origin_access_control_id = aws_cloudfront_origin_access_control.webui.id
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD", "OPTIONS"]
    cached_methods         = ["GET", "HEAD"]
    target_origin_id       = "s3-webui"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true

    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }

    min_ttl     = 0
    default_ttl = 3600
    max_ttl     = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-cf-webui" })
}

data "aws_iam_policy_document" "webui_bucket_policy" {
  statement {
    sid    = "AllowCloudFrontReadViaOAC"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.webui.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.this.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "webui" {
  bucket = aws_s3_bucket.webui.id
  policy = data.aws_iam_policy_document.webui_bucket_policy.json

  depends_on = [aws_cloudfront_distribution.this]
}

# --- Cognito ---

resource "aws_cognito_user_pool" "this" {
  name = "${local.name_prefix}-users"

  mfa_configuration = "OPTIONAL"

  auto_verified_attributes = ["email"]

  account_recovery_setting {
    recovery_mechanism {
      name     = "verified_email"
      priority = 1
    }
  }

  email_configuration {
    email_sending_account = "COGNITO_DEFAULT"
  }

  password_policy {
    minimum_length    = 10
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-users" })
}

resource "aws_cognito_user_pool_client" "spa" {
  name         = "${local.name_prefix}-spa-client"
  user_pool_id = aws_cognito_user_pool.this.id

  generate_secret                      = false
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_flows                  = ["code", "implicit"]
  allowed_oauth_scopes                 = ["email", "openid", "profile"]

  callback_urls = ["https://localhost/callback"]
  logout_urls   = ["https://localhost/logout"]

  supported_identity_providers = ["COGNITO"]

  explicit_auth_flows = [
    "ALLOW_REFRESH_TOKEN_AUTH",
    "ALLOW_USER_SRP_AUTH",
    "ALLOW_USER_PASSWORD_AUTH",
  ]
}

# --- DynamoDB Settings ---

resource "aws_dynamodb_table" "settings" {
  name         = "${local.name_prefix}-settings"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "settingId"

  attribute {
    name = "settingId"
    type = "S"
  }

  server_side_encryption {
    enabled = true
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-settings" })
}

# --- Settings Lambda ---

resource "aws_sqs_queue" "settings_dlq" {
  name                      = "${local.name_prefix}-settings-dlq"
  message_retention_seconds = 1209600

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-settings-dlq" })
}

data "aws_iam_policy_document" "settings_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "settings" {
  name               = "${local.name_prefix}-settings-lambda"
  assume_role_policy = data.aws_iam_policy_document.settings_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-settings-lambda" })
}

resource "aws_iam_role_policy_attachment" "settings_basic" {
  role       = aws_iam_role.settings.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

data "aws_iam_policy_document" "settings_ddb" {
  statement {
    sid    = "DynamoDBSettings"
    effect = "Allow"
    actions = [
      "dynamodb:GetItem",
      "dynamodb:PutItem",
      "dynamodb:DeleteItem",
      "dynamodb:Scan",
    ]
    resources = [aws_dynamodb_table.settings.arn]
  }
}

resource "aws_iam_role_policy" "settings_ddb" {
  name   = "ddb-settings"
  role   = aws_iam_role.settings.id
  policy = data.aws_iam_policy_document.settings_ddb.json
}

data "archive_file" "settings_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/settings"
  output_path = "${path.module}/.build/settings.zip"
}

resource "aws_cloudwatch_log_group" "settings_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-settings"
  retention_in_days = 14

  tags = merge(local.common_tags, { Name = "/aws/lambda/${local.name_prefix}-settings" })
}

resource "aws_lambda_function" "settings" {
  function_name = "${local.name_prefix}-settings"
  role          = aws_iam_role.settings.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  timeout       = 15
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.settings_zip.output_path
  source_code_hash = data.archive_file.settings_zip.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.settings_dlq.arn
  }

  environment {
    variables = {
      SETTINGS_TABLE_NAME = aws_dynamodb_table.settings.name
    }
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-settings" })

  depends_on = [aws_cloudwatch_log_group.settings_lambda]
}

# --- AppSync ---

locals {
  graphql_schema = <<SCHEMA
scalar AWSJSON

type Settings {
  settingId: ID!
  value: AWSJSON
}

type GremlinQueryResult {
  data: AWSJSON
}

type SearchQueryResult {
  data: AWSJSON
}

type Query {
  getSetting(settingId: ID!): Settings
  gremlinQuery(query: String!): GremlinQueryResult
  searchQuery(q: String!): SearchQueryResult
}

type Mutation {
  putSetting(settingId: ID!, value: AWSJSON): Settings
}

schema {
  query: Query
  mutation: Mutation
}
SCHEMA
}

resource "aws_appsync_graphql_api" "this" {
  name                = "${local.name_prefix}-graphql"
  authentication_type = "AMAZON_COGNITO_USER_POOLS"
  schema              = local.graphql_schema
  xray_enabled        = var.enable_xray

  additional_authentication_provider {
    authentication_type = "API_KEY"
  }

  user_pool_config {
    user_pool_id   = aws_cognito_user_pool.this.id
    aws_region     = data.aws_region.current.name
    default_action = "ALLOW"
  }

  log_config {
    cloudwatch_logs_role_arn = aws_iam_role.appsync_logs.arn
    field_log_level          = "ERROR"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-graphql" })

  depends_on = [aws_iam_role_policy.appsync_logs]
}

resource "aws_appsync_api_key" "public" {
  api_id      = aws_appsync_graphql_api.this.id
  description = "Optional public queries"
  # RFC3339 — rotate periodically.
  expires = "2030-04-01T00:00:00Z"
}

data "aws_iam_policy_document" "appsync_logs_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["appsync.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "appsync_logs" {
  name               = "${local.name_prefix}-appsync-logs"
  assume_role_policy = data.aws_iam_policy_document.appsync_logs_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-appsync-logs" })
}

data "aws_iam_policy_document" "appsync_logs" {
  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:*"]
  }
}

resource "aws_iam_role_policy" "appsync_logs" {
  name   = "appsync-logs"
  role   = aws_iam_role.appsync_logs.id
  policy = data.aws_iam_policy_document.appsync_logs.json
}

# --- AppSync Lambda data sources ---

resource "aws_appsync_datasource" "settings" {
  api_id           = aws_appsync_graphql_api.this.id
  name             = "SettingsLambda"
  service_role_arn = aws_iam_role.appsync_invoke.arn
  type             = "AWS_LAMBDA"

  lambda_config {
    function_arn = aws_lambda_function.settings.arn
  }
}

resource "aws_appsync_datasource" "gremlin" {
  api_id           = aws_appsync_graphql_api.this.id
  name             = "GremlinLambda"
  service_role_arn = aws_iam_role.appsync_invoke.arn
  type             = "AWS_LAMBDA"

  lambda_config {
    function_arn = var.gremlin_lambda_arn
  }
}

resource "aws_appsync_datasource" "search" {
  api_id           = aws_appsync_graphql_api.this.id
  name             = "SearchLambda"
  service_role_arn = aws_iam_role.appsync_invoke.arn
  type             = "AWS_LAMBDA"

  lambda_config {
    function_arn = var.search_lambda_arn
  }
}

data "aws_iam_policy_document" "appsync_invoke_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["appsync.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "appsync_invoke" {
  name               = "${local.name_prefix}-appsync-invoke"
  assume_role_policy = data.aws_iam_policy_document.appsync_invoke_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-appsync-invoke" })
}

data "aws_iam_policy_document" "appsync_invoke" {
  statement {
    effect = "Allow"
    actions = [
      "lambda:InvokeFunction",
    ]
    resources = [
      aws_lambda_function.settings.arn,
      "${aws_lambda_function.settings.arn}:*",
      var.gremlin_lambda_arn,
      "${var.gremlin_lambda_arn}:*",
      var.search_lambda_arn,
      "${var.search_lambda_arn}:*",
    ]
  }
}

resource "aws_iam_role_policy" "appsync_invoke" {
  name   = "invoke-resolvers"
  role   = aws_iam_role.appsync_invoke.id
  policy = data.aws_iam_policy_document.appsync_invoke.json
}

locals {
  lambda_request_template  = <<-VTL
  {
    "version": "2018-05-29",
    "operation": "Invoke",
    "payload": $util.toJson($ctx)
  }
  VTL
  lambda_response_template = "$util.toJson($ctx.result)"
}

resource "aws_appsync_resolver" "get_setting" {
  api_id      = aws_appsync_graphql_api.this.id
  type        = "Query"
  field       = "getSetting"
  data_source = aws_appsync_datasource.settings.name

  request_template  = local.lambda_request_template
  response_template = local.lambda_response_template
}

resource "aws_appsync_resolver" "put_setting" {
  api_id      = aws_appsync_graphql_api.this.id
  type        = "Mutation"
  field       = "putSetting"
  data_source = aws_appsync_datasource.settings.name

  request_template  = local.lambda_request_template
  response_template = local.lambda_response_template
}

resource "aws_appsync_resolver" "gremlin_query" {
  api_id      = aws_appsync_graphql_api.this.id
  type        = "Query"
  field       = "gremlinQuery"
  data_source = aws_appsync_datasource.gremlin.name

  request_template  = local.lambda_request_template
  response_template = local.lambda_response_template
}

resource "aws_appsync_resolver" "search_query" {
  api_id      = aws_appsync_graphql_api.this.id
  type        = "Query"
  field       = "searchQuery"
  data_source = aws_appsync_datasource.search.name

  request_template  = local.lambda_request_template
  response_template = local.lambda_response_template
}

# Resource-based permissions for AppSync to invoke Lambdas

resource "aws_lambda_permission" "settings_appsync" {
  statement_id  = "AllowAppSyncInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.settings.function_name
  principal     = "appsync.amazonaws.com"
  source_arn    = aws_appsync_graphql_api.this.arn
}

resource "aws_lambda_permission" "gremlin_appsync" {
  statement_id  = "AllowAppSyncInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.gremlin_lambda_arn
  principal     = "appsync.amazonaws.com"
  source_arn    = aws_appsync_graphql_api.this.arn
}

resource "aws_lambda_permission" "search_appsync" {
  statement_id  = "AllowAppSyncInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.search_lambda_arn
  principal     = "appsync.amazonaws.com"
  source_arn    = aws_appsync_graphql_api.this.arn
}
