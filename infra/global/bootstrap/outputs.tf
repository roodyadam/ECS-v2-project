output "github_deploy_role_arn" {
  description = "ARN of the GitHub deploy role (for OIDC) - Use this in GitHub Secrets as AWS_ROLE_ARN"
  value       = aws_iam_role.github_deploy.arn
  sensitive   = false
}

