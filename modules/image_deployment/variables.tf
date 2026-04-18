variable "project_name" {
  type = string
}

variable "environment" {
  type = string
}

variable "discovery_bucket_id" {
  type = string
}

variable "discovery_bucket_arn" {
  type = string
}

variable "ecr_repository_url" {
  type = string
}

variable "ecr_repository_arn" {
  type = string
}

variable "codebuild_source_type" {
  type = string
}

variable "codebuild_source_location" {
  type    = string
  default = ""
}

variable "codebuild_s3_object_key" {
  type        = string
  description = "When source is S3, object key containing source zip (upload outside Terraform)."
  default     = "source/build.zip"
}

variable "tags" {
  type    = map(string)
  default = {}
}
