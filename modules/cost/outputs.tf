output "cur_bucket_id" {
  value = aws_s3_bucket.cur.id
}

output "athena_results_bucket_id" {
  value = aws_s3_bucket.athena_results.id
}

output "glue_database_name" {
  value = aws_glue_catalog_database.cur.name
}

output "cost_lambda_function_name" {
  value = aws_lambda_function.cost.function_name
}

output "cost_lambda_function_arn" {
  value = aws_lambda_function.cost.arn
}
