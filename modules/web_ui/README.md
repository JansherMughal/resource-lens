# Module: web_ui

## Purpose

Hosts the **static web UI** on **S3** with **CloudFront** (OAC), optional **WAFv2** (CloudFront scope, **us-east-1** provider), **Cognito** user pool and SPA client, **DynamoDB** settings table, **Settings** Lambda (Node.js), **AppSync GraphQL API** (Cognito default auth + API key additional provider), Lambda data sources and resolvers for settings, Gremlin, and Search, plus **IAM** for AppSync logging and Lambda invoke. Requires **provider `aws.us_east_1`** for WAF.

## Resources Created

- `aws_s3_bucket` (webui) + versioning, encryption, public access block, logging, **bucket policy** for CloudFront OAC
- `aws_cloudfront_origin_access_control`
- `aws_wafv2_web_acl` (count; optional managed rule groups)
- `aws_cloudfront_distribution`
- `aws_cognito_user_pool`, `aws_cognito_user_pool_client` (SPA)
- `aws_dynamodb_table` (settings)
- `aws_sqs_queue` (settings_dlq)
- `aws_iam_role` / policies for Settings Lambda; `aws_lambda_function` settings; `aws_cloudwatch_log_group`
- `data.archive_file` (settings zip from `lambdas/settings`)
- `aws_appsync_graphql_api`, `aws_appsync_api_key`
- `aws_iam_role` appsync_logs + policy; AppSync `log_config`
- `aws_iam_role` appsync_invoke + policy for `lambda:InvokeFunction`
- `aws_appsync_datasource` (Settings, Gremlin, Search Lambdas)
- `aws_appsync_resolver` (getSetting, putSetting, gremlinQuery, searchQuery)
- `aws_lambda_permission` (AppSync invoke) for settings, gremlin, search ARNs

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | string | Project prefix |
| `environment` | string | Environment name |
| `access_logs_bucket_id` | string | Central access logs bucket ID |
| `access_logs_bucket_arn` | string | Central access logs bucket ARN |
| `cloudfront_price_class` | string | CloudFront price class |
| `enable_waf` | bool | Create and attach WAF to distribution |
| `lambda_memory_size` | number | Memory for Lambdas in this module |
| `lambda_reserved_concurrency` | number | Optional reserved concurrency |
| `enable_xray` | bool | X-Ray on Lambdas and AppSync |
| `gremlin_lambda_arn` | string | Gremlin Lambda ARN (from data module) |
| `search_lambda_arn` | string | Search Lambda ARN (from data module) |
| `tags` | map(string) | Optional tags |

## Outputs

| Name | Description |
|------|-------------|
| `web_ui_bucket_id` | Web UI S3 bucket ID |
| `web_ui_bucket_arn` | Web UI bucket ARN |
| `cloudfront_domain_name` | CloudFront domain name |
| `cloudfront_distribution_id` | Distribution ID |
| `cloudfront_distribution_arn` | Distribution ARN |
| `cognito_user_pool_id` | Cognito user pool ID |
| `cognito_user_pool_client_id` | App client ID |
| `cognito_user_pool_endpoint` | User pool endpoint |
| `appsync_graphql_api_id` | AppSync API ID |
| `appsync_graphql_url` | GraphQL HTTPS URL |
| `settings_lambda_function_name` | Settings Lambda name |
| `settings_lambda_function_arn` | Settings Lambda ARN |
| `dynamodb_settings_table_name` | DynamoDB settings table name |

## Dependencies

- **data** module (Gremlin and Search Lambda ARNs).
- Root must pass **`providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }`**.

## Notes

- Default Cognito **callback/logout URLs** are localhost — change for production.
- Web UI S3 bucket uses `prevent_destroy`.
- Gremlin/Search Lambdas are invoked by AppSync via ARNs passed from the root module.
