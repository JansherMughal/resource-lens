output "access_logs_bucket_id" {
  description = "Central S3 server access logging bucket."
  value       = aws_s3_bucket.access_logs.id
}

output "vpc_id" {
  value = module.networking.vpc_id
}

output "cloudfront_domain_name" {
  description = "CloudFront URL (HTTPS) for the static web UI."
  value       = module.web_ui.cloudfront_domain_name
}

output "cloudfront_distribution_id" {
  value = module.web_ui.cloudfront_distribution_id
}

output "appsync_graphql_url" {
  description = "AppSync GraphQL HTTPS endpoint."
  value       = module.web_ui.appsync_graphql_url
}

output "appsync_api_id" {
  value = module.web_ui.appsync_graphql_api_id
}

output "cognito_user_pool_id" {
  value = module.web_ui.cognito_user_pool_id
}

output "cognito_user_pool_client_id" {
  value = module.web_ui.cognito_user_pool_client_id
}

output "neptune_cluster_endpoint" {
  value = module.data.neptune_cluster_endpoint
}

output "opensearch_endpoint" {
  value = module.data.opensearch_endpoint
}

output "discovery_bucket_id" {
  value = module.discovery.discovery_bucket_id
}

output "ecr_repository_url" {
  value = module.discovery.ecr_repository_url
}

output "ecs_cluster_name" {
  value = module.discovery.ecs_cluster_name
}

output "cur_bucket_id" {
  value = module.cost.cur_bucket_id
}

output "athena_workgroup_name" {
  value = var.athena_workgroup_name
}

output "glue_database_name" {
  value = module.cost.glue_database_name
}

output "amplify_app_id" {
  value = module.storage.amplify_app_id
}

output "amplify_default_domain" {
  value = module.storage.amplify_default_domain
}

output "amplify_storage_bucket_id" {
  value = module.storage.amplify_storage_bucket_id
}

output "sns_alerts_topic_arn" {
  value = module.observability.sns_topic_arn
}

output "codebuild_project_name" {
  value = module.image_deployment.codebuild_project_name
}
