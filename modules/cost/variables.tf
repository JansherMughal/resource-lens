variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "access_logs_bucket_id" {
  type = string
}

variable "access_logs_bucket_arn" {
  type = string
}

variable "athena_workgroup_name" {
  type = string
}

variable "cur_report_name" {
  type = string
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

variable "cost_lambda_schedule_expression" {
  type    = string
  default = ""
}

variable "tags" {
  type    = map(string)
  default = {}
}
