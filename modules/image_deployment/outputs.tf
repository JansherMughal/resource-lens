output "codebuild_project_name" {
  value = aws_codebuild_project.discovery.name
}

output "codebuild_project_arn" {
  value = aws_codebuild_project.discovery.arn
}

output "eventbridge_rule_arn" {
  value = aws_cloudwatch_event_rule.s3_put.arn
}
