# Module: storage

## Purpose

Adds **Amplify Hosting**-style resources: **S3 bucket** for Amplify storage (encryption, versioning, CORS allowing the **CloudFront** domain as origin), **IAM role** for Amplify with S3 policy, **bucket policy** trusting that role, **Amplify app** (optional Git repository, placeholder **build_spec** if no repo), **main branch**, and environment variable **`WEB_UI_BUCKET`** when connecting to the web UI bucket.

## Resources Created

- `aws_s3_bucket` (amplify_storage) + versioning, encryption, public access block, logging, **CORS**
- `aws_iam_role` amplify + `aws_iam_role_policy` (S3 object/bucket access)
- `aws_s3_bucket_policy` (Amplify service role principal)
- `aws_amplify_app`, `aws_amplify_branch` (main)

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | string | Project prefix |
| `environment` | string | Environment name |
| `access_logs_bucket_id` | string | Access logging target |
| `access_logs_bucket_arn` | string | Access logging target ARN |
| `cloudfront_domain_name` | string | Used to build HTTPS CORS origin |
| `amplify_repository_url` | string | Git repo URL or empty |
| `amplify_connect_to_web_ui_bucket` | bool | Set env `WEB_UI_BUCKET` from web UI bucket |
| `web_ui_bucket_id` | string | Web UI bucket ID when connecting (default `""`) |
| `tags` | map(string) | Optional tags |

## Outputs

| Name | Description |
|------|-------------|
| `amplify_app_id` | Amplify application ID |
| `amplify_default_domain` | Amplify default domain |
| `amplify_storage_bucket_id` | Amplify storage bucket ID |
| `amplify_storage_bucket_arn` | Amplify storage bucket ARN |
| `amplify_service_role_arn` | IAM service role ARN for Amplify |

## Dependencies

- **web_ui** module (`cloudfront_domain_name`, `web_ui_bucket_id`).

## Notes

- Amplify storage bucket uses `prevent_destroy`.
- With no repository URL, the app uses a minimal placeholder **build_spec** — replace via real repo or manual workflow.
