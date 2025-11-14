# Deployment Guide - Step by Step

This guide will walk you through deploying your URL shortener service to AWS.

## Prerequisites

- AWS CLI configured with credentials
- Terraform >= 1.5.0 installed
- Docker installed (for local testing)
- GitHub repository set up
- AWS account with appropriate permissions

## Step 1: Create Terraform Backend (One-Time Setup)

The backend stores your Terraform state in S3 with DynamoDB locking.

```bash
cd infra/global/backend

# Create terraform.tfvars
cat > terraform.tfvars << EOF
state_bucket_name = "your-unique-terraform-state-bucket-name"
aws_region        = "us-east-1"
lock_table_name   = "terraform-state-lock"
EOF

# Initialize and apply
terraform init
terraform plan
terraform apply

# Note the bucket name - you'll need it in Step 2
terraform output state_bucket_name
```

**Important:** The bucket name must be globally unique. Use something like: `yourname-terraform-state-2024`

## Step 2: Configure Environment Variables

```bash
cd ../../envs/dev

# Copy the example file
cp terraform.tfvars.example terraform.tfvars

# Edit terraform.tfvars with your values
# Required:
# - Update backend bucket name in main.tf (line 15)
# - Set github_repo to your actual repo (e.g., "yourusername/ECS-V2-Project")
```

Edit `infra/envs/dev/main.tf` and update the backend configuration:

```hcl
backend "s3" {
  bucket         = "your-actual-bucket-name-from-step-1"  # UPDATE THIS
  key            = "envs/dev/terraform.tfstate"
  region         = "us-east-1"
  dynamodb_table = "terraform-state-lock"
  encrypt        = true
}
```

Edit `infra/envs/dev/terraform.tfvars`:

```hcl
project_name = "url-shortener"
aws_region   = "us-east-1"
vpc_cidr     = "10.0.0.0/16"

# Your GitHub repository in format: owner/repo
github_repo = "yourusername/ECS-V2-Project"  # UPDATE THIS

create_github_oidc_provider = true
ecs_desired_count = 2
```

## Step 3: Deploy Infrastructure

```bash
cd infra/envs/dev

# Initialize Terraform
terraform init

# Review the plan
terraform plan

# Apply (this will create all AWS resources)
terraform apply
```

This will take 10-15 minutes to create:
- VPC with subnets and endpoints
- DynamoDB table
- ECR repository
- IAM roles (including GitHub OIDC)
- ALB with WAF
- ECS cluster and service
- CodeDeploy application

## Step 4: Set Up GitHub OIDC

After infrastructure is deployed:

```bash
# Get the GitHub deploy role ARN
terraform output github_deploy_role_arn
```

Then in GitHub:
1. Go to your repository → Settings → Secrets and variables → Actions
2. Click "New repository secret"
3. Name: `AWS_ROLE_ARN`
4. Value: Paste the ARN from the terraform output
5. Click "Add secret"

## Step 5: Build and Push Initial Container Image

Before the CI/CD can work, you need an initial image in ECR:

```bash
# Get ECR repository URL
ECR_URL=$(cd infra/envs/dev && terraform output -raw ecr_repository_url)

# Login to ECR
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL

# Build the image
docker build -t url-shortener:latest ./app

# Tag and push
docker tag url-shortener:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

## Step 6: Update ECS Service with Initial Image

```bash
# Get cluster and service names
CLUSTER=$(cd infra/envs/dev && terraform output -raw ecs_cluster_name)
SERVICE=$(cd infra/envs/dev && terraform output -raw ecs_service_name)

# Get current task definition
TASK_DEF_ARN=$(aws ecs describe-services --cluster $CLUSTER --services $SERVICE --query 'services[0].taskDefinition' --output text)

# Get task definition JSON
aws ecs describe-task-definition --task-definition $TASK_DEF_ARN --query 'taskDefinition' > task-def.json

# Update image in task definition
jq --arg IMG "$ECR_URL:latest" '.containerDefinitions[0].image = $IMG | del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)' task-def.json > new-task-def.json

