# Module: networking

## Purpose

Creates the **VPC** foundation for Resource Lens: **public and private subnets** across two Availability Zones, **Internet Gateway**, **NAT Gateway** (single NAT in the first public subnet), routing, and **security groups** for Lambda, Neptune, OpenSearch, and ECS tasks. Security group rules allow Lambda to reach Neptune (8182) and OpenSearch (443) and general HTTPS/DNS egress.

## Resources Created

- `data.aws_availability_zones`
- `aws_vpc`, `aws_internet_gateway`
- `aws_subnet` (public ×2, private ×2)
- `aws_eip`, `aws_nat_gateway`
- `aws_route_table` (public, private), `aws_route_table_association`
- `aws_security_group` (lambda, neptune, opensearch, ecs)
- `aws_security_group_rule` (Neptune/OpenSearch ingress from Lambda; Lambda egress to Neptune/OpenSearch/HTTPS/DNS; ECS ingress HTTP/HTTPS from VPC CIDR; egress rules for ECS, Neptune, OpenSearch)

## Inputs

| Name | Type | Description |
|------|------|-------------|
| `project_name` | string | Project prefix for naming |
| `environment` | string | Environment name |
| `vpc_cidr` | string | VPC CIDR block |
| `tags` | map(string) | Optional extra tags (default `{}`) |

## Outputs

| Name | Description |
|------|-------------|
| `vpc_id` | VPC ID |
| `public_subnet_ids` | Public subnet IDs |
| `private_subnet_ids` | Private subnet IDs |
| `sg_lambda_id` | Security group ID for VPC Lambdas |
| `sg_neptune_id` | Security group ID for Neptune |
| `sg_opensearch_id` | Security group ID for OpenSearch |
| `sg_ecs_id` | Security group ID for ECS tasks |
| `vpc_cidr_block` | VPC CIDR block |

## Dependencies

- None (foundational module).

## Notes

- Private subnets use the NAT Gateway for outbound internet (e.g. Lambda AWS APIs, ECS pulls).
- Neptune and OpenSearch clusters are **not** created here; see the **data** module.
