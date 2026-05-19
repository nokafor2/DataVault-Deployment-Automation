variable "aws_region" {
  description = "AWS region for the Terraform state bucket and lock table"
  type        = string
  default     = "eu-west-2"
}

variable "project_name" {
  description = "Prefix for resource names (bucket suffix, DynamoDB table name)"
  type        = string
  default     = "datavault"
}

variable "state_bucket_name" {
  description = "Globally unique S3 bucket name. Leave empty to use {project_name}-tfstate-{account_id}"
  type        = string
  default     = "datavault-state-bucket-ayua"
}

variable "enable_dynamodb_lock" {
  description = "Create a DynamoDB table for Terraform state locking (recommended for CI/teams)"
  type        = bool
  default     = true
}

variable "dynamodb_table_name" {
  description = "DynamoDB table name for state locks. Leave empty to use {project_name}-terraform-locks"
  type        = string
  default     = "datavault-terraform-locks-ayua"
}
