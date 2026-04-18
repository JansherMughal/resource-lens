data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(
    { Component = "data" },
    var.tags,
  )
  # OpenSearch domain name must be <= 28 chars; keep readable but bounded.
  opensearch_domain_name = substr(lower(replace("${var.project_name}-${var.environment}-os", "_", "-")), 0, 28)
}

# --- Neptune ---

resource "aws_neptune_subnet_group" "this" {
  name       = "${local.name_prefix}-neptune-subnets"
  subnet_ids = var.private_subnet_ids

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-neptune-subnets" })
}

resource "aws_neptune_cluster" "this" {
  cluster_identifier                  = "${local.name_prefix}-neptune"
  engine                              = "neptune"
  engine_version                      = var.neptune_engine_version
  neptune_subnet_group_name           = aws_neptune_subnet_group.this.name
  vpc_security_group_ids              = [var.sg_neptune_id]
  iam_database_authentication_enabled = true
  backup_retention_period             = 7
  storage_encrypted                   = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-neptune" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_neptune_cluster_instance" "this" {
  count = 1

  identifier                   = "${local.name_prefix}-neptune-${count.index + 1}"
  cluster_identifier           = aws_neptune_cluster.this.id
  instance_class               = var.neptune_instance_class
  engine                       = aws_neptune_cluster.this.engine
  neptune_subnet_group_name    = aws_neptune_subnet_group.this.name
  preferred_backup_window      = "07:00-09:00"
  preferred_maintenance_window = "sun:09:00-sun:10:00"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-neptune-${count.index + 1}" })
}

# --- OpenSearch ---

data "aws_iam_policy_document" "opensearch_domain_access" {
  statement {
    sid     = "AllowSearchLambda"
    effect  = "Allow"
    actions = ["es:*"]

    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.search.arn]
    }

    resources = [
      "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*"
    ]
  }
}

resource "aws_opensearch_domain" "this" {
  domain_name    = local.opensearch_domain_name
  engine_version = var.opensearch_engine_version

  cluster_config {
    instance_type          = var.opensearch_instance_type
    instance_count         = 1
    zone_awareness_enabled = false
  }

  # Single-node domain: one private subnet is sufficient; stays off public subnets per requirement.
  vpc_options {
    subnet_ids         = [var.private_subnet_ids[0]]
    security_group_ids = [var.sg_opensearch_id]
  }

  ebs_options {
    ebs_enabled = true
    volume_size = 20
  }

  encrypt_at_rest {
    enabled = true
  }

  node_to_node_encryption {
    enabled = true
  }

  domain_endpoint_options {
    enforce_https       = true
    tls_security_policy = "Policy-Min-TLS-1-2-2019-07"
  }

  access_policies = data.aws_iam_policy_document.opensearch_domain_access.json

  tags = merge(local.common_tags, { Name = local.opensearch_domain_name })

  lifecycle {
    prevent_destroy = true
  }

  depends_on = [aws_iam_role.search]
}

# --- Dead letter queues (Lambda) ---

resource "aws_sqs_queue" "gremlin_dlq" {
  name                      = "${local.name_prefix}-gremlin-dlq"
  message_retention_seconds = 1209600

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-gremlin-dlq" })
}

resource "aws_sqs_queue" "search_dlq" {
  name                      = "${local.name_prefix}-search-dlq"
  message_retention_seconds = 1209600

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-search-dlq" })
}

# --- IAM: Gremlin Lambda ---

data "aws_iam_policy_document" "gremlin_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "gremlin" {
  name               = "${local.name_prefix}-gremlin-lambda"
  assume_role_policy = data.aws_iam_policy_document.gremlin_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-gremlin-lambda" })
}

