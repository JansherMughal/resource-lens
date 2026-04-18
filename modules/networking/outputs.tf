output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  value = aws_subnet.private[*].id
}

output "sg_lambda_id" {
  value = aws_security_group.lambda.id
}

output "sg_neptune_id" {
  value = aws_security_group.neptune.id
}

output "sg_opensearch_id" {
  value = aws_security_group.opensearch.id
}

output "sg_ecs_id" {
  value = aws_security_group.ecs.id
}

output "vpc_cidr_block" {
  value = aws_vpc.this.cidr_block
}
