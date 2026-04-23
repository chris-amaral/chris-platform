###############################################################################
# Module: storage
# Description: S3 bucket for Terraform remote state + DynamoDB for state lock.
#              Bucket has versioning, encryption and public access fully blocked.
#              Bucket name includes AWS account ID to avoid global name collisions.
# Author: Christopher Amaral
###############################################################################

data "aws_caller_identity" "current" {}

locals {
  account_id  = data.aws_caller_identity.current.account_id
  bucket_name = "${var.project_name}-tfstate-${local.account_id}"
  table_name  = "${var.project_name}-tfstate-lock"
}

# --- S3 Bucket (Terraform State) -------------------------------------------
resource "aws_s3_bucket" "tfstate" {
  bucket = local.bucket_name

  tags = merge(var.tags, {
    Name    = local.bucket_name
    Purpose = "terraform-state"
  })
}

resource "aws_s3_bucket_versioning" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "tfstate" {
  bucket = aws_s3_bucket.tfstate.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- DynamoDB Table (State Lock) --------------------------------------------
resource "aws_dynamodb_table" "tfstate_lock" {
  name         = local.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = merge(var.tags, {
    Name    = local.table_name
    Purpose = "terraform-state-lock"
  })
}
