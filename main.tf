data "aws_availability_zones" "available" {}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = merge(var.tags, {
    Environment = var.environment
    ManagedBy   = "terraform"
    Project     = "inference-solution"
  })

  instance_name = "inference-${var.environment}"
}

# VPC and networking
module "vpc" {
  source = "./modules/vpc"
  name = "inference-solution"
  vpc_cidr      = var.vpc_cidr
  azs           = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]
  tags = local.tags
}

# ECR repository for storing Docker images
module "ecr" {
  source = "./modules/ecr"
  repository_name = "inference-app-${var.environment}"
  tags           = local.tags
  instance_role_arn = module.ec2.instance_role_arn
}

# EC2 instance for running the inference application
module "ec2" {
  source = "./modules/ec2"
  name              = local.instance_name
  vpc_id            = module.vpc.vpc_id
  subnet_id         = module.vpc.public_subnets[0]  # Use first public subnet
  instance_type     = var.instance_type
  use_gpu           = var.use_gpu_instance
  gpu_instance_type = var.gpu_instance_type
  key_name          = var.key_name
  app_port          = var.app_port
  vllm_port         = var.vllm_port
  model_id          = var.model_id
  max_model_len     = var.max_model_len
  gpu_memory_utilization = var.gpu_memory_utilization
  vllm_image_tag    = var.vllm_image_tag
  hf_token_parameter_name = var.hf_token_parameter_name
  region            = var.region
  allowed_cidr_blocks = concat(["0.0.0.0/0"], var.allowed_admin_ips)
  ecr_repository_url = module.ecr.repository_url
  tags              = local.tags
}

# Build and push the Docker image
module "build" {
  source = "./modules/build"
  ecr_repository_url = module.ecr.repository_url
  aws_region         = var.region

  depends_on = [module.ecr]
}

# DNS configuration
module "route53" {
  source = "./modules/route53"
  count  = var.create_route53_records ? 1 : 0
  domain_name         = var.domain_name
  instance_public_ip  = module.ec2.instance_public_ip
  create_example_record = true

  depends_on = [module.ec2]
}