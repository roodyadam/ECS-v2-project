# URL Shortener - ECS V2 Project

A production-ready URL shortener service deployed on AWS ECS Fargate with blue/green deployments, WAF protection, and CI/CD via GitHub Actions OIDC.

## Architecture Overview

- **Compute**: ECS Fargate (no server management, auto-scaling)
- **Load Balancing**: Application Load Balancer (ALB) with AWS WAF
- **Storage**: DynamoDB (PAY_PER_REQUEST, PITR enabled)
- **Networking**: VPC with private subnets only, VPC endpoints (no NAT gateways)
- **Deployments**: AWS CodeDeploy with blue/green strategy
- **CI/CD**: GitHub Actions with OIDC authentication

## Project Structure

```
ECS-V2-Project/
├── app/                    # Application code
│   ├── src/               # Python FastAPI application
│   ├── tests/             # Unit tests
│   ├── Dockerfile         # Container definition
│   └── requirements.txt   # Python dependencies
├── infra/                 # Terraform infrastructure
│   ├── global/            # Global infrastructure (run once)
│   │   ├── backend/       # Terraform state backend
│   │   └── bootstrap/     # GitHub OIDC provider & deploy role
│   ├── modules/           # Reusable Terraform modules
│   │   ├── vpc/          # VPC, subnets, endpoints
│   │   ├── dynamodb/     # DynamoDB table
│   │   ├── iam/          # IAM roles
│   │   ├── ecr/          # ECR repository
│   │   ├── alb/          # ALB + WAF
│   │   ├── ecs/          # ECS cluster, service, tasks
│   │   └── codedeploy/   # CodeDeploy app & deployment group
│   └── envs/dev/         # Environment-specific configuration
├── .github/workflows/     # GitHub Actions CI/CD
│   ├── ci.yml            # Build, test, scan, push to ECR
│   ├── cd.yml            # Terraform apply, CodeDeploy
│   └── destroy.yml       # Terraform destroy (manual trigger)
└── README.md             # Project documentation
```

## Prerequisites

- AWS CLI configured with appropriate credentials
- Terraform >= 1.5.0
- Docker (for local testing)
- GitHub repository with Actions enabled

## Setup Instructions

### 1. Create Terraform Backend (One-time)

```bash
cd infra/global/backend
terraform init
terraform plan
terraform apply
```

Note the S3 bucket name and DynamoDB table name for the next step.

### 2. Configure Environment

```bash
cd infra/envs/dev
cp terraform.tfvars.example terraform.tfvars
# Edit terraform.tfvars with your values:
# - Update backend S3 bucket name in main.tf
# - Set github_repo to your repository (e.g., "username/url-shortener")
```

### 3. Set Up GitHub OIDC

1. Deploy bootstrap infrastructure to create the OIDC provider and IAM role:
   ```bash
   cd infra/global/bootstrap
   terraform init
   terraform apply
   ```

2. Get the GitHub deploy role ARN:
   ```bash
   terraform output github_deploy_role_arn
   ```

3. Add GitHub secret:
   - Go to your GitHub repository → Settings → Secrets and variables → Actions
   - Add secret: `AWS_ROLE_ARN` with the value from step 2

### 4. Deploy Infrastructure

```bash
cd infra/envs/dev
terraform init
terraform plan
terraform apply
```

### 5. Build and Push Initial Image

The CI workflow will handle this automatically, but for manual testing:

```bash
# Get ECR repository URL
cd infra/envs/dev
ECR_URL=$(terraform output -raw ecr_repository_url)

# Build and push
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $ECR_URL
docker build -t url-shortener:latest ./app
docker tag url-shortener:latest $ECR_URL:latest
docker push $ECR_URL:latest
```

## API Endpoints

Once deployed, access the service via the ALB DNS name:

- `GET /healthz` - Health check endpoint
  ```json
  {"status": "ok", "ts": 1234567890}
  ```

- `POST /shorten` - Create short URL
  ```json
  Request: {"url": "https://example.com/very/long/url"}
  Response: {"short": "abc123ef", "url": "https://example.com/very/long/url"}
  ```

- `GET /{short_code}` - Redirect to original URL
  - Returns HTTP 302 redirect

## Key Design Decisions & Trade-offs

### Infrastructure

- **VPC Endpoints vs NAT Gateways**
  - **Decision**: Use VPC endpoints for all AWS services
  - **Rationale**: Eliminates NAT gateway costs (~$32/month per AZ) while maintaining connectivity
  - **Trade-off**: Slightly more complex setup, but significant cost savings for low-traffic workloads

- **ECS Fargate vs EC2**
  - **Decision**: Use Fargate for compute
  - **Rationale**: No server management, automatic scaling, pay-per-use
  - **Trade-off**: Slightly higher cost per task, but eliminates operational overhead

