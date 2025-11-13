variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for task role policy"
  type        = string
}

variable "aws_account_id" {
  description = "AWS account ID"
  type        = string
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo' (e.g., 'username/url-shortener')"
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Whether to create the GitHub OIDC provider (set to false if already exists)"
  type        = bool
  default     = true
}


