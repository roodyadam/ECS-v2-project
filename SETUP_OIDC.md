# Quick Setup Guide for GitHub OIDC

## The Problem

GitHub Actions needs AWS credentials to deploy, but the IAM role is created by Terraform. This creates a chicken-and-egg situation for the first deployment.

## Solution: Manual First Deployment

You need to deploy infrastructure **once manually** to create the OIDC provider and IAM role, then the GitHub Actions workflows will work automatically.

## Steps

### 1. Create Terraform Backend (One-time)

```bash
cd infra/global/backend

# Create terraform.tfvars
cat > terraform.tfvars << EOF
state_bucket_name = "your-unique-bucket-name-$(date +%s)"
aws_region        = "us-east-1"
lock_table_name   = "terraform-state-lock"
EOF

terraform init
terraform apply
```

**Note the bucket name** - you'll need it in step 2.

### 2. Configure Environment

```bash
cd ../../envs/dev

# Update backend in main.tf (line 15) with your bucket name
# Then create terraform.tfvars
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your GitHub repo name
```

### 3. Deploy Infrastructure (Manual First Time)

```bash
cd infra/envs/dev

terraform init
terraform plan
terraform apply
```

This creates:
- VPC, ALB, ECS, DynamoDB, etc.
- **GitHub OIDC provider**
- **GitHub deploy IAM role**

### 4. Get the Role ARN

```bash
terraform output github_deploy_role_arn
```

Copy the ARN (looks like: `arn:aws:iam::123456789012:role/url-shortener-github-deploy-role`)

### 5. Add GitHub Secret

1. Go to your GitHub repository
2. Settings → Secrets and variables → Actions
3. Click "New repository secret"
4. Name: `AWS_ROLE_ARN`
5. Value: Paste the ARN from step 4
6. Click "Add secret"

### 6. Verify

After adding the secret, push a commit to `main` branch. The CD workflow should now:
- ✅ Authenticate using OIDC
- ✅ Run Terraform apply
- ✅ Trigger CodeDeploy deployment

## Troubleshooting

### Error: "Credentials could not be loaded"
- Check that `AWS_ROLE_ARN` secret exists in GitHub
- Verify the ARN is correct (no extra spaces)
- Ensure infrastructure was deployed (OIDC provider and role exist)

### Error: "Access denied" or "Not authorized"
- Check the IAM role trust policy matches your GitHub repo
- Verify the OIDC provider exists in AWS IAM
- Ensure the repository name in `terraform.tfvars` matches your GitHub repo format: `owner/repo`

### OIDC Provider Already Exists
If you get an error that the OIDC provider already exists:
- Set `create_github_oidc_provider = false` in `terraform.tfvars`
- The role will still be created and will use the existing provider

## After Initial Setup

Once the secret is configured, all future deployments will be fully automated via GitHub Actions! 🎉

