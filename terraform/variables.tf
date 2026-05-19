# Input variables — override via terraform.tfvars or -var flags at apply time.

variable "aws_region" {
  description = "AWS region for DataVault infrastructure"
  type        = string
  default     = "eu-west-2"  # London — typical for UK FCA-regulated clients
}

variable "project_name" {
  description = "Prefix for resource naming (ECR, EC2, IAM, security groups)"
  type        = string
  default     = "datavault"  # Produces e.g. datavault-api ECR repo
}

variable "instance_type" {
  description = "EC2 instance type for k3s cluster"
  type        = string
  default     = "t3.small"  # Sufficient for demo; 2 vCPU, 2 GiB RAM
}

variable "ssh_key_name" {
  description = "Name of an existing EC2 key pair for SSH access (required, no default)"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "CIDR allowed to SSH and access k8s API / ArgoCD UI — restrict in production"
  type        = string
  default     = "0.0.0.0/0"  # Open for lab; use your IP e.g. 203.0.113.10/32
}
