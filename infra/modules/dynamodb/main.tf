# DynamoDB Module
# Creates DynamoDB table for URL mappings with PAY_PER_REQUEST billing and PITR enabled

resource "aws_dynamodb_table" "url_mappings" {
  name           = var.table_name
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"

  attribute {
    name = "id"
    type = "S"
  }

  # Point-in-time recovery enabled
  point_in_time_recovery {
    enabled = true
  }

  # Server-side encryption
  server_side_encryption {
    enabled = true
  }

  tags = {
    Name        = var.table_name
    Environment = var.environment
    ManagedBy   = "terraform"
  }
}


