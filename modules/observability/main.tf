locals {
  name_prefix = "${var.project_name}-${var.environment}"
  common_tags = merge(
    { Component = "observability" },
    var.tags,
  )
}

# --- SNS ---

resource "aws_sns_topic" "alerts" {
  name = "${local.name_prefix}-alerts-topic"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-alerts-topic" })
}

# Lambda log groups (/aws/lambda/...) are created in web_ui, data, and cost modules before functions run.
# ECS log group is created in the discovery module.

# --- Alarms: Lambda error rate > 1% ---

resource "aws_cloudwatch_metric_alarm" "lambda_error_rate" {
  for_each = var.lambda_function_names

  alarm_name          = "${local.name_prefix}-${each.key}-lambda-error-rate"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  threshold           = 1
  alarm_description   = "Lambda ${each.value} error rate > 1%"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  metric_query {
    id          = "m1"
    return_data = false
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Invocations"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = each.value
      }
    }
  }

  metric_query {
    id          = "m2"
    return_data = false
    metric {
      namespace   = "AWS/Lambda"
      metric_name = "Errors"
      period      = 300
      stat        = "Sum"
      dimensions = {
        FunctionName = each.value
      }
    }
  }

  metric_query {
    id          = "e1"
    return_data = true
    expression  = "IF(m1>0, (m2/m1)*100, 0)"
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-${each.key}-lambda-err" })
}

# --- Neptune CPU ---

resource "aws_cloudwatch_metric_alarm" "neptune_cpu" {
  alarm_name          = "${local.name_prefix}-neptune-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/Neptune"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "Neptune CPU > 80%"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DBClusterIdentifier = var.neptune_cluster_identifier
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-neptune-cpu" })
}

# --- OpenSearch cluster status red ---

resource "aws_cloudwatch_metric_alarm" "opensearch_red" {
  alarm_name          = "${local.name_prefix}-opensearch-red"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 1
  metric_name         = "ClusterStatus.red"
  namespace           = "AWS/ES"
  period              = 60
  statistic           = "Maximum"
  threshold           = 1
  alarm_description   = "OpenSearch cluster status red"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    DomainName = var.opensearch_domain_name
    ClientId   = data.aws_caller_identity.current.account_id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-opensearch-red" })
}

data "aws_caller_identity" "current" {}

# --- ECS service CPU ---

resource "aws_cloudwatch_metric_alarm" "ecs_cpu" {
  alarm_name          = "${local.name_prefix}-ecs-cpu"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/ECS"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  alarm_description   = "ECS service CPU > 80%"
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]

  dimensions = {
    ClusterName = var.ecs_cluster_name
    ServiceName = var.ecs_service_name
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-ecs-cpu" })
}
