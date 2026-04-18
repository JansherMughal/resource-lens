variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "access_logs_bucket_id" {
  type        = string
  description = "Central S3 access logs bucket id."
}

variable "access_logs_bucket_arn" {
  type = string
}

variable "cloudfront_price_class" {
  type = string
}

variable "enable_waf" {
  type = bool
}

variable "lambda_memory_size" {
  type = number
}

variable "lambda_reserved_concurrency" {
  type    = number
  default = null
}

variable "enable_xray" {
  type = bool
}

variable "gremlin_lambda_arn" {
  type = string
}

variable "search_lambda_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
