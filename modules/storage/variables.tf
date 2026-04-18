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

variable "cloudfront_domain_name" {
  type        = string
  description = "CloudFront domain used as allowed CORS origin for the Amplify storage bucket."
}

variable "amplify_repository_url" {
  type    = string
  default = ""
}

variable "amplify_connect_to_web_ui_bucket" {
  type    = bool
  default = false
}

variable "web_ui_bucket_id" {
  type        = string
  default     = ""
  description = "When amplify_connect_to_web_ui_bucket is true, used as Amplify source bucket."
}

variable "tags" {
  type    = map(string)
  default = {}
}
