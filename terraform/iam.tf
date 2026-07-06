data "aws_iam_policy_document" "assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "vip_management" {
  statement {
    effect    = "Allow"
    actions   = ["ec2:AssignPrivateIpAddresses", "ec2:DescribeNetworkInterfaces"]
    resources = ["*"]
  }
}

data "aws_iam_policy_document" "pgbackrest_s3" {
  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ]
    resources = [
      "arn:aws:s3:::${var.s3_bucket_name}",
      "arn:aws:s3:::${var.s3_bucket_name}/*"
    ]
  }
}

# IAM Role
resource "aws_iam_role" "pg_cluster_vip" {
  name               = "pg-cluster-vip-role"
  assume_role_policy = data.aws_iam_policy_document.assume_role.json

  tags = {
    Name = "pg-cluster-vip-role"
  }
}

# VIP management inline policy
resource "aws_iam_role_policy" "vip_management" {
  name   = "pg-cluster-vip-policy"
  role   = aws_iam_role.pg_cluster_vip.id
  policy = data.aws_iam_policy_document.vip_management.json
}

# pgBackRest S3 inline policy
resource "aws_iam_role_policy" "pgbackrest_s3" {
  name   = "pg-cluster-pgbackrest-policy"
  role   = aws_iam_role.pg_cluster_vip.id
  policy = data.aws_iam_policy_document.pgbackrest_s3.json
}

# Instance profile — attached to all EC2 instances
resource "aws_iam_instance_profile" "pg_cluster" {
  name = "pg-cluster-instance-profile"
  role = aws_iam_role.pg_cluster_vip.name
}
