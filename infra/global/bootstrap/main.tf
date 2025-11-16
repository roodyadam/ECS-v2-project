
terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket         = "ecs-v2-terraform-state-roodyadams-88975-eu-west-2"
    key            = "global/bootstrap/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

# Data source to get existing GitHub OIDC Provider (if it exists)
data "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 0 : 1
  url   = "https://token.actions.githubusercontent.com"
}

# GitHub OIDC Provider (only create if create_github_oidc_provider is true)
# Note: If provider already exists, set create_github_oidc_provider = false in terraform.tfvars
resource "aws_iam_openid_connect_provider" "github" {
  count = var.create_github_oidc_provider ? 1 : 0

  url = "https://token.actions.githubusercontent.com"

  client_id_list = [
    "sts.amazonaws.com"
  ]

  thumbprint_list = [
    "6938fd4d98bab03faadb97b34396831e3780aea1",
    "1c58a3a8518e8759bf075b76b750d4f2df264fcd"
  ]

  tags = {
    Name        = "GitHub-OIDC-Provider"
    ManagedBy   = "terraform"
    Purpose     = "CI/CD Bootstrap"
  }
}

# Local value to get the OIDC provider ARN (either from resource or data source)
locals {
  oidc_provider_arn = var.create_github_oidc_provider && length(aws_iam_openid_connect_provider.github) > 0 ? aws_iam_openid_connect_provider.github[0].arn : data.aws_iam_openid_connect_provider.github[0].arn
}

# GitHub Actions Deploy Role (for CI/CD via OIDC)
resource "aws_iam_role" "github_deploy" {
  name = "${var.project_name}-github-deploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = local.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
          }
          StringLike = {
            "token.actions.githubusercontent.com:sub" = "repo:${var.github_repo}:*"
          }
        }
      }
    ]
  })

  tags = {
    Name        = "${var.project_name}-github-deploy-role"
    ManagedBy   = "terraform"
    Purpose     = "CI/CD Bootstrap"
  }
}

# GitHub deploy role policy - permissions for Terraform and CodeDeploy
resource "aws_iam_role_policy" "github_deploy" {
  name = "${var.project_name}-github-deploy-policy"
  role = aws_iam_role.github_deploy.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ecs:*",
          "ecr:*",
          "iam:PassRole",
          "iam:GetRole",
          "iam:ListRolePolicies",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:CreateRole",
          "iam:AttachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "iam:ListOpenIDConnectProviders",
          "iam:GetOpenIDConnectProvider",
          "iam:DeleteRole",
          "iam:DeleteRolePolicy",
          "iam:DetachRolePolicy",
          "codedeploy:*",
          "s3:*",
          "dynamodb:*",
          "logs:*",
          "wafv2:*",
          "elasticloadbalancing:*",
          "acm:*",
          "route53:*",
          "ec2:*"
        ]
        Resource = "*"
      }
    ]
  })
}

