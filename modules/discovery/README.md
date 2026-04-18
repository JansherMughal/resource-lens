# Module: discovery

## Purpose

Provides **artifact storage** and **container runtime** for the discovery workload: **S3 bucket** (versioned, encrypted, access logging, **EventBridge** notifications enabled), **ECR repository**, **ECS cluster** (Fargate + capacity providers), **CloudWatch log group**, **IAM** execution and task roles, **task definition**, and **ECS service** (Fargate in private subnets, no public IP). Container image defaults to **`${ecr_url}:latest`** on port **8080**.

## Resources Created

- `aws_s3_bucket` (discovery) + versioning, encryption, public access block, logging
- `aws_s3_bucket_notification` (EventBridge enabled)
- `aws_ecr_repository` (scan on push, AES256 encryption)
- `aws_ecs_cluster`, `aws_ecs_cluster_capacity_providers`
- `aws_cloudwatch_log_group` (`/ecs/${prefix}-discovery`)
- `aws_iam_role` ecs_execution + managed/extra policies (ECR pull, logs)
- `aws_iam_role` ecs_task (task role — extend for app permissions)
- `aws_ecs_task_definition` (Fargate, awsvpc)
- `aws_ecs_service` (desired count, deployment settings; `lifecycle.ignore_changes` on `task_definition`)

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | string | Project prefix |
| `environment` | string | Environment name |
| `private_subnet_ids` | list(string) | Subnets for ECS tasks |
| `vpc_id` | string | VPC ID (reference / future use) |
| `sg_ecs_id` | string | ECS tasks security group |
| `ecs_task_cpu` | number | Task CPU units |
| `ecs_task_memory` | number | Task memory (MiB) |
| `ecs_desired_count` | number | Desired task count |
| `access_logs_bucket_id` | string | Access logging target bucket |
| `access_logs_bucket_arn` | string | Access logging target ARN |
| `tags` | map(string) | Optional tags |

## Outputs

| Name | Description |
|------|-------------|
| `discovery_bucket_id` | Discovery S3 bucket ID |
| `discovery_bucket_arn` | Discovery bucket ARN |
| `ecr_repository_url` | ECR repository URL |
| `ecr_repository_arn` | ECR repository ARN |
| `ecs_cluster_name` | ECS cluster name |
| `ecs_cluster_arn` | ECS cluster ARN |
| `ecs_service_name` | ECS service name |
| `ecs_task_definition_arn` | Task definition ARN |
| `ecs_task_execution_role_arn` | Task execution role ARN |
| `ecs_log_group_name` | CloudWatch log group name |

## Dependencies

- **networking** (private subnets, `sg_ecs_id`).

## Notes

- Discovery bucket uses `prevent_destroy`.
- Push an initial image to ECR before relying on stable deployments; CodeBuild in **image_deployment** builds from zip uploads.
- EventBridge on the bucket supports the **image_deployment** pipeline.
