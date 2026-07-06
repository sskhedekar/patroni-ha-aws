# Latest Ubuntu 24.04 LTS AMI — dynamically fetched so it stays current
data "aws_ami" "ubuntu_24_04" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# pg-node-1 — primary candidate, holds VIP secondary IP 10.0.0.100
resource "aws_instance" "pg_node_1" {
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = var.pg_nodes["pg-node-1"].instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.pg_cluster.id
  private_ip             = var.pg_nodes["pg-node-1"].private_ip
  secondary_private_ips  = ["10.0.0.100"]
  vpc_security_group_ids = [aws_security_group.pg_cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.pg_cluster.name
  user_data_base64       = filebase64("${path.module}/scripts/userdata-pg-node.sh")

  root_block_device {
    volume_type = "gp3"
    volume_size = var.pg_nodes["pg-node-1"].volume_size
    encrypted   = false
  }

  lifecycle {
    ignore_changes = [secondary_private_ips]
  }

  tags = {
    Name = "pg-node-1"
  }
}

# pg-node-2 and pg-node-3
resource "aws_instance" "pg_nodes" {
  for_each = {
    for k, v in var.pg_nodes : k => v
    if k != "pg-node-1"
  }

  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = each.value.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.pg_cluster.id
  private_ip             = each.value.private_ip
  vpc_security_group_ids = [aws_security_group.pg_cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.pg_cluster.name
  user_data_base64       = filebase64("${path.module}/scripts/userdata-pg-node.sh")

  root_block_device {
    volume_type = "gp3"
    volume_size = each.value.volume_size
    encrypted   = false
  }

  lifecycle {
    ignore_changes = [secondary_private_ips]
  }

  tags = {
    Name = each.key
  }
}

# pgbr-host — pgBackRest repository host
resource "aws_instance" "pgbr_host" {
  ami                    = data.aws_ami.ubuntu_24_04.id
  instance_type          = var.pgbr_host.instance_type
  key_name               = var.key_pair_name
  subnet_id              = aws_subnet.pg_cluster.id
  private_ip             = var.pgbr_host.private_ip
  vpc_security_group_ids = [aws_security_group.pg_cluster.id]
  iam_instance_profile   = aws_iam_instance_profile.pg_cluster.name

  root_block_device {
    volume_type = "gp3"
    volume_size = var.pgbr_host.volume_size
    encrypted   = false
  }

  tags = {
    Name = "pgbr-host"
  }
}

# Elastic IP — pg-node-1
resource "aws_eip" "pg_node_1" {
  domain = "vpc"
  tags   = { Name = "pg-node-1-eip" }
}

# Elastic IPs — pg-node-2 and pg-node-3
resource "aws_eip" "pg_nodes" {
  for_each = {
    for k, v in var.pg_nodes : k => v
    if k != "pg-node-1"
  }
  domain = "vpc"
  tags   = { Name = "${each.key}-eip" }
}

# Elastic IP — pgbr-host
resource "aws_eip" "pgbr_host" {
  domain = "vpc"
  tags   = { Name = "pgbr-host-eip" }
}

# Associate Elastic IP with pg-node-1
resource "aws_eip_association" "pg_node_1" {
  instance_id   = aws_instance.pg_node_1.id
  allocation_id = aws_eip.pg_node_1.id
}

# Associate Elastic IPs with pg-node-2 and pg-node-3
resource "aws_eip_association" "pg_nodes" {
  for_each = {
    for k, v in var.pg_nodes : k => v
    if k != "pg-node-1"
  }
  instance_id   = aws_instance.pg_nodes[each.key].id
  allocation_id = aws_eip.pg_nodes[each.key].id
}

# Associate Elastic IP with pgbr-host
resource "aws_eip_association" "pgbr_host" {
  instance_id   = aws_instance.pgbr_host.id
  allocation_id = aws_eip.pgbr_host.id
}
