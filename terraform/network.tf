# VPC
resource "aws_vpc" "pg_cluster" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "pg-cluster-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "pg_cluster" {
  vpc_id = aws_vpc.pg_cluster.id

  tags = {
    Name = "pg-cluster-igw"
  }
}

# Subnet — single AZ
resource "aws_subnet" "pg_cluster" {
  vpc_id                  = aws_vpc.pg_cluster.id
  cidr_block              = var.subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = false

  tags = {
    Name = "pg-cluster-subnet"
  }
}

# Route Table
resource "aws_route_table" "pg_cluster" {
  vpc_id = aws_vpc.pg_cluster.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.pg_cluster.id
  }

  tags = {
    Name = "pg-cluster-rt"
  }
}

# Route Table Association
resource "aws_route_table_association" "pg_cluster" {
  subnet_id      = aws_subnet.pg_cluster.id
  route_table_id = aws_route_table.pg_cluster.id
}

# VPC Gateway Endpoint for S3 — free, keeps backup traffic private
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.pg_cluster.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.pg_cluster.id]

  tags = {
    Name = "pg-cluster-s3-endpoint"
  }
}
