variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "dynamodb_table_arn" {
  description = "ARN of the DynamoDB table for task role policy"
  type        = string
}


