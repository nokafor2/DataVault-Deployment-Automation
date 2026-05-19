# Bootstrap stack — local state only. Run once before the main terraform/ stack.
# Creates the S3 bucket (and optional DynamoDB lock table) used by ../backend.tf.
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}
