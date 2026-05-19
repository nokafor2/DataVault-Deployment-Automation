locals {
  state_bucket_name = coalesce(
    var.state_bucket_name != "" ? var.state_bucket_name : null,
    "${var.project_name}-tfstate-${data.aws_caller_identity.current.account_id}"
  )
  dynamodb_table_name = coalesce(
    var.dynamodb_table_name != "" ? var.dynamodb_table_name : null,
    "${var.project_name}-terraform-locks"
  )
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = local.state_bucket_name

  tags = {
    Project = var.project_name
    Purpose = "Terraform remote state for DataVault GitOps"
  }
}

resource "aws_s3_bucket_versioning" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "terraform_state" {
  bucket = aws_s3_bucket.terraform_state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_dynamodb_table" "terraform_locks" {
  count = var.enable_dynamodb_lock ? 1 : 0

  name         = local.dynamodb_table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }

  tags = {
    Project = var.project_name
    Purpose = "Terraform state locking"
  }
}
