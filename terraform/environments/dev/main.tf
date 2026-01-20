# Development Environment - Main Configuration

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Environment = "dev"
      Project     = "luma-video-ai"
      ManagedBy   = "terraform"
    }
  }
}

# VPC Module
module "vpc" {
  source = "../../modules/vpc"

  environment         = var.environment
  vpc_cidr            = var.vpc_cidr
  availability_zones  = var.availability_zones
}

# EC2 Module
module "ec2" {
  source = "../../modules/ec2"

  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  private_subnet_ids  = module.vpc.private_subnet_ids
  instance_type       = var.instance_type
  min_instances       = var.min_instances
  max_instances       = var.max_instances
}

# RDS Module
module "rds" {
  source = "../../modules/rds"

  environment         = var.environment
  vpc_id              = module.vpc.vpc_id
  database_subnet_ids = module.vpc.database_subnet_ids
  instance_class      = var.rds_instance_class
  enable_multi_az     = var.enable_multi_az
}

# S3 Module
module "s3" {
  source = "../../modules/s3"

  environment = var.environment
}
