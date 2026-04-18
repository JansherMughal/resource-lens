# Infrastructure — Terraform (Resource Lens)

This directory contains **Terraform** that provisions the AWS environment for **Resource Lens**: a **VPC** with public and private subnets, **Neptune** (graph) and **OpenSearch** (search), **VPC-attached Lambda** resolvers for Gremlin and OpenSearch queries, an **AppSync GraphQL API** with **Cognito** authentication, a **CloudFront**-fronted **S3** web UI (optional **WAF**), an **ECS Fargate** discovery service with **ECR**, **CodeBuild** triggered by uploads to a discovery **S3** bucket, **Cost & Usage Report** delivery with **Athena**, **Glue**, and a **cost** Lambda, **Amplify** app and storage bucket, central **S3 access logging**, and **CloudWatch** alarms to **SNS**.

If you are new to this project, read this document top-to-bottom — it covers **what gets created**, **how components connect**, and **commands to run**.

---

## Table of Contents

- [Directory Layout](#directory-layout)
- [Architecture](#architecture)
  - [User and Data Flow](#user-and-data-flow)
  - [Ingestion, Cost, and Ops](#ingestion-cost-and-ops)
- [Prerequisites](#prerequisites)
- [Step-by-Step: First Deployment](#step-by-step-first-deployment)
- [Repeat Deployments](#repeat-deployments)
- [Configuration Reference](#configuration-reference)
  - [Terraform Variables](#terraform-variables)
  - [Secrets and Sensitive Inputs](#secrets-and-sensitive-inputs)
  - [Provider and Tags](#provider-and-tags)
- [Terraform Outputs](#terraform-outputs)
- [Operations](#operations)
- [How the Root Module Wires Things Together](#how-the-root-module-wires-things-together)
- [Terraform Modules Index](#terraform-modules-index)
- [Cost Notes](#cost-notes)
- [Related Documentation](#related-documentation)

---

## Directory Layout

```
resource-lens/
├── main.tf                 # Root module — access-logs bucket + child modules
├── providers.tf            # AWS provider, default tags, us-east-1 alias (WAF, CUR)
├── variables.tf            # Input variables
├── outputs.tf              # Stack outputs
├── terraform.tfvars.example  # Example overrides (copy to terraform.tfvars)
├── .gitignore
├── .terraform.lock.hcl
│
└── modules/
    ├── networking/         # VPC, IGW, NAT, public/private subnets, security groups
    ├── data/               # Neptune, OpenSearch, Gremlin + Search Lambdas
    ├── web_ui/             # S3 web bucket, CloudFront, WAF, Cognito, AppSync, Settings Lambda, DynamoDB
    ├── discovery/        # Discovery S3, ECR, ECS Fargate cluster/service
    ├── image_deployment/   # CodeBuild + EventBridge (S3 object created → build)
    ├── cost/               # CUR bucket, Athena results, Glue, Cost Lambda, optional schedule
    ├── storage/            # Amplify app, branch, Amplify storage S3 + IAM
    └── observability/      # SNS topic, CloudWatch alarms (Lambda, Neptune, OpenSearch, ECS)
```

---

## Architecture

### User and Data Flow

```
                         Internet
                             │
                             ▼
                    ┌─────────────────┐
                    │   CloudFront    │
                    │   (HTTPS)       │
                    └────────┬────────┘
                             │
              ┌──────────────┴──────────────┐
              │  S3 origin: static Web UI   │
              └──────────────┬──────────────┘
                             │
         ┌───────────────────┴───────────────────┐
         │                                         │
         ▼                                         ▼
┌─────────────────┐                    ┌─────────────────┐
│ Cognito User    │                    │ AppSync GraphQL │
│ Pool + SPA      │ ─── JWT ─────────► │ (primary auth)  │
│ client          │                    │ + optional API  │
└─────────────────┘                    │   key           │
                                       └────────┬────────┘
                                                │
                         ┌──────────────────────┼──────────────────────┐
                         │                      │                      │
                         ▼                      ▼                      ▼
                 ┌───────────────┐      ┌───────────────┐      ┌───────────────┐
                 │ Settings      │      │ Gremlin       │      │ Search        │
                 │ Lambda        │      │ Lambda        │      │ Lambda        │
                 │ (DynamoDB)    │      │ (VPC)         │      │ (VPC)         │
                 └───────────────┘      └───────┬───────┘      └───────┬───────┘
                                                │                      │
                                                ▼                      ▼
                                        ┌───────────────┐      ┌───────────────┐
                                        │ Neptune       │      │ OpenSearch    │
                                        │ (Gremlin)     │      │ (HTTPS)       │
                                        └───────────────┘      └───────────────┘

  Private subnets (ECS discovery task)
  ┌──────────────────────────────────────────────────────────────┐
  │ ECS Fargate discovery service → ECR image (container :8080)  │
  │ Logs → CloudWatch; artifacts → discovery S3 (EventBridge)    │
  └──────────────────────────────────────────────────────────────┘
```

- **CloudFront** serves the static web UI from **S3** using **Origin Access Control** (not public website hosting). When `enable_waf = true`, a **WAF Web ACL** (scope `CLOUDFRONT`) is created in **us-east-1** and attached to the distribution.
- **AppSync** uses **Cognito User Pools** as the default auth mode, with an additional **API_KEY** provider for optional public-style queries. Resolvers invoke **Settings**, **Gremlin**, and **Search** Lambdas.
- **Gremlin** and **Search** Lambdas run in **private subnets** with the Lambda security group; they reach **Neptune** (port 8182) and **OpenSearch** (HTTPS 443) per security group rules.
- **Discovery** runs as **ECS Fargate** in private subnets (`assign_public_ip = false`); tasks pull images from **ECR**. Task definition changes can be ignored by Terraform after first deploy (`lifecycle.ignore_changes` on the service).

### Ingestion, Cost, and Ops

- **Discovery bucket:** Uploads emit **EventBridge** events; **image_deployment** starts **CodeBuild** to build a Docker image and push **`:latest`** to the discovery **ECR** repository.
- **Cost:** A **Cost & Usage Report** is defined in **us-east-1** and delivers **Parquet** to the **CUR** S3 bucket. **Glue** crawls `s3://.../cur/` into a **Glue** database; **Athena** uses a dedicated workgroup with results in an **Athena results** bucket. The **cost** Lambda can query Athena/Glue (optional **EventBridge** schedule).
- **Access logging:** Root `aws_s3_bucket.access_logs` receives server access logs from data buckets (web UI, discovery, CUR, Athena results, Amplify storage) where configured in child modules.
- **Observability:** **SNS** topic receives **CloudWatch** alarm notifications for Lambda error rates, Neptune CPU, OpenSearch cluster red, and ECS service CPU.

---

## Prerequisites

| Tool | Notes |
|------|--------|
| **AWS CLI** | v2 recommended (`aws --version`) |
| **Terraform** | `>= 1.5` (`terraform --version`) |
| **Docker** | Optional — CodeBuild uses Docker in privileged mode for discovery image builds |

**AWS credentials:** Configure credentials for the account and region you set in `terraform.tfvars` (`aws_region`). The stack needs permissions for VPC, IAM, S3, Neptune, OpenSearch, Lambda, AppSync, Cognito, CloudFront, WAF (in **us-east-1**), ECS, ECR, CodeBuild, EventBridge, Glue, Athena, Billing/CUR, Amplify, SNS, CloudWatch, and DynamoDB.

**Dual region note:** The root module defines `provider "aws"` with `alias = "us_east_1"` for resources that must live in **us-east-1** (CloudFront-scoped WAF, CUR report definition). Primary application resources use `var.aws_region`.

---

## Step-by-Step: First Deployment

All Terraform commands below run from **`resource-lens/`** unless noted.

### Step 1 — Configure variables

1. Copy the example file:

   ```bash
   cp terraform.tfvars.example terraform.tfvars
   ```

2. Edit `terraform.tfvars` for your environment (`project_name`, `environment`, `aws_region`, VPC CIDR, Neptune/OpenSearch sizes, ECS task size, WAF, CodeBuild source, optional Amplify and cost schedule, `tags`).

3. This project does **not** require a separate secrets file for Terraform variables — keep any long-lived tokens out of version control if you add them later.

### Step 2 — Initialize Terraform

```bash
terraform init
```

### Step 3 — Plan and apply

```bash
terraform plan
terraform apply
```

The apply creates networking, data stores, Lambdas, web UI, discovery infrastructure, CodeBuild pipeline, cost analytics resources, Amplify, and alarms. **Neptune**, **OpenSearch**, and several **S3** buckets use `prevent_destroy` — plan teardown carefully.

### Step 4 — Seed the discovery container build

1. Upload a **zip** containing your `Dockerfile` (and app source) to the discovery bucket at the key expected by CodeBuild (default in **image_deployment** module: `source/build.zip` — see [modules/image_deployment/README.md](modules/image_deployment/README.md)).

2. **EventBridge** detects **Object Created** and starts **CodeBuild**, which builds and pushes **`:latest`** to ECR.

3. If the service was already running, **force a new ECS deployment** so tasks pull the new image (see [Operations](#operations)).

### Step 5 — Deploy the web UI assets

Sync static files (e.g. `index.html`) to the **web UI S3 bucket** output or use your frontend pipeline. Update **Cognito** app client **callback/logout URLs** in Terraform if you are not using localhost.

Optionally configure **Amplify** (`amplify_repository_url`, `amplify_connect_to_web_ui_bucket`) per [modules/storage/README.md](modules/storage/README.md).

### Step 6 — Verify

1. Open `https://<cloudfront_domain_name>` from outputs (or your custom domain if you add one later).
2. Sign in via **Cognito** (after creating a user in the pool).
3. Call **AppSync** `graphql` URL with a Cognito JWT or API key as appropriate.
4. Check **CloudWatch** log groups for Lambdas and `/ecs/<prefix>-discovery` for ECS.

---

## Repeat Deployments

- **Infrastructure:** Change `terraform.tfvars` or `.tf` files, then `terraform plan` / `terraform apply`.
- **Discovery image:** Upload a new zip to the discovery bucket path; CodeBuild runs again. Run **ECS force new deployment** if the task definition tag is unchanged.
- **Lambda code:** Bundled in-repo under `modules/*/lambdas/`; `terraform apply` updates functions when the zip hash changes.

---

## Configuration Reference

### Terraform Variables

Defined in [`variables.tf`](variables.tf). Override via `terraform.tfvars` / `*.auto.tfvars`.

#### General

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `project_name` | string | — | Short name used in resource prefixes |
| `environment` | string | — | Stage (e.g. dev, prod) |
| `aws_region` | string | `us-east-1` | Primary AWS region for regional resources |
| `tags` | map(string) | `{}` | Extra tags merged where supported |

#### Network

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `vpc_cidr` | string | `10.0.0.0/16` | VPC CIDR block |

#### Data layer (Neptune / OpenSearch)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `neptune_instance_class` | string | `db.r6g.large` | Neptune instance class |
| `neptune_engine_version` | string | `1.3.1.0` | Neptune engine version |
| `opensearch_instance_type` | string | `t3.medium.search` | OpenSearch data node type |
| `opensearch_engine_version` | string | `OpenSearch_2.11` | OpenSearch engine version |

#### Web UI (CloudFront / WAF / Lambdas)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `enable_waf` | bool | `true` | Attach WAF Web ACL to CloudFront |
| `cloudfront_price_class` | string | `PriceClass_100` | CloudFront price class |
| `lambda_memory_size` | number | `256` | Memory (MB) for Lambdas where shared |
| `lambda_reserved_concurrency` | number | `null` | Reserved concurrency (null = account default) |
| `enable_xray` | bool | `true` | Active X-Ray on Lambdas / AppSync where configured |

#### Discovery (ECS)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `ecs_task_cpu` | number | `512` | Fargate CPU units for discovery task |
| `ecs_task_memory` | number | `1024` | Fargate memory (MiB) |
| `ecs_desired_count` | number | `1` | Desired ECS task count |

#### CodeBuild (root passes to **image_deployment**)

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `codebuild_source_type` | string | `S3` | CodeBuild source type (e.g. S3, GITHUB) |
| `codebuild_source_location` | string | `""` | Non-S3 source location when applicable |

See [modules/image_deployment/README.md](modules/image_deployment/README.md) for `codebuild_s3_object_key` (module-only default).

#### Cost

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `athena_workgroup_name` | string | `cost-analysis` | Athena workgroup name |
| `cur_report_name` | string | `daily-cur` | Daily CUR report name |
| `cost_lambda_schedule_expression` | string | `""` | EventBridge schedule for Cost Lambda (empty = none) |

#### Amplify / storage

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `amplify_repository_url` | string | `""` | Git URL for Amplify app, or empty |
| `amplify_connect_to_web_ui_bucket` | bool | `false` | Wire Amplify env to web UI bucket pattern |

### Secrets and Sensitive Inputs

- No Terraform variables in this root module are marked `sensitive` or require a dedicated `secrets.auto.tfvars` for core functionality.
- **Cognito** default callback URLs are **localhost** — update for production hosts.
- **AppSync** creates an **API key** with a long expiry; rotate or restrict usage as needed.

### Provider and Tags

[`providers.tf`](providers.tf) sets Terraform `>= 1.5`, AWS provider `~> 5.0`, and **default_tags** on both the default provider and **`aws.us_east_1`**: `Project`, `Environment`, `ManagedBy`. Merge additional tags via `tags` in tfvars.

---

## Terraform Outputs

| Output | Description |
|--------|-------------|
| `access_logs_bucket_id` | Central S3 server access logging bucket |
| `vpc_id` | VPC ID |
| `cloudfront_domain_name` | CloudFront domain for static web UI |
| `cloudfront_distribution_id` | CloudFront distribution ID |
| `appsync_graphql_url` | AppSync GraphQL HTTPS endpoint |
| `appsync_api_id` | AppSync API ID |
| `cognito_user_pool_id` | Cognito user pool ID |
| `cognito_user_pool_client_id` | Cognito app client ID (SPA) |
| `neptune_cluster_endpoint` | Neptune cluster endpoint |
| `opensearch_endpoint` | OpenSearch domain endpoint |
| `discovery_bucket_id` | Discovery artifacts S3 bucket |
| `ecr_repository_url` | Discovery ECR repository URL |
| `ecs_cluster_name` | ECS cluster name (discovery) |
| `cur_bucket_id` | CUR delivery S3 bucket |
| `athena_workgroup_name` | Athena workgroup (from variable) |
| `glue_database_name` | Glue catalog database for CUR |
| `amplify_app_id` | Amplify application ID |
| `amplify_default_domain` | Amplify default domain |
| `amplify_storage_bucket_id` | Amplify storage S3 bucket |
| `sns_alerts_topic_arn` | SNS topic for alarm notifications |
| `codebuild_project_name` | CodeBuild project name (discovery image) |

---

## Operations

### Force ECS discovery to pull a new image

After CodeBuild pushes `:latest`, force task replacement. Discovery service name is **`${project_name}-${environment}-discovery-service`** (same prefix as `ecs_cluster_name`, which ends with `-discovery-cluster`).

**Bash** (set `REGION` to match `aws_region` in `terraform.tfvars`):

```bash
REGION=us-east-1
CLUSTER="$(terraform output -raw ecs_cluster_name)"
SERVICE="<project_name>-<environment>-discovery-service"

aws ecs update-service \
  --region "$REGION" \
  --cluster "$CLUSTER" \
  --service "$SERVICE" \
  --force-new-deployment
```

**PowerShell:**

```powershell
$Region = "us-east-1"   # match var.aws_region
$Cluster = terraform output -raw ecs_cluster_name
$Service = "<project_name>-<environment>-discovery-service"

aws ecs update-service `
  --region $Region `
  --cluster $Cluster `
  --service $Service `
  --force-new-deployment
```

Replace `<project_name>` and `<environment>` with values from `terraform.tfvars`, or copy the service name from the ECS console.

### Invoke Cost Lambda manually

```bash
aws lambda invoke --function-name "<project>-<env>-cost" --payload '{}' out.json
cat out.json
```

### Enable cost schedule

Set `cost_lambda_schedule_expression` in `terraform.tfvars` (e.g. `cron(0 12 * * ? *)`) and `terraform apply`.

### Teardown

1. Empty **S3** buckets that block destroy (versioned objects, access logs objects).
2. **Neptune** / **OpenSearch**: snapshots and `prevent_destroy` may require Terraform changes or manual steps.
3. **CUR**: disable or remove report in Billing console if needed before bucket deletion.
4. Run `terraform destroy`.

---

## How the Root Module Wires Things Together

[`main.tf`](main.tf) composes modules in this dependency shape:

```
aws_s3_bucket.access_logs (root)
module.networking
    ├── module.data (vpc_id, private subnets, security groups)
    └── module.discovery (vpc_id, private subnets, sg_ecs)

module.data
    └── module.web_ui (gremlin_lambda_arn, search_lambda_arn)

module.web_ui
    └── module.storage (cloudfront_domain_name, web_ui_bucket_id)

module.discovery
    └── module.image_deployment (discovery_bucket, ecr_repo)

module.cost (uses access_logs + provider aws.us_east_1 for CUR)

module.observability
    └── depends_on [web_ui, data, cost, discovery]
```

---

## Terraform Modules Index

Each module has its own README with purpose, inputs, outputs, and dependency notes.

| Module | What it creates | README |
|--------|-----------------|--------|
| **networking** | VPC, subnets, NAT, security groups | [modules/networking/README.md](modules/networking/README.md) |
| **data** | Neptune, OpenSearch, Gremlin + Search Lambdas | [modules/data/README.md](modules/data/README.md) |
| **web_ui** | S3, CloudFront, WAF, Cognito, AppSync, Settings Lambda, DynamoDB | [modules/web_ui/README.md](modules/web_ui/README.md) |
| **discovery** | Discovery S3, ECR, ECS Fargate | [modules/discovery/README.md](modules/discovery/README.md) |
| **image_deployment** | CodeBuild, EventBridge → CodeBuild | [modules/image_deployment/README.md](modules/image_deployment/README.md) |
| **cost** | CUR, Athena, Glue, Cost Lambda | [modules/cost/README.md](modules/cost/README.md) |
| **storage** | Amplify app, branch, storage bucket | [modules/storage/README.md](modules/storage/README.md) |
| **observability** | SNS, CloudWatch alarms | [modules/observability/README.md](modules/observability/README.md) |

---

## Cost Notes

Rough categories (varies by region and usage):

| Area | Notes |
|------|--------|
| **VPC** | NAT Gateway hourly + data processing |
| **Neptune** | Instance hours, storage, I/O |
| **OpenSearch** | Instance hours, EBS |
| **Lambda** | Invocations, duration, optional X-Ray |
| **AppSync** | Requests, caching (if added) |
| **CloudFront** | Data transfer + requests |
| **WAF** | Web ACL + rule capacity units |
| **ECS Fargate** | vCPU and memory for discovery tasks |
| **ECR** | Image storage |
| **CodeBuild** | Build minutes |
| **S3** | Storage and requests (web UI, discovery, CUR, Athena results, Amplify storage, access logs) |
| **Athena** | Data scanned per query |
| **Glue** | Crawler and catalog operations |
| **Amplify** | Build/hosting if used |
| **CloudWatch** | Logs and alarms |
| **SNS** | Notifications |

Use **AWS Cost Explorer** and tag-based reports (`Project`, `Environment`, etc.) for actuals.

---

## Related Documentation

| Topic | Location |
|-------|----------|
| Example Terraform values | [terraform.tfvars.example](terraform.tfvars.example) |
| Workspace rule (graphify) | [.cursor/rules/graphify.mdc](.cursor/rules/graphify.mdc) |
| Module READMEs | [modules/](modules/) (see [Terraform Modules Index](#terraform-modules-index)) |
