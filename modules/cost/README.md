# Module: cost

## Purpose

Enables **cost analytics** on **Cost & Usage Report (CUR)** data: **S3 buckets** for CUR delivery and **Athena query results**, bucket policy allowing billing/CUR services, **`aws_cur_report_definition`** (requires **`aws.us_east_1`** provider), **Athena workgroup**, **Glue** catalog database, **Glue crawler** with IAM role to read CUR Parquet under `s3://.../cur/`, **Cost Lambda** (Python) with Athena/Glue/S3 permissions, DLQ, optional **EventBridge** schedule + Lambda permission. Access logging targets the central access-logs bucket.

## Resources Created

- `aws_s3_bucket` (cur, athena_results) + versioning, encryption, public access block, logging, **cur bucket policy**
- `aws_cur_report_definition` (daily Parquet, provider `aws.us_east_1`)
- `aws_athena_workgroup` (enforced config, SSE-S3 results path)
- `aws_glue_catalog_database`
- `aws_iam_role` glue_crawler + attachments/policies, `aws_glue_crawler` (S3 target `.../cur/`)
- `aws_sqs_queue` (cost_dlq)
- `aws_iam_role` cost Lambda + inline policy (Athena, S3, Glue)
- `data.archive_file` (cost zip from `lambdas/cost`)
- `aws_cloudwatch_log_group`, `aws_lambda_function` (cost)
- `aws_cloudwatch_event_rule` / `event_target` / `lambda_permission` (optional schedule)

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | string | Project prefix |
| `environment` | string | Environment name |
| `access_logs_bucket_id` | string | Central access logs bucket |
| `access_logs_bucket_arn` | string | Central access logs bucket ARN |
| `athena_workgroup_name` | string | Athena workgroup name |
| `cur_report_name` | string | CUR report definition name |
| `lambda_memory_size` | number | Cost Lambda memory |
| `lambda_reserved_concurrency` | number | Optional reserved concurrency |
| `enable_xray` | bool | X-Ray on Cost Lambda |
| `cost_lambda_schedule_expression` | string | EventBridge schedule (empty = no schedule) |
| `tags` | map(string) | Optional tags |

## Outputs

| Name | Description |
|------|-------------|
| `cur_bucket_id` | CUR delivery bucket ID |
| `athena_results_bucket_id` | Athena results bucket ID |
| `glue_database_name` | Glue database name |
| `cost_lambda_function_name` | Cost Lambda name |
| `cost_lambda_function_arn` | Cost Lambda ARN |

## Dependencies

- Root must pass **`providers = { aws = aws, aws.us_east_1 = aws.us_east_1 }`** for CUR.
- Central **access_logs** bucket from root.

## Notes

- CUR S3 region in the report definition uses the **current** region from the default provider; ensure the CUR bucket policy and account billing settings align with AWS requirements.
- After first deploy, **Glue crawler** may need time and correct CUR paths before Athena queries succeed.
