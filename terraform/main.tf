# DataVault platform infrastructure — ECR (images) + EC2 (k3s, ArgoCD, workloads).
# Replaces three bare-metal servers with one reproducible, version-controlled stack.

provider "aws" {
  region = var.aws_region
}

# Current AWS account — used to build ECR registry URL in user_data and outputs
data "aws_caller_identity" "current" {}

# Latest Amazon Linux 2023 AMI for the k3s node
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }
}

# ── ECR: private registry for images built by GitHub Actions ─────────────────
resource "aws_ecr_repository" "datavault_api" {
  name                 = "${var.project_name}-api"  # e.g. datavault-api
  image_tag_mutability = "MUTABLE"                # CI pushes :latest and :<sha>
  force_delete         = true                     # Allow terraform destroy to remove images

  image_scanning_configuration {
    scan_on_push = true  # CVE scanning — relevant for FCA 72-hour patch requirements
  }

  tags = {
    Project = var.project_name
    Purpose = "DataVault compliance API container images"
  }
}

# ── IAM: EC2 instance role so k3s can pull from ECR without static credentials ─
resource "aws_iam_role" "k3s_ec2" {
  name = "${var.project_name}-k3s-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecr_read_only" {
  role       = aws_iam_role.k3s_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.k3s_ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"  # Optional Session Manager access
}

resource "aws_iam_instance_profile" "k3s_ec2" {
  name = "${var.project_name}-k3s-instance-profile"
  role = aws_iam_role.k3s_ec2.name
}

# ── Security group: ingress for SSH, k8s API, app NodePort, ArgoCD UI ─────────
resource "aws_security_group" "k3s" {
  name        = "${var.project_name}-k3s-sg"
  description = "k3s node: SSH, Kubernetes API, NodePort for DataVault API"

  ingress {
    description = "SSH - admin access to EC2"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "Kubernetes API - kubectl from your machine"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  ingress {
    description = "DataVault API - NodePort 30080 from clients"
    from_port   = 30080
    to_port     = 30080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Public API for demo; restrict in production
  }

  ingress {
    description = "ArgoCD UI - NodePort 30081 for GitOps dashboard"
    from_port   = 30081
    to_port     = 30081
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Outbound: pull images, install k3s, ArgoCD, etc.
  }

  tags = { Name = "${var.project_name}-k3s-sg" }
}

# ── EC2: single-node k3s cluster; user_data bootstraps k3s + ArgoCD on first boot ─
resource "aws_instance" "k3s" {
  ami                    = data.aws_ami.amazon_linux.id
  instance_type          = var.instance_type
  key_name               = var.ssh_key_name
  iam_instance_profile   = aws_iam_instance_profile.k3s_ec2.name
  vpc_security_group_ids = [aws_security_group.k3s.id]

  # Rendered at launch — installs k3s, metrics-server, ECR pull secret, ArgoCD
  user_data = templatefile("${path.module}/user_data.sh", {
    aws_region     = var.aws_region
    ecr_registry   = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
    ecr_repository = aws_ecr_repository.datavault_api.name
    project_name   = var.project_name
  })

  root_block_device {
    volume_size = 20    # GB — room for container images and logs
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-k3s-node"
    Project = var.project_name
  }
}
