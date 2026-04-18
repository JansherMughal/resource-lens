variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "lambda_function_names" {
  type        = map(string)
  description = "Map of logical names to Lambda function names (for log groups and alarms)."
}

variable "neptune_cluster_identifier" {
  type = string
}

variable "opensearch_domain_name" {
  type = string
}

variable "ecs_cluster_name" {
  type = string
}

variable "ecs_service_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
