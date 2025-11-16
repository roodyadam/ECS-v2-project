variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "eu-west-2"
}

variable "github_repo" {
  description = "GitHub repository in format 'owner/repo' (e.g., 'username/url-shortener')"
  type        = string
}

variable "create_github_oidc_provider" {
  description = "Whether to create the GitHub OIDC provider (set to false if already exists)"
  type        = bool
  default     = false
}

