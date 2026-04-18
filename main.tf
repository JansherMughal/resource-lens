# Root module wiring: central S3 access logging + child modules.
# Order follows dependencies (e.g. web_ui needs data-layer Lambda ARNs for AppSync).

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
}

# -----------------------------------------------------------------------------
# Central access-logs bucket (all data buckets log here; this bucket is not self-logged)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "access_logs" {
  bucket = "${local.name_prefix}-access-logs-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, {
    Component   = "logging"
    Name        = "${local.name_prefix}-access-logs"
    Project     = var.project_name
    Environment = var.environment
    ManagedBy   = "Terraform"
  })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

data "aws_iam_policy_document" "access_logs_policy" {
  statement {
    sid    = "AllowS3ServerAccessLogs"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }

    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.access_logs.arn}/*"]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs_policy.json
}

# -----------------------------------------------------------------------------
# Modules
# -----------------------------------------------------------------------------

module "networking" {
  source = "./modules/networking"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
  tags         = var.tags
}

module "data" {
  source = "./modules/data"

  project_name                = var.project_name
  environment                 = var.environment
  private_subnet_ids          = module.networking.private_subnet_ids
  vpc_id                      = module.networking.vpc_id
  sg_lambda_id                = module.networking.sg_lambda_id
  sg_neptune_id               = module.networking.sg_neptune_id
  sg_opensearch_id            = module.networking.sg_opensearch_id
  neptune_instance_class      = var.neptune_instance_class
  neptune_engine_version      = var.neptune_engine_version
  opensearch_instance_type    = var.opensearch_instance_type
  opensearch_engine_version   = var.opensearch_engine_version
  lambda_memory_size          = var.lambda_memory_size
  lambda_reserved_concurrency = var.lambda_reserved_concurrency
  enable_xray                 = var.enable_xray
  tags                        = var.tags
}

module "web_ui" {
  source = "./modules/web_ui"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name                = var.project_name
  environment                 = var.environment
  access_logs_bucket_id       = aws_s3_bucket.access_logs.id
  access_logs_bucket_arn      = aws_s3_bucket.access_logs.arn
  cloudfront_price_class      = var.cloudfront_price_class
  enable_waf                  = var.enable_waf
  lambda_memory_size          = var.lambda_memory_size
  lambda_reserved_concurrency = var.lambda_reserved_concurrency
  enable_xray                 = var.enable_xray
  gremlin_lambda_arn          = module.data.gremlin_lambda_function_arn
  search_lambda_arn           = module.data.search_lambda_function_arn
  tags                        = var.tags

  depends_on = [module.data]
}

module "discovery" {
  source = "./modules/discovery"

  project_name           = var.project_name
  environment            = var.environment
  private_subnet_ids     = module.networking.private_subnet_ids
  vpc_id                 = module.networking.vpc_id
  sg_ecs_id              = module.networking.sg_ecs_id
  ecs_task_cpu           = var.ecs_task_cpu
  ecs_task_memory        = var.ecs_task_memory
  ecs_desired_count      = var.ecs_desired_count
  access_logs_bucket_id  = aws_s3_bucket.access_logs.id
  access_logs_bucket_arn = aws_s3_bucket.access_logs.arn
  tags                   = var.tags

  depends_on = [module.networking]
}

module "image_deployment" {
  source = "./modules/image_deployment"

  project_name              = var.project_name
  environment               = var.environment
  discovery_bucket_id       = module.discovery.discovery_bucket_id
  discovery_bucket_arn      = module.discovery.discovery_bucket_arn
  ecr_repository_url        = module.discovery.ecr_repository_url
  ecr_repository_arn        = module.discovery.ecr_repository_arn
  codebuild_source_type     = var.codebuild_source_type
  codebuild_source_location = var.codebuild_source_location
  tags                      = var.tags

  depends_on = [module.discovery]
}

module "cost" {
  source = "./modules/cost"

  providers = {
    aws           = aws
    aws.us_east_1 = aws.us_east_1
  }

  project_name                    = var.project_name
  environment                     = var.environment
  access_logs_bucket_id           = aws_s3_bucket.access_logs.id
  access_logs_bucket_arn          = aws_s3_bucket.access_logs.arn
  athena_workgroup_name           = var.athena_workgroup_name
  cur_report_name                 = var.cur_report_name
  lambda_memory_size              = var.lambda_memory_size
  lambda_reserved_concurrency     = var.lambda_reserved_concurrency
  enable_xray                     = var.enable_xray
  cost_lambda_schedule_expression = var.cost_lambda_schedule_expression
  tags                            = var.tags
}

module "storage" {
  source = "./modules/storage"

  project_name                     = var.project_name
  environment                      = var.environment
  access_logs_bucket_id            = aws_s3_bucket.access_logs.id
  access_logs_bucket_arn           = aws_s3_bucket.access_logs.arn
  cloudfront_domain_name           = module.web_ui.cloudfront_domain_name
  amplify_repository_url           = var.amplify_repository_url
  amplify_connect_to_web_ui_bucket = var.amplify_connect_to_web_ui_bucket
  web_ui_bucket_id                 = module.web_ui.web_ui_bucket_id
  tags                             = var.tags

  depends_on = [module.web_ui]
}

module "observability" {
  source = "./modules/observability"

  project_name = var.project_name
  environment  = var.environment

  lambda_function_names = {
    settings = module.web_ui.settings_lambda_function_name
    gremlin  = module.data.gremlin_lambda_function_name
    search   = module.data.search_lambda_function_name
    cost     = module.cost.cost_lambda_function_name
  }

  neptune_cluster_identifier = module.data.neptune_cluster_identifier
  opensearch_domain_name     = module.data.opensearch_domain_name
  ecs_cluster_name           = module.discovery.ecs_cluster_name
  ecs_service_name           = module.discovery.ecs_service_name
  tags                       = var.tags

  depends_on = [
    module.web_ui,
    module.data,
    module.cost,
    module.discovery,
  ]
}
