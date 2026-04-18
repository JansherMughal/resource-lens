locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(
    { Component = "image_deployment" },
    var.tags,
  )

  # S3 source location for CodeBuild when using S3 (zip uploaded by CI or manually).
  s3_source_location = "${var.discovery_bucket_id}/${var.codebuild_s3_object_key}"
}

# --- CodeBuild IAM ---

data "aws_iam_policy_document" "codebuild_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["codebuild.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "codebuild" {
  name               = "${local.name_prefix}-codebuild"
  assume_role_policy = data.aws_iam_policy_document.codebuild_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-codebuild" })
}

data "aws_iam_policy_document" "codebuild" {
  statement {
    sid    = "CloudWatchLogs"
    effect = "Allow"
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
    ]
    resources = ["arn:aws:logs:*:*:log-group:/aws/codebuild/*"]
  }

  statement {
    sid    = "S3ReadSource"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectVersion",
      "s3:ListBucket",
    ]
    resources = [
      var.discovery_bucket_arn,
      "${var.discovery_bucket_arn}/*",
    ]
  }

  statement {
    sid    = "EcrAuthAndPush"
    effect = "Allow"
    actions = [
      "ecr:GetAuthorizationToken",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "EcrPush"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:PutImage",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
    ]
    resources = [var.ecr_repository_arn]
  }
}

resource "aws_iam_role_policy" "codebuild" {
  name   = "codebuild-policy"
  role   = aws_iam_role.codebuild.id
  policy = data.aws_iam_policy_document.codebuild.json
}

resource "aws_codebuild_project" "discovery" {
  name          = "${local.name_prefix}-discovery-image-builder"
  description   = "Builds and pushes discovery container image to ECR"
  build_timeout = 60
  service_role  = aws_iam_role.codebuild.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type    = "BUILD_GENERAL1_SMALL"
    image           = "aws/codebuild/standard:7.0"
    type            = "LINUX_CONTAINER"
    privileged_mode = true

    environment_variable {
      name  = "ECR_REPOSITORY_URI"
      value = var.ecr_repository_url
    }

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = data.aws_region.current.name
    }
  }

  source {
    type      = var.codebuild_source_type
    location  = var.codebuild_source_type == "S3" ? local.s3_source_location : var.codebuild_source_location
    buildspec = <<-EOT
      version: 0.2
      phases:
        pre_build:
          commands:
            - echo Logging in to Amazon ECR...
            - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $(echo $ECR_REPOSITORY_URI | cut -d/ -f1)
        build:
          commands:
            - echo Build started on `date`
            - |
              if [ -f Dockerfile ]; then
                docker build -t discovery:latest .
              else
                echo "No Dockerfile in source; using public placeholder (replace with real Dockerfile)."
                echo 'FROM public.ecr.aws/docker/library/nginx:alpine' > Dockerfile
                docker build -t discovery:latest .
              fi
            - docker tag discovery:latest $ECR_REPOSITORY_URI:latest
        post_build:
          commands:
            - echo Pushing the Docker image...
            - docker push $ECR_REPOSITORY_URI:latest
      EOT
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-discovery-image-builder" })
}

data "aws_region" "current" {}

# --- EventBridge: S3 PutObject -> CodeBuild ---

data "aws_iam_policy_document" "events_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "events_invoke" {
  name               = "${local.name_prefix}-events-codebuild"
  assume_role_policy = data.aws_iam_policy_document.events_assume.json

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-events-codebuild" })
}

data "aws_iam_policy_document" "events_invoke" {
  statement {
    effect = "Allow"
    actions = [
      "codebuild:StartBuild",
    ]
    resources = [aws_codebuild_project.discovery.arn]
  }
}

resource "aws_iam_role_policy" "events_invoke" {
  name   = "invoke-codebuild"
  role   = aws_iam_role.events_invoke.id
  policy = data.aws_iam_policy_document.events_invoke.json
}

resource "aws_cloudwatch_event_rule" "s3_put" {
  name        = "${local.name_prefix}-discovery-s3-put"
  description = "Trigger CodeBuild when objects are uploaded to the discovery bucket"

  event_pattern = jsonencode({
    source      = ["aws.s3"]
    detail-type = ["Object Created"]
    detail = {
      bucket = {
        name = [var.discovery_bucket_id]
      }
    }
  })

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-discovery-s3-put" })
}

resource "aws_cloudwatch_event_target" "codebuild" {
  rule      = aws_cloudwatch_event_rule.s3_put.name
  target_id = "CodeBuild"
  arn       = aws_codebuild_project.discovery.arn
  role_arn  = aws_iam_role.events_invoke.arn
}
