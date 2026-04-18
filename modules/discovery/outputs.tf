output "discovery_bucket_id" {
  value = aws_s3_bucket.discovery.id
}

output "discovery_bucket_arn" {
  value = aws_s3_bucket.discovery.arn
}

output "ecr_repository_url" {
  value = aws_ecr_repository.discovery.repository_url
}

output "ecr_repository_arn" {
  value = aws_ecr_repository.discovery.arn
}

output "ecs_cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "ecs_cluster_arn" {
  value = aws_ecs_cluster.this.id
}

output "ecs_service_name" {
  value = aws_ecs_service.discovery.name
}

output "ecs_task_definition_arn" {
  value = aws_ecs_task_definition.discovery.arn
}

output "ecs_task_execution_role_arn" {
  value = aws_iam_role.ecs_execution.arn
}

output "ecs_log_group_name" {
  value = aws_cloudwatch_log_group.ecs.name
}
