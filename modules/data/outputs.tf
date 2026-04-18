output "neptune_cluster_endpoint" {
  value = aws_neptune_cluster.this.endpoint
}

output "neptune_cluster_id" {
  value = aws_neptune_cluster.this.id
}

output "neptune_cluster_identifier" {
  value = aws_neptune_cluster.this.cluster_identifier
}

output "neptune_cluster_arn" {
  value = aws_neptune_cluster.this.arn
}

output "opensearch_endpoint" {
  value = aws_opensearch_domain.this.endpoint
}

output "opensearch_domain_name" {
  value = aws_opensearch_domain.this.domain_name
}

output "opensearch_domain_arn" {
  value = aws_opensearch_domain.this.arn
}

output "gremlin_lambda_function_arn" {
  value = aws_lambda_function.gremlin.arn
}

output "gremlin_lambda_function_name" {
  value = aws_lambda_function.gremlin.function_name
}

output "search_lambda_function_arn" {
  value = aws_lambda_function.search.arn
}

output "search_lambda_function_name" {
  value = aws_lambda_function.search.function_name
}
