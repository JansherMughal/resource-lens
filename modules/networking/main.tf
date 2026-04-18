data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "${var.project_name}-${var.environment}"
  azs         = slice(data.aws_availability_zones.available.names, 0, 2)
  common_tags = merge(
    {
      Component = "networking"
    },
    var.tags,
  )
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-vpc" })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-igw" })
}

resource "aws_subnet" "public" {
  count = 2

  vpc_id                  = aws_vpc.this.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-${count.index + 1}" })
}

resource "aws_subnet" "private" {
  count = 2

  vpc_id            = aws_vpc.this.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 2)
  availability_zone = local.azs[count.index]

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private-${count.index + 1}" })
}

resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nat-eip" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public[0].id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-nat" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-public-rt" })
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this.id
  }

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-private-rt" })
}

resource "aws_route_table_association" "private" {
  count = length(aws_subnet.private)

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# --- Security groups (referenced by name in architecture) ---

resource "aws_security_group" "lambda" {
  name        = "${local.name_prefix}-sg-lambda"
  description = "Lambda in VPC: egress to Neptune, OpenSearch, and HTTPS"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg-lambda" })
}

resource "aws_security_group" "neptune" {
  name        = "${local.name_prefix}-sg-neptune"
  description = "Neptune: Gremlin from Lambda only"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg-neptune" })
}

resource "aws_security_group" "opensearch" {
  name        = "${local.name_prefix}-sg-opensearch"
  description = "OpenSearch: HTTPS from Lambda only"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg-opensearch" })
}

resource "aws_security_group" "ecs" {
  name        = "${local.name_prefix}-sg-ecs"
  description = "ECS tasks: HTTP/S from VPC (ALB or internal)"
  vpc_id      = aws_vpc.this.id

  tags = merge(local.common_tags, { Name = "${local.name_prefix}-sg-ecs" })
}

# Neptune ingress from Lambda SG
resource "aws_security_group_rule" "neptune_from_lambda" {
  type                     = "ingress"
  security_group_id        = aws_security_group.neptune.id
  from_port                = 8182
  to_port                  = 8182
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda.id
}

# OpenSearch ingress from Lambda SG
resource "aws_security_group_rule" "opensearch_from_lambda" {
  type                     = "ingress"
  security_group_id        = aws_security_group.opensearch.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.lambda.id
}

# Lambda egress: Neptune
resource "aws_security_group_rule" "lambda_to_neptune" {
  type                     = "egress"
  security_group_id        = aws_security_group.lambda.id
  from_port                = 8182
  to_port                  = 8182
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.neptune.id
}

# Lambda egress: OpenSearch HTTPS
resource "aws_security_group_rule" "lambda_to_opensearch" {
  type                     = "egress"
  security_group_id        = aws_security_group.lambda.id
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.opensearch.id
}

# Lambda egress: general HTTPS (AppSync, AWS APIs, NAT path, etc.)
resource "aws_security_group_rule" "lambda_to_internet_https" {
  type              = "egress"
  security_group_id = aws_security_group.lambda.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Resolver traffic to Route 53 Resolver / AmazonProvidedDNS inside the VPC (required for Neptune/OpenSearch DNS names)
resource "aws_security_group_rule" "lambda_dns_udp" {
  type              = "egress"
  security_group_id = aws_security_group.lambda.id
  from_port         = 53
  to_port           = 53
  protocol          = "udp"
  cidr_blocks       = [aws_vpc.this.cidr_block]
}

# ECS ingress from VPC (covers ALB in VPC or east-west traffic)
resource "aws_security_group_rule" "ecs_ingress_http" {
  type              = "ingress"
  security_group_id = aws_security_group.ecs.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.this.cidr_block]
}

resource "aws_security_group_rule" "ecs_ingress_https" {
  type              = "ingress"
  security_group_id = aws_security_group.ecs.id
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = [aws_vpc.this.cidr_block]
}

resource "aws_security_group_rule" "ecs_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.ecs.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

# Deny-by-default: no extra egress on Neptune/OpenSearch SGs beyond what AWS adds implicitly is N/A;
# Neptune/OpenSearch need egress for AWS management — use default egress all (AWS adds default allow all egress on creation)
# Explicit default egress for Neptune cluster ENIs is typically open; we add explicit egress all for clarity.
resource "aws_security_group_rule" "neptune_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.neptune.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}

resource "aws_security_group_rule" "opensearch_egress_all" {
  type              = "egress"
  security_group_id = aws_security_group.opensearch.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
}
