# CodeDeploy Module
# Creates CodeDeploy application and deployment group for blue/green ECS deployments

# IAM role for CodeDeploy
resource "aws_iam_role" "codedeploy" {
  name = "${var.project_name}-codedeploy-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "codedeploy.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name = "${var.project_name}-codedeploy-role"
  }
}

# Attach AWS managed policy for CodeDeploy to ECS
resource "aws_iam_role_policy_attachment" "codedeploy" {
  role       = aws_iam_role.codedeploy.name
  policy_arn = "arn:aws:iam::aws:policy/AWSCodeDeployRoleForECS"
}

# CodeDeploy Application
resource "aws_codedeploy_app" "main" {
  compute_platform = "ECS"
  name             = "${var.project_name}-app"

  tags = {
    Name = "${var.project_name}-codedeploy-app"
  }
}

# CodeDeploy Deployment Group
resource "aws_codedeploy_deployment_group" "main" {
  app_name               = aws_codedeploy_app.main.name
  deployment_group_name   = "${var.project_name}-dg"
  service_role_arn        = aws_iam_role.codedeploy.arn
  # Must specify an ECS deployment config (even for blue/green)
  # The blue_green_deployment_config block handles the blue/green strategy
  deployment_config_name  = "CodeDeployDefault.ECSAllAtOnce"

  ecs_service {
    cluster_name = var.ecs_cluster_name
    service_name = var.ecs_service_name
  }

  blue_green_deployment_config {
    deployment_ready_option {
      action_on_timeout = "CONTINUE_DEPLOYMENT"
    }

    # For ECS, green_fleet_provisioning_option is not supported
    # ECS automatically provisions the green fleet from the new task definition

    terminate_blue_instances_on_deployment_success {
      action                           = "TERMINATE"
      termination_wait_time_in_minutes = 5
    }
  }

  auto_rollback_configuration {
    enabled = true
    events  = ["DEPLOYMENT_FAILURE"]
  }

  # For ECS CodeDeploy, load_balancer_info is required with target_group_pair_info
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

  deployment_style {
    deployment_option = "WITH_TRAFFIC_CONTROL"
    deployment_type   = "BLUE_GREEN"
  }

  tags = {
    Name = "${var.project_name}-codedeploy-dg"
  }
}

