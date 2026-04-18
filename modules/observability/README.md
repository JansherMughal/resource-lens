# Module: observability

## Purpose

Centralizes **alerting**: an **SNS topic** and **CloudWatch metric alarms** for **Lambda error rate** (per function name in a map), **Neptune CPUUtilization**, **OpenSearch ClusterStatus.red**, and **ECS service CPUUtilization**. Alarm actions publish to the SNS topic.

## Resources Created

- `aws_sns_topic` (alerts)
- `aws_cloudwatch_metric_alarm` `lambda_error_rate` (for_each over `lambda_function_names` — metric math on Invocations/Errors)
- `aws_cloudwatch_metric_alarm` neptune_cpu
- `aws_cloudwatch_metric_alarm` opensearch_red
- `aws_cloudwatch_metric_alarm` ecs_cpu
- `data.aws_caller_identity` (OpenSearch alarm dimensions)

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | string | Project prefix |
| `environment` | string | Environment name |
| `lambda_function_names` | map(string) | Logical key → Lambda **function name** (settings, gremlin, search, cost) |
| `neptune_cluster_identifier` | string | Neptune cluster identifier for dimensions |
| `opensearch_domain_name` | string | OpenSearch domain name for dimensions |
| `ecs_cluster_name` | string | ECS cluster name |
| `ecs_service_name` | string | ECS service name |
| `tags` | map(string) | Optional tags |

## Outputs

| Name | Description |
|------|-------------|
| `sns_topic_arn` | SNS topic ARN for subscriptions |

## Dependencies

- **web_ui**, **data**, **cost**, **discovery** (for Lambda names and ECS identifiers passed from root).

## Notes

- Subscribe email/SMS/Chatbot to **`sns_topic_arn`** after apply.
- Lambda alarms use **metric_query** expressions; threshold is **1** on the computed error **percentage** expression (see `main.tf`).
