# Terraform backend and provider constraints.
# State bucket + DynamoDB lock table: provision with terraform/bootstrap/ first, then:
#   terraform output -raw backend_hcl > ../backend.hcl   (from bootstrap/)
#   terraform init -backend-config=backend.hcl           (from this directory)
terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    key     = "datavault-gitops/terraform.tfstate"
    region  = "eu-west-2"
    encrypt = true
    # bucket and dynamodb_table come from backend.hcl (see backend.hcl.example)
  }
}
