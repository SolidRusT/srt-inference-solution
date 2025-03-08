# AWS EC2 Inference Solution - Architecture

## Overview

This document describes the architecture and design decisions for the AWS EC2 Inference Solution. The solution provides a fully automated, Infrastructure-as-Code approach to deploying a containerized inference application on AWS with minimal user intervention.

## Core Principles

The solution was designed with the following principles:
- **Idempotency**: Resources can be created, updated, or destroyed reliably
- **Simplicity**: Minimal configuration required to deploy the complete solution
- **Security**: Follow AWS best practices for secure infrastructure
- **Maintainability**: Modular design for easy updates and extensions
- **Automation**: Eliminate manual steps in deployment and operation

## Architecture Components

The solution consists of the following core components:

### 1. Infrastructure Components

#### VPC and Networking
- **VPC**: Isolates the solution in a dedicated virtual network
- **Subnets**: 
  - **Public Subnets**: Host the EC2 instance with public internet access
  - **Private Subnets**: Reserved for future expansion (databases, internal services)
- **NAT Gateway**: Enables outbound internet access from private subnets
- **Internet Gateway**: Provides inbound/outbound internet access for public subnets
- **Security Groups**: Restrict network traffic to the EC2 instance

#### Compute
- **EC2 Instance**: Hosts the containerized application
  - Uses latest Ubuntu AMI from Canonical
  - Configured with user-data script to install Docker and set up services
  - IAM Role with permissions for ECR access
  - Security group limits access to specified ports and IP ranges

#### Storage and Registry
- **ECR Repository**: Stores Docker container images
  - Lifecycle policies to limit stored images
  - Repository policies for secure access

#### DNS Management
- **Route53 Records**: Maps domain names to EC2 public IP
  - Creates `infer.domain.com` pointing to the EC2 instance

### 2. Application Components

#### Docker Container
- NodeJS Express application
- Simple API endpoints:
  - `/`: Basic information
  - `/health`: Health check endpoint
  - `/api/infer`: Sample inference endpoint

#### Systemd Service
- Manages the Docker container lifecycle
- Ensures container starts on instance boot
- Handles automatic restarts on failure

#### Update Mechanism
- Hourly cron job to check for new images
- Automated login to ECR and image pulls
- Seamless container updates

## Infrastructure as Code Structure

```
inference-solution/
├── app/                         # Application code
│   ├── Dockerfile               # Container definition
│   ├── package.json             # Node.js dependencies
│   └── server.js                # API implementation
├── modules/                     # Terraform modules
│   ├── build/                   # Image build/push logic
│   ├── ec2/                     # EC2 instance configuration
│   ├── ecr/                     # Container registry
│   ├── route53/                 # DNS configuration
│   └── vpc/                     # Network infrastructure
├── backend.tf                   # Terraform state configuration
├── main.tf                      # Main infrastructure definition
├── outputs.tf                   # Output values and information
├── terraform.tf                 # Provider configuration
├── terraform.tfvars             # Variable values
└── variables.tf                 # Variable definitions
```

## Deployment Workflow

1. **Prepare S3 Backend**: Create an S3 bucket for Terraform state
2. **Initialize Terraform**: Run `terraform init`
3. **Apply Infrastructure**: Run `terraform apply`
4. **Build Process**:
   - Application code is built into a Docker image
   - Image is pushed to ECR
5. **Instance Provisioning**:
   - EC2 instance is launched with user-data script
   - Docker is installed
   - Systemd service is configured
6. **Application Deployment**:
   - EC2 instance pulls Docker image from ECR
   - Application starts running
7. **DNS Configuration**: Route53 records are created

## Security Considerations

- **IAM**: Least privilege principle for EC2 instance role
- **Security Groups**: Traffic restrictions by port and source IP
- **Instance Hardening**:
  - IMDSv2 required
  - Root volume encryption
  - No direct SSH (use Session Manager)
- **Container Security**:
  - Minimal base image (Node Alpine)
  - No unnecessary packages
  - Regular updates via cron job

## Future Enhancements

1. **Scaling**:
   - Auto Scaling Group for high availability
   - Load Balancer for traffic distribution

2. **Security**:
   - HTTPS with ACM certificates
   - WAF integration for API protection

3. **Monitoring**:
   - CloudWatch alarms and dashboards
   - Log aggregation and analysis

4. **CI/CD**:
   - GitHub Actions integration
   - Automated testing pipeline

## Technical Debt & Known Limitations

1. Single instance deployment (no high availability)
2. HTTP only (no HTTPS/TLS)
3. Basic authentication mechanism
4. Limited monitoring and alerting
