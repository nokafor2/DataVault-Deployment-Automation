# Outputs — run `terraform output` after apply; values feed k8s manifests and CI setup.

output "aws_account_id" {
  description = "AWS account ID — replace 000000000000 in k8s/deployment.yaml image URI"
  value       = data.aws_caller_identity.current.account_id
}

output "ecr_repository_url" {
  description = "Full ECR URL for docker push (GitHub Actions) and kubectl image reference"
  value       = aws_ecr_repository.datavault_api.repository_url
}

output "ecr_repository_name" {
  description = "Short repo name — must match ECR_REPOSITORY in .github/workflows/ci.yml"
  value       = aws_ecr_repository.datavault_api.name
}

output "k3s_instance_id" {
  description = "EC2 instance ID — for AWS Console and support tickets"
  value       = aws_instance.k3s.id
}

output "k3s_public_ip" {
  description = "SSH target and NodePort base URL: http://<ip>:30080"
  value       = aws_instance.k3s.public_ip
}

output "k3s_public_dns" {
  description = "Public DNS hostname for the k3s node"
  value       = aws_instance.k3s.public_dns
}

output "datavault_api_url" {
  description = "API endpoint after kubectl apply -f k8s/"
  value       = "http://${aws_instance.k3s.public_ip}:30080"
}

output "deployment_image_placeholder" {
  description = "Copy into k8s/deployment.yaml image field before first deploy"
  value       = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com/${aws_ecr_repository.datavault_api.name}"
}
