data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(
    { Component = "discovery" },
    var.tags,
  )
  # Log group path per spec; prefix with project/env for uniqueness.
  ecs_log_group_name = "/ecs/${local.name_prefix}-discovery"
}

# --- Discovery artifacts bucket ---

resource "aws_s3_bucket" "discovery" {
  bucket = "${local.name_prefix}-discovery-${data.aws_caller_identity.current.account_id}"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-discovery" })

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "discovery" {
  bucket = aws_s3_bucket.discovery.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "discovery" {
  bucket = aws_s3_bucket.discovery.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "discovery" {
  bucket = aws_s3_bucket.discovery.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "discovery" {
  bucket = aws_s3_bucket.discovery.id

  target_bucket = var.access_logs_bucket_id
  target_prefix = "${local.name_prefix}/discovery/"
}

# Enable EventBridge notifications for image_deployment pipeline (single notification resource per bucket).
resource "aws_s3_bucket_notification" "eventbridge" {
  bucket = aws_s3_bucket.discovery.id

  eventbridge = true

  depends_on = [aws_s3_bucket.discovery]
}

# --- ECR ---

resource "aws_ecr_repository" "discovery" {
  name                 = "${local.name_prefix}-discovery-service"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-discovery-ecr" })
}

# --- ECS cluster + capacity providers ---

resource "aws_ecs_cluster" "this" {
  name = "${local.name_prefix}-discovery-cluster"

  setting {
    name  = "containerInsights"
    value = "enabled"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-discovery-cluster" })
}

resource "aws_ecs_cluster_capacity_providers" "this" {
  cluster_name = aws_ecs_cluster.this.name

  capacity_providers = ["FARGATE", "FARGATE_SPOT"]

  default_capacity_provider_strategy {
    capacity_provider = "FARGATE"
    weight            = 1
    base              = 0
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = local.ecs_log_group_name
  retention_in_days = 14

  tags = merge(local.common_tags, { Name = local.ecs_log_group_name })
}

# --- IAM: task execution ---

data "aws_iam_policy_document" "ecs_execution_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_execution" {
  name               = "${local.name_prefix}-ecs-exec"
  assume_role_policy = data.aws_iam_policy_document.ecs_execution_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecs-exec" })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_managed" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ecs_execution_extra" {
  statement {
    sid    = "EcrPull"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcrReadRepo"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:GetDownloadUrlForLayer",
      "ecr:BatchGetImage",
    ]
    resources = [aws_ecr_repository.discovery.arn]
  }

  statement {
    sid    = "CwLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["${aws_cloudwatch_log_group.ecs.arn}:*"]
  }
}

resource "aws_iam_role_policy" "ecs_execution_extra" {
  name   = "exec-extra"
  role   = aws_iam_role.ecs_execution.id
  policy = data.aws_iam_policy_document.ecs_execution_extra.json
}

# --- IAM: task role (application permissions; extend as needed) ---

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task" {
  name               = "${local.name_prefix}-ecs-task"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecs-task" })
}

# --- Task definition & service ---
# Image must exist in ECR (push initial image before stable deploy).

resource "aws_ecs_task_definition" "discovery" {
  family                   = "${local.name_prefix}-discovery-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = tostring(var.ecs_task_cpu)
  memory                   = tostring(var.ecs_task_memory)
  execution_role_arn       = aws_iam_role.ecs_execution.arn
  task_role_arn            = aws_iam_role.ecs_task.arn

  container_definitions = jsonencode([
    {
      name      = "discovery"
      image     = "${aws_ecr_repository.discovery.repository_url}:latest"
      essential = true
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.ecs.name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-discovery-task" })
}

resource "aws_ecs_service" "discovery" {
  name            = "${local.name_prefix}-discovery-service"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.discovery.arn
  desired_count   = var.ecs_desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [var.sg_ecs_id]
    assign_public_ip = false
  }

  deployment_minimum_healthy_percent = 50
  deployment_maximum_percent         = 200

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-discovery-service" })

  lifecycle {
    ignore_changes = [task_definition]
  }
}
