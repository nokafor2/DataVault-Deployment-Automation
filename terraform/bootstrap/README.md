# Terraform bootstrap (state bucket)

Creates the **S3 bucket** and **DynamoDB lock table** used by the main stack in `../`. This module uses **local state** only (no chicken-and-egg with the remote backend).

## Prerequisites (main stack)

Before `terraform apply` in `../`, ensure:

1. An EC2 key pair exists in **eu-west-2** (same name as in `../terraform.tfvars`).
2. `../terraform.tfvars` sets `ssh_key_name` (gitignored). Example:

   ```hcl
   ssh_key_name = "datavault-key-pair"
   ```

   Create the key pair if needed:

   ```powershell
   aws ec2 create-key-pair --key-name datavault-key-pair --region eu-west-2 `
     --query KeyMaterial --output text | Out-File -Encoding ascii datavault-key-pair.pem
   ```

## One-time setup

```powershell
cd terraform/bootstrap
terraform init
terraform apply
```

Optional custom bucket name:

```powershell
terraform apply -var="state_bucket_name=my-unique-tfstate-bucket"
```

## Wire the main stack

From `terraform/bootstrap`:

```powershell
terraform output -raw backend_hcl > ../backend.hcl
```

Then initialize and apply the main stack (`terraform.tfvars` supplies `ssh_key_name` automatically):

```powershell
cd ..
terraform init -backend-config=backend.hcl
terraform apply
```

`backend.hcl` is gitignored — each environment generates its own from bootstrap outputs.

## Teardown

Destroy the **main** stack first, then bootstrap:

```powershell
cd terraform
terraform destroy

cd bootstrap
terraform destroy
```
