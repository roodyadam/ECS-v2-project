output "alb_dns_name" {
  description = "DNS name of the Application Load Balancer"
  value       = module.alb.alb_dns_name
}

output "ecr_repository_url" {
  description = "URL of the ECR repository"
  value       = module.ecr.repository_url
}

output "dynamodb_table_name" {
  description = "Name of the DynamoDB table"
  value       = module.dynamodb.table_name
}

output "github_deploy_role_arn" {
  description = "ARN of the GitHub deploy role (for OIDC) - from bootstrap stack"
  value       = data.aws_iam_role.github_deploy.arn
  sensitive   = false
}

output "codedeploy_app_name" {
  description = "Name of the CodeDeploy application"
  value       = module.codedeploy.codedeploy_app_name
}

output "codedeploy_deployment_group_name" {
  description = "Name of the CodeDeploy deployment group"
  value       = module.codedeploy.codedeploy_deployment_group_name
}

output "ecs_cluster_name" {
  description = "Name of the ECS cluster"
  value       = module.ecs.cluster_name
}

output "ecs_service_name" {
  description = "Name of the ECS service"
  value       = module.ecs.service_name
}


