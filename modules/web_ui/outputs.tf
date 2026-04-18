output "web_ui_bucket_id" {
  value = aws_s3_bucket.webui.id
}

output "web_ui_bucket_arn" {
  value = aws_s3_bucket.webui.arn
}

output "cloudfront_domain_name" {
  value = aws_cloudfront_distribution.this.domain_name
}

output "cloudfront_distribution_id" {
  value = aws_cloudfront_distribution.this.id
}

output "cloudfront_distribution_arn" {
  value = aws_cloudfront_distribution.this.arn
}

output "cognito_user_pool_id" {
  value = aws_cognito_user_pool.this.id
}

output "cognito_user_pool_client_id" {
  value = aws_cognito_user_pool_client.spa.id
}

output "cognito_user_pool_endpoint" {
  value = aws_cognito_user_pool.this.endpoint
}

output "appsync_graphql_api_id" {
  value = aws_appsync_graphql_api.this.id
}

output "appsync_graphql_url" {
  value = aws_appsync_graphql_api.this.uris["GRAPHQL"]
}

output "settings_lambda_function_name" {
  value = aws_lambda_function.settings.function_name
}

output "settings_lambda_function_arn" {
  value = aws_lambda_function.settings.arn
}

output "dynamodb_settings_table_name" {
  value = aws_dynamodb_table.settings.name
}
