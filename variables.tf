variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "environment" {
  description = "Environment name for the cluster"
  type        = string
  default     = "production"
}

variable "tags" {
  description = "Tags to be applied to all resources"
  type        = map(string)
  default = {
    Environment = "production"
    ManagedBy   = "terraform"
    Project     = "rancher-platform"
  }
}

variable "domain_name" {
  description = "Domain name for platform components"
  type        = string
  default     = "live.ca.obenv.net"
}

variable "create_route53_records" {
  description = "Whether to create Route53 records (requires domain to exist)"
  type        = bool
  default     = true
}

variable "vpc_cidr" {
  description = "CIDR block for VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "email_address" {
  description = "Email address for Let's Encrypt certificate notifications"
  type        = string
  default     = "admin@example.com"
}

variable "allowed_admin_ips" {
  description = "List of CIDRs that can access the load balancer endpoints (e.g. your office or home IP)"
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "EC2 instance type for the inference server"
  type        = string
  default     = "t3.small"
}

variable "key_name" {
  description = "Name of the SSH key pair to use for the EC2 instance"
  type        = string
  default     = null
}

variable "app_port" {
  description = "Port on which the inference API will run"
  type        = number
  default     = 8080
}