- **DynamoDB PAY_PER_REQUEST vs Provisioned**
  - **Decision**: PAY_PER_REQUEST billing mode
  - **Rationale**: Cost-effective for variable/unpredictable traffic, no capacity planning needed
  - **Trade-off**: Can be more expensive at very high sustained throughput, but simpler for this use case

- **Private Subnets Only for Tasks**
  - **Decision**: ECS tasks run in private subnets with no public IPs
  - **Rationale**: Security best practice, tasks only accessible via ALB
  - **Trade-off**: Requires VPC endpoints for AWS service access (implemented)

### Security

- **WAF Rules**
  - **Decision**: Use AWS Managed Rule Sets (Common, Known Bad Inputs, Linux)
  - **Rationale**: Protection against common attacks without custom rule maintenance
  - **Trade-off**: May need custom rules for specific threats, but covers 90% of use cases

- **IAM Least Privilege**
  - **Decision**: Task role limited to `dynamodb:GetItem` and `dynamodb:PutItem` only
  - **Rationale**: Minimizes blast radius if credentials are compromised
  - **Trade-off**: Requires updates to IAM if app needs additional permissions

- **GitHub OIDC vs Static Credentials**
  - **Decision**: Use OIDC for GitHub Actions
  - **Rationale**: No long-lived credentials, automatic rotation, more secure
  - **Trade-off**: Slightly more complex initial setup, but industry best practice

### Deployment

- **CodeDeploy Blue/Green vs Rolling**
  - **Decision**: Blue/green deployments with CodeDeploy
  - **Rationale**: Zero-downtime deployments, automatic rollback on health check failures
  - **Trade-off**: Requires two target groups, but provides production-grade deployment safety

- **Container Image Tagging**
  - **Decision**: Tag images with both `latest` and commit SHA
  - **Rationale**: `latest` for convenience, SHA for traceability and rollback capability
  - **Trade-off**: Slightly more storage, but enables precise version control

### Cost Optimization

- **No NAT Gateways**: Saves ~$32/month per AZ
- **PAY_PER_REQUEST DynamoDB**: No idle capacity costs
- **Fargate Spot**: Could be used for dev environments (not implemented, but possible)
- **ALB**: Required for WAF, but adds ~$16/month base cost
- **WAF**: Adds per-request costs, but essential for production security

### Monitoring & Observability

- **CloudWatch Logs**: Centralized logging with 7-day retention
- **Container Insights**: Enabled on ECS cluster for metrics
- **Health Checks**: ALB target group + container-level health checks
- **Trade-off**: Could add more detailed metrics/dashboards (bonus feature)

## Testing

### Local Testing

```bash
# Run tests
cd app
pip install -r requirements.txt pytest pytest-asyncio httpx
pytest tests/ -v

# Test Docker build
docker build -t url-shortener:test ./app
docker run -p 8080:8080 -e TABLE_NAME=test-table url-shortener:test
```

### Integration Testing

After deployment, test the endpoints:

```bash
ALB_DNS=$(cd infra/envs/dev && terraform output -raw alb_dns_name)

# Health check
curl http://$ALB_DNS/healthz

# Shorten URL
curl -X POST http://$ALB_DNS/shorten \
  -H "Content-Type: application/json" \
  -d '{"url": "https://example.com"}'

# Test redirect (use short code from previous response)
curl -I http://$ALB_DNS/{short_code}
```

## Teardown

**⚠️ IMPORTANT**: Tear down resources to avoid ongoing costs:

### Option 1: Using GitHub Actions (Recommended)

1. Go to Actions → Destroy Infrastructure
2. Click "Run workflow"
3. Type "destroy" in the confirmation field
4. Click "Run workflow"

### Option 2: Manual Terraform Destroy

```bash
cd infra/envs/dev
terraform destroy -auto-approve
```

**Note**: 
- The bootstrap resources (GitHub OIDC provider and deploy role) are kept separate and won't be destroyed
- The backend S3 bucket and DynamoDB table should be kept for future use, or manually deleted if no longer needed

## Troubleshooting

### ECS Tasks Not Starting
- Check CloudWatch Logs: `/ecs/url-shortener`
- Verify VPC endpoints are working (check security groups)
- Check IAM roles have correct permissions
- Verify container image exists in ECR

### CodeDeploy Failures
- Check CodeDeploy deployment logs in AWS Console
- Verify target groups are healthy
- Check ECS service events
- Ensure task definition is valid

### WAF Blocking Requests
- Check WAF logs in CloudWatch
- Review WAF metrics for blocked requests
- Adjust rules if needed (may require custom rules)

## Future Enhancements (Bonus Features)

- [ ] HTTPS with ACM certificate and Route53 DNS
- [ ] CloudWatch dashboard with p50/p95 latency, error rates
- [ ] Infracost/tfsec/Trivy in CI pipeline
- [ ] Multi-region deployment for high availability
- [ ] DynamoDB TTL for URL expiration
- [ ] Analytics endpoint for click tracking

## License

This project is part of the CoderCo ECS V2 Project challenge.


