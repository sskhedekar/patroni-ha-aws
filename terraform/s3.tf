# pgBackRest backup bucket
resource "aws_s3_bucket" "pgbackrest" {
  bucket        = var.s3_bucket_name
  force_destroy = true

  tags = {
    Name = var.s3_bucket_name
  }
}

# Block all public access
resource "aws_s3_bucket_public_access_block" "pgbackrest" {
  bucket = aws_s3_bucket.pgbackrest.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# SSE-S3 encryption
resource "aws_s3_bucket_server_side_encryption_configuration" "pgbackrest" {
  bucket = aws_s3_bucket.pgbackrest.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Versioning left off — pgBackRest manages its own retention
# Not setting aws_s3_bucket_versioning leaves versioning in the default off state
# "Disabled" is not a valid AWS API value; only "Enabled" and "Suspended" are supported