resource "aws_iam_role_policy_attachment" "gremlin_basic" {
  role       = aws_iam_role.gremlin.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "gremlin_vpc" {
  role       = aws_iam_role.gremlin.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "gremlin_neptune" {
  statement {
    sid       = "NeptuneDb"
    effect    = "Allow"
    actions   = ["neptune-db:*"]
    resources = [aws_neptune_cluster.this.arn, "${aws_neptune_cluster.this.arn}/*"]
  }
}

resource "aws_iam_role_policy" "gremlin_neptune" {
  name   = "neptune-access"
  role   = aws_iam_role.gremlin.id
  policy = data.aws_iam_policy_document.gremlin_neptune.json
}

# --- IAM: Search Lambda ---

data "aws_iam_policy_document" "search_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "search" {
  name               = "${local.name_prefix}-search-lambda"
  assume_role_policy = data.aws_iam_policy_document.search_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-search-lambda" })
}

resource "aws_iam_role_policy_attachment" "search_basic" {
  role       = aws_iam_role.search.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "search_vpc" {
  role       = aws_iam_role.search.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "search_es" {
  statement {
    sid    = "OpenSearchHttp"
    effect = "Allow"
    actions = [
      "es:ESHttpGet",
      "es:ESHttpHead",
      "es:ESHttpPost",
      "es:ESHttpPut",
      "es:ESHttpDelete",
      "es:DescribeElasticsearchDomain",
      "es:DescribeDomain",
    ]
    resources = [
      "arn:aws:es:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:domain/${local.opensearch_domain_name}/*",
      aws_opensearch_domain.this.arn,
    ]
  }
}

resource "aws_iam_role_policy" "search_es" {
  name   = "opensearch-http"
  role   = aws_iam_role.search.id
  policy = data.aws_iam_policy_document.search_es.json

  depends_on = [aws_opensearch_domain.this]
}

# --- Lambda packages ---

data "archive_file" "gremlin_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/gremlin"
  output_path = "${path.module}/.build/gremlin.zip"
}

data "archive_file" "search_zip" {
  type        = "zip"
  source_dir  = "${path.module}/lambdas/search"
  output_path = "${path.module}/.build/search.zip"
}

resource "aws_cloudwatch_log_group" "gremlin_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-gremlin-resolver"
  retention_in_days = 14

  tags = merge(local.common_tags, { Name = "/aws/lambda/${local.name_prefix}-gremlin-resolver" })
}

resource "aws_cloudwatch_log_group" "search_lambda" {
  name              = "/aws/lambda/${local.name_prefix}-search-resolver"
  retention_in_days = 14

  tags = merge(local.common_tags, { Name = "/aws/lambda/${local.name_prefix}-search-resolver" })
}

resource "aws_lambda_function" "gremlin" {
  function_name = "${local.name_prefix}-gremlin-resolver"
  role          = aws_iam_role.gremlin.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.gremlin_zip.output_path
  source_code_hash = data.archive_file.gremlin_zip.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.gremlin_dlq.arn
  }

  environment {
    variables = {
      NEPTUNE_ENDPOINT = aws_neptune_cluster.this.endpoint
      NEPTUNE_PORT     = "8182"
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.sg_lambda_id]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-gremlin-resolver" })

  depends_on = [
    aws_iam_role_policy_attachment.gremlin_vpc,
    aws_neptune_cluster_instance.this,
    aws_cloudwatch_log_group.gremlin_lambda,
  ]
}

resource "aws_lambda_function" "search" {
  function_name = "${local.name_prefix}-search-resolver"
  role          = aws_iam_role.search.arn
  handler       = "handler.handler"
  runtime       = "python3.12"
  timeout       = 30
  memory_size   = var.lambda_memory_size

  filename         = data.archive_file.search_zip.output_path
  source_code_hash = data.archive_file.search_zip.output_base64sha256

  reserved_concurrent_executions = var.lambda_reserved_concurrency

  tracing_config {
    mode = var.enable_xray ? "Active" : "PassThrough"
  }

  dead_letter_config {
    target_arn = aws_sqs_queue.search_dlq.arn
  }

  environment {
    variables = {
      OPENSEARCH_ENDPOINT = "https://${aws_opensearch_domain.this.endpoint}"
    }
  }

  vpc_config {
    subnet_ids         = var.private_subnet_ids
    security_group_ids = [var.sg_lambda_id]
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-search-resolver" })

  depends_on = [
    aws_iam_role_policy_attachment.search_vpc,
    aws_opensearch_domain.this,
    aws_cloudwatch_log_group.search_lambda,
  ]
}
