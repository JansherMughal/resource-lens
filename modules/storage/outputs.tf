output "amplify_app_id" {
  value = aws_amplify_app.this.id
}

output "amplify_default_domain" {
  value = aws_amplify_app.this.default_domain
}

output "amplify_storage_bucket_id" {
  value = aws_s3_bucket.amplify_storage.id
}

output "amplify_storage_bucket_arn" {
  value = aws_s3_bucket.amplify_storage.arn
}

output "amplify_service_role_arn" {
  value = aws_iam_role.amplify.arn
}
