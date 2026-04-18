# Module: image_deployment

## Purpose

Automates **Docker image builds** for the discovery service: **IAM role** for **CodeBuild** (S3 read, ECR push, logs), **CodeBuild project** (privileged, `aws/codebuild/standard:7.0`, inline buildspec that builds `Dockerfile` or falls back to nginx), and **EventBridge** rule on **S3 Object Created** for the discovery bucket with **IAM role** allowing `codebuild:StartBuild` on the project.

## Resources Created

- `aws_iam_role` codebuild + `aws_iam_role_policy`
- `aws_codebuild_project` (discovery image builder; `NO_ARTIFACTS`)
- `aws_iam_role` events_invoke + `aws_iam_role_policy` for EventBridge
- `aws_cloudwatch_event_rule` (S3 object created, bucket filter)
- `aws_cloudwatch_event_target` (CodeBuild)

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | string | Project prefix |
| `environment` | string | Environment name |
| `discovery_bucket_id` | string | Discovery bucket ID (for rule + S3 path) |
| `discovery_bucket_arn` | string | Discovery bucket ARN |
| `ecr_repository_url` | string | ECR repo URL for push |
| `ecr_repository_arn` | string | ECR repo ARN for IAM |
| `codebuild_source_type` | string | e.g. `S3`, `GITHUB` |
| `codebuild_source_location` | string | Non-S3 source location when applicable (default `""`) |
| `codebuild_s3_object_key` | string | S3 object key for source zip when type is S3 (default `source/build.zip`) |
| `tags` | map(string) | Optional tags |

## Outputs

| Name | Description |
|------|-------------|
| `codebuild_project_name` | CodeBuild project name |
| `codebuild_project_arn` | CodeBuild project ARN |
| `eventbridge_rule_arn` | EventBridge rule ARN |

## Dependencies

- **discovery** module (bucket and ECR must exist).

## Notes

- When `codebuild_source_type = "S3"`, source location is **`${discovery_bucket_id}/${codebuild_s3_object_key}`** — upload your zip there to trigger builds.
- Root `main.tf` does not expose `codebuild_s3_object_key`; the **module default** applies unless you add a root variable later.
