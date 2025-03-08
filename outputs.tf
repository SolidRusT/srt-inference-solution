output "region" {
  description = "AWS region"
  value       = var.region
}

# VPC Outputs
output "vpc_id" {
  description = "VPC ID that the inference solution is using"
  value       = module.vpc.vpc_id
}

output "vpc_private_subnets" {
  description = "List of IDs of private subnets"
  value       = module.vpc.private_subnets
}

output "vpc_public_subnets" {
  description = "List of IDs of public subnets"
  value       = module.vpc.public_subnets
}

output "vpc_nat_public_ips" {
  description = "List of public Elastic IPs created for AWS NAT Gateway"
  value       = module.vpc.nat_public_ips
}

# EC2 Instance Outputs
output "instance_id" {
  description = "ID of the inference EC2 instance"
  value       = module.ec2.instance_id
}

output "instance_public_ip" {
  description = "Public IP address of the inference EC2 instance"
  value       = module.ec2.instance_public_ip
}

output "instance_private_ip" {
  description = "Private IP address of the inference EC2 instance"
  value       = module.ec2.instance_private_ip
}

output "api_endpoint" {
  description = "HTTP endpoint for the inference API"
  value       = module.ec2.api_endpoint
}

# ECR Outputs
output "ecr_repository_url" {
  description = "URL of the ECR repository for inference application images"
  value       = module.ecr.repository_url
}

# DNS Outputs
output "domain_name" {
  description = "Domain name used for the platform"
  value       = var.domain_name
}

output "dns_records_created" {
  description = "Whether DNS records were created"
  value       = var.create_route53_records
}

output "route53_zone_id" {
  description = "The Route 53 zone ID when records are created"
  value       = var.create_route53_records ? try(module.route53[0].zone_id, null) : null
}

output "api_domain" {
  description = "Full domain name for the inference API"
  value       = var.create_route53_records ? "http://infer.${var.domain_name}:${var.app_port}" : null
}

# Application Outputs
output "app_port" {
  description = "Port on which the inference API is running"
  value       = var.app_port
}

output "deployment_environment" {
  description = "Environment name for this deployment"
  value       = var.environment
}

# Summary
output "inference_solution_info" {
  description = "Summary of the inference solution deployment"
  value = {
    api_url            = "http://${module.ec2.instance_public_ip}:${var.app_port}"
    api_domain         = var.create_route53_records ? "http://infer.${var.domain_name}:${var.app_port}" : null
    ssh_connection     = "ssh -i ${var.key_name}.pem ubuntu@${module.ec2.instance_public_ip}"
    ecr_repository     = module.ecr.repository_url
    environment        = var.environment
    deployed_timestamp = timestamp()
  }
}
