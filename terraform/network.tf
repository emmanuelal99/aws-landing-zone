# Landing zone network (Dev account)
# Shared by workloads: VPC, public and private subnets, internet gateway,
# route tables and a free S3 gateway endpoint. The NAT gateway is created
# on demand by scripts/nat-on.sh and is not managed here.

locals {
  common_tags = {
    Project = "Portfolio"
    Env     = "Dev"
    Owner   = "Emmy"
  }
}

resource "aws_vpc" "portfolio" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "portfolio-vpc" })
}

resource "aws_internet_gateway" "portfolio" {
  vpc_id = aws_vpc.portfolio.id

  tags = merge(local.common_tags, { Name = "portfolio-igw" })
}

# Public subnet: holds the NAT gateway when it is switched on. No instances.
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.portfolio.id
  cidr_block              = "10.0.0.0/28"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, { Name = "portfolio-public-a" })
}

# Private subnet: workloads run here with no public IP addresses.
resource "aws_subnet" "private_a" {
  vpc_id                  = aws_vpc.portfolio.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-west-2a"
  map_public_ip_on_launch = false

  tags = merge(local.common_tags, { Name = "portfolio-private-a" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.portfolio.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.portfolio.id
  }

  tags = merge(local.common_tags, { Name = "portfolio-public-rt" })
}

# No "route" argument on purpose: nat-on.sh adds and nat-off.sh removes the
# 0.0.0.0/0 route. Leaving it out stops Terraform from removing that route.
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.portfolio.id

  tags = merge(local.common_tags, { Name = "portfolio-private-rt" })
}

resource "aws_route_table_association" "public_a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

# Without this, the private subnet falls back to the main route table
# (the cause of TargetNotConnected in Phase 6).
resource "aws_route_table_association" "private_a" {
  subnet_id      = aws_subnet.private_a.id
  route_table_id = aws_route_table.private.id
}

# Free gateway endpoint: private access to S3 without the NAT.
# The full-access policy is kept as it is for now. Restricting it is a
# deferred Prowler finding (vpc_endpoint_connections_trust_boundaries).
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.portfolio.id
  service_name      = "com.amazonaws.eu-west-2.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.private.id]

  policy = jsonencode({
    Version = "2008-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = "*"
      Action    = "*"
      Resource  = "*"
    }]
  })

  tags = merge(local.common_tags, { Name = "portfolio-s3-endpoint" })
}