# Register new task definition
NEW_TASK_DEF_ARN=$(aws ecs register-task-definition --cli-input-json file://new-task-def.json --query 'taskDefinition.taskDefinitionArn' --output text)

# Update service (this will trigger CodeDeploy)
aws ecs update-service --cluster $CLUSTER --service $SERVICE --task-definition $NEW_TASK_DEF_ARN
```

## Step 7: Get Service URL

```bash
cd infra/envs/dev
ALB_DNS=$(terraform output -raw alb_dns_name)
echo "Your service URL: http://$ALB_DNS"
```

## Step 8: Test the Service

```bash
# Health check
curl http://$ALB_DNS/healthz

# Shorten a URL
curl -X POST http://$ALB_DNS/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com/very/long/url"}'

# Test redirect (use the short code from above)
curl -I http://$ALB_DNS/{short_code}
```

## Step 9: Test CI/CD Pipeline

1. Make a small change to the code
2. Commit and push to `main` branch
3. Watch GitHub Actions:
   - CI workflow: Build, test, scan, push to ECR
   - CD workflow: Terraform apply, CodeDeploy deployment
4. Verify blue/green deployment in AWS Console

## Step 10: Capture Evidence Screenshots

Take screenshots of:

1. **OIDC Role Trust Policy**
   - AWS Console → IAM → Roles → `url-shortener-github-deploy-role`
   - Trust relationships tab

2. **CodeDeploy Deployment**
   - AWS Console → CodeDeploy → Applications → `url-shortener-app`
   - Show a deployment with blue/green traffic shifting

3. **WAF Association**
   - AWS Console → WAF → Web ACLs
   - Show WAF associated with ALB

4. **VPC Endpoints**
   - AWS Console → VPC → Endpoints
   - Show all endpoints: S3, DynamoDB, ECR API, ECR Docker, CloudWatch Logs

## Step 11: Test Blue/Green Deployment

To test the rollback feature:

1. Deploy a bad image (one that fails health checks)
2. Watch CodeDeploy detect the failure
3. Verify automatic rollback occurs
4. Service should return to previous working version

## Step 12: TEARDOWN (IMPORTANT!)

**⚠️ Always tear down after testing to avoid costs!**

```bash
cd infra/envs/dev
terraform destroy -auto-approve
```

This will delete all resources except:
- S3 bucket (has prevent_destroy)
- DynamoDB lock table (has prevent_destroy)

To delete the backend (optional, only if you're done completely):

```bash
cd ../../global/backend
# First, manually delete the bucket contents
aws s3 rm s3://your-bucket-name --recursive
# Then destroy
terraform destroy -auto-approve
```

## Troubleshooting

### ECS Tasks Not Starting
- Check CloudWatch Logs: `/ecs/url-shortener`
- Verify VPC endpoints are working
- Check IAM roles have correct permissions
- Verify container image exists in ECR

### CodeDeploy Failures
- Check CodeDeploy deployment logs in AWS Console
- Verify target groups are healthy
- Check ECS service events
- Ensure task definition is valid

### GitHub Actions Failing
- Verify `AWS_ROLE_ARN` secret is set correctly
- Check OIDC provider exists in AWS
- Verify repository name matches in terraform.tfvars

### Can't Access Service
- Check ALB security group allows HTTP (port 80)
- Verify ECS tasks are running and healthy
- Check target group health checks

## Cost Estimate (While Running)

- ALB: ~$16/month base + $0.008/GB
- WAF: ~$5/month base + $1/rule/month + $0.60/million requests
- ECS Fargate: ~$0.04/vCPU-hour + $0.004/GB-hour (2 tasks = ~$60/month)
- DynamoDB: Pay-per-request (minimal if no traffic)
- VPC Endpoints: Interface endpoints ~$7/month each (3 total = ~$21/month)
- **Total: ~$100-150/month if left running**

**Always tear down when not testing!**

