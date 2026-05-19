output "state_bucket_name" {
  description = "S3 bucket for main stack remote state — use in ../backend.hcl"
  value       = aws_s3_bucket.terraform_state.id
}

output "dynamodb_table_name" {
  description = "DynamoDB lock table name (empty if locking disabled)"
  value       = var.enable_dynamodb_lock ? aws_dynamodb_table.terraform_locks[0].name : ""
}

output "aws_region" {
  description = "Region where state resources were created"
  value       = var.aws_region
}

output "state_key" {
  description = "State object key — must match key in ../backend.tf"
  value       = "datavault-gitops/terraform.tfstate"
}

# Paste into terraform/backend.hcl after bootstrap apply:
#   terraform output -raw backend_hcl > ../backend.hcl
output "backend_hcl" {
  description = "Ready-to-use backend config for the main terraform/ stack"
  value = var.enable_dynamodb_lock ? trimspace(<<-EOT
    bucket         = "${aws_s3_bucket.terraform_state.id}"
    key            = "datavault-gitops/terraform.tfstate"
    region         = "${var.aws_region}"
    dynamodb_table = "${aws_dynamodb_table.terraform_locks[0].name}"
    encrypt        = true
  EOT
    ) : trimspace(<<-EOT
    bucket  = "${aws_s3_bucket.terraform_state.id}"
    key     = "datavault-gitops/terraform.tfstate"
    region  = "${var.aws_region}"
    encrypt = true
  EOT
  )
}
