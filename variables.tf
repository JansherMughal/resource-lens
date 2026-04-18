variable "project_name" {
  description = "Short project name used in resource naming prefixes."
  type        = string
}

variable "environment" {
  description = "Deployment stage (e.g. dev, staging, prod)."
  type        = string
}

variable "aws_region" {
  description = "Primary AWS region for regional resources (AppSync, Lambda, VPC, etc.)."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC."
  type        = string
  default     = "10.0.0.0/16"
}

variable "neptune_instance_class" {
  description = "Neptune DB instance class."
  type        = string
  default     = "db.r6g.large"
}

variable "opensearch_instance_type" {
  description = "OpenSearch data node instance type."
  type        = string
  default     = "t3.medium.search"
}

variable "ecs_task_cpu" {
  description = "Fargate task CPU units (e.g. 512)."
  type        = number
  default     = 512
}

variable "ecs_task_memory" {
  description = "Fargate task memory (MiB)."
  type        = number
  default     = 1024
}

variable "ecs_desired_count" {
  description = "Desired ECS task count for the discovery service."
  type        = number
  default     = 1
}

variable "lambda_reserved_concurrency" {
  description = "Reserved concurrent executions for each Lambda (null = use account default / unreserved)."
  type        = number
  default     = null
}

variable "lambda_memory_size" {
  description = "Memory size (MB) for Lambda functions (where a single value applies)."
  type        = number
  default     = 256
}

variable "enable_waf" {
  description = "When true, attach WAF WebACL to CloudFront."
  type        = bool
  default     = true
}

variable "enable_xray" {
  description = "When true, enable active X-Ray tracing on Lambda functions."
  type        = bool
  default     = true
}

variable "cloudfront_price_class" {
  description = "CloudFront price class (e.g. PriceClass_100)."
  type        = string
  default     = "PriceClass_100"
}

variable "athena_workgroup_name" {
  description = "Athena workgroup name for cost analysis queries."
  type        = string
  default     = "cost-analysis"
}

variable "cur_report_name" {
  description = "Name of the daily Cost & Usage Report."
  type        = string
  default     = "daily-cur"
}

# --- Additional inputs (referenced by modules / root) ---

variable "neptune_engine_version" {
  description = "Neptune engine version."
  type        = string
  default     = "1.3.1.0"
}

variable "opensearch_engine_version" {
  description = "OpenSearch engine version string."
  type        = string
  default     = "OpenSearch_2.11"
}

variable "codebuild_source_type" {
  description = "CodeBuild source: S3, CODECOMMIT, GITHUB, or GITHUB_ENTERPRISE."
  type        = string
  default     = "S3"
}

variable "codebuild_source_location" {
  description = "For S3: bucket/prefix key path. For Git: repo URL. Leave empty when using S3 with discovery bucket."
  type        = string
  default     = ""
}

variable "cost_lambda_schedule_expression" {
  description = "If set, creates an EventBridge schedule for CostFunction (e.g. cron(0 8 * * ? *)). Empty = no schedule."
  type        = string
  default     = ""
}

variable "amplify_repository_url" {
  description = "Optional Git repository URL for Amplify (e.g. https://github.com/org/repo). Empty = app without repo connection."
  type        = string
  default     = ""
}

variable "amplify_connect_to_web_ui_bucket" {
  description = "When true, Amplify branch uses the Web UI S3 bucket as source (manual deploy pattern)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Extra tags merged into resources that support the tags attribute."
  type        = map(string)
  default     = {}
}
