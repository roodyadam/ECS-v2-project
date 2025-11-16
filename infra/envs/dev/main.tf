
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
    key            = "envs/dev/terraform.tfstate"
    region         = "eu-west-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_iam_role" "github_deploy" {
  name = "${var.project_name}-github-deploy-role"
}

module "vpc" {
  source = "../../modules/vpc"

  project_name = var.project_name
  vpc_cidr     = var.vpc_cidr
  aws_region   = var.aws_region
}

module "dynamodb" {
  source = "../../modules/dynamodb"

  table_name  = "${var.project_name}-url-mappings"
  environment = "dev"
}

module "iam" {
  source = "../../modules/iam"

  project_name       = var.project_name
  dynamodb_table_arn = module.dynamodb.table_arn
}

module "ecr" {
  source = "../../modules/ecr"

  repository_name = "${var.project_name}-repo"
  environment     = "dev"
}

module "alb" {
  source = "../../modules/alb"

  project_name      = var.project_name
  vpc_id            = module.vpc.vpc_id
  public_subnet_ids = module.vpc.public_subnet_ids
}

module "ecs" {
  source = "../../modules/ecs"

  project_name          = var.project_name
  vpc_id                = module.vpc.vpc_id
  private_subnet_ids    = module.vpc.private_subnet_ids
  alb_arn               = module.alb.alb_arn
  alb_security_group_id = module.alb.alb_security_group_id
  blue_target_group_arn = module.alb.blue_target_group_arn
  execution_role_arn    = module.iam.ecs_execution_role_arn
  task_role_arn         = module.iam.ecs_task_role_arn
  table_name            = module.dynamodb.table_name
  container_image       = "${module.ecr.repository_url}:latest"
  aws_region            = var.aws_region
  desired_count         = var.ecs_desired_count
}

module "codedeploy" {
  source = "../../modules/codedeploy"

  project_name            = var.project_name
  ecs_cluster_name       = module.ecs.cluster_name
  ecs_service_name        = module.ecs.service_name
  blue_target_group_name  = module.alb.blue_target_group_name
  green_target_group_name = module.alb.green_target_group_name
  container_name          = "url-shortener"
  container_port          = 8080
  listener_arn            = module.alb.listener_arn
}


