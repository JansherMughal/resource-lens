variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "vpc_id" {
  type = string
}

variable "sg_ecs_id" {
  type = string
}

variable "ecs_task_cpu" {
  type = number
}

variable "ecs_task_memory" {
  type = number
}

variable "ecs_desired_count" {
  type = number
}

variable "access_logs_bucket_id" {
  type = string
}

variable "access_logs_bucket_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}
