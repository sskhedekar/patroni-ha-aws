resource "aws_security_group" "pg_cluster" {
  name        = "pg-cluster-sg"
  description = "Security group for Patroni HA cluster"
  vpc_id      = aws_vpc.pg_cluster.id

  # SSH — open to all (change to your IP for production)
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  # etcd client
  ingress {
    from_port   = 2379
    to_port     = 2379
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
    description = "etcd client"
  }

  # etcd peer
  ingress {
    from_port   = 2380
    to_port     = 2380
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
    description = "etcd peer"
  }

  # PostgreSQL
  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
    description = "PostgreSQL"
  }

  # Patroni REST API
  ingress {
    from_port   = 8008
    to_port     = 8008
    protocol    = "tcp"
    cidr_blocks = [var.subnet_cidr]
    description = "Patroni REST API"
  }

  # HAProxy primary port
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HAProxy primary"
  }

  # HAProxy replica port
  ingress {
    from_port   = 5001
    to_port     = 5001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HAProxy replica"
  }

  # HAProxy stats UI
  ingress {
    from_port   = 7000
    to_port     = 7000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HAProxy stats"
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound"
  }

  tags = {
    Name = "pg-cluster-sg"
  }
}
