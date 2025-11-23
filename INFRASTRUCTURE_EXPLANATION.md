# Infrastructure and Dockerfile Explanation

This document explains the reasoning behind every line of code in the Dockerfile and Terraform infrastructure configuration.

## Table of Contents
1. [Dockerfile](#dockerfile)
2. [Terraform Configuration](#terraform-configuration)
   - [Environment Configuration](#environment-configuration)
   - [VPC Module](#vpc-module)
   - [DynamoDB Module](#dynamodb-module)
   - [IAM Module](#iam-module)
   - [ECR Module](#ecr-module)
   - [ALB Module](#alb-module)
   - [ECS Module](#ecs-module)
   - [CodeDeploy Module](#codedeploy-module)

---

## Dockerfile

### Multi-Stage Build Pattern

```dockerfile
FROM python:3.12-slim-bookworm AS dependencies
```
**Why:** Uses a multi-stage build to separate dependency installation from the final image. The `AS dependencies` stage creates a named intermediate stage that we'll copy from later. This reduces the final image size by excluding build tools and intermediate files.

**Why `python:3.12-slim-bookworm`:** 
- `python:3.12` provides the latest Python 3.12 features and performance improvements
- `slim` variant excludes unnecessary packages, reducing image size (~45MB vs ~150MB for full image)
- `bookworm` is the Debian 12 codename, providing a stable base with security updates

```dockerfile
WORKDIR /install
```
**Why:** Sets the working directory for the dependencies stage. Using `/install` as a non-standard path makes it clear this is temporary and will be copied to the final image.

```dockerfile
COPY requirements.txt .
```
**Why:** Copies only the requirements file first (before source code). This leverages Docker layer caching - if requirements.txt doesn't change, Docker can reuse the cached layer with installed dependencies, speeding up builds.

```dockerfile
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt
```
**Why:**
- `--no-cache-dir`: Prevents pip from storing cache files, reducing image size
- `--prefix=/install`: Installs packages to `/install` instead of system Python, allowing us to copy them to the final image
- `-r requirements.txt`: Installs all dependencies from the requirements file

```dockerfile
FROM python:3.12-slim-bookworm
```
**Why:** Starts a fresh base image for the final stage. This ensures we only include what we explicitly copy, resulting in a minimal production image.

```dockerfile
RUN groupadd -r appuser && useradd -r -g appuser appuser
```
**Why:** Creates a non-root user for security best practices. Running containers as root is a security risk - if the container is compromised, an attacker would have root access. The `-r` flag creates a system user/group (no login shell, no home directory by default).

```dockerfile
ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PATH=/home/appuser/.local/bin:$PATH
```
**Why:**
- `PYTHONUNBUFFERED=1`: Ensures Python output is sent directly to stdout/stderr without buffering, critical for container logging and debugging
- `PYTHONDONTWRITEBYTECODE=1`: Prevents Python from creating `.pyc` files, reducing image size and avoiding permission issues
- `PATH=/home/appuser/.local/bin:$PATH`: Adds the user's local bin directory to PATH so installed packages are accessible

```dockerfile
WORKDIR /app
```
**Why:** Sets the working directory for the application. All subsequent commands run from this directory.

```dockerfile
COPY --from=dependencies /install /home/appuser/.local
```
**Why:** Copies installed Python packages from the dependencies stage to the user's local directory. This includes only the installed packages, not pip or build tools, keeping the final image small.

```dockerfile
COPY src/ ./src
```
**Why:** Copies application source code. Done after dependency installation to maximize cache efficiency - code changes more frequently than dependencies.

```dockerfile
RUN chown -R appuser:appuser /app
```
**Why:** Changes ownership of the application directory to the non-root user, ensuring the application can read/write files without root permissions.

```dockerfile
USER appuser
```
**Why:** Switches to the non-root user. All subsequent commands and the container runtime will execute as this user, following the principle of least privilege.

```dockerfile
EXPOSE 8080
```
**Why:** Documents that the container listens on port 8080. This is metadata for Docker and doesn't actually publish the port, but it's a best practice for documentation and helps orchestration tools understand the container's needs.

```dockerfile
CMD ["python", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8080"]
```
**Why:**
- `python -m uvicorn`: Runs uvicorn as a module, ensuring the correct Python environment is used
- `src.main:app`: Points to the FastAPI app instance in `src/main.py`
- `--host 0.0.0.0`: Binds to all interfaces, not just localhost, allowing external connections (required for containers)
- `--port 8080`: Matches the EXPOSE directive and ECS task definition

---

## Terraform Configuration

### Environment Configuration

#### `infra/envs/dev/main.tf`

```terraform
terraform {
  required_version = ">= 1.5"
```
**Why:** Enforces a minimum Terraform version to ensure compatibility with features used (like `required_providers` block syntax). Version 1.5+ includes important improvements and security fixes.

```terraform
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
```
**Why:**
- `source = "hashicorp/aws"`: Uses the official HashiCorp AWS provider from the Terraform Registry
- `version = "~> 5.0"`: Allows any 5.x version but prevents upgrading to 6.0 (which may have breaking changes). This balances getting bug fixes while avoiding unexpected breaking changes.

```terraform
  backend "s3" {
    key            = "envs/dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
```
**Why:**
- **S3 Backend:** Stores Terraform state remotely, enabling team collaboration and preventing state file conflicts
- **key = "envs/dev/terraform.tfstate"**: Organizes state files by environment, allowing separate state management per environment
- **region = "eu-west-2"**: Matches the deployment region for lower latency and compliance
- **dynamodb_table = "terraform-state-lock"**: Enables state locking to prevent concurrent modifications (critical for team environments)
- **encrypt = true**: Encrypts state at rest in S3, protecting sensitive data (passwords, keys) that may be stored in state

```terraform
provider "aws" {
  region = var.aws_region
}
```
**Why:** Configures the AWS provider to use the region from variables, making it easy to deploy to different regions by changing a single variable.

```terraform
data "aws_caller_identity" "current" {}
```
**Why:** Retrieves the current AWS account ID and user/role ARN. Useful for constructing ARNs dynamically and for output/reference purposes.

```terraform
data "aws_iam_role" "github_deploy" {
  name = "${var.project_name}-github-deploy-role"
}
```
**Why:** References an IAM role created in a bootstrap stack (likely for GitHub Actions OIDC authentication). This allows the infrastructure to reference the role without managing it, following separation of concerns.

#### Module Invocations

```terraform
module "vpc" {
  source = "../../modules/vpc"
  ...
}
```
**Why:** Modularizes infrastructure into reusable components. The VPC module encapsulates all networking concerns, making it reusable across environments.

```terraform
module "dynamodb" {
  source = "../../modules/dynamodb"
  table_name  = "${var.project_name}-url-mappings"
  environment = "dev"
}
```
**Why:** 
- **table_name**: Uses project name prefix for consistent naming and easy identification
- **environment = "dev"**: Hardcoded for this environment file; each environment (dev/staging/prod) would have its own value

```terraform
module "iam" {
  source = "../../modules/iam"
  project_name       = var.project_name
  dynamodb_table_arn = module.dynamodb.table_arn
}
```
**Why:** Passes the DynamoDB table ARN to the IAM module so it can create policies granting access to the specific table (principle of least privilege).

```terraform
module "ecr" {
  source = "../../modules/ecr"
  repository_name = "${var.project_name}-repo"
  environment     = "dev"
}
```
**Why:** Creates an ECR repository for storing Docker images. The environment tag helps organize resources and apply environment-specific policies.

```terraform
module "alb" {
  source = "../../modules/alb"
  project_name      = var.project_name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}
```
**Why:** 
- **public_subnet_ids**: ALB must be in public subnets to receive internet traffic
- Uses VPC module outputs to ensure proper integration

```terraform
module "ecs" {
  source = "../../modules/ecs"
  ...
  private_subnet_ids    = module.vpc.private_subnet_ids
  ...
  container_image       = "${module.ecr.repository_url}:latest"
  ...
}
```
**Why:**
- **private_subnet_ids**: ECS tasks run in private subnets for security (no direct internet access)
- **container_image**: References the ECR repository URL with `:latest` tag (in production, use specific tags)

```terraform
module "codedeploy" {
  source = "../../modules/codedeploy"
  ...
  container_port          = 8080
  ...
}
```
**Why:** Configures CodeDeploy for blue/green deployments. The container port matches the Dockerfile EXPOSE and ECS task definition.

---

### VPC Module

#### `infra/modules/vpc/main.tf`

```terraform
data "aws_availability_zones" "available" {
  state = "available"
}
```
**Why:** Dynamically fetches available AZs in the current region, ensuring we only use zones that are actually available (some regions have fewer zones).

```terraform
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  ...
}
```
**Why:**
- **cidr_block**: Uses variable for flexibility (default 10.0.0.0/16 provides 65,536 IPs)
- **enable_dns_hostnames = true**: Allows EC2 instances to get DNS hostnames (required for some AWS services)
- **enable_dns_support = true**: Enables DNS resolution within the VPC (required for VPC endpoints and service discovery)

```terraform
resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.main.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index)
  availability_zone = data.aws_availability_zones.available.names[count.index]
  ...
}
```
**Why:**
- **count = 2**: Creates 2 subnets for high availability (spreads across 2 AZs)
- **cidrsubnet(var.vpc_cidr, 8, count.index)**: 
  - `8` means 8 additional bits (creates /24 subnets from /16 VPC = 256 IPs each)
  - `count.index` (0, 1) creates subnets 10.0.0.0/24 and 10.0.1.0/24
- **availability_zone**: Distributes subnets across different AZs for fault tolerance

```terraform
resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  timeouts {
    delete = "10m"
  }
}
```
**Why:**
- **Internet Gateway**: Required for public subnets to access the internet
- **timeouts.delete = "10m"**: Gives AWS more time to delete (sometimes takes longer if dependencies exist)

```terraform
resource "aws_subnet" "public" {
  count                   = 2
  ...
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index + 10)
  map_public_ip_on_launch = true
  ...
}
```
**Why:**
- **count.index + 10**: Creates subnets 10.0.10.0/24 and 10.0.11.0/24, keeping them separate from private subnets (0, 1) for clarity
- **map_public_ip_on_launch = true**: Automatically assigns public IPs to instances launched in these subnets (required for ALB)

```terraform
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  lifecycle {
    create_before_destroy = false
  }
}
```
**Why:**
- **lifecycle.create_before_destroy = false**: Default behavior, but explicit. Route tables are replaced in-place, which is fine for public routes.

```terraform
resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.main.id
}
```
**Why:**
- **destination_cidr_block = "0.0.0.0/0"**: Routes all traffic (default route) to the internet gateway
- This enables internet access for resources in public subnets

```terraform
resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.main.id
  ...
}
```
**Why:** Creates separate route tables for each private subnet. While they could share one, separate tables allow for future customization (e.g., different NAT gateways per subnet).

```terraform
resource "aws_security_group" "vpc_endpoint" {
  ...
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = [var.vpc_cidr]
  }
  ...
}
```
**Why:**
- **Port 443**: VPC endpoints use HTTPS
- **cidr_blocks = [var.vpc_cidr]**: Only allows traffic from within the VPC (principle of least privilege)

```terraform
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.aws_region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = aws_route_table.private[*].id
  ...
}
```
**Why:**
- **Gateway type**: S3 and DynamoDB use gateway endpoints (free, no ENIs, automatically routes traffic)
- **route_table_ids**: Associates with private route tables so ECS tasks can access S3 without internet/NAT
- **service_name format**: AWS standard format for VPC endpoint service names

```terraform
resource "aws_vpc_endpoint" "ecr_api" {
  ...
  vpc_endpoint_type   = "Interface"
  subnet_ids          = aws_subnet.private[*].id
  security_group_ids  = [aws_security_group.vpc_endpoint.id]
  private_dns_enabled = true
  ...
}
```
**Why:**
- **Interface type**: ECR uses interface endpoints (creates ENIs, costs money but required for ECR API)
- **subnet_ids**: Must be in private subnets where ECS tasks run
- **security_group_ids**: Controls access to the endpoint
- **private_dns_enabled = true**: Allows using standard AWS service DNS names (e.g., `ecr.eu-west-2.amazonaws.com`) from within VPC

```terraform
resource "aws_vpc_endpoint" "ecr_dkr" {
  ...
}
```
**Why:** ECR requires two endpoints:
- **ecr.api**: For API calls (pulling image manifests)
- **ecr.dkr**: For Docker registry operations (pulling image layers)

```terraform
resource "aws_vpc_endpoint" "logs" {
  ...
}
```
**Why:** Allows ECS tasks to send logs to CloudWatch Logs without internet access, enabling logging from private subnets.

---

### DynamoDB Module

#### `infra/modules/dynamodb/main.tf`

```terraform
resource "aws_dynamodb_table" "url_mappings" {
  name           = var.table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  ...
}
```
**Why:**
- **billing_mode = "PAY_PER_REQUEST"**: 
  - No need to provision read/write capacity units
  - Automatically scales to traffic
  - Pay only for what you use
  - Ideal for variable or unpredictable traffic (like a URL shortener)
- **hash_key = "id"**: Simple key structure for URL shortener (each shortened URL has a unique ID)

```terraform
  attribute {
    name = "id"
    type = "S"
  }
```
**Why:** Defines the hash key attribute. `"S"` means String type, which is appropriate for URL IDs.

```terraform
  point_in_time_recovery {
    enabled = true
  }
```
**Why:** Enables PITR, allowing restoration to any point in time within the last 35 days. Critical for data protection and recovery from accidental deletions or corruption.

```terraform
  server_side_encryption {
    enabled = true
  }
```
**Why:** Encrypts data at rest using AWS-managed keys. Required for compliance and security best practices.

---

### IAM Module

#### `infra/modules/iam/main.tf`

```terraform
resource "aws_iam_role" "ecs_execution" {
  name = "${var.project_name}-ecs-execution-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  ...
}
```
**Why:**
- **Execution Role**: Used by ECS to pull images from ECR, write logs to CloudWatch, and retrieve secrets
- **Principal = "ecs-tasks.amazonaws.com"**: Only ECS service can assume this role (security boundary)
- **sts:AssumeRole**: Standard AWS action for role assumption

```terraform
resource "aws_iam_role_policy_attachment" "ecs_execution" {
  role       = aws_iam_role.ecs_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
```
**Why:** Attaches AWS managed policy that grants permissions for:
- Pulling images from ECR
- Writing logs to CloudWatch Logs
- Retrieving secrets from Secrets Manager/Parameter Store

```terraform
resource "aws_iam_role" "ecs_task" {
  ...
  Principal = {
    Service = "ecs-tasks.amazonaws.com"
  }
  ...
}
```
**Why:** **Task Role** is different from execution role - this is what the application code uses to access AWS services (like DynamoDB). The application assumes this role's permissions.

```terraform
resource "aws_iam_role_policy" "ecs_task_dynamodb" {
  ...
  policy = jsonencode({
    ...
    Action = [
      "dynamodb:GetItem",
      "dynamodb:PutItem"
    ]
    Resource = var.dynamodb_table_arn
    ...
  })
}
```
**Why:**
- **Custom policy**: Grants only the specific DynamoDB actions needed (GetItem for retrieving URLs, PutItem for creating shortened URLs)
- **Resource = var.dynamodb_table_arn**: Restricts access to only this specific table (principle of least privilege)
- Uses `var.dynamodb_table_arn` instead of wildcard to ensure tight security

---

### ECR Module

#### `infra/modules/ecr/main.tf`

```terraform
resource "aws_ecr_repository" "app" {
  name                 = var.repository_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true
  ...
}
```
**Why:**
- **image_tag_mutability = "MUTABLE"**: Allows overwriting tags (e.g., `:latest`). `IMMUTABLE` would prevent overwrites, which is safer but less flexible for dev environments
- **force_delete = true**: Allows deleting the repository even if it contains images (useful for dev/test cleanup)

```terraform
  image_scanning_configuration {
    scan_on_push = true
  }
```
**Why:** Automatically scans images for vulnerabilities when pushed. Helps identify security issues early in the CI/CD pipeline.

```terraform
  encryption_configuration {
    encryption_type = "AES256"
  }
```
**Why:** Encrypts images at rest using AWS-managed keys (AES256). Required for compliance and security.

```terraform
resource "aws_ecr_lifecycle_policy" "app" {
  ...
  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Keep last 10 images"
        selection = {
          tagStatus     = "any"
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
```
**Why:**
- **Keep last 10 images**: Prevents ECR from growing indefinitely and accumulating costs
- **tagStatus = "any"**: Applies to all images regardless of tag
- **countType = "imageCountMoreThan"**: When more than 10 images exist, oldest are expired
- Automatically cleans up old images, reducing storage costs

---

### ALB Module

#### `infra/modules/alb/main.tf`

```terraform
resource "aws_security_group" "alb" {
  ...
  ingress {
    description = "HTTP from internet"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ...
}
```
**Why:**
- **Port 80**: Standard HTTP port (in production, use HTTPS/443)
- **cidr_blocks = ["0.0.0.0/0"]**: Allows traffic from anywhere (required for public-facing ALB)
- Security is enforced by WAF rules, not just security groups

```terraform
resource "aws_lb" "main" {
  name               = "${var.project_name}-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids
  enable_deletion_protection = false
  ...
}
```
**Why:**
- **internal = false**: Internet-facing load balancer (receives traffic from internet)
- **load_balancer_type = "application"**: Layer 7 (HTTP/HTTPS) load balancer, provides advanced routing and WAF integration
- **subnets = var.public_subnet_ids**: Must be in public subnets to receive internet traffic
- **enable_deletion_protection = false**: Set to `true` in production to prevent accidental deletion

```terraform
resource "aws_lb_target_group" "blue" {
  name        = "${var.project_name}-blue-tg"
  port        = 8080
  protocol    = "HTTP"
  vpc_id      = var.vpc_id
  target_type = "ip"
  ...
}
```
**Why:**
- **port = 8080**: Matches container port from Dockerfile
- **target_type = "ip"**: Required for Fargate (tasks use ENI IPs, not instance IDs)
- **Blue/Green naming**: Supports blue/green deployments - blue is current production, green is new version

```terraform
  health_check {
    enabled             = true
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 5
    interval            = 30
    path                = "/healthz"
    matcher             = "200"
    protocol            = "HTTP"
  }
```
**Why:**
- **enabled = true**: Enables health checks to route traffic only to healthy targets
- **healthy_threshold = 2**: Requires 2 consecutive successful checks before marking healthy (prevents flapping)
- **unhealthy_threshold = 2**: Requires 2 consecutive failures before marking unhealthy (avoids false positives)
- **timeout = 5**: Maximum time to wait for response (should be less than interval)
- **interval = 30**: Check every 30 seconds (balance between responsiveness and load)
- **path = "/healthz"**: Application health check endpoint
- **matcher = "200"**: Only HTTP 200 responses are considered healthy

```terraform
  deregistration_delay = 30
```
**Why:** Waits 30 seconds after deregistration before terminating connections. Allows in-flight requests to complete gracefully during deployments.

```terraform
resource "aws_lb_listener" "main" {
  load_balancer_arn = aws_lb.main.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.blue.arn
  }
  lifecycle {
    ignore_changes = [
      default_action
    ]
  }
}
```
**Why:**
- **port = "80"**: Listens on HTTP (use 443/HTTPS in production)
- **default_action = forward to blue**: Initially routes to blue target group
- **lifecycle.ignore_changes**: CodeDeploy will change the default_action during blue/green deployments, so Terraform should ignore these changes to avoid conflicts

```terraform
resource "aws_wafv2_web_acl" "main" {
  name        = "${var.project_name}-waf"
  description = "WAF for ${var.project_name} ALB"
  scope       = "REGIONAL"
  ...
}
```
**Why:**
- **WAF (Web Application Firewall)**: Protects against common web exploits (SQL injection, XSS, etc.)
- **scope = "REGIONAL"**: For ALB (not CloudFront). Regional scope is required for ALB association.

```terraform
  default_action {
    allow {}
  }
```
**Why:** By default, allow all traffic. Rules below will block/allow based on conditions. This is a "deny by exception" approach.

```terraform
  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    ...
  }
```
**Why:** AWS managed rule set that protects against OWASP Top 10 vulnerabilities (SQL injection, XSS, etc.). Using managed rules reduces maintenance burden.

```terraform
  rule {
    name     = "RateLimitShorten"
    priority = 4
    action {
      count {}
    }
    statement {
      rate_based_statement {
        limit              = 60
        aggregate_key_type = "IP"
        ...
      }
    }
    ...
  }
```
**Why:**
- **Rate limiting**: Prevents abuse of the `/shorten` endpoint
- **limit = 60**: Allows 60 requests per 5-minute window per IP
- **aggregate_key_type = "IP"**: Tracks by source IP address
- **action = count**: Counts but doesn't block (for monitoring). Change to `block` to actually block requests
- **scope_down_statement**: Only applies to POST requests to `/shorten` path

```terraform
  rule {
    name     = "ShortenJsonContentType"
    priority = 5
    action {
      count {}
    }
    ...
    statement {
      byte_match_statement {
        search_string = "application/json"
        field_to_match {
          single_header {
            name = "content-type"
          }
        }
        ...
      }
    }
    ...
  }
```
**Why:** Validates that POST requests to `/shorten` have `Content-Type: application/json` header. Helps prevent malformed requests and enforces API contract.

```terraform
resource "aws_wafv2_web_acl_association" "main" {
  resource_arn = aws_lb.main.arn
  web_acl_arn  = aws_wafv2_web_acl.main.arn
}
```
**Why:** Associates the WAF with the ALB, enabling WAF rules to inspect and filter traffic before it reaches the application.

---

### ECS Module

#### `infra/modules/ecs/main.tf`

```terraform
resource "aws_cloudwatch_log_group" "app" {
  name              = "/ecs/${var.project_name}"
  retention_in_days = 7
  ...
}
```
**Why:**
- **name = "/ecs/..."**: Standard CloudWatch Logs path for ECS
- **retention_in_days = 7**: Keeps logs for 7 days (balance between debugging needs and cost). Increase for production.

```terraform
resource "aws_ecs_cluster" "main" {
  name = "${var.project_name}-cluster"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
  ...
}
```
**Why:**
- **containerInsights = enabled**: Enables CloudWatch Container Insights for enhanced monitoring, metrics, and dashboards
- Provides detailed performance metrics (CPU, memory, network) without additional instrumentation

```terraform
resource "aws_security_group" "ecs" {
  ...
  ingress {
    description     = "HTTP from ALB"
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [var.alb_security_group_id]
  }
  ...
}
```
**Why:**
- **Port 8080**: Matches container port
- **security_groups = [var.alb_security_group_id]**: Only allows traffic from ALB security group (not from internet directly)
- This implements defense in depth - even if ALB is compromised, ECS tasks are not directly accessible

```terraform
resource "aws_ecs_task_definition" "main" {
  family                   = "${var.project_name}-task"
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = var.task_cpu
  memory                   = var.task_memory
  execution_role_arn       = var.execution_role_arn
  task_role_arn            = var.task_role_arn
  ...
}
```
**Why:**
- **network_mode = "awsvpc"**: Each task gets its own ENI with private IP (required for Fargate, enables security groups)
- **requires_compatibilities = ["FARGATE"]**: Uses Fargate (serverless, no EC2 management)
- **cpu/memory**: Configurable via variables (defaults: 256 CPU units = 0.25 vCPU, 512 MB memory)
- **execution_role_arn**: Role for ECS to pull images, write logs
- **task_role_arn**: Role for application to access AWS services (DynamoDB)

```terraform
  container_definitions = jsonencode([
    {
      name  = var.container_name
      image = var.container_image
      portMappings = [
        {
          containerPort = 8080
          protocol      = "tcp"
        }
      ]
      ...
    }
  ])
```
**Why:**
- **jsonencode**: Converts HCL to JSON (required for container_definitions)
- **containerPort = 8080**: Exposes port 8080 from container to host
- **protocol = "tcp"**: HTTP uses TCP

```terraform
      environment = [
        {
          name  = "TABLE_NAME"
          value = var.table_name
        }
      ]
```
**Why:** Passes DynamoDB table name as environment variable to the application. Application reads this to know which table to use.

```terraform
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.app.name
          "awslogs-region"        = var.aws_region
          "awslogs-stream-prefix" = "ecs"
        }
      }
```
**Why:**
- **logDriver = "awslogs"**: Sends container logs to CloudWatch Logs
- **awslogs-group**: Log group created above
- **awslogs-region**: Region for CloudWatch Logs
- **awslogs-stream-prefix = "ecs"**: Creates log streams like `/ecs/url-shortener/ecs/container-name/task-id`

```terraform
      healthCheck = {
        command     = ["CMD-SHELL", "python -c \"import http.client; conn = http.client.HTTPConnection('localhost', 8080); conn.request('GET', '/healthz'); r = conn.getresponse(); exit(0 if r.status == 200 else 1)\""]
        interval    = 30
        timeout     = 5
        retries     = 3
        startPeriod = 60
      }
```
**Why:**
- **command**: Python one-liner that makes HTTP request to `/healthz` endpoint
- **interval = 30**: Check every 30 seconds
- **timeout = 5**: 5 second timeout per check
- **retries = 3**: 3 consecutive failures mark unhealthy
- **startPeriod = 60**: 60 second grace period after container start before health checks count (allows app to initialize)

```terraform
resource "aws_ecs_service" "main" {
  name            = "${var.project_name}-service"
  cluster         = aws_ecs_cluster.main.id
  task_definition = aws_ecs_task_definition.main.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"
  ...
}
```
**Why:**
- **desired_count**: Number of tasks to run (default 2 for high availability)
- **launch_type = "FARGATE"**: Serverless compute, no EC2 instances to manage

```terraform
  network_configuration {
    subnets          = var.private_subnet_ids
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = false
  }
```
**Why:**
- **subnets = private_subnet_ids**: Tasks run in private subnets (no direct internet access)
- **assign_public_ip = false**: No public IPs (traffic goes through ALB, VPC endpoints for AWS services)
- **security_groups**: Applies ECS security group (only allows ALB traffic)

```terraform
  load_balancer {
    target_group_arn = var.blue_target_group_arn
    container_name   = var.container_name
    container_port   = 8080
  }
```
**Why:** Registers tasks with the blue target group. CodeDeploy will manage switching between blue/green during deployments.

```terraform
  deployment_controller {
    type = "CODE_DEPLOY"
  }
```
**Why:** Uses CodeDeploy for deployments instead of ECS rolling updates. Enables blue/green deployments with traffic shifting.

```terraform
  lifecycle {
    ignore_changes = [task_definition, load_balancer]
  }
```
**Why:**
- **ignore_changes**: CodeDeploy manages task definition updates and load balancer target group changes
- Prevents Terraform from reverting CodeDeploy changes during deployments
- Terraform creates initial service, CodeDeploy handles updates

---

### CodeDeploy Module

#### `infra/modules/codedeploy/main.tf`

```terraform
resource "aws_iam_role" "codedeploy" {
  ...
  Principal = {
    Service = "codedeploy.amazonaws.com"
  }
  ...
}
```
**Why:** IAM role for CodeDeploy service to manage ECS deployments. CodeDeploy assumes this role to update ECS services and ALB target groups.

```terraform
resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}
```
**Why:** AWS managed policy that grants CodeDeploy permissions to:
- Update ECS services
- Modify ALB target groups and listeners
- Describe ECS tasks and services

```terraform
resource "aws_codedeploy_app" "main" {
  compute_platform = "ECS"
  name             = "${var.project_name}-app"
  ...
}
```
**Why:**
- **compute_platform = "ECS"**: Specifies ECS as the deployment target (vs EC2 or Lambda)
- Creates the CodeDeploy application (container for deployment groups)

```terraform
resource "aws_codedeploy_deployment_group" "main" {
  ...
  deployment_config_name  = "CodeDeployDefault.ECSAllAtOnce"
  ...
}
```
**Why:**
- **deployment_config_name**: 
  - `ECSAllAtOnce`: Deploys all tasks at once (fastest, but higher risk)
  - Alternatives: `ECSLinear10PercentEvery1Minute`, `ECSLinear10PercentEvery3Minutes` for gradual rollouts
  - For production, consider gradual deployments

```terraform
  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.ecs_service_name
  }
```
**Why:** Specifies which ECS service CodeDeploy will manage deployments for.

```terraform
  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }
    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }
```
**Why:**
- **action_on_timeout = "CONTINUE_DEPLOYMENT"**: If green deployment takes too long, continue anyway (vs rollback)
- **terminate_blue_instances_on_deployment_success**: After green is healthy and traffic is shifted, terminate old blue tasks
- **termination_wait_time_in_minutes = 5**: Wait 5 minutes before terminating (allows rollback if issues discovered)

```terraform
  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }
```
**Why:**
- **enabled = true**: Automatically rollback to previous version if deployment fails
- **events = ["DEPLOYMENT_FAILURE"]**: Triggers rollback on deployment failure (can also include "DEPLOYMENT_STOP_ON_ALARM")

```terraform
  load_balancer_info {
    target_group_pair_info {
      target_group {
        name = var.blue_target_group_name
      }
      target_group {
        name = var.green_target_group_name
      }
      prod_traffic_route {
        listener_arns = [var.listener_arn]
      }
    }
  }
```
**Why:**
- **target_group_pair_info**: Defines blue and green target groups for blue/green deployment
- **prod_traffic_route**: Specifies which ALB listener receives production traffic
- CodeDeploy shifts traffic from blue → green during deployment

```terraform
  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }
```
**Why:**
- **deployment_type = "BLUE_GREEN"**: Blue/green deployment (creates new version alongside old, then switches)
- **deployment_option = "WITH_TRAFFIC_CONTROL"**: CodeDeploy manages traffic shifting (vs manual control)
- Alternative: `IN_PLACE` for rolling updates (not used here)

---

## Summary

This infrastructure implements a production-ready, secure, and scalable URL shortener service on AWS:

1. **Security**: Private subnets, security groups, WAF, encryption, non-root containers, least-privilege IAM
2. **High Availability**: Multi-AZ deployment, load balancing, health checks
3. **Scalability**: Fargate auto-scaling, DynamoDB on-demand, ALB
4. **Observability**: CloudWatch Logs, Container Insights, health checks
5. **Deployment**: Blue/green deployments via CodeDeploy for zero-downtime updates
6. **Cost Optimization**: VPC endpoints (no NAT gateway), ECR lifecycle policies, log retention limits

Each configuration choice balances functionality, security, cost, and operational simplicity.

