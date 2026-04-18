# Module: data

## Purpose

Provisions the **data plane** for graph and search: **Amazon Neptune** (Gremlin), **Amazon OpenSearch Service** (VPC domain), **SQS dead-letter queues**, **IAM roles** for two **Lambda** functions (**Gremlin** resolver and **Search** resolver), and the Lambdas themselves (Python 3.12, VPC-attached, optional X-Ray).

## Resources Created

- `aws_neptune_subnet_group`
- `aws_neptune_cluster`, `aws_neptune_cluster_instance` (single writer)
- `aws_opensearch_domain` (VPC options, EBS, encryption, access policy allowing Search Lambda role)
- `aws_sqs_queue` (gremlin_dlq, search_dlq)
- `aws_iam_role` / policies / attachments for **gremlin** and **search** Lambdas (Neptune DB access, OpenSearch HTTP, VPC execution)
- `data.archive_file` (gremlin_zip, search_zip from `lambdas/gremlin`, `lambdas/search`)
- `aws_cloudwatch_log_group` for each Lambda
- `aws_lambda_function` (gremlin, search) with `vpc_config`, DLQ, environment variables for endpoints

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | string | Project prefix |
| `environment` | string | Environment name |
| `private_subnet_ids` | list(string) | Private subnets for Neptune, OpenSearch, Lambdas |
| `vpc_id` | string | VPC ID |
| `sg_lambda_id` | string | Lambda security group ID |
| `sg_neptune_id` | string | Neptune security group ID |
| `sg_opensearch_id` | string | OpenSearch security group ID |
| `neptune_instance_class` | string | Neptune instance class |
| `neptune_engine_version` | string | Neptune engine version |
| `opensearch_instance_type` | string | OpenSearch instance type |
| `opensearch_engine_version` | string | OpenSearch engine version |
| `lambda_memory_size` | number | Lambda memory (MB) |
| `lambda_reserved_concurrency` | number | Optional reserved concurrency (default `null`) |
| `enable_xray` | bool | X-Ray tracing mode |
| `tags` | map(string) | Optional tags (default `{}`) |

## Outputs

| Name | Description |
|------|-------------|
| `neptune_cluster_endpoint` | Neptune cluster endpoint |
| `neptune_cluster_id` | Neptune cluster resource ID |
| `neptune_cluster_identifier` | Neptune cluster identifier |
| `neptune_cluster_arn` | Neptune cluster ARN |
| `opensearch_endpoint` | OpenSearch domain endpoint (hostname) |
| `opensearch_domain_name` | OpenSearch domain name |
| `opensearch_domain_arn` | OpenSearch domain ARN |
| `gremlin_lambda_function_arn` | Gremlin Lambda ARN |
| `gremlin_lambda_function_name` | Gremlin Lambda function name |
| `search_lambda_function_arn` | Search Lambda ARN |
| `search_lambda_function_name` | Search Lambda function name |

## Dependencies

- **networking** module (subnets and security groups).

## Notes

- Neptune and OpenSearch use `prevent_destroy` on clusters/domain — adjust lifecycle for non-prod teardown if needed.
- OpenSearch domain name is truncated to AWS limits via `substr` in `locals`.
- Lambda source is packaged from `modules/data/lambdas/` at plan/apply time.
