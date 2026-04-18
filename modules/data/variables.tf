variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_subnet_ids" {
  type        = list(string)
  description = "Private subnets for Neptune, OpenSearch, and VPC-attached Lambdas."
}

variable "vpc_id" {
  type = string
}

variable "sg_lambda_id" {
  type = string
}

variable "sg_neptune_id" {
  type = string
}

variable "sg_opensearch_id" {
  type = string
}

variable "neptune_instance_class" {
  type = string
}

variable "neptune_engine_version" {
  type = string
}

variable "opensearch_instance_type" {
  type = string
}

variable "opensearch_engine_version" {
  type = string
}

variable "lambda_memory_size" {
  type = number
}

variable "lambda_reserved_concurrency" {
  type        = number
  default     = null
  description = "Optional reserved concurrency for data Lambdas."
}

variable "enable_xray" {
  type = bool
}

variable "tags" {
  type    = map(string)
  default = {}
}
