variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "vpc_id" {
  description = "VPC ID"
  type        = string
}

variable "private_subnet_ids" {
  description = "List of private subnet IDs"
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "Security group ID of the ALB"
  type        = string
}

variable "blue_target_group_arn" {
  description = "ARN of the blue target group"
  type        = string
}

variable "execution_role_arn" {
  description = "ARN of the ECS task execution role"
  type        = string
}

variable "task_role_arn" {
  description = "ARN of the ECS task role"
  type        = string
}

variable "table_name" {
  description = "Name of the DynamoDB table"
  type        = string
}

variable "container_name" {
  description = "Name of the container"
  type        = string
  default     = "url-shortener"
}

variable "container_image" {
  description = "Container image URI"
  type        = string
}

variable "task_cpu" {
  description = "CPU units for the task (256, 512, 1024, etc.)"
  type        = string
  default     = "256"
}

variable "task_memory" {
  description = "Memory for the task in MB (512, 1024, 2048, etc.)"
  type        = string
  default     = "512"
}

variable "desired_count" {
  description = "Desired number of tasks"
  type        = number
  default     = 2
}

variable "aws_region" {
  description = "AWS region"
  type        = string
}


