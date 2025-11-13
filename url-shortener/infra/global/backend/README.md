# Terraform Backend Setup

This directory contains the Terraform configuration for setting up the backend infrastructure (S3 bucket and DynamoDB table) for Terraform state management.

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5 installed

## Usage

1. Update `terraform.tfvars` with your unique bucket name:
   ```hcl
   state_bucket_name = "your-unique-terraform-state-bucket-name"
   aws_region        = "us-east-1"
   ```

2. Initialize and apply:
   ```bash
   terraform init
   terraform plan
   terraform apply
   ```

3. After creation, note the bucket name and use it in your main Terraform backend configuration.

## Important

- The bucket name must be globally unique
- This should be run **once** before deploying the main infrastructure
- The bucket has `prevent_destroy` lifecycle rule to protect state files


